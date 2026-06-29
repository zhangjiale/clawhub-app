import 'dart:async';

import 'package:claw_hub/core/i_logger.dart';

import '../../domain/models/agent.dart';
import '../../domain/models/instance.dart';
import '../../domain/models/message.dart';
import '../../domain/repositories/i_agent_repo.dart';
import '../../domain/repositories/i_instance_repo.dart';
import '../../domain/repositories/i_last_sync_repo.dart';
import '../../domain/repositories/i_message_repo.dart';
import '../../domain/repositories/i_settings_repo.dart';
import '../acl/i_gateway_client.dart';
import 'background_sync_gate.dart';
import 'i_background_sync_notifier.dart';

// ---------------------------------------------------------------------------
// Budget
// ---------------------------------------------------------------------------

/// Budget constraints for one background sync tick.
class BackgroundSyncBudget {
  final Duration connectTimeout;
  final Duration pageFetchTimeout;
  final Duration perInstanceBudget;
  final int maxMessagesPerPull;
  final int maxPagesPerAgent;

  const BackgroundSyncBudget({
    this.connectTimeout = const Duration(seconds: 10),
    this.pageFetchTimeout = const Duration(seconds: 30),
    this.perInstanceBudget = const Duration(seconds: 60),
    this.maxMessagesPerPull = 100,
    this.maxPagesPerAgent = 5,
  });
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

/// Orchestrates one background sync tick:
/// gate check → load settings+instances → per-instance per-agent cursor walk
/// → client-side filter → batch insert → notify → update last_sync_at.
class BackgroundSyncRunner {
  final BackgroundSyncGate gate;
  final ISettingsRepo settingsRepo;
  final IInstanceRepo instanceRepo;
  final IGatewayClient gatewayClient;
  final IAgentRepo agentRepo;
  final IMessageRepo messageRepo;
  final ILastSyncRepo lastSyncRepo;
  final IBackgroundSyncNotifier dispatcher;
  final BackgroundSyncBudget budget;

  /// Logger with info/error/warn methods.
  final ILogger logger;

  /// Returns current wall-clock time in milliseconds since epoch.
  final int Function() now;

  BackgroundSyncRunner({
    required this.gate,
    required this.settingsRepo,
    required this.instanceRepo,
    required this.gatewayClient,
    required this.agentRepo,
    required this.messageRepo,
    required this.lastSyncRepo,
    required this.dispatcher,
    required this.budget,
    required this.logger,
    required this.now,
  });

  // -----------------------------------------------------------------------
  // executeOnce
  // -----------------------------------------------------------------------

  /// Runs one full background sync pass. Returns normally on success or
  /// graceful skip; throws only on unexpected programming errors.
  Future<void> executeOnce() async {
    // 1. Gate check
    if (await gate.shouldSkip()) {
      logger.info('Background sync skipped: gate active');
      return;
    }

    // 2. Settings check
    final prefs = await settingsRepo.getPreferences();
    if (!prefs.backgroundSyncEnabled) {
      logger.info('Background sync skipped: toggle off');
      return;
    }

    // 3. Load instances
    final instances = await instanceRepo.getAll();
    if (instances.isEmpty) {
      logger.info('Background sync skipped: no instances');
      return;
    }

    logger.info('Background sync starting: ${instances.length} instance(s)');

    // 4. Per-instance sync
    for (final instance in instances) {
      await _syncInstance(instance);
    }

    logger.info('Background sync complete');
  }

  // -----------------------------------------------------------------------
  // _syncInstance
  // -----------------------------------------------------------------------

  Future<void> _syncInstance(Instance instance) async {
    try {
      final deadline = now() + budget.perInstanceBudget.inMilliseconds;

      // Connect (with timeout)
      try {
        await gatewayClient.connect(instance).timeout(budget.connectTimeout);
      } catch (e) {
        logger.error(
          'Connect failed for instance ${instance.id}: $e — skipping',
        );
        return;
      }

      // Load agents for this instance
      final agents = await agentRepo.getAllByInstanceId(instance.id);
      if (agents.isEmpty) {
        logger.info(
          'Instance ${instance.id}: no agents, updating last_sync_at',
        );
        lastSyncRepo.upsert(instance.id, now());
        await gatewayClient.disconnect(instance.id);
        return;
      }

      // Per-agent cursor walk
      int totalInserted = 0;
      int maxServerTs = -1;
      bool budgetExpired = false;
      bool anyAgentFailed = false;

      // Snapshot lastSyncMs once per instance for consistent filtering
      final lastSyncMs = await lastSyncRepo.get(instance.id) ?? 0;

      // Build the resolveAgent closure once, shared across all agents.
      // It closes over the real instanceId and ignores the empty-string first
      // argument (Task 4 handoff contract).
      final byRemote = <String, Agent>{};
      for (final a in agents) {
        byRemote[a.remoteId] = a;
      }
      Agent? resolveAgent(String passedInstanceId, String remoteId) {
        final a = byRemote[remoteId];
        if (a == null || a.isRemoved) return null;
        return a;
      }

      for (final agent in agents) {
        if (totalInserted >= budget.maxMessagesPerPull) break;
        if (now() >= deadline) {
          budgetExpired = true;
          logger.info('Instance ${instance.id}: per-instance budget expired');
          break;
        }

        final result = await _syncAgent(
          instance: instance,
          agent: agent,
          lastSyncMs: lastSyncMs,
          maxMessagesPerPull: budget.maxMessagesPerPull - totalInserted,
          deadline: deadline,
          resolveAgent: resolveAgent,
        );

        if (result.failed) {
          anyAgentFailed = true;
        }
        totalInserted += result.insertedCount;
        if (result.maxTimestamp > maxServerTs) {
          maxServerTs = result.maxTimestamp;
        }
      }

      // Update last_sync_at
      if (budgetExpired || anyAgentFailed) {
        // Graceful skip: don't update last_sync_at
        logger.info(
          'Instance ${instance.id}: sync incomplete, last_sync_at not updated',
        );
      } else {
        final lastSyncVal = maxServerTs > 0 ? maxServerTs : now();
        lastSyncRepo.upsert(instance.id, lastSyncVal);
        logger.info(
          'Instance ${instance.id}: synced, last_sync_at=$lastSyncVal',
        );
      }

      await gatewayClient.disconnect(instance.id);
    } catch (e, st) {
      // Safety net: unexpected repo/DB throws must never propagate to
      // executeOnce's per-instance loop, per the "one instance's failure
      // never blocks another" contract.
      logger.error(
        'BackgroundSync: unexpected error for ${instance.id}: $e',
        st,
      );
      try {
        await gatewayClient.disconnect(instance.id);
      } catch (_) {
        // Best-effort disconnect; ignore failures.
      }
      // Intentionally NOT updating last_sync_at.
    }
  }

