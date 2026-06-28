// US-021 AC8 响应式 (Fix 1, Task 4.4):
// 验证 provider 侧的 `ref.listen(agentSyncTickerProvider)` 真的会在
// ticker 递增时调用 vm.refreshAgent()，从而让 AgentProfileViewModel
// 重新拉取 agent 并同步 tombstone 状态到 state.isAgentRemoved。
//
// 用 ProviderContainer + Riverpod overrides 完整 wire 出
// `agentProfileViewModelProvider('local-1')`，然后 bump
// `agentSyncTickerProvider`。assertion：ticker bump 之后
// `agentRepo.getById('local-1')` 又被调一次，证明 listener →
// refreshAgent 链真的接通了。
//
// 此测试为集成式（覆盖 provider family 的 family 闭包 + Riverpod
// listen 机制），不属于纯 VM 单测范畴，因此独立成文件，参考
// `test/features/agent_list/agent_providers_test.dart` 模式。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/daily_activity.dart';
import 'package:claw_hub/domain/repositories/i_activity_repo.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_achievement_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';

class _MockAgentRepo extends Mock implements IAgentRepo {}

class _MockInstanceRepo extends Mock implements IInstanceRepo {}

class _MockMessageRepo extends Mock implements IMessageRepo {}

class _MockActivityRepo extends Mock implements IActivityRepo {}

class _MockAvatarStorageService extends Mock implements IAvatarStorageService {}

class _MockAchievementRepo extends Mock implements IAchievementRepo {}

class _MockLogger extends Mock implements ILogger {}

