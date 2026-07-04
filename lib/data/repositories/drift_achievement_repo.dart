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
/// message/tool_call data — no cache layer.
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
    // F5: 三个 SELECT 是独立读,不需要 snapshot consistency。stat 是用户视图,
    // 边界场景(读 1 与读 2 之间新增消息)造成的轻微不一致可接受。原本包在
    // _database.transaction() 里有两个问题:
    //   1. Drift transaction 在单连接上 BEGIN,Future.wait 在同一连接上
    //      串行执行 —— claim 是 cosmetic parallelism。
    //   2. 阻碍未来多连接 pool 的真正并行 (Drift NativeDatabase 默认单
    //      连接,但若未来调 connectionPool 即可生效)。
    //
    // 移出 transaction 后,3 SELECT 各自从 pool 取连接、并发调度。Behavior
    // 对外不变 (return 值仍一致,只要不是 strict-snapshot 场景)。
    final results = await Future.wait([
      _database.getMessageStatsForAgent(agentId),
      _database.countToolCallsForAgent(agentId),
      _database.getActiveDayBucketsForAgent(agentId),
    ]);

    final msgStats =
        results[0]
            as ({int dialogs, int messages, int? firstMsg, int? lastMsg});
    final totalToolCalls = results[1] as int;
    final dayBuckets = results[2] as List<int>;

    return AgentStats(
      agentId: agentId,
      // 数据库层的 getMessageStatsForAgent 已经收紧为非空 aggregate
      // (database.dart 注释解释了 SQL 永远返回一行)。之前 `?? 0` 是
      // 防御型可达性为零的死代码——一个未来 SQL 改动让它真正可触达时,
      // 会直接 0/0 静默穿透。现类型层面保证调用方要么拿到真值,要么让
      // SQLite 抛错。
      totalDialogs: msgStats.dialogs,
      totalMessages: msgStats.messages,
      totalToolCalls: totalToolCalls,
      activeDays: dayBuckets.length,
      // 上下游都用 millisecond day-indexes (86400000 ms)。原 spec 用了
      // `now ~/ 86400`(秒),与 SQL `/86400000`(毫秒)错位 → currentStreak
      // 永远 0。Fix 已合入 (#fixed in prior round)。
      currentStreak: computeCurrentStreak(
        dayBuckets,
        todayBucket: DateTime.now().millisecondsSinceEpoch ~/ 86400000,
      ),
      // firstMsg / lastMsg 合法可以为 null (零活动) —— 与 dialogs /
      // messages 区别在于语义,不是反 defensive-skip。
      firstDialogDate: msgStats.firstMsg,
      lastDialogDate: msgStats.lastMsg,
    );
  }
}
