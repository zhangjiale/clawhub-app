import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';

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
}
