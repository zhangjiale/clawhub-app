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
import 'package:claw_hub/ui_kit/async_state.dart';

class _MockAgentRepo extends Mock implements IAgentRepo {}

class _MockInstanceRepo extends Mock implements IInstanceRepo {}

class _MockMessageRepo extends Mock implements IMessageRepo {}

class _MockActivityRepo extends Mock implements IActivityRepo {}

class _MockAvatarStorageService extends Mock implements IAvatarStorageService {}

class _MockAchievementRepo extends Mock implements IAchievementRepo {}

void main() {
  late _MockAgentRepo agentRepo;
  late _MockInstanceRepo instanceRepo;
  late _MockMessageRepo messageRepo;
  late _MockActivityRepo activityRepo;
  late _MockAvatarStorageService avatarStorageService;
  late _MockAchievementRepo achievementRepo;

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

    // Achievement evaluator 默认 stub
    when(() => achievementRepo.getStats(any())).thenAnswer((_) async => null);
    when(
      () => achievementRepo.computeStats(any()),
    ).thenAnswer((_) async => AgentStats(agentId: 'local-1'));
    when(() => achievementRepo.saveStats(any())).thenAnswer((_) async {});
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

    // 模拟后台 sync: ticker 递增一次 → ref.listen 回调触发 vm.refreshAgent()
    container.read(agentSyncTickerProvider.notifier).state++;
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

  test('ticker bump also updates isAgentRemoved when agent becomes tombstoned '
      'between init and sync', () async {
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

    expect(vm.state.isAgentRemoved, isFalse);

    container.read(agentSyncTickerProvider.notifier).state++;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      vm.state.isAgentRemoved,
      isTrue,
      reason: 'ticker → refreshAgent → refreshAgent 应捕获后台 tombstone',
    );
  });
}
