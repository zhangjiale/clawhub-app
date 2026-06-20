import '../models/agent_stats.dart';
import '../models/achievement.dart';

/// 成就仓库抽象接口
///
/// 定义成就数据（统计缓存 + 解锁记录）的读取和写入操作。
/// 实现在 data/repositories/drift_achievement_repo.dart 中。
abstract class IAchievementRepo {
  /// 获取缓存的统计数据，若无则为 null
  Future<AgentStats?> getStats(String agentId);

  /// 保存统计数据到缓存
  Future<void> saveStats(AgentStats stats);

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

  /// 从原始数据聚合计算统计数据
  ///
  /// 不读缓存 — 始终执行全量聚合查询（COUNT DISTINCT, MIN/MAX 等）。
  /// 调用方负责在计算后将结果通过 [saveStats] 持久化。
  Future<AgentStats> computeStats(String agentId);
}
