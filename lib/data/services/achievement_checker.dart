import 'dart:async';
import 'dart:collection';

import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
// `@visibleForTesting` annotation — explicit dep on package:meta in pubspec.
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

  /// Exposed for cap-bound eviction tests. The `debug` prefix is the
  /// Dart convention for "test-only public API surface" — keeps the
  /// signal even though [@visibleForTesting] is applied. Public so tests
  /// can assert the current tuning constants without going through a
  /// getter wrapper (compile-time const is cheaper than a getter call).
  @visibleForTesting
  static const debugMinInterval = _minInterval;

  @visibleForTesting
  static const debugMaxAge = _maxAge;

  @visibleForTesting
  static const debugMaxEntries = _maxEntries;

  /// Read-only debug view of [_lastChecks] for direct assertion in tests.
  ///
  /// **Live view, not a snapshot.** Backed by [UnmodifiableMapView], so the
  /// returned map reflects all subsequent mutations of the debounce map
  /// (inserts, eviction sweep, `dispose().clear()`) through the same
  /// reference. Use `Map.unmodifiable(_lastChecks)` instead if you need a
  /// detached frozen copy at a specific call site — the existing tests
  /// intentionally want the live view so dispose() empties the assertion
  /// target without re-fetching the reference.
  ///
  /// Do NOT capture this view across an intervening `check()` or
  /// `dispose()` and then assert on the captured reference's `length` —
  /// the live semantics will surprise you. Pattern of correct use:
  ///   1. `checker.check(...)` / `checker.dispose()`
  ///   2. `expect(checker.debugLastChecks, isEmpty)`  ← re-fetched here
  @visibleForTesting
  Map<String, DateTime> get debugLastChecks => UnmodifiableMapView(_lastChecks);

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
    // Post-dispose guard — calling check() after dispose() must be a no-op.
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
      // Always compute fresh stats — no cache layer.
      await _useCase.execute(agentId);
      // 通知订阅者（profile VM 等）该 agent 的 stats 已是最新值，可以
      // 拉自己一份新快照。仅在成功时通知——失败时让下一条消息自然触发
      // 下一次 check() 重试，避免堆积无效通知风暴。
      //
      // Post-await isClosed guard: dispose() may fire while _useCase.execute
      // is in flight, closing _updates between the await and this line.
      // [check]'s top-level isClosed guard only protects synchronous entry;
      // this guard closes the in-flight gap so a disposed checker is silent
      // on BOTH the updates stream AND the logger (T-LIFECYCLE-01).
      if (!_updates.isClosed) _updates.add(agentId);
    } catch (e, st) {
      // Best-effort — 成就检查失败不得影响聊天流程
      _logger.error('Achievement check failed for $agentId: $e', st);
    }
  }
}