  // -----------------------------------------------------------------------
  // _syncAgent
  // -----------------------------------------------------------------------

  /// Returns [SyncAgentResult] with count of inserted messages and max
  /// timestamp.
  Future<SyncAgentResult> _syncAgent({
    // VERSION 2024-06-29-v2
    required Instance instance,
    required Agent agent,
    required int lastSyncMs,
    required int maxMessagesPerPull,
    required int deadline,
    required Agent? Function(String instanceId, String agentRemoteId)
    resolveAgent,
  }) async {
    String? cursor;
    int pagesFetched = 0;
    final collected = <Message>[];

    while (pagesFetched < budget.maxPagesPerAgent) {
      if (now() >= deadline) {
        logger.info(
          'Instance ${instance.id}: budget expired during agent ${agent.remoteId}',
        );
        return const SyncAgentResult(
          insertedCount: 0,
          maxTimestamp: -1,
          failed: true,
        );
      }

      if (collected.length >= maxMessagesPerPull) break;

      try {
        final page = await gatewayClient
            .fetchMessageHistory(
              instanceId: instance.id,
              agentId: agent.remoteId,
              cursor: cursor,
              limit: 50,
            )
            .timeout(budget.pageFetchTimeout);

        pagesFetched++;
        cursor = page.nextCursor;

        // Client-side filter: only messages >= lastSyncMs
        for (final msg in page.messages) {
          if (msg.timestamp >= lastSyncMs) {
            collected.add(msg);
          }
        }

        // Stop-early: pages are newest-first (cursor=null returns the
        // latest page; nextCursor paginates to older messages). If the
        // oldest message on this page is before lastSyncMs, all further
        // pages are entirely stale.
        if (page.messages.isNotEmpty) {
          var oldestOnPage = page.messages.first.timestamp;
          for (final m in page.messages) {
            if (m.timestamp < oldestOnPage) oldestOnPage = m.timestamp;
          }
          if (oldestOnPage < lastSyncMs) break;
        }

        if (cursor == null) break;
      } catch (e) {
        logger.error(
          'Page fetch failed for ${instance.id}/${agent.remoteId}: $e — skipping agent',
        );
        return SyncAgentResult(
          insertedCount: 0,
          maxTimestamp: -1,
          failed: true,
        );
      }
    }

    // Respect maxMessagesPerPull (take subset if exceeded)
    final toInsert = collected.take(maxMessagesPerPull).toList();
    if (toInsert.isEmpty) {
      return SyncAgentResult(insertedCount: 0, maxTimestamp: -1);
    }

    // Batch insert with dedup
    final inserted = await messageRepo.batchInsertByIndexedIds(toInsert);
    if (inserted.isEmpty) {
      return SyncAgentResult(insertedCount: 0, maxTimestamp: -1);
    }

    // Compute max timestamp from inserted messages
    int maxTs = -1;
    for (final m in inserted) {
      if (m.timestamp > maxTs) maxTs = m.timestamp;
    }

    // Notify dispatcher with inserted messages only.
    // Only dispatch if the agent is not tombstoned (resolver returns non-null).
    if (resolveAgent('', agent.remoteId) != null) {
      await dispatcher.handlePulledMessages(
        messages: inserted,
        resolveAgent: resolveAgent,
      );
    }

    return SyncAgentResult(insertedCount: inserted.length, maxTimestamp: maxTs);
  }
}

/// Result of syncing a single agent.
class SyncAgentResult {
  final int insertedCount;
  final int maxTimestamp;
  final bool failed;

  const SyncAgentResult({
    required this.insertedCount,
    required this.maxTimestamp,
    this.failed = false,
  });
}
