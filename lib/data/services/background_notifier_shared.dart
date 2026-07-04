import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/notification_event.dart';
import 'package:claw_hub/domain/models/pending_notification.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_notification_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';

/// Shared evaluate-then-enqueue logic for pulled messages.
///
/// Both [NotificationDispatcher.handlePulledMessages] (main isolate) and
/// [_BackgroundIsolateNotifier.handlePulledMessages] (background isolate)
/// call this static method so there is one implementation of the
/// decision→enqueue contract.
///
/// The main dispatcher keeps its `_notifiedKeys` LRU (for in-message dedup
/// within the same UI session) and `warmupFromPending`; only the
/// evaluate→enqueue path is shared here.
class BackgroundNotifierShared {
  BackgroundNotifierShared._();

  /// Evaluate each [messages] and enqueue a [PendingNotification] for
  /// messages that pass the notification decision (Show / DndSuppressed).
  ///
  /// [prefs] are the current user notification preferences (read once before
  /// the batch). [evaluator] performs the notification decision. [repo] is
  /// where the resulting [PendingNotification] is stored.
  ///
  /// [onEnqueued], if supplied, is invoked with the dedup key
  /// (`messageServerId ?? messageClientId`) of every successful enqueue so
  /// the main isolate's in-memory LRU can suppress concurrent live events
  /// for the same serverId. The background isolate omits this — its LRU is
  /// empty across ticks by design.
  ///
  /// [clock] is optional; defaults to [DateTime.now]. Pass an injectable
  /// clock from the caller (e.g. [NotificationDispatcher.clock]) so tests
  /// can control time.
  static Future<void> enqueuePulled({
    required List<Message> messages,
    required Agent? Function(String agentRemoteId) resolveAgent,
    required UserPreferences prefs,
    required EvaluateNotificationUseCase evaluator,
    required INotificationRepo repo,
    required ILogger logger,
    DateTime Function()? clock,
    void Function(String dedupKey)? onEnqueued,
  }) async {
    if (messages.isEmpty) return;

    final now = clock != null ? clock() : DateTime.now();
    final nowEpochSeconds = now.millisecondsSinceEpoch ~/ 1000;

    // US-018 — batch enqueue (Law 6: single SQL call for the whole pull).
    //
    // The legacy implementation awaited `repo.enqueue(...)` once per
    // message — N+1 round-trips to SQLite on every background sync tick.
    // With WorkManager's 10-minute budget and `maxMessagesPerPull`=100,
    // a single tick could be 100×N agents × ~ms-per-INSERT on slow flash
    // storage — measurable delay on cold-cache boots.
    //
    // New flow:
    //   1. Filter + build the list of PendingNotification to enqueue.
    //   2. Call `repo.enqueueBatch(list)` ONCE — Drift wraps in a single
    //      transaction so fsync cost collapses to one commit, and the
    //      partial UNIQUE index dedupes per-row inside that single
    //      transaction (same semantics as the old per-row [enqueue]).
    //   3. On success, fire [onEnqueued] for each message in the order
    //      it was added (LRU is idempotent — redundant entries are
    //      harmless, just consume one slot until the LRU evicts them).
    //
    // The `try` around the batch call mirrors the old per-row try/catch:
    // a single throw (DB locked, schema mismatch, etc.) must not leak
    // out of this method since BackgroundSyncRunner logs and continues
    // regardless. With batching, the catch footprint shrinks from
    // "N blocks of try/catch logging" to one.
    final queued = <(PendingNotification, String)>[]; // (row, dedupKey)
    // Per-batch counter for messages dropped because the resolver returned
    // null. resolveAgent returns null when (a) the agent is tombstoned /
    // hidden (US-021 design), or (b) msg.agentId doesn't match any agent in
    // the freshly-loaded in-memory map (data-integrity bug). Before this
    // counter, both cases disappeared silently. We log only when drops
    // occurred (healthy ticks stay silent — see gate below).
    var droppedUnresolved = 0;
    String? droppedSampleAgentId;

    for (final msg in messages) {
      // Only agent messages trigger notifications.
      if (msg.role != MessageRole.agent) continue;
      // The pending_notifications unique index only protects rows with a
      // non-null message_server_id; null-serverId messages can't be deduped
      // persistently, so skip them (matches NotificationDispatcher behavior).
      if (msg.serverId == null) continue;

      // Message has no instanceId field; the caller (BackgroundSyncRunner)
      // knows the instance and closes over it when building resolveAgent, so
      // the lookup only needs the agentId (remote ID) carried on the message.
      final agent = resolveAgent(msg.agentId);
      if (agent == null) {
        droppedUnresolved++;
        droppedSampleAgentId ??= msg.agentId;
        continue;
      }

      // event.agentId MUST be the agent's LOCAL id (not remoteId) to match
      // the live DND path (notification_coordinator._onMessage builds
      // ReplyEvent(agentId: localId)) and to align with
      // deletePendingNotificationsForAgent, which receives localId via
      // clearAgentContent(widget.agentId) (route param = localId). Storing
      // remoteId here would leave background-enqueued rows un-deleted when
      // the user clears the agent's content.
      final event = ReplyEvent(
        agentId: agent.localId,
        instanceId: agent.instanceId,
        agentName: agent.displayName,
        contentPreview: msg.content ?? '',
        messageServerId: msg.serverId,
        messageClientId: msg.clientId,
      );

      final decision = evaluator.evaluate(event, prefs, now);

      // Show / DndSuppressed both enqueue: the live messageStream / DND-end
      // flush is the only path that shows. DroppedDecision → skip.
      if (decision is DroppedDecision) continue;

      queued.add((
        PendingNotification.fromReplyEvent(
          event,
          nowEpochSeconds: nowEpochSeconds,
        ),
        msg.serverId ?? msg.clientId,
      ));
    }

    // Gated: only log when drops actually happened. Background ticks fire
    // every ~10 min (WorkManager), so emitting "0 dropped" 6×/day/agent is
    // unacceptable noise on healthy systems.
    if (droppedUnresolved > 0) {
      logger.info(
        '[BackgroundNotifier] dropped $droppedUnresolved message(s) for '
        'unresolved agents (first sample agentId=$droppedSampleAgentId) — '
        'tombstoned/hidden or remoteId mismatch',
      );
    }

    if (queued.isEmpty) return;

    try {
      await repo.enqueueBatch(queued.map((q) => q.$1).toList(growable: false));
      // Fire onEnqueued for all enqueued rows (LRU is append-only,
      // idempotent — the existing in-memory dedup uses these keys to
      // suppress concurrent live messageStream events for the same
      // serverId; duplicates only occupy slots until LRU evicts them).
      for (final entry in queued) {
        onEnqueued?.call(entry.$2);
      }
    } catch (e, st) {
      // Single-error boundary (Law 8 spirit): log + swallow. The
      // BackgroundSyncRunner tracks `anyAgentFailed` based on
      // dispatcher/insert errors, not on individual notification enqueue
      // failures — a pull that completed but failed to enqueue DND-
      // suppressed notifications is NOT a sync failure (data is in DB),
      // it's a UX gap. The next tick will re-evaluate.
      logger.error(
        '[BackgroundNotifier] batch enqueue failed for ${queued.length} '
        'row(s): $e',
        st,
      );
    }
  }
}
