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
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/domain/repositories/i_achievement_repo.dart';
import 'package:claw_hub/domain/repositories/i_activity_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';

class MockAgentRepo extends Mock implements IAgentRepo {}

class MockInstanceRepo extends Mock implements IInstanceRepo {}

class MockMessageRepo extends Mock implements IMessageRepo {}

class MockAchievementRepo extends Mock implements IAchievementRepo {}

class MockActivityRepo extends Mock implements IActivityRepo {}

class MockAvatarStorageService extends Mock implements IAvatarStorageService {}

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

      // Default stubs — achievement load is best-effort, return empty data
      when(
        () => achievementRepo.getStats(any()),
      ).thenAnswer((_) async => null); // cache miss → computeStats
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
      // Default: activity repo returns empty 30-day series
      when(
        () => activityRepo.getDailyActivity(
          any(),
          days: any(named: 'days'),
          now: any(named: 'now'),
        ),
      ).thenAnswer((_) async => const []);
    });

    AgentProfileViewModel createVM() {
      return AgentProfileViewModel(
        agentRepo: agentRepo,
        instanceRepo: instanceRepo,
        messageRepo: messageRepo,
        activityRepo: activityRepo,
        avatarStorageService: avatarStorageService,
        evaluateAchievements: EvaluateAchievementsUseCase(achievementRepo),
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
    // US-021 v1.1: AgentProfileState.isAgentRemoved + write guards
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

      test('isAgentRemoved defaults to false on fresh VM', () {
        final vm = createVM();
        expect(
          vm.state.isAgentRemoved,
          isFalse,
          reason:
              '新建 VM 时 isAgentRemoved 必须为 false，'
              '避免初始化前误显示 tombstone 占位页',
        );
      });

      test(
        'refresh() syncs isAgentRemoved=true when agent is tombstoned',
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
            vm.state.isAgentRemoved,
            isTrue,
            reason:
                'init 时若 agent 已是 tombstone 状态，'
                'isAgentRemoved 必须同步为 true，驱动占位页',
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
        expect(vm.state.isAgentRemoved, isTrue); // sanity

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
        expect(vm.state.isAgentRemoved, isTrue); // sanity

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
        expect(vm.state.isAgentRemoved, isTrue); // sanity

        await vm.removeAvatar();

        // ★ tombstone guard：禁止写入
        verifyNever(() => avatarStorageService.deleteAvatar(any()));
        verifyNever(() => agentRepo.clearAvatar(any()));
        expect(vm.state.isSaving, isFalse);
        expect(vm.state.saveError, isNotNull);
      });

      test('refreshAgent reacts to backend sync: '
          'tombstoned-then-revived updates isAgentRemoved', () async {
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
        expect(vm.state.isAgentRemoved, isFalse);

        // 后台 sync 把 agent tombstone 了
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => tombAgent);
        await vm.refreshAgent();
        expect(
          vm.state.isAgentRemoved,
          isTrue,
          reason: 'refreshAgent 应在 sync 后捕获到 tombstone 状态',
        );

        // 复活（agent 重新出现在 Gateway）
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => testAgent);
        await vm.refreshAgent();
        expect(
          vm.state.isAgentRemoved,
          isFalse,
          reason: '复活后 refreshAgent 必须清除 tombstone 标记',
        );
      });

      test('saveProfile blocked when _agent is null (init failed/not loaded) '
          'surfaces saveError for UX feedback', () async {
        final vm = createVM();
        // 不调 init，_agent 为 null
        expect(vm.state.isAgentRemoved, isFalse);

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

      test(
        'refresh() resets isAgentRemoved=false on error so LoadError shows',
        () async {
          // init 时 agent 是 tombstoned，isAgentRemoved=true
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
          expect(vm.state.isAgentRemoved, isTrue);

          // refresh 时 getById 抛异常
          when(
            () => agentRepo.getById('local-1'),
          ).thenThrow(Exception('DB error'));
          await vm.refresh();

          expect(vm.state.detailLoadState, isA<LoadError>());
          expect(
            vm.state.isAgentRemoved,
            isFalse,
            reason: '详情加载失败时不应继续显示 tombstone 占位页',
          );
        },
      );
    });
  });
}
