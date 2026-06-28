// package:meta is pulled in transitively (flutter SDK + every Flutter
// plugin), so we use the annotation without taking an explicit dep on it.
// Suppress the lint to avoid a pubspec churn for what is effectively a
// zero-cost const annotation.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
// `@visibleForTesting` annotation — package:meta is transitive dep.
import 'package:meta/meta.dart';

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

  /// 成功完成一次重新评估后，向订阅者广播 agentId。
  ///
  /// 用于通知关注此 agent 的 UI（例如 [AgentProfileViewModel]）刷新其
  /// 缓存的快照。否则 profile 页只在 init()/refresh() 时拉一次数据，
  /// 后续新消息到达后用户看到的还是旧的全 0 状态。
  final StreamController<String> _updates =
      StreamController<String>.broadcast();

  static const _minInterval = Duration(seconds: 5);
  static const _maxAge = Duration(minutes: 30);
  static const _maxEntries = 50;

  /// Read-only debug view of [_lastChecks] for direct assertion in tests.
  ///
  /// T-LIFECYCLE-04 strengthening: dispose must clear the debounce map, but
  /// the previous round-2 test verified this only INDIRECTLY (a fresh
  /// checker firing on a never-seen agentId). That style of test would pass
  /// even if dispose() forgot to call `_lastChecks.clear()` — provided a
  /// different agentId was used. This getter lets tests assert the
  /// disposed instance's map is literally empty.
  @visibleForTesting
  Map<String, DateTime> get debugLastChecks => Map.unmodifiable(_lastChecks);

  /// Read-only debug accessors for the eviction constants — tests need
  /// these to assert cap-bound eviction without hardcoding 50/30min/5s
  /// literals (so future tuning of these constants is reflected
  /// automatically in the test).
  @visibleForTesting
  static int get debugMaxEntries => _maxEntries;

  @visibleForTesting
  static Duration get debugMaxAge => _maxAge;

  @visibleForTesting
  static Duration get debugMinInterval => _minInterval;

  AchievementChecker(this._useCase, this._logger);

  @override
  Stream<String> get updates => _updates.stream;

  /// 关停广播流。Riverpod provider 持有单例，App 生命周期内通常不调用；
  /// 保留接口供将来 autoDispose 或测试收尾使用。
  void dispose() {
    _lastChecks.clear();
    if (!_updates.isClosed) _updates.close();
  }

  /// Fire-and-forget 成就重新评估。
  ///
  /// 在消息发送/接收后调用 — 不阻塞热路径。
  /// 即使 agent 的 Profile 页从未被打开过也可以安全调用。
  /// 失败时静默记录日志，不向调用方传播异常。
  @override
  void check(String agentId) {
    // Guard: post-dispose check() is a safe no-op. Without this, _lastChecks
    // gets written and an unawaited future fires on a closed controller
    // (caught by T-LIFECYCLE-03). Tests-as-design-tool discovery.
    if (_updates.isClosed) return;
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
      // Always compute fresh stats (no cache read path — 3A removed the
      // forceRecompute parameter because both callers always passed true,
      // making it a misleading API).
      await _useCase.execute(agentId);
      // 通知订阅者（profile VM 等）该 agent 的 stats 已是最新值，可以
      // 拉自己一份新快照。仅在成功时通知——失败时让下一条消息自然触发
      // 下一次 check() 重试，避免堆积无效通知风暴。
      if (!_updates.isClosed) _updates.add(agentId);
    } catch (e, st) {
      // Best-effort — 成就检查失败不得影响聊天流程
      _logger.error('Achievement check failed for $agentId: $e', st);
    }
  }
}
