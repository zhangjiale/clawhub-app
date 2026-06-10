import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/errors.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';

class MockAgentRepo extends Mock implements IAgentRepo {}
class MockInstanceRepo extends Mock implements IInstanceRepo {}
class MockMessageRepo extends Mock implements IMessageRepo {}

void main() {
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
    });

    AgentProfileViewModel createVM() {
      return AgentProfileViewModel(
        agentRepo: agentRepo,
        instanceRepo: instanceRepo,
        messageRepo: messageRepo,
        agentId: 'local-1',
      );
    }

    test('init() loads agent and sets LoadData on success', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 42);

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
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenThrow(Exception('DB error'));
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      final state = vm.state;
      expect(state.detailLoadState, isA<LoadData<AgentDetailData>>());
      final data = (state.detailLoadState as LoadData<AgentDetailData>).value;
      expect(data.instance, isNull);
    });

    test('saveProfile updates state on success', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);
      when(() => agentRepo.updateLocalProfile(
        'local-1',
        nickname: '我的产品虾',
        themeColor: '#0984e3',
      )).thenAnswer((_) async => testAgent.copyWith(
        nickname: '我的产品虾',
        themeColor: '#0984e3',
      ));

      final vm = createVM();
      await vm.init();

      // Re-stub for the refresh() inside saveProfile
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent.copyWith(
        nickname: '我的产品虾',
        themeColor: '#0984e3',
      ));
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      await vm.saveProfile('local-1', '我的产品虾', '#0984e3');

      final state = vm.state;
      expect(state.saveSuccess, true);
      expect(state.isSaving, false);
    });

    test('saveProfile sets saveError on failure', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      when(() => agentRepo.updateLocalProfile(
        'local-1',
        nickname: any(named: 'nickname'),
        themeColor: any(named: 'themeColor'),
      )).thenThrow(Exception('Save failed'));

      await vm.saveProfile('local-1', 'nick', '#0984e3');

      final state = vm.state;
      expect(state.saveError, isNotNull);
      expect(state.isSaving, false);
      expect(state.saveSuccess, false);
    });

    test('clearSaveResult resets save flags', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      when(() => agentRepo.updateLocalProfile(
        'local-1',
        nickname: any(named: 'nickname'),
        themeColor: any(named: 'themeColor'),
      )).thenThrow(Exception('Save failed'));
      await vm.saveProfile('local-1', 'nick', '#0984e3');
      expect(vm.state.saveError, isNotNull);

      vm.clearSaveResult();
      expect(vm.state.saveError, isNull);
      expect(vm.state.saveSuccess, false);
    });

    test('agent getter returns loaded agent', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      expect(vm.agent, isNotNull);
      expect(vm.agent!.name, '产品虾');
    });

    test('dispose can be called safely', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();
      vm.dispose();
    });
  });
}
