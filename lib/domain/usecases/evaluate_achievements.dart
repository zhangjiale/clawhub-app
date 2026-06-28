import '../models/agent_stats.dart';
import '../models/achievement.dart';
import '../repositories/i_achievement_repo.dart';

/// 成就评估结果 — 封装一次完整的「读缓存→评估→解锁」流程的输出。
class EvaluateAchievementsResult {
  /// 本次使用的统计数据（可能来自缓存或新计算）。
  final AgentStats stats;

  /// 全部 8 个成就（含已锁和未锁），按 tier 降序排列。
  final List<Achievement> achievements;

  /// 本次调用中新解锁的成就（用于 UI 庆祝动画）。
  final List<Achievement> freshUnlocks;

  const EvaluateAchievementsResult({
    required this.stats,
    required this.achievements,
    this.freshUnlocks = const [],
  });
}

/// 成就评估用例 — 封装「统计数据计算 → 成就评估 → 批量解锁」的完整管线。
///
/// 消除 [AgentProfileViewModel] 与 [AchievementChecker] 之间的重复逻辑。
///
/// 所有 DB 操作在同一事务语义下执行（由 [IAchievementRepo] 实现保证），
/// 异常直接向上传播，由调用方决定如何处理（ViewModel 显示错误 UI，
/// AchievementChecker 静默记录日志）。
class EvaluateAchievementsUseCase {
  final IAchievementRepo _repo;

  const EvaluateAchievementsUseCase(this._repo);

  /// 执行成就评估管线。
  ///
  /// 1. 走 [IAchievementRepo.computeStats] 全量聚合计算 stats — 始终实时
  ///    聚合，无缓存层（3A 删除 forceRecompute + cache-first 分支，3B 删除
  ///    `agent_stats` 缓存表与 saveStats/getStats 接口）。
  /// 2. 获取已解锁成就列表，过滤出尚未解锁的预设成就。
  /// 3. 若有新成就，通过 [IAchievementRepo.batchUnlock] 原子写入。
  /// 4. 返回 [EvaluateAchievementsResult]。
  ///
  /// 异常直接传播给调用方（不在此处静默）。
  Future<EvaluateAchievementsResult> execute(String agentId) async {
    final stats = await _repo.computeStats(agentId);

    final existingUnlocks = await _repo.getUnlocks(agentId);
    final unlockedIds = existingUnlocks
        .where((a) => a.unlocked)
        .map((a) => a.id)
        .toSet();

    final newDefs = evaluateNewAchievements(stats, unlockedIds);

    // Default to existing unlocks so the caller always sees a valid list
    // even if batchUnlock fails downstream.
    List<Achievement> achievements = existingUnlocks;
    List<Achievement> freshUnlocks = const [];

    if (newDefs.isNotEmpty) {
      final newIds = newDefs.map((d) => d.id).toSet();
      achievements = await _repo.batchUnlock(agentId, newIds);
      freshUnlocks = achievements
          .where((a) => a.unlocked && newIds.contains(a.id))
          .toList();
    }

    return EvaluateAchievementsResult(
      stats: stats,
      achievements: achievements,
      freshUnlocks: freshUnlocks,
    );
  }
}
