import '../models/agent_stats.dart';
import '../models/achievement.dart';

/// 成就仓库抽象接口
///
/// 定义成就数据（解锁记录 + 实时聚合统计）的读取操作。
/// 实现在 data/repositories/drift_achievement_repo.dart 中。
abstract class IAchievementRepo {
  /// 获取某 Agent 的成就列表（含解锁状态）
  Future<List<Achievement>> getUnlocks(String agentId);

  /// 批量解锁 + 返回最新成就列表，在单个事务内完成。
  ///
  /// 避免逐条 INSERT（N+1 写入）和 unlock→get 之间的竞态窗口。
  /// [achievementIds] 为空时直接返回当前列表（不开启事务）。
  Future<List<Achievement>> batchUnlock(
    String agentId,
    Set<String> achievementIds,
  );

  /// 从原始消息/工具调用数据全量聚合计算统计数据。
  ///
  /// 始终走实时聚合（COUNT DISTINCT, MIN/MAX, day buckets 等），不读缓存。
  /// 3B 起无缓存层 —— 此前 `agent_stats` 缓存表已删除（写无读路径）。
  Future<AgentStats> computeStats(String agentId);
}
