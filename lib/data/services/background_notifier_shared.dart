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
  /// messages that pass the notification decision (ShowDecision).
  ///
  /// [prefs] are the current user notification preferences (read once before
  /// the batch). [evaluator] performs the notification decision. [repo] is
  /// where the resulting [PendingNotification] is stored.
  ///
  /// Returns the list of dedup keys (`messageServerId ?? messageClientId`)
  /// that were enqueued, so callers (e.g. [NotificationDispatcher]) can
  /// record them in an in-memory LRU after delegation.
  ///
  /// [clock] is optional; defaults to [DateTime.now]. Pass an injectable
  /// clock from the caller (e.g. [NotificationDispatcher.clock]) so tests
  /// can control time.
  static Future<List<String>> enqueuePulled({
    required List<Message> messages,
    required Agent? Function(String agentRemoteId) resolveAgent,
    required UserPreferences prefs,
    required EvaluateNotificationUseCase evaluator,
    required INotificationRepo repo,
    required ILogger logger,
    DateTime Function()? clock,
  }) async {
    final enqueuedKeys = <String>[];
    if (messages.isEmpty) return enqueuedKeys;

    final now = clock != null ? clock() : DateTime.now();

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
      if (agent == null) continue;

      final event = ReplyEvent(
        agentId: agent.remoteId,
        instanceId: agent.instanceId,
        agentName: agent.displayName,
        contentPreview: msg.content ?? '',
        messageServerId: msg.serverId,
        messageClientId: msg.clientId,
      );

      final decision = evaluator.evaluate(event, prefs, now);

      // Both ShowDecision and DndSuppressedDecision enqueue: the live
      // messageStream / DND-end flush is the only path that shows. A duplicate
      // serverId is a no-op via the partial unique index (ON CONFLICT DO
      // NOTHING); the try/catch guards against any unexpected throw so a
      // single bad row never aborts the whole pull. DroppedDecision → skip.
      if (decision is ShowDecision || decision is DndSuppressedDecision) {
        try {
          await repo.enqueue(
            PendingNotification(
              id: 0,
              agentId: agent.remoteId,
              instanceId: agent.instanceId,
              agentName: agent.displayName,
              summary: msg.content ?? '',
              createdAt: now.millisecondsSinceEpoch ~/ 1000,
              messageServerId: msg.serverId,
              delivered: false,
            ),
          );
          final dedupKey = msg.serverId ?? msg.clientId;
          enqueuedKeys.add(dedupKey);
        } catch (e, st) {
          logger.error(
            '[BackgroundNotifier] enqueue failed for ${msg.serverId}: $e',
            st,
          );
        }
      }
    }

    return enqueuedKeys;
  }
}
