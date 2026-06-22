import 'package:claw_hub/domain/models/daily_activity.dart';
import 'package:claw_hub/domain/repositories/i_activity_repo.dart';
import 'package:drift/drift.dart' show Variable;

import '../local/database/database.dart' as db;

/// Drift/SQLite implementation of [IActivityRepo].
///
/// 单次 SQL 聚合 + Dart 端补全空日 — Law 6 批量,无 N+1。
/// 不动 `agent_stats` 缓存表(30 天数组入缓存成本太高,新鲜查询即可)。
class DriftActivityRepo implements IActivityRepo {
  final db.AppDatabase _database;

  DriftActivityRepo(this._database);

  @override
  Future<List<DailyActivity>> getDailyActivity(
    String agentId, {
    int days = 30,
    DateTime? now,
  }) async {
    final anchor = (now ?? DateTime.now()).toUtc();
    final todayBucket = anchor.millisecondsSinceEpoch ~/ 86400000;
    final minBucket = todayBucket - (days - 1);

    // 单次 SQL 聚合(Law 6):按 day_bucket 分组 + 过滤窗口边界。
    // `idx_msgs_agent` 索引覆盖 agent_id 过滤。
    final rows = await _database
        .customSelect(
          'SELECT (timestamp / 86400000) AS day_bucket, COUNT(*) AS cnt '
          'FROM messages WHERE agent_id = ? '
          'AND (timestamp / 86400000) >= ? '
          'GROUP BY day_bucket '
          'ORDER BY day_bucket ASC',
          variables: [
            Variable.withString(agentId),
            Variable.withInt(minBucket),
          ],
        )
        .map(
          (row) => (
            dayBucket: row.read<int>('day_bucket'),
            count: row.read<int>('cnt'),
          ),
        )
        .get();

    // Dart 端补全空日(纯 loop,无 DB 压力,30 次迭代可忽略)
    final byBucket = <int, int>{for (final r in rows) r.dayBucket: r.count};
    return List.generate(days, (i) {
      final bucket = minBucket + i;
      return DailyActivity(
        agentId: agentId,
        dayBucket: bucket,
        messageCount: byBucket[bucket] ?? 0,
      );
    });
  }
}
