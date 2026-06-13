import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';

/// Minimal IGatewayClient that returns the given agent lists per instance
/// or throws when configured.
class _TestGatewayClient implements IGatewayClient {
  final Map<String, List<Agent>> _agents;
  final Set<String> _failingInstances;

  _TestGatewayClient(this._agents, this._failingInstances);

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async {
    if (_failingInstances.contains(instanceId)) {
      throw Exception('Connection refused for $instanceId');
    }
    return _agents[instanceId] ?? [];
  }

  @override
  Future<void> connect(Instance instance) => throw UnimplementedError();

  @override
  Future<void> disconnect(String instanceId) => throw UnimplementedError();

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) => throw UnimplementedError();

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) => throw UnimplementedError();

  @override
  Future<bool> testConnection(Instance instance) => throw UnimplementedError();

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) =>
      throw UnimplementedError();

  @override
  void resetConnectionState(String instanceId) => throw UnimplementedError();

  @override
  Stream<Message> messageStream(String instanceId) =>
      throw UnimplementedError();

  @override
  Stream<ToolCall> toolCallStream(String instanceId) =>
      throw UnimplementedError();

  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId) =>
      Stream.value(null);

  @override
  Future<void> dispose() => throw UnimplementedError();
}

/// Helper to create an Agent with minimal required fields.
Agent _agent(String localId, String instanceId, String name) {
  return Agent(
    localId: localId,
    remoteId: 'r-$localId',
    instanceId: instanceId,
    name: name,
  );
}

/// Helper to create an Instance with minimal required fields.
Instance _instance(String id, String name) {
  return Instance(
    id: id,
    name: name,
    gatewayUrl: 'wss://test.com:18789',
    tokenRef: 'ref-$id',
  );
}

void main() {
  group('SyncAgentsUseCase', () {
    test('returns cached agents when all instances fail', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      // Seed cached agents
      await instanceRepo.save(_instance('inst-1', 'Alpha'));
      await agentRepo.syncFromGateway('inst-1', [
        _agent('a1', 'inst-1', '产品虾'),
      ]);

      final gateway = _TestGatewayClient({}, {'inst-1'});

      final useCase = SyncAgentsUseCase(
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        gatewayClient: gateway,
      );

      final result = await useCase.execute();

      expect(result.agents.length, 1);
      expect(result.agents.first.name, '产品虾');
      expect(result.syncErrors, isNotEmpty);
      expect(result.syncErrors.containsKey('inst-1'), isTrue);
      expect(result.syncErrors['inst-1'], contains('Connection refused'));
    });

    test('syncErrors only contains failed instances', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      await instanceRepo.save(_instance('inst-ok', 'OK'));
      await instanceRepo.save(_instance('inst-fail', 'Fail'));

      // Seed agents for both
      await agentRepo.syncFromGateway('inst-ok', [
        _agent('a1', 'inst-ok', '产品虾'),
      ]);
      await agentRepo.syncFromGateway('inst-fail', [
        _agent('a2', 'inst-fail', '代码虾'),
      ]);

      final gateway = _TestGatewayClient(
        {
          'inst-ok': [_agent('g1', 'inst-ok', '远程产品虾')],
        },
        {'inst-fail'},
      );

      final useCase = SyncAgentsUseCase(
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        gatewayClient: gateway,
      );

      final result = await useCase.execute();

      // inst-ok should have been updated with remote data
      expect(result.syncErrors.length, 1);
      expect(result.syncErrors.containsKey('inst-fail'), isTrue);
      expect(result.syncErrors.containsKey('inst-ok'), isFalse);
    });

    test('syncErrors is empty when all instances succeed', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      await instanceRepo.save(_instance('inst-1', 'Alpha'));

      final gateway = _TestGatewayClient({
        'inst-1': [_agent('g1', 'inst-1', '产品虾')],
      }, {});

      final useCase = SyncAgentsUseCase(
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        gatewayClient: gateway,
      );

      final result = await useCase.execute();

      expect(result.syncErrors, isEmpty);
      expect(result.agents.length, 1);
      expect(result.agents.first.name, '产品虾');
    });

    test('aggregates agents from all instances', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      await instanceRepo.save(_instance('inst-1', 'Alpha'));
      await instanceRepo.save(_instance('inst-2', 'Beta'));

      final gateway = _TestGatewayClient({
        'inst-1': [_agent('g1', 'inst-1', '虾A')],
        'inst-2': [_agent('g2', 'inst-2', '虾B')],
      }, {});

      final useCase = SyncAgentsUseCase(
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        gatewayClient: gateway,
      );

      final result = await useCase.execute();

      expect(result.agents.length, 2);
      final names = result.agents.map((a) => a.name).toSet();
      expect(names, containsAll(['虾A', '虾B']));
      expect(result.syncErrors, isEmpty);
    });

    test(
      'preserves instanceNames and instanceStatuses on partial failure',
      () async {
        final agentRepo = InMemoryAgentRepo();
        final instanceRepo = InMemoryInstanceRepo();

        await instanceRepo.save(_instance('inst-ok', 'OK Server'));
        await instanceRepo.save(_instance('inst-fail', 'Dead Server'));

        // Seed cached agent for failing instance
        await agentRepo.syncFromGateway('inst-fail', [
          _agent('a1', 'inst-fail', '离线虾'),
        ]);

        final gateway = _TestGatewayClient(
          {
            'inst-ok': [_agent('g1', 'inst-ok', '在线虾')],
          },
          {'inst-fail'},
        );

        final useCase = SyncAgentsUseCase(
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
          gatewayClient: gateway,
        );

        final result = await useCase.execute();

        // Both instances appear in name/status maps even though one failed
        expect(result.instanceNames['inst-ok'], 'OK Server');
        expect(result.instanceNames['inst-fail'], 'Dead Server');
        expect(result.instanceStatuses.containsKey('inst-ok'), isTrue);
        expect(result.instanceStatuses.containsKey('inst-fail'), isTrue);
        expect(result.syncErrors.length, 1);
      },
    );
  });
}
