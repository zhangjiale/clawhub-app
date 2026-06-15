import 'dart:async';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/errors.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';

class MockAgentRepo extends Mock implements IAgentRepo {}

class MockInstanceRepo extends Mock implements IInstanceRepo {}

class MockMessageRepo extends Mock implements IMessageRepo {}

class MockAvatarStorageService extends Mock implements IAvatarStorageService {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
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
      avatarStorageService = MockAvatarStorageService();
    });

    AgentProfileViewModel createVM() {
      return AgentProfileViewModel(
        agentRepo: agentRepo,
        instanceRepo: instanceRepo,
        messageRepo: messageRepo,
        avatarStorageService: avatarStorageService,
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
        () => agentRepo.updateLocalProfile(
          'local-1',
          nickname: any(named: 'nickname'),
          themeColor: any(named: 'themeColor'),
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

      final completer = Completer<Agent>();
      when(
        () => agentRepo.updateLocalProfile(
          'local-1',
          nickname: any(named: 'nickname'),
          themeColor: any(named: 'themeColor'),
        ),
      ).thenAnswer((_) => completer.future);

      // 第一次调用进入 isSaving
      final first = vm.saveProfile(nickname: 'nick', themeColor: '#0984e3');
      // 第二次调用应被 guard 直接丢弃
      final second = vm.saveProfile(nickname: 'nick2', themeColor: '#a29bfe');

      completer.complete(testAgent);
      await first;
      await second;

      verify(
        () => agentRepo.updateLocalProfile(
          'local-1',
          nickname: any(named: 'nickname'),
          themeColor: any(named: 'themeColor'),
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
        () => agentRepo.updateLocalProfile(
          'local-1',
          nickname: any(named: 'nickname'),
          themeColor: any(named: 'themeColor'),
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
  });
}
