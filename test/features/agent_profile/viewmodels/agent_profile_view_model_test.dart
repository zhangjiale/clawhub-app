import 'dart:async';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/domain/models/daily_activity.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/errors.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import '../../../_helpers/fake_logger.dart';
import '../../../_helpers/mocks.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(AgentStats(agentId: 'fallback'));
    registerFallbackValue(<String>{''});
  });

  group('AgentDetailData', () {
    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划',
      themeColor: '#6c5ce7',
    );

    final testInstance = Instance(
      id: 'inst-1',
      name: '我的MacBook',
      gatewayUrl: 'ws://192.168.1.1:18789',
      tokenRef: 'key-1',
    );

    test('equality — same fields are equal', () {
      final a = AgentDetailData(agent: testAgent, messageCount: 10);
      final b = AgentDetailData(agent: testAgent, messageCount: 10);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equality — different messageCount are not equal', () {
      final a = AgentDetailData(agent: testAgent, messageCount: 10);
      final b = AgentDetailData(agent: testAgent, messageCount: 20);
      expect(a, isNot(b));
    });

    test('instance is optional (null)', () {
      final data = AgentDetailData(agent: testAgent, messageCount: 0);
      expect(data.instance, isNull);
    });

    test('instance can be provided', () {
      final data = AgentDetailData(
        agent: testAgent,
        instance: testInstance,
        messageCount: 5,
      );
      expect(data.instance, testInstance);
    });
  });

  group('AgentProfileState', () {
    test('default state has LoadInProgress', () {
      const state = AgentProfileState();
      expect(state.detailLoadState, isA<LoadInProgress>());
      expect(state.isSaving, false);
      expect(state.saveError, isNull);
      expect(state.saveSuccess, false);
    });

    test('copyWith preserves unchanged fields', () {
      const state = AgentProfileState();
      final updated = state.copyWith(isSaving: true);
      expect(updated.isSaving, true);
      expect(updated.detailLoadState, state.detailLoadState);
      expect(updated.saveError, state.saveError);
    });
  });

  group('AgentProfileViewModel', () {
    late MockAgentRepo agentRepo;
    late MockInstanceRepo instanceRepo;
    late MockMessageRepo messageRepo;
    late MockAchievementRepo achievementRepo;
    late MockActivityRepo activityRepo;
    late MockAvatarStorageService avatarStorageService;
    late FakeLogger logger;

    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划、需求分析',
      themeColor: '#6c5ce7',
    );

    setUp(() {
      agentRepo = MockAgentRepo();
      instanceRepo = MockInstanceRepo();
      messageRepo = MockMessageRepo();
      achievementRepo = MockAchievementRepo();
      activityRepo = MockActivityRepo();
      avatarStorageService = MockAvatarStorageService();
      logger = FakeLogger();

      // Default stubs — achievement load is best-effort, return empty data
      when(
        () => achievementRepo.computeStats(any()),
      ).thenAnswer((_) async => AgentStats(agentId: 'local-1'));
      when(
        () => achievementRepo.getUnlocks(any()),
      ).thenAnswer((_) async => <Achievement>[]);
      when(
        () => achievementRepo.batchUnlock(any(), any()),
      ).thenAnswer((_) async => <Achievement>[]);
      // Default: activity repo returns empty 30-day series
      when(
        () => activityRepo.getDailyActivity(
          any(),
          days: any(named: 'days'),
          now: any(named: 'now'),
        ),
      ).thenAnswer((_) async => const []);
    });

    AgentProfileViewModel createVM({
      EvaluateAchievementsUseCase? evaluateAchievements,
    }) {
      return AgentProfileViewModel(
        agentRepo: agentRepo,
        instanceRepo: instanceRepo,
        messageRepo: messageRepo,
        activityRepo: activityRepo,
        avatarStorageService: avatarStorageService,
        evaluateAchievements:
            evaluateAchievements ??
            EvaluateAchievementsUseCase(achievementRepo),
        logger: logger,
        agentId: 'local-1',
      );
    }

    test('init() loads agent and sets LoadData on success', () async {
      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 42);

      final vm = createVM();
      await vm.init();

      final state = vm.state;
      expect(state.detailLoadState, isA<LoadData<AgentDetailData>>());
      final data = (state.detailLoadState as LoadData<AgentDetailData>).value;
      expect(data.agent, testAgent);
      expect(data.messageCount, 42);
      expect(data.instance, isNull);
    });

    test('init() sets LoadError when agent not found', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => null);

      final vm = createVM();
      await vm.init();

      final state = vm.state;
      expect(state.detailLoadState, isA<LoadError>());
      expect(
        (state.detailLoadState as LoadError).error,
        isA<AgentNotFoundError>(),
      );
    });

    test('init() does not fail when instance is not found', () async {
      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(
        () => instanceRepo.getById('inst-1'),
      ).thenThrow(Exception('DB error'));
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      final state = vm.state;
      expect(state.detailLoadState, isA<LoadData<AgentDetailData>>());
      final data = (state.detailLoadState as LoadData<AgentDetailData>).value;
      expect(data.instance, isNull);
    });

    test('saveProfile updates state on success', () async {
      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);
      when(
        () => agentRepo.updateLocalProfile(
          'local-1',
          nickname: '我的产品虾',
          themeColor: '#0984e3',
        ),
      ).thenAnswer(
        (_) async =>
            testAgent.copyWith(nickname: '我的产品虾', themeColor: '#0984e3'),
      );
      when(
        () => agentRepo.updateFullProfile(
          'local-1',
          nickname: any(named: 'nickname'),
          avatarUrl: any(named: 'avatarUrl'),
          themeColor: any(named: 'themeColor'),
          quickCommands: any(named: 'quickCommands'),
        ),
      ).thenAnswer((_) async {});

      final vm = createVM();
      await vm.init();

      // Re-stub for the refresh() inside saveProfile
      when(() => agentRepo.getById('local-1')).thenAnswer(
        (_) async =>
            testAgent.copyWith(nickname: '我的产品虾', themeColor: '#0984e3'),
      );
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);

      await vm.saveProfile(nickname: '我的产品虾', themeColor: '#0984e3');

      final state = vm.state;
      expect(state.saveSuccess, true);
      expect(state.isSaving, false);
    });

    test('saveProfile sets saveError on failure', () async {
      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      when(
        () => agentRepo.updateFullProfile(
          'local-1',
          nickname: any(named: 'nickname'),
          avatarUrl: any(named: 'avatarUrl'),
          themeColor: any(named: 'themeColor'),
          quickCommands: any(named: 'quickCommands'),
        ),
      ).thenThrow(Exception('Save failed'));

      await vm.saveProfile(nickname: 'nick', themeColor: '#0984e3');

      final state = vm.state;
      expect(state.saveError, isNotNull);
      expect(state.isSaving, false);
      expect(state.saveSuccess, false);
    });

    test('saveProfile ignores concurrent invocation while isSaving', () async {
      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      final completer = Completer<void>();
      when(
        () => agentRepo.updateFullProfile(
          'local-1',
          nickname: any(named: 'nickname'),
          avatarUrl: any(named: 'avatarUrl'),
          themeColor: any(named: 'themeColor'),
          quickCommands: any(named: 'quickCommands'),
        ),
      ).thenAnswer((_) => completer.future);

      // 第一次调用进入 isSaving
      final first = vm.saveProfile(nickname: 'nick', themeColor: '#0984e3');
      // 第二次调用应被 guard 直接丢弃
      final second = vm.saveProfile(nickname: 'nick2', themeColor: '#a29bfe');

      completer.complete();
      await first;
      await second;

      verify(
        () => agentRepo.updateFullProfile(
          'local-1',
          nickname: any(named: 'nickname'),
          avatarUrl: any(named: 'avatarUrl'),
          themeColor: any(named: 'themeColor'),
          quickCommands: any(named: 'quickCommands'),
        ),
      ).called(1);
    });

    test('clearSaveResult resets save flags', () async {
      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      when(
        () => agentRepo.updateFullProfile(
          'local-1',
          nickname: any(named: 'nickname'),
          avatarUrl: any(named: 'avatarUrl'),
          themeColor: any(named: 'themeColor'),
          quickCommands: any(named: 'quickCommands'),
        ),
      ).thenThrow(Exception('Save failed'));
      await vm.saveProfile(nickname: 'nick', themeColor: '#0984e3');
      expect(vm.state.saveError, isNotNull);

      vm.clearSaveResult();
      expect(vm.state.saveError, isNull);
      expect(vm.state.saveSuccess, false);
    });

    test('agent data is accessible via detailLoadState after init', () async {
      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      final state = vm.state;
      final detail = (state.detailLoadState as LoadData<AgentDetailData>).value;
      expect(detail.agent.name, '产品虾');
    });

    test('dispose can be called safely', () async {
      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();
      vm.dispose();
    });

    // 3B: profile page init triggers a fresh computeStats — use case 已删除
    // saveStats/getStats 接口，统计全量实时聚合（无 agent_stats 缓存层）。
    // 这个测试断言 VM 经 use case 调用 computeStats 拿到当前消息的真实
    // 聚合值。
    test('init() computes fresh stats (3B: no cache layer)', () async {
      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 47);

      final freshStats = AgentStats(
        agentId: 'local-1',
        totalDialogs: 3,
        totalMessages: 47,
        totalToolCalls: 12,
        activeDays: 5,
        currentStreak: 3,
      );
      when(
        () => achievementRepo.computeStats('local-1'),
      ).thenAnswer((_) async => freshStats);
      when(
        () => achievementRepo.getUnlocks('local-1'),
      ).thenAnswer((_) async => const []);

      final vm = createVM();
      await vm.init();

      verify(() => achievementRepo.computeStats('local-1')).called(1);

      final data =
          (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
      expect(data.stats?.totalMessages, 47);
      expect(data.stats?.totalDialogs, 3);
      expect(data.stats?.activeDays, 5);
    });

    test('init() loads dailyActivity from IActivityRepo', () async {
      // Override default empty stub with a real 30-day series
      final fakeActivity = List.generate(
        30,
        (i) => DailyActivity(agentId: 'local-1', dayBucket: i, messageCount: i),
      );
      when(
        () => activityRepo.getDailyActivity(
          'local-1',
          days: any(named: 'days'),
          now: any(named: 'now'),
        ),
      ).thenAnswer((_) async => fakeActivity);

      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      final data =
          (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
      expect(data.dailyActivity, equals(fakeActivity));
      expect(data.dailyActivity.length, 30);
    });

    test('init() still succeeds when activityRepo throws '
        '(best-effort, empty timeline)', () async {
      when(
        () => activityRepo.getDailyActivity(
          any(),
          days: any(named: 'days'),
          now: any(named: 'now'),
        ),
      ).thenThrow(Exception('DB down'));

      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      final data =
          (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
      expect(data.dailyActivity, isEmpty);
    });

    group('updateAvatar', () {
      setUp(() {
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);
      });

      test('delegates to storage service and repo', () async {
        when(
          () => avatarStorageService.saveAvatar('local-1', any<Uint8List>()),
        ).thenAnswer((_) async => '/path/to/avatars/local-1.jpg');
        when(
          () => agentRepo.updateLocalProfile(
            'local-1',
            avatarUrl: '/path/to/avatars/local-1.jpg',
          ),
        ).thenAnswer((_) async => testAgent);
        // refresh() 内部调用 getById — 需要返回带有新 avatarUrl 的 agent
        when(() => agentRepo.getById('local-1')).thenAnswer(
          (_) async =>
              testAgent.copyWith(avatarUrl: '/path/to/avatars/local-1.jpg'),
        );

        final vm = createVM();
        await vm.init();

        await vm.updateAvatar(Uint8List.fromList([1, 2, 3]));

        verify(
          () => avatarStorageService.saveAvatar('local-1', any()),
        ).called(1);
        verify(
          () => agentRepo.updateLocalProfile(
            'local-1',
            avatarUrl: '/path/to/avatars/local-1.jpg',
          ),
        ).called(1);
        // 头像操作不设置 saveSuccess（仅 saveProfile 设置），避免触发配置页弹回
        expect(vm.state.saveSuccess, false);
        expect(vm.state.isSaving, false);
        // 验证 refresh() 后 state 中 agent 的 avatarUrl 已更新
        final detail = switch (vm.state.detailLoadState) {
          LoadData<AgentDetailData>(:final value) => value,
          _ => null,
        };
        expect(detail?.agent.avatarUrl, '/path/to/avatars/local-1.jpg');
      });

      test('sets saveError on failure', () async {
        when(
          () => avatarStorageService.saveAvatar('local-1', any<Uint8List>()),
        ).thenThrow(Exception('Disk full'));

        final vm = createVM();
        await vm.init();

        await vm.updateAvatar(Uint8List.fromList([1, 2, 3]));

        expect(vm.state.saveError, isNotNull);
        expect(vm.state.isSaving, false);
        expect(vm.state.saveSuccess, false);
      });

      test('cleans up orphaned file when DB update fails', () async {
        // Step 1: saveAvatar succeeds → file written to disk
        when(
          () => avatarStorageService.saveAvatar('local-1', any<Uint8List>()),
        ).thenAnswer((_) async => '/path/to/avatars/local-1.jpg');
        // Step 2: updateLocalProfile throws → DB write failed
        when(
          () => agentRepo.updateLocalProfile(
            'local-1',
            avatarUrl: any(named: 'avatarUrl'),
          ),
        ).thenThrow(Exception('DB locked'));

        final vm = createVM();
        await vm.init();

        await vm.updateAvatar(Uint8List.fromList([1, 2, 3]));

        // 验证回滚：deleteAvatar 被调用以清理孤儿文件
        verify(() => avatarStorageService.deleteAvatar('local-1')).called(1);
        expect(vm.state.saveError, isNotNull);
        expect(vm.state.isSaving, false);
      });

      test('ignores concurrent invocation while isSaving', () async {
        final completer = Completer<String>();
        when(
          () => avatarStorageService.saveAvatar('local-1', any<Uint8List>()),
        ).thenAnswer((_) => completer.future);
        when(
          () => agentRepo.updateLocalProfile(
            'local-1',
            avatarUrl: any(named: 'avatarUrl'),
          ),
        ).thenAnswer((_) async => testAgent);

        final vm = createVM();
        await vm.init();

        final first = vm.updateAvatar(Uint8List.fromList([1, 2, 3]));
        final second = vm.updateAvatar(Uint8List.fromList([4, 5, 6]));

        completer.complete('/path/to/avatar.jpg');
        await first;
        await second;

        verify(
          () => avatarStorageService.saveAvatar('local-1', any()),
        ).called(1);
      });
    });

    group('removeAvatar', () {
      setUp(() {
        when(() => agentRepo.getById('local-1')).thenAnswer(
          (_) async => testAgent.copyWith(avatarUrl: '/path/to/old-avatar.jpg'),
        );
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);
      });

      test(
        'deletes file and calls clearAvatar (not updateLocalProfile)',
        () async {
          when(
            () => avatarStorageService.deleteAvatar('local-1'),
          ).thenAnswer((_) async {});
          when(() => agentRepo.clearAvatar('local-1')).thenAnswer((_) async {});

          final vm = createVM();
          await vm.init();

          await vm.removeAvatar();

          verify(() => avatarStorageService.deleteAvatar('local-1')).called(1);
          // 验证：应使用 clearAvatar() 而非 updateLocalProfile(avatarUrl: null)
          verify(() => agentRepo.clearAvatar('local-1')).called(1);
          verifyNever(
            () => agentRepo.updateLocalProfile(
              'local-1',
              avatarUrl: any(named: 'avatarUrl'),
            ),
          );
          // 头像操作不设置 saveSuccess
          expect(vm.state.saveSuccess, false);
          expect(vm.state.isSaving, false);
        },
      );

      test('verifies avatarUrl is cleared in refreshed state', () async {
        // setUp stub 返回带有 avatarUrl 的 agent — init 后 state 中 avatarUrl 非 null
        when(
          () => avatarStorageService.deleteAvatar('local-1'),
        ).thenAnswer((_) async {});
        when(() => agentRepo.clearAvatar('local-1')).thenAnswer((_) async {});

        final vm = createVM();
        await vm.init();

        // 确认 remove 前 avatarUrl 存在
        final before = switch (vm.state.detailLoadState) {
          LoadData<AgentDetailData>(:final value) => value,
          _ => null,
        };
        expect(before?.agent.avatarUrl, '/path/to/old-avatar.jpg');

        // 重新 stub getById → 返回无 avatarUrl 的 agent，模拟 clearAvatar 后的 DB 状态
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent); // avatarUrl is null

        await vm.removeAvatar();

        // removeAvatar 内部的 refresh() 调用 getById → 现在返回无 avatarUrl 的 agent
        final after = switch (vm.state.detailLoadState) {
          LoadData<AgentDetailData>(:final value) => value,
          _ => null,
        };
        expect(after?.agent.avatarUrl, isNull);
      });

      test('does not fail when file does not exist', () async {
        when(
          () => avatarStorageService.deleteAvatar('local-1'),
        ).thenAnswer((_) async {});
        when(() => agentRepo.clearAvatar('local-1')).thenAnswer((_) async {});

        final vm = createVM();
        await vm.init();

        // Should not throw even if deleteAvatar is no-op
        await vm.removeAvatar();
        expect(vm.state.saveSuccess, false);
        expect(vm.state.saveError, isNull);
        expect(vm.state.isSaving, false);
      });
    });

    group('saveProfile with quickCommands', () {
      setUp(() {
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);
        when(
          () => agentRepo.updateFullProfile(
            'local-1',
            nickname: any(named: 'nickname'),
            avatarUrl: any(named: 'avatarUrl'),
            themeColor: any(named: 'themeColor'),
            quickCommands: any(named: 'quickCommands'),
          ),
        ).thenAnswer((_) async {});
      });

      test('calls updateFullProfile when quickCommands provided', () async {
        final cmds = [
          QuickCommand(
            id: '1',
            agentId: 'local-1',
            label: '状态',
            payload: '/status',
          ),
        ];

        final vm = createVM();
        await vm.init();

        await vm.saveProfile(quickCommands: cmds);

        verify(
          () => agentRepo.updateFullProfile(
            'local-1',
            nickname: any(named: 'nickname'),
            avatarUrl: any(named: 'avatarUrl'),
            themeColor: any(named: 'themeColor'),
            quickCommands: any(named: 'quickCommands'),
          ),
        ).called(1);
        expect(vm.state.saveSuccess, true);
      });

      test('empty list clears quick commands', () async {
        final vm = createVM();
        await vm.init();

        await vm.saveProfile(quickCommands: []);

        verify(
          () => agentRepo.updateFullProfile(
            'local-1',
            quickCommands: any(named: 'quickCommands'),
          ),
        ).called(1);
      });

      test('does not pass quickCommands when null', () async {
        final vm = createVM();
        await vm.init();

        await vm.saveProfile(nickname: 'nick');

        verify(
          () => agentRepo.updateFullProfile(
            'local-1',
            nickname: any(named: 'nickname'),
            avatarUrl: any(named: 'avatarUrl'),
            themeColor: any(named: 'themeColor'),
            quickCommands: any(named: 'quickCommands'),
          ),
        ).called(1);
      });

      test('saveError set when updateFullProfile fails', () async {
        when(
          () => agentRepo.updateFullProfile(
            'local-1',
            nickname: any(named: 'nickname'),
            avatarUrl: any(named: 'avatarUrl'),
            themeColor: any(named: 'themeColor'),
            quickCommands: any(named: 'quickCommands'),
          ),
        ).thenThrow(Exception('DB error'));

        final vm = createVM();
        await vm.init();

        await vm.saveProfile(quickCommands: []);

        expect(vm.state.saveError, isNotNull);
        expect(vm.state.saveSuccess, false);
      });
    });

    // ============================================================
    // US-021 v1.1: AgentProfileState tombstone via vm.agent + write guards
    // Step 6 改造: 不再依赖 state.isAgentRemoved 字段,改读 vm.agent.isRemoved。
    // ============================================================
    group('US-021 tombstone reactive state', () {
      final tombAgent = Agent(
        localId: 'local-1',
        remoteId: 'remote-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
        removedAt: 1719200000000,
      );

      test('vm.agent defaults to null on fresh VM', () {
        final vm = createVM();
        expect(
          vm.agent?.isRemoved ?? false,
          isFalse,
          reason:
              '新建 VM 时 vm.agent 必须为 null（init 尚未跑），'
              '避免初始化前误显示 tombstone 占位页',
        );
      });

      test(
        'refresh() syncs vm.agent.isRemoved=true when agent is tombstoned',
        () async {
          when(
            () => agentRepo.getById('local-1'),
          ).thenAnswer((_) async => tombAgent);
          when(
            () => instanceRepo.getById('inst-1'),
          ).thenAnswer((_) async => null);
          when(
            () => messageRepo.getMessageCount('local-1'),
          ).thenAnswer((_) async => 0);

          final vm = createVM();
          await vm.init();

          expect(
            vm.agent?.isRemoved ?? false,
            isTrue,
            reason:
                'init 时若 agent 已是 tombstone 状态，'
                'vm.agent.isRemoved 必须同步为 true，驱动占位页',
          );
        },
      );

      test('saveProfile blocked when agent is tombstoned '
          '(updateFullProfile not called) + saveError surfaced', () async {
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => tombAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);

        final vm = createVM();
        await vm.init();
        expect(vm.agent?.isRemoved ?? false, isTrue); // sanity

        await vm.saveProfile(nickname: 'ignored');

        // ★ tombstone guard：禁止写入
        verifyNever(
          () => agentRepo.updateFullProfile(
            'local-1',
            nickname: any(named: 'nickname'),
            avatarUrl: any(named: 'avatarUrl'),
            themeColor: any(named: 'themeColor'),
            quickCommands: any(named: 'quickCommands'),
          ),
        );
        // 不进入 isSaving（早返回，未触发状态机）
        expect(vm.state.isSaving, isFalse);
        expect(vm.state.saveSuccess, isFalse);
        // US-021 v1.2 修复：阻断必须 surface 错误，文案应明确说明 tombstone。
        expect(vm.state.saveError, isNotNull);
        expect(
          vm.state.saveError,
          contains('移除'),
          reason: 'tombstone 阻断文案必须说明"已被移除"原因',
        );
      });

      test('updateAvatar blocked when agent is tombstoned '
          '(storage service not called) + saveError surfaced', () async {
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => tombAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);

        final vm = createVM();
        await vm.init();
        expect(vm.agent?.isRemoved ?? false, isTrue); // sanity

        await vm.updateAvatar(Uint8List.fromList([1, 2, 3]));

        // ★ tombstone guard：禁止写入
        verifyNever(() => avatarStorageService.saveAvatar(any(), any()));
        verifyNever(
          () => agentRepo.updateLocalProfile(
            'local-1',
            avatarUrl: any(named: 'avatarUrl'),
          ),
        );
        expect(vm.state.isSaving, isFalse);
        expect(vm.state.saveError, isNotNull);
      });

      test('removeAvatar blocked when agent is tombstoned '
          '(clearAvatar not called) + saveError surfaced', () async {
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => tombAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);

        final vm = createVM();
        await vm.init();
        expect(vm.agent?.isRemoved ?? false, isTrue); // sanity

        await vm.removeAvatar();

        // ★ tombstone guard：禁止写入
        verifyNever(() => avatarStorageService.deleteAvatar(any()));
        verifyNever(() => agentRepo.clearAvatar(any()));
        expect(vm.state.isSaving, isFalse);
        expect(vm.state.saveError, isNotNull);
      });

      test('refreshAgent reacts to backend sync: '
          'tombstoned-then-revived updates vm.agent.isRemoved', () async {
        // init 时是 alive agent
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);

        final vm = createVM();
        await vm.init();
        expect(vm.agent?.isRemoved ?? false, isFalse);

        // 后台 sync 把 agent tombstone 了
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => tombAgent);
        await vm.refreshAgent();
        expect(
          vm.agent?.isRemoved ?? false,
          isTrue,
          reason: 'refreshAgent 应在 sync 后捕获到 tombstone 状态',
        );

        // 复活（agent 重新出现在 Gateway）
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent);
        await vm.refreshAgent();
        expect(
          vm.agent?.isRemoved ?? false,
          isFalse,
          reason: '复活后 refreshAgent 必须清除 tombstone 标记',
        );
      });

      test(
        'refreshAgent updates loaded detailLoadState agent without reloading stats',
        () async {
          final updatedAgent = testAgent.copyWith(nickname: '同步后的昵称');
          when(
            () => agentRepo.getById('local-1'),
          ).thenAnswer((_) async => testAgent);
          when(
            () => instanceRepo.getById('inst-1'),
          ).thenAnswer((_) async => null);
          when(
            () => messageRepo.getMessageCount('local-1'),
          ).thenAnswer((_) async => 7);

          final vm = createVM();
          await vm.init();
          final before =
              (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
          expect(before.agent.nickname, isNull);
          expect(before.messageCount, 7);

          when(
            () => agentRepo.getById('local-1'),
          ).thenAnswer((_) async => updatedAgent);
          await vm.refreshAgent();

          expect(vm.agent?.nickname, '同步后的昵称');
          final after =
              (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
          expect(after.agent.nickname, '同步后的昵称');
          expect(
            after.messageCount,
            7,
            reason: 'refreshAgent 只替换 agent，不重跑统计查询',
          );
          verify(() => messageRepo.getMessageCount('local-1')).called(1);
        },
      );

      // US-021 tombstone transition contract: when a sync discovers the
      // agent has been tombstoned, refreshAgent must (a) still call
      // setAgent so vm.agent.isRemoved = true drives the page-level
      // AgentRemovedPlaceholder, AND (b) skip the _updateState that would
      // copy the previous (alive) LoadData's instance/messageCount/stats/
      // achievements on top of the placeholder. Otherwise the page would
      // show a half-populated LoadData next to the tombstone UI, with
      // stale messageCount from before the tombstone.
      //
      // Two-step scenario: init with alive agent (so detailLoadState has a
      // populated LoadData), then sync with tombstoned agent. refreshAgent
      // must flip vm.agent.isRemoved WITHOUT mutating detailLoadState.
      //
      // Note: state itself DOES change (setAgent bumps contentRevision via
      // AgentReactiveState mixin's onAgentUpdated) — that's expected, it
      // drives Riverpod's rebuild for the tombstone placeholder. What must
      // NOT change is the detailLoadState wrapper (the LoadData inner
      // value). Without the tombstone guard, _updateState would re-wrap
      // `current.value` (the alive snapshot) with the tombstoned agent,
      // producing a stale LoadData.
      test('refreshAgent skips detailLoadState re-write when sync '
          'discovers a tombstone (US-021 — avoid stale LoadData '
          'on tombstone placeholder)', () async {
        // Arrange: init with ALIVE agent so detailLoadState has populated
        // messageCount=7, stats=non-null, achievements=[…]. This is what the
        // bug scenario requires — a populated LoadData that would be
        // wrongly copied if _updateState runs.
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 7);

        final vm = createVM();
        await vm.init();
        // Sanity: LoadData is populated
        final aliveDetail =
            (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
        expect(aliveDetail.agent.isRemoved, isFalse);
        expect(aliveDetail.messageCount, 7);

        // Capture detailLoadState identity — refreshAgent must NOT re-wrap
        // this LoadData when freshAgent.isRemoved is true. State will
        // still change (contentRevision bumps) — that's the signal the
        // page needs to swap in AgentRemovedPlaceholder.
        final detailBefore = vm.state.detailLoadState;
        final messageCountBefore = aliveDetail.messageCount;

        // Act: sync delivers a tombstoned agent
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => tombAgent);
        await vm.refreshAgent();

        // Assert 1: vm.agent flipped to tombstoned (drives page placeholder)
        expect(vm.agent?.isRemoved ?? false, isTrue);

        // Assert 2: detailLoadState NOT re-written with stale tombstone
        // wrapper. The alive LoadData stays intact — page-level placeholder
        // handles the tombstone UI based on vm.agent.isRemoved, not on a
        // tombstoned detailLoadState.
        expect(
          identical(vm.state.detailLoadState, detailBefore),
          isTrue,
          reason:
              'refreshAgent must skip _updateState when freshAgent.isRemoved '
              'is true — copying previous LoadData.instance/messageCount/'
              'stats/achievements would yield a half-populated LoadData '
              'alongside the tombstone placeholder UI.',
        );

        // Assert 3: the alive LoadData is preserved untouched (messageCount
        // still 7, agent still alive in detailLoadState — vm.agent is the
        // SSOT for tombstone, NOT detailLoadState.agent).
        final after = vm.state.detailLoadState as LoadData<AgentDetailData>;
        expect(after.value.messageCount, messageCountBefore);
        expect(after.value.agent.isRemoved, isFalse);
      });

      // Round 4 fix #3: refreshAgent 必须 guard against 3 个 async-gap race:
      //   (a) detailLoadState 还未到达 LoadData (init 未完成)
      //   (b) detailLoadState 是 LoadError (init 失败)
      //   (c) VM 已 dispose (ticker 在 getById await 期间触发 dispose)
      // 这三条都必须在不修改 state 的前提下早返回。
      test('refreshAgent is no-op when detailLoadState is LoadInProgress '
          '(init still in flight)', () async {
        // arrange — 不调 init,detailLoadState 保持 LoadInProgress
        final vm = createVM();
        expect(vm.state.detailLoadState, isA<LoadInProgress>());

        await vm.refreshAgent();

        verifyNever(() => agentRepo.getById('local-1'));
        expect(
          vm.state.detailLoadState,
          isA<LoadInProgress>(),
          reason: 'LoadInProgress 期间 refreshAgent 必须 no-op',
        );
      });

      test('refreshAgent is no-op when detailLoadState is LoadError '
          '(avoid clobbering error state)', () async {
        // arrange — init 失败 → detailLoadState = LoadError
        when(() => agentRepo.getById('local-1')).thenAnswer((_) async => null);
        final vm = createVM();
        await vm.init();
        expect(vm.state.detailLoadState, isA<LoadError>());

        // 即使 ticker 想抢救(getById 返回一个 active agent),refreshAgent
        // 也必须拒绝写入 — 否则 LoadError UI 会被半成品的 LoadData 覆盖。
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent);
        await vm.refreshAgent();

        expect(
          vm.state.detailLoadState,
          isA<LoadError>(),
          reason:
              'LoadError 期间 refreshAgent 必须 no-op,'
              '不能让 ticker 写入"半成品"LoadData 覆盖错误状态',
        );
        expect(
          vm.agent?.isRemoved ?? false,
          isFalse,
          reason: 'refreshAgent 失败时也不应调用 setAgent 留下半成品状态',
        );
      });

      test('refreshAgent is safe to call after dispose '
          '(async-gap dispose race)', () async {
        // arrange — init 完成让 VM 进入 LoadData,然后 dispose。
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);
        final vm = createVM();
        await vm.init();
        vm.dispose();
        // 模拟 ticker 在 dispose 后又 fire 一次 — 现在 mounted=false。
        expect(
          () => vm.refreshAgent(),
          returnsNormally,
          reason: 'dispose 后 refreshAgent 必须 no-op,不抛 StateError',
        );
      });

      test('saveProfile blocked when _agent is null (init failed/not loaded) '
          'surfaces saveError for UX feedback', () async {
        final vm = createVM();
        // 不调 init，_agent 为 null
        expect(vm.agent?.isRemoved ?? false, isFalse);

        await vm.saveProfile(nickname: 'ignored');

        verifyNever(
          () => agentRepo.updateFullProfile(
            'local-1',
            nickname: any(named: 'nickname'),
            avatarUrl: any(named: 'avatarUrl'),
            themeColor: any(named: 'themeColor'),
            quickCommands: any(named: 'quickCommands'),
          ),
        );
        expect(vm.state.isSaving, isFalse);
        // US-021 v1.1 修复：阻断必须 surface 错误，否则用户看不到反馈。
        expect(
          vm.state.saveError,
          isNotNull,
          reason:
              'tombstoned/null _agent 的 saveProfile 必须 surface '
              'saveError 让 UI 显示 toast/banner，不能静默 no-op',
        );
      });

      test('updateAvatar blocked when _agent is null (init failed/not loaded) '
          'surfaces saveError for UX feedback', () async {
        final vm = createVM();

        await vm.updateAvatar(Uint8List.fromList([1, 2, 3]));

        verifyNever(() => avatarStorageService.saveAvatar(any(), any()));
        verifyNever(
          () => agentRepo.updateLocalProfile(
            'local-1',
            avatarUrl: any(named: 'avatarUrl'),
          ),
        );
        expect(vm.state.isSaving, isFalse);
        expect(
          vm.state.saveError,
          isNotNull,
          reason: '阻断 updateAvatar 必须 surface saveError',
        );
      });

      test('removeAvatar blocked when _agent is null (init failed/not loaded) '
          'surfaces saveError for UX feedback', () async {
        final vm = createVM();

        await vm.removeAvatar();

        verifyNever(() => avatarStorageService.deleteAvatar(any()));
        verifyNever(() => agentRepo.clearAvatar(any()));
        expect(vm.state.isSaving, isFalse);
        expect(
          vm.state.saveError,
          isNotNull,
          reason: '阻断 removeAvatar 必须 surface saveError',
        );
      });

      test('refresh() clears vm.agent on error so LoadError shows', () async {
        // init 时 agent 是 tombstoned，vm.agent.isRemoved=true
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => tombAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);

        final vm = createVM();
        await vm.init();
        expect(vm.agent?.isRemoved ?? false, isTrue);

        // refresh 时 getById 抛异常
        when(
          () => agentRepo.getById('local-1'),
        ).thenThrow(Exception('DB error'));
        await vm.refresh();

        expect(vm.state.detailLoadState, isA<LoadError>());
        expect(
          vm.agent?.isRemoved ?? false,
          isFalse,
          reason: '详情加载失败时不应继续显示 tombstone 占位页',
        );
      });
    });

    // ============================================================
    // AchievementRefresh: 局部刷新入口 (race 修复)
    // AchievementChecker.updates listener 通过 achievementRefresh()
    // 只刷 stats/achievements/newUnlocks,不动 detailLoadState、
    // isSaving/saveError,避免与 saveProfile 内部的 refresh() 互相
    // 覆盖 detailLoadState。
    // ============================================================
    group('achievementRefresh', () {
      setUp(() {
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent);
        when(
          () => instanceRepo.getById('inst-1'),
        ).thenAnswer((_) async => null);
        when(
          () => messageRepo.getMessageCount('local-1'),
        ).thenAnswer((_) async => 0);
      });

      test('exposes achievementRefresh() as Future<void> Function()', () {
        final vm = createVM();
        // 编译期契约：方法存在且签名匹配
        expect(vm.achievementRefresh, isNotNull);
        expect(vm.achievementRefresh, isA<Future<void> Function()>());
      });

      test('updates only stats/achievements/newUnlocks, '
          'detailLoadState stays LoadData', () async {
        // arrange — init with stale stats
        when(
          () => achievementRepo.computeStats('local-1'),
        ).thenAnswer((_) async => AgentStats(agentId: 'local-1'));
        final vm = createVM();
        await vm.init();
        final before =
            (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
        final beforeMsgCount = before.messageCount;
        final beforeAgent = before.agent;

        // act — re-stub computeStats to return fresh stats, then refresh
        final freshStats = AgentStats(
          agentId: 'local-1',
          totalDialogs: 5,
          totalMessages: 99,
          totalToolCalls: 12,
          activeDays: 7,
          currentStreak: 3,
        );
        final freshAchievement = Achievement(
          // id 必须与 freshStats 触发的预设成就 ID 一致 ('first_dialog'),
          // 否则 use case 的 freshUnlocks 过滤 (newIds.contains(a.id)) 会
          // 把这个 freshUnlocks 项过滤掉,newUnlocks 断言失败。
          id: 'first_dialog',
          icon: '🏆',
          name: '初次对话',
          description: '与虾完成第一次对话',
          tier: AchievementTier.gold,
          unlocked: true,
          unlockedAt: 1719500000000,
        );
        when(
          () => achievementRepo.computeStats('local-1'),
        ).thenAnswer((_) async => freshStats);
        // getUnlocks 返回 [] — 让 use case 通过 evaluateNewAchievements
        // 发现 first_dialog 预设 (totalDialogs=5 ≥ 1),再走 batchUnlock
        // 分支,这样 freshUnlocks 会被填充 [freshAchievement]。
        when(
          () => achievementRepo.getUnlocks('local-1'),
        ).thenAnswer((_) async => const <Achievement>[]);
        // batchUnlock 也 stub — freshStats 可能触发 evaluateNewAchievements
        // 产生 newDefs,这时 use case 会走 batchUnlock 分支而不是返回
        // existingUnlocks。需要保证两条分支都返回 [freshAchievement] 才能让断言稳定。
        when(
          () => achievementRepo.batchUnlock(any(), any()),
        ).thenAnswer((_) async => [freshAchievement]);

        await vm.achievementRefresh();

        // assert — stats/achievements/newUnlocks updated
        final data =
            (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
        expect(data.stats, equals(freshStats));
        expect(data.achievements, equals([freshAchievement]));
        expect(vm.state.newUnlocks, equals([freshAchievement]));

        // assert — detailLoadState 没被重置
        expect(
          vm.state.detailLoadState,
          isA<LoadData<AgentDetailData>>(),
          reason: 'detailLoadState 必须保持 LoadData,不能回到 LoadInProgress',
        );

        // assert — 其他字段未变 (agent/instance/messageCount/dailyActivity)
        expect(data.agent, equals(beforeAgent));
        expect(data.instance, equals(before.instance));
        expect(data.messageCount, beforeMsgCount);
        expect(data.dailyActivity, equals(before.dailyActivity));

        // assert — isSaving/saveError/saveSuccess 未被触碰
        expect(vm.state.isSaving, isFalse);
        expect(vm.state.saveError, isNull);
        expect(vm.state.saveSuccess, isFalse);
      });

      test('is no-op when detailLoadState is LoadInProgress', () async {
        // arrange — 不调用 init,detailLoadState 保持 LoadInProgress
        final vm = createVM();
        expect(vm.state.detailLoadState, isA<LoadInProgress>());

        await vm.achievementRefresh();

        // act — _safeEvaluateAchievements 不应被调用
        verifyNever(() => achievementRepo.computeStats('local-1'));
        // detailLoadState 仍为 LoadInProgress
        expect(vm.state.detailLoadState, isA<LoadInProgress>());
      });

      test('is no-op when detailLoadState is LoadError', () async {
        // arrange — init 失败 → detailLoadState = LoadError
        when(() => agentRepo.getById('local-1')).thenAnswer((_) async => null);
        final vm = createVM();
        await vm.init();
        expect(vm.state.detailLoadState, isA<LoadError>());

        await vm.achievementRefresh();

        // act — _safeEvaluateAchievements 不应被调用
        verifyNever(() => achievementRepo.computeStats('local-1'));
        // detailLoadState 仍为 LoadError
        expect(vm.state.detailLoadState, isA<LoadError>());
      });

      test(
        'does NOT overwrite saveError/isSaving during saveProfile (race fix)',
        () async {
          // arrange — init 完成
          final vm = createVM();
          await vm.init();
          expect(vm.state.detailLoadState, isA<LoadData<AgentDetailData>>());

          // act — 模拟 saveProfile 启动:isSaving=true, saveError=null
          vm.state = vm.state.copyWith(
            isSaving: true,
            saveError: null,
            saveSuccess: false,
          );
          final snapshotDuringSave = vm.state;

          // 此时 AchievementChecker 触发 → achievementRefresh 并发
          await vm.achievementRefresh();

          // assert — isSaving/saveError 字段未被 achievementRefresh 触碰
          expect(
            vm.state.isSaving,
            snapshotDuringSave.isSaving,
            reason: 'achievementRefresh 不应修改 isSaving 字段',
          );
          expect(
            vm.state.saveError,
            snapshotDuringSave.saveError,
            reason: 'achievementRefresh 不应修改 saveError 字段',
          );
          expect(
            vm.state.saveSuccess,
            snapshotDuringSave.saveSuccess,
            reason: 'achievementRefresh 不应修改 saveSuccess 字段',
          );

          // assert — detailLoadState 仍为 LoadData (不是 LoadInProgress)
          expect(
            vm.state.detailLoadState,
            isA<LoadData<AgentDetailData>>(),
            reason: 'achievementRefresh 期间 detailLoadState 不应被重置',
          );

          // assert — achievementRefresh 自己的写入(stats/achievements) 仍然生效
          final data =
              (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
          expect(
            data.stats,
            isNotNull,
            reason: 'achievementRefresh 应在不影响 save 字段的前提下刷 stats',
          );
        },
      );

      // Identity-blindspot regression guard (model-equals-identity-blindspot.md):
      // The skip-if-unchanged block at agent_profile_view_model.dart:423 must
      // use CONTENT equality on the achievements list, not List.== (which is
      // identity in Dart and would never match across two fresh list
      // instances). The early-return is the only thing protecting downstream
      // widgets from rebuilds on every chat message — if it never fires, the
      // optimization is dead code.
      //
      // This test detects the bug by checking `identical` of the detail data
      // reference: if the skip fires, no new AgentDetailData is constructed;
      // if the skip doesn't fire, `_updateState` always wraps a new one.
      test('skips state write when stats+achievements are content-equal '
          '(different list instance, same content)', () async {
        // arrange — init with baseline stats + empty achievements
        when(
          () => achievementRepo.computeStats('local-1'),
        ).thenAnswer((_) async => AgentStats(agentId: 'local-1'));
        when(
          () => achievementRepo.getUnlocks('local-1'),
        ).thenAnswer((_) async => <Achievement>[]);
        final vm = createVM();
        await vm.init();
        final beforeDetail =
            (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
        final beforeAchievements = beforeDetail.achievements;

        // act — re-stub with NEW instances but SAME content. The
        // non-const constructors ensure different identities for both
        // the AgentStats and the empty list.
        when(
          () => achievementRepo.computeStats('local-1'),
        ).thenAnswer((_) async => AgentStats(agentId: 'local-1'));
        when(
          () => achievementRepo.getUnlocks('local-1'),
        ).thenAnswer((_) async => <Achievement>[]);

        await vm.achievementRefresh();

        // assert — early-return fired, so detail data reference is unchanged
        final afterDetail =
            (vm.state.detailLoadState as LoadData<AgentDetailData>).value;
        expect(
          identical(beforeDetail, afterDetail),
          isTrue,
          reason:
              'Content-equal stats+achievements must skip state write, '
              'leaving the AgentDetailData reference unchanged. If this '
              'fails, the skip-if-unchanged check is using identity '
              'equality on the achievements list (List.==) instead of '
              'content equality (listEquals).',
        );
        // Sanity: achievements list itself is also the same reference
        expect(
          identical(beforeAchievements, afterDetail.achievements),
          isTrue,
          reason: 'achievements list reference must be unchanged',
        );
      });

      // Latent celebration-drop guard: when the skip-if-unchanged optimization
      // fires (e.g. after fix #2 above), the early-return at line 423 must
      // NOT also drop `result.freshUnlocks`. Otherwise a recompute that
      // returns the same stats+achievements but a non-empty freshUnlocks
      // (e.g. a celebration replay path, or any future use-case change
      // that decouples the two) would silently fail to update
      // state.newUnlocks and the UI would never see the unlock event.
      //
      // The real use case couples achievements+freshUnlocks (a new unlock
      // always changes the achievements list), so the latent bug only
      // surfaces via a mocked use case that returns mismatched data —
      // which is the exact defensive case this test pins.
      test('propagates freshUnlocks to state.newUnlocks even when stats+'
          'achievements are content-equal', () async {
        // Use a mocked use case to construct the latent scenario.
        final useCase = MockEvaluateAchievementsUseCase();
        when(() => useCase.execute('local-1')).thenAnswer(
          (_) async => EvaluateAchievementsResult(
            stats: const AgentStats(agentId: 'local-1'),
            achievements: const <Achievement>[],
            freshUnlocks: const <Achievement>[],
          ),
        );

        final vm = createVM(evaluateAchievements: useCase);
        await vm.init();
        expect(
          vm.state.newUnlocks,
          isEmpty,
          reason: 'baseline: no fresh unlocks yet',
        );

        // Re-stub: SAME stats+achievements, but a non-empty freshUnlocks.
        // (Real use case never produces this, but a future variant
        // could — and the VM must handle it correctly.)
        const freshUnlock = Achievement(
          id: 'first_dialog',
          icon: '🏆',
          name: '初次对话',
          description: '与虾完成第一次对话',
          tier: AchievementTier.gold,
          unlocked: true,
          unlockedAt: 1719500000000,
        );
        when(() => useCase.execute('local-1')).thenAnswer(
          (_) async => EvaluateAchievementsResult(
            stats: const AgentStats(agentId: 'local-1'),
            achievements: const <Achievement>[],
            freshUnlocks: const [freshUnlock],
          ),
        );

        await vm.achievementRefresh();

        // freshUnlocks MUST be written to state even when stats+achievements
        // are content-equal. Otherwise the celebration gets silently dropped
        // by the skip-if-unchanged early-return.
        expect(
          vm.state.newUnlocks,
          equals([freshUnlock]),
          reason:
              'freshUnlocks must propagate to state.newUnlocks even when '
              'stats+achievements are content-equal. If this fails, the '
              'skip-if-unchanged early-return is dropping the celebration '
              'event along with the (correctly-skipped) data update.',
        );
      });
    });
  });
}
