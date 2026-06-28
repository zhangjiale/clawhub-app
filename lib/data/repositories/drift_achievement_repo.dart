import 'package:drift/drift.dart' show InsertMode;
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/domain/repositories/i_achievement_repo.dart';
import 'package:claw_hub/domain/utils/streak_calculator.dart';

import '../local/database/database.dart' as db;

/// Drift/SQLite implementation of [IAchievementRepo].
///
/// Achievements are unlocked via INSERT OR IGNORE into
/// achievement_unlocks. Stats are computed on-demand from raw
/// message/tool_call data — no cache layer (3B removed the write-only
/// `agent_stats` cache table).
class DriftAchievementRepo implements IAchievementRepo {
  final db.AppDatabase _database;

  DriftAchievementRepo(this._database);

  // ---------------------------------------------------------------------------
  // Achievement unlocks
  // ---------------------------------------------------------------------------

  @override
  Future<List<Achievement>> getUnlocks(String agentId) async {
    final rows = await _database.getAchievementUnlocksForAgent(agentId).get();
    return _buildFromRows(rows);
  }

  @override
  Future<List<Achievement>> batchUnlock(
    String agentId,
    Set<String> achievementIds,
  ) async {
    if (achievementIds.isEmpty) {
      return getUnlocks(agentId);
    }

    return _database.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Bulk insert via batch API — single round-trip instead of N+1 writes.
      // Achievement count is bounded (< 10) so perf gain is marginal, but
      // batch() is the correct pattern for multi-row inserts.
      await _database.batch((batch) {
        for (final id in achievementIds) {
          batch.insert(
            _database.achievementUnlocks,
            db.AchievementUnlocksCompanion.insert(
              achievementId: id,
              agentId: agentId,
              unlockedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
      // 在同事务内读取最新列表，关闭竞态窗口
      final rows = await _database.getAchievementUnlocksForAgent(agentId).get();
      return _buildFromRows(rows);
    });
  }

  /// Build [Achievement] list from raw unlock rows.
  List<Achievement> _buildFromRows(List<db.AchievementUnlock> rows) {
    final unlockedIds = rows.map((r) => r.achievementId).toSet();
    final unlockedAtMap = <String, int>{
      for (final r in rows) r.achievementId: r.unlockedAt,
    };
    return buildAchievementList(unlockedIds, unlockedAtMap);
  }

  // ---------------------------------------------------------------------------
  // Stats computation
  // ---------------------------------------------------------------------------

  @override
  Future<AgentStats> computeStats(String agentId) async {
    // Transaction keeps the 3 queries on the same snapshot for consistency.
    // Merged query replaces 3 separate messages-table scans (countDialogs,
    // getMessageCount, getTimestampRange) with one.
    return _database.transaction(() async {
      final results = await Future.wait([
        _database.getMessageStatsForAgent(agentId),
        _database.countToolCallsForAgent(agentId),
        _database.getActiveDayBucketsForAgent(agentId),
      ]);

      final msgStats =
          results[0]
              as ({int dialogs, int messages, int? firstMsg, int? lastMsg})?;
      final totalToolCalls = results[1] as int;
      final dayBuckets = results[2] as List<int>;

      return AgentStats(
        agentId: agentId,
        totalDialogs: msgStats?.dialogs ?? 0,
        totalMessages: msgStats?.messages ?? 0,
        totalToolCalls: totalToolCalls,
        activeDays: dayBuckets.length,
        // Fix: previous code used `now ~/ 86400` (seconds) while SQL
        // uses `timestamp / 86400000` (ms), causing currentStreak to
        // always be 0. Both sides now use millisecond day-indexes.
        currentStreak: computeCurrentStreak(
          dayBuckets,
          todayBucket: DateTime.now().millisecondsSinceEpoch ~/ 86400000,
        ),
        firstDialogDate: msgStats?.firstMsg,
        lastDialogDate: msgStats?.lastMsg,
      );
    });
  }
}
