import 'dart:async';

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
///
/// **F4 修复 — per-agentId 串行化**：当两个调用方（chat-message
/// `AchievementChecker` + profile-page `vm.achievementRefresh`）几乎同时
/// 触发 `execute(agentId)` 时，串行化保证第二个调用看到第一个调用已
/// 写入的 unlocks 状态，从而返回空的 `freshUnlocks`。否则两边都读到
/// `existingUnlocks=[]`、都调 `batchUnlock`、都返回 `freshUnlocks=
/// [achievement]`，UI 庆祝动画会重复触发（详见
/// `evaluate_achievements_test.dart` 的 `T-CONCURRENT-DEDUP` 用例）。
class EvaluateAchievementsUseCase {
  final IAchievementRepo _repo;

  /// F4: in-flight tracking per agentId. 当同 agentId 有未完成调用时，
  /// 后续调用 await 它结束后再启动 fresh call,而不是并发跑(否则两边都
  /// 看不到对方的写入)。Map value 用 future 而非 Completer,让 try/catch
  /// 集中在调用点。
  final Map<String, Future<EvaluateAchievementsResult>> _inFlight = {};

  // 非 const 构造函数：F4 加入 _inFlight 状态字段后,无法维持原 const。
  // 调用方 (DI provider) 一次性构造,无 perf 影响。
  EvaluateAchievementsUseCase(this._repo);

  /// 执行成就评估管线。
  ///
  /// 1. 走 [IAchievementRepo.computeStats] 全量聚合计算 stats — 始终实时
  ///    聚合，无缓存层。
  /// 2. 获取已解锁成就列表，过滤出尚未解锁的预设成就。
  /// 3. 若有新成就，通过 [IAchievementRepo.batchUnlock] 原子写入。
  /// 4. 返回 [EvaluateAchievementsResult]。
  ///
  /// 异常直接传播给调用方（不在此处静默）。
  ///
  /// **F4 串行化**：同 agentId 的并发调用按到达顺序串行执行,每个调用都
  /// 是独立的 fresh read(不复用前一个 future 的结果,因为调用方需要最新
  /// stats/achievements)。第一个调用获得 `freshUnlocks`,后续调用读到已
  /// 更新状态 → `freshUnlocks=[]` → 不会触发重复 UI 庆祝。
  Future<EvaluateAchievementsResult> execute(String agentId) async {
    // F4: 先 await 同 agentId 的 in-flight call(若有),确保它的事务边界
    // (commit batchUnlock) 已落地,本调用读 existingUnlocks 时能看到结果。
    // 即使前一个调用抛错,我们也继续跑 fresh call —— 不让一个失败污染后续。
    final previous = _inFlight[agentId];
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // swallow: 失败不应阻塞后续调用,即使前一个调用抛错也继续
      }
    }

    // 直接用 _doExecute 返回的 future 作为 in-flight 标记 —— 不另起 Completer。
    // Completer 方案会让 in-flight future 的 error 在未被 await 时变成 unhandled
    // async error,污染测试运行时。直接 future 让 error 自然沿着 await 链路传播。
    final future = _doExecute(agentId);
    _inFlight[agentId] = future;
    try {
      return await future;
    } finally {
      // 双重检查:确保移除的是自己的 future(防御 _inFlight 已被重新赋值的边界)
      if (_inFlight[agentId] == future) {
        _inFlight.remove(agentId);
      }
    }
  }

  /// 实际执行评估的私有方法 —— F4 串行化包装后的核心逻辑。
  Future<EvaluateAchievementsResult> _doExecute(String agentId) async {
    // computeStats and getUnlocks are independent reads — run concurrently.
    final (stats, existingUnlocks) = await (
      _repo.computeStats(agentId),
      _repo.getUnlocks(agentId),
    ).wait;
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