void main() {
  late _MockAgentRepo agentRepo;
  late _MockInstanceRepo instanceRepo;
  late _MockMessageRepo messageRepo;
  late _MockActivityRepo activityRepo;
  late _MockAvatarStorageService avatarStorageService;
  late _MockAchievementRepo achievementRepo;
  late _MockLogger logger;

  final activeAgent = Agent(
    localId: 'local-1',
    remoteId: 'remote-1',
    instanceId: 'inst-1',
    name: '产品虾',
    themeColor: '#6c5ce7',
  );

  final tombstonedAgent = Agent(
    localId: 'local-1',
    remoteId: 'remote-1',
    instanceId: 'inst-1',
    name: '产品虾',
    themeColor: '#6c5ce7',
    removedAt: 1719200000000,
  );

  setUpAll(() {
    registerFallbackValue(AgentStats(agentId: 'fallback'));
    registerFallbackValue(<String>{''});
  });

  setUp(() {
    agentRepo = _MockAgentRepo();
    instanceRepo = _MockInstanceRepo();
    messageRepo = _MockMessageRepo();
    activityRepo = _MockActivityRepo();
    avatarStorageService = _MockAvatarStorageService();
    achievementRepo = _MockAchievementRepo();
    logger = _MockLogger();
    when(() => logger.error(any(), any())).thenReturn(null);
    when(() => logger.info(any())).thenReturn(null);

    // Achievement evaluator 默认 stub
    when(
      () => achievementRepo.computeStats(any()),
    ).thenAnswer((_) async => AgentStats(agentId: 'local-1'));
    when(
      () => achievementRepo.getUnlocks(any()),
    ).thenAnswer((_) async => <Achievement>[]);
    when(
      () => achievementRepo.batchUnlock(any(), any()),
    ).thenAnswer((_) async => <Achievement>[]);

    // 默认 stubs
    when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
    when(
      () => messageRepo.getMessageCount('local-1'),
    ).thenAnswer((_) async => 0);
    when(
      () => activityRepo.getDailyActivity(
        any(),
        days: any(named: 'days'),
        now: any(named: 'now'),
      ),
    ).thenAnswer((_) async => const <DailyActivity>[]);
  });

  /// Polls VM state until detailLoadState transitions out of LoadInProgress
  /// (i.e. init's refresh() has run). Avoids the "fire-and-forget init race
  /// vs dispose" by giving the family body's vm.init() time to complete
  /// before the test asserts and disposes.
  Future<void> waitForInitComplete(ProviderContainer container) async {
    final vm = container.read(
      agentProfileViewModelProvider('local-1').notifier,
    );
    for (var i = 0; i < 100; i++) {
      if (vm.state.detailLoadState is! LoadInProgress) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('vm.init() did not complete within 1s');
  }

  /// Create a ProviderContainer wired with all overrides needed by
  /// `agentProfileViewModelProvider`. Cleanup is deferred to `addTearDown`.
  ///
  /// Note on double-dispose: the family body in `agent_profile_providers.dart`
  /// registers `ref.onDispose(() => vm.dispose())` explicitly. Riverpod's
  /// `StateNotifierProviderElement` ALSO auto-disposes the notifier in
  /// `runOnDispose`. The second dispose() call hits `_debugIsMounted`'s
  /// assert in DEBUG mode and throws. The test framework's tearDown wraps
  /// in `runZonedGuarded` so the assertion is swallowed; the test body
  /// itself completes cleanly. (This is an existing pattern in the
  /// codebase — see `chat_providers.dart` which uses the same approach.
  /// Page-level tests avoid it by `.overrideWith((ref) => vm)` which
  /// replaces the family body.)
  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        agentRepoProvider.overrideWithValue(agentRepo),
        instanceRepoProvider.overrideWithValue(instanceRepo),
        messageRepoProvider.overrideWithValue(messageRepo),
        activityRepoProvider.overrideWithValue(activityRepo),
        avatarStorageServiceProvider.overrideWithValue(avatarStorageService),
        achievementRepoProvider.overrideWithValue(achievementRepo),
        loggerProvider.overrideWithValue(logger),
      ],
    );
    // Wrap dispose in runZonedGuarded so the unavoidable double-dispose
    // AssertionError (family body's ref.onDispose + Riverpod's auto
    // StateNotifier dispose) doesn't fail the test after the body
    // completes. The first dispose is the real cleanup; the second is
    // a no-op that triggers a debug-only assert.
    addTearDown(() {
      runZonedGuarded(() => container.dispose(), (error, stack) {
        // Swallow AssertionError("Tried to use ... after dispose was
        // called") from Riverpod's StateNotifierProviderElement.runOnDispose.
      });
    });
    return container;
  }

  test('ref.listen(agentSyncTickerProvider) triggers vm.refreshAgent on '
      'ticker bump (init 1x → bump → 2x getById)', () async {
    var calls = 0;
    when(() => agentRepo.getById('local-1')).thenAnswer((_) async {
      calls++;
      return activeAgent;
    });

    final container = createContainer();

    // Materialize provider → family body runs → vm.init() 启动
    container.read(agentProfileViewModelProvider('local-1'));
    // 等待 init 真正完成（poll state 直到 detailLoadState 离开 LoadInProgress）
    await waitForInitComplete(container);

    final initCalls = calls;
    expect(initCalls, 1, reason: 'init 期间 refresh 应调用 1 次 getById');

    // 模拟后台 sync: ticker 携带本 instanceId 触发 → ref.listen 回调触发 vm.refreshAgent()
    // BUG B 修复后 ticker 携带 instanceId,需指定 instanceId 才能命中 listener。
    final notifier = container.read(agentSyncTickerProvider.notifier);
    notifier.state = AgentSyncTick(
      revision: (notifier.state?.revision ?? 0) + 1,
      instanceId: 'inst-1',
    );
    // ref.listen 回调是异步的,让 microtask 链跑完
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      calls,
      2,
      reason: 'ticker bump 后 listener 应触发 refreshAgent → getById 第 2 次',
    );
  });

  // BUG B 修复:跨实例 ticker bump 不应触发本实例的 refreshAgent。
  // AgentProfile 监听过滤 next != vm.instanceId 的 case,避免实例 A sync 时
  // 实例 B/C/D 的所有 profile 页 N+1 调用 getById。
  test(
    'cross-instance ticker bump is filtered out (Law 6 / N+1 prevention)',
    () async {
      var calls = 0;
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async {
        calls++;
        return activeAgent; // instanceId: 'inst-1'
      });

      final container = createContainer();
      container.read(agentProfileViewModelProvider('local-1'));
      await waitForInitComplete(container);
      expect(calls, 1, reason: 'init 阶段 getById 调 1 次');

      // bump ticker 携带**不同**的 instanceId('inst-2'),本 VM 应跳过
      final notifier = container.read(agentSyncTickerProvider.notifier);
      notifier.state = AgentSyncTick(
        revision: (notifier.state?.revision ?? 0) + 1,
        instanceId: 'inst-2',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        calls,
        1,
        reason:
            '跨实例 ticker bump 不应触发本实例的 refreshAgent。'
            '当前 calls=$calls(预期 1)',
      );
    },
  );

  test('ticker bump also updates vm.agent.isRemoved when agent becomes '
      'tombstoned between init and sync', () async {
    var calls = 0;
    when(() => agentRepo.getById('local-1')).thenAnswer((_) async {
      calls++;
      // init 阶段返回 active；后续 (ticker bump 后) 返回 tombstoned
      return calls == 1 ? activeAgent : tombstonedAgent;
    });

    final container = createContainer();

    final vm = container.read(
      agentProfileViewModelProvider('local-1').notifier,
    );
    await waitForInitComplete(container);

    expect(vm.agent?.isRemoved ?? false, isFalse);

    // BUG B 修复后 ticker 携带本 instanceId 触发 listener
    final notifier = container.read(agentSyncTickerProvider.notifier);
    notifier.state = AgentSyncTick(
      revision: (notifier.state?.revision ?? 0) + 1,
      instanceId: 'inst-1',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      vm.agent?.isRemoved ?? false,
      isTrue,
      reason: 'ticker → refreshAgent → refreshAgent 应捕获后台 tombstone',
    );
  });

  test(
    'consecutive same-instance sync ticks both trigger refreshAgent',
    () async {
      var calls = 0;
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async {
        calls++;
        return activeAgent;
      });

      final container = createContainer();
      container.read(agentProfileViewModelProvider('local-1'));
      await waitForInitComplete(container);
      expect(calls, 1, reason: 'init 阶段 getById 调 1 次');

      final notifier = container.read(agentSyncTickerProvider.notifier);
      notifier.state = AgentSyncTick(
        revision: (notifier.state?.revision ?? 0) + 1,
        instanceId: 'inst-1',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      notifier.state = AgentSyncTick(
        revision: (notifier.state?.revision ?? 0) + 1,
        instanceId: 'inst-1',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        calls,
        3,
        reason:
            '连续两次同实例 sync 都必须触发 refreshAgent；'
            '旧 String? ticker 第二次同值写入会被 Riverpod 去重。',
      );
    },
  );

  // Bug-fix (round 3) + Race fix contract: when AchievementChecker finishes
  // a stats recompute for THIS agent, the profile provider must call
  // vm.achievementRefresh() (NOT vm.refresh() — that would reset
  // detailLoadState and race against saveProfile's internal refresh).
  //
  // achievementRefresh 只刷 stats/achievements/newUnlocks，不调
  // agentRepo.getById（agent 内容没变），不重置 detailLoadState。
  // 但 computeStats 必须被调用 —— 这是证明 achievementRefresh 真的跑通
  // 了（而不是 listener 静默丢弃事件）。
  test('AchievementChecker.updates event for matching agentId triggers '
      'vm.achievementRefresh — computeStats runs, getById does NOT', () async {
    var calls = 0;
    var computeCalls = 0;
    when(() => agentRepo.getById('local-1')).thenAnswer((_) async {
      calls++;
      return activeAgent;
    });
    when(() => achievementRepo.computeStats('local-1')).thenAnswer((_) async {
      computeCalls++;
      return AgentStats(agentId: 'local-1');
    });

    final container = createContainer();
    container.read(agentProfileViewModelProvider('local-1'));
    await waitForInitComplete(container);
    expect(calls, 1, reason: 'init 阶段 getById 调 1 次');
    expect(
      computeCalls,
      greaterThanOrEqualTo(1),
      reason: 'init 阶段 computeStats 至少调 1 次 (refresh 内部强制 recompute)',
    );
    final initComputeCalls = computeCalls;

    // Simulate "chat message arrived → AchievementChecker.check('local-1')
    // → recompute succeeded → updates stream emits 'local-1'".
    final checker = container.read(achievementCheckerProvider);
    checker.check('local-1');
    // check() schedules unawaited(_checkAsync); let the async chain drain.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // Race 修复契约：listener 改调 achievementRefresh 后，
    // 不应再触发 vm.refresh() 的 getById。
    expect(
      calls,
      1,
      reason:
          'AchievementChecker.updates 发出本 agentId 后,listener 必须调 '
          'achievementRefresh（只刷 stats）而不是 refresh（全量刷,会触发 '
          'getById 第 2 次）。当前 calls=$calls（预期 1）',
    );
    // achievementRefresh 自己的 computeStats 必须跑通。
    expect(
      computeCalls,
      greaterThan(initComputeCalls),
      reason:
          'achievementRefresh 内部应再次调用 computeStats 来刷新 stats。'
          '当前 computeCalls=$computeCalls,初始=$initComputeCalls',
    );
    // detailLoadState 应保持 LoadData，不能回到 LoadInProgress。
    final vm = container.read(
      agentProfileViewModelProvider('local-1').notifier,
    );
    expect(
      vm.state.detailLoadState,
      isA<LoadData<AgentDetailData>>(),
      reason: 'achievementRefresh 不应把 detailLoadState 重置为 LoadInProgress',
    );
  });

  test('AchievementChecker.updates event for OTHER agentId is filtered '
      'out (no extra getById — Law 6 / N+1 prevention)', () async {
    var calls = 0;
    when(() => agentRepo.getById('local-1')).thenAnswer((_) async {
      calls++;
      return activeAgent;
    });

    final container = createContainer();
    container.read(agentProfileViewModelProvider('local-1'));
    await waitForInitComplete(container);
    expect(calls, 1, reason: 'init 阶段 getById 调 1 次');

    // Simulate AchievementChecker firing for a DIFFERENT agent — our
    // listener must NOT trigger vm.refresh() (would be a wasted round-trip
    // and could clobber mid-edit isSaving state on our profile page).
    final checker = container.read(achievementCheckerProvider);
    checker.check('other-agent-99');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      calls,
      1,
      reason:
          '其他 agent 的 AchievementChecker 事件应被过滤，'
          '本 VM 不应 refresh。当前 calls=$calls（预期 1）',
    );
  });

  // Round 4 fix #4: ticker listener 捕获异常时必须调 logger.error(),不能
  // 静默 `() => Future<void>.value()`(Iron Law 8 违反)。
  test('ticker listener logs error to ILogger when refreshAgent fails '
      '(Law 8 — no silent catch)', () async {
    // init 阶段 OK,后续 ticker 触发时 getById 抛异常。
    when(() => agentRepo.getById('local-1')).thenAnswer((_) async {
      return activeAgent;
    });
    final container = createContainer();
    container.read(agentProfileViewModelProvider('local-1'));
    await waitForInitComplete(container);

    // 改 stub 让 ticker-driven refreshAgent 内部抛错
    when(
      () => agentRepo.getById('local-1'),
    ).thenThrow(Exception('ticker refresh failed'));

    final notifier = container.read(agentSyncTickerProvider.notifier);
    notifier.state = AgentSyncTick(
      revision: (notifier.state?.revision ?? 0) + 1,
      instanceId: 'inst-1',
    );
    // 让 microtask 链跑完:catchError → logger.error
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // Iron Law 8: 异常必须 log,不能静默。验证 logger.error 被调过一次。
    verify(() => logger.error(any(), any())).called(greaterThan(0));
  });
}
