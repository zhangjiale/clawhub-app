import '../models/agent_stats.dart';
import '../models/achievement.dart';

/// 成就仓库抽象接口
///
/// 定义成就数据（解锁记录 + 实时聚合统计）的读取操作。
/// 实现在 data/repositories/drift_achievement_repo.dart 中。
///
/// ## 设计意图：始终实时聚合，无缓存层
///
/// 接口只暴露 `computeStats`（实时全量聚合），**故意不提供** `getStats` /
/// `saveStats` 形式的预聚合缓存方法。原因：
///   - Agent 统计（totalDialogs / totalMessages / currentStreak 等）依赖
///     message / activity 表的实时数据，预聚合缓存会在消息写入和统计读取
///     之间产生一致性问题（写入成功但缓存过期）。
///   - 写入路径上多一条 cache.update 会拖慢 message 发送热路径。
///   - 评测管线（[EvaluateAchievementsUseCase]）每条 chat 消息只调用一次，
///     量级不足以触发性能优化。
///
/// **如果将来有人想加 `getStats` / `saveStats` 缓存方法**：先评估以下三条
/// 是否仍然成立，否则需要重新讨论设计（不要在没有评估的情况下"加个小优化"）：
///   1. 写入路径上增加 cache.update 的延迟是否可接受？
///   2. 缓存与 message / activity 表的一致性窗口谁来兜底？
///   3. 评测管线每条消息调一次的频率是否仍是性能瓶颈？
///
/// 这个注释等价于 [AchievementChecker._minInterval] 等常量上的 `debug`
/// 前缀：用人类可读的契约替代 runtime enforce。
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
  /// 始终走实时聚合（COUNT DISTINCT, MIN/MAX, day buckets 等），无缓存层。
  Future<AgentStats> computeStats(String agentId);
}
