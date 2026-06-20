import 'package:drift/drift.dart' show InsertMode;
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/domain/repositories/i_achievement_repo.dart';

import '../local/database/database.dart' as db;

/// Drift/SQLite implementation of [IAchievementRepo].
///
/// Stats are pre-computed from raw message/tool_call data and cached in the
/// agent_stats table. Achievements are unlocked via INSERT OR IGNORE into
/// achievement_unlocks.
class DriftAchievementRepo implements IAchievementRepo {
  final db.AppDatabase _database;

  DriftAchievementRepo(this._database);

  // ---------------------------------------------------------------------------
  // Stats cache
  // ---------------------------------------------------------------------------

  @override
  Future<AgentStats?> getStats(String agentId) async {
    final row = await _database.getAgentStats(agentId).getSingleOrNull();
    if (row == null) return null;
    return AgentStats(
      agentId: row.agentId ?? agentId,
      totalDialogs: row.totalDialogs,
      totalMessages: row.totalMessages,
      totalToolCalls: row.totalToolCalls,
      activeDays: row.activeDays,
      currentStreak: row.currentStreak,
      firstDialogDate: row.firstDialogDate,
      lastDialogDate: row.lastDialogDate,
    );
  }

  @override
  Future<void> saveStats(AgentStats stats) async {
    await _database.upsertAgentStats(
      stats.agentId,
      stats.totalDialogs,
      stats.totalMessages,
      stats.totalToolCalls,
      stats.activeDays,
      stats.currentStreak,
      stats.firstDialogDate,
      stats.lastDialogDate,
    );
  }

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
        currentStreak: _computeStreak(dayBuckets),
        firstDialogDate: msgStats?.firstMsg,
        lastDialogDate: msgStats?.lastMsg,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Streak computation (pure, Dart-side)
  // ---------------------------------------------------------------------------

  /// Compute consecutive days from the most recent day bucket backward.
  ///
  /// [dayBuckets] are Unix day-indexes (timestamp / 86400) in ascending
  /// order. Returns the count of consecutive days ending at the most recent
  /// bucket (or ending today if the most recent bucket is today).
  static int _computeStreak(List<int> dayBuckets) {
    if (dayBuckets.isEmpty) return 0;

    // Today's bucket (UTC calendar date converted to day index)
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final todayBucket = now ~/ 86400;

    // Walk backward from today. If today has messages, start from today;
    // otherwise start from the most recent day bucket (even if it's
    // yesterday — that's still a streak starting from yesterday).
    int expectedBucket;
    if (dayBuckets.last == todayBucket) {
      expectedBucket = todayBucket;
    } else if (dayBuckets.last == todayBucket - 1) {
      // Most recent message was yesterday — valid streak anchor
      expectedBucket = todayBucket - 1;
    } else {
      // Gap >1 day from today — streak is broken, just count the
      // single most-recent day
      return 1;
    }

    int streak = 0;
    for (var i = dayBuckets.length - 1; i >= 0; i--) {
      if (dayBuckets[i] == expectedBucket) {
        streak++;
        expectedBucket--;
      } else if (dayBuckets[i] < expectedBucket) {
        // Gap found — streak broken
        break;
      }
    }

    return streak;
  }
}
