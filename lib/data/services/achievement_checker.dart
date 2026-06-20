import 'dart:async';

import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';

/// 独立的成就检查服务 — 不继承 StateNotifier，不持有 UI 状态。
///
/// 依赖 [EvaluateAchievementsUseCase] 执行「缓存优先→评估→批量解锁」管线，
/// 与 [AgentProfileViewModel] 共享同一用例，消除重复逻辑。
/// 与 [AgentProfileViewModel] 完全解耦：聊天热路径不会初始化 Profile 页的
/// ViewModel 及其完整数据加载生命周期。
class AchievementChecker implements IAchievementChecker {
  final EvaluateAchievementsUseCase _useCase;
  final ILogger _logger;

  /// Per-agent 防抖：记录每个 agent 上次检查的时间，避免快速连续消息
  /// 触发重复的 computeStats 查询。
  ///
  /// 容量超过 [_maxEntries] 时自动驱逐超过 [_maxAge] 的陈旧条目，
  /// 防止长时间会话中 Map 无限增长。
  final Map<String, DateTime> _lastChecks = {};

  static const _minInterval = Duration(seconds: 5);
  static const _maxAge = Duration(minutes: 30);
  static const _maxEntries = 50;

  AchievementChecker(this._useCase, this._logger);

  /// Fire-and-forget 成就重新评估。
  ///
  /// 在消息发送/接收后调用 — 不阻塞热路径。
  /// 即使 agent 的 Profile 页从未被打开过也可以安全调用。
  /// 失败时静默记录日志，不向调用方传播异常。
  @override
  void check(String agentId) {
    final now = DateTime.now();

    // Evict stale entries when the map grows beyond the cap.
    if (_lastChecks.length >= _maxEntries) {
      _lastChecks.removeWhere((_, t) => now.difference(t) > _maxAge);
    }

    final last = _lastChecks[agentId];
    if (last != null && now.difference(last) < _minInterval) {
      return; // 短时间内已检查过，跳过
    }
    _lastChecks[agentId] = now;
    unawaited(_checkAsync(agentId));
  }

  Future<void> _checkAsync(String agentId) async {
    try {
      // Delegate to shared use case — same pipeline as the Profile VM.
      await _useCase.execute(agentId);
    } catch (e, st) {
      // Best-effort — 成就检查失败不得影响聊天流程
      _logger.error('Achievement check failed for $agentId: $e', st);
    }
  }
}
