import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';

/// Minimal gateway that throws for configured instances.
class _FailingGateway implements IGatewayClient {
  final Set<String> failingInstances;

  _FailingGateway(this.failingInstances);

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async {
    if (failingInstances.contains(instanceId)) {
      throw Exception('Connection refused');
    }
    return [];
  }

  @override
  Future<void> connect(Instance i) => throw UnimplementedError();
  @override
  Future<void> disconnect(String id) => throw UnimplementedError();
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
  Future<bool> testConnection(Instance i) => throw UnimplementedError();
  @override
  Stream<GatewayConnectionState> connectionStateStream(String id) =>
      throw UnimplementedError();
  @override
  void resetConnectionState(String id) => throw UnimplementedError();
  @override
  Stream<Message> messageStream(String id) => throw UnimplementedError();
  @override
  Stream<ToolCall> toolCallStream(String id) => throw UnimplementedError();
  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String id) =>
      Stream.value(null);
  @override
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) =>
      const Stream<StreamingEvent>.empty();
  @override
  Stream<GatewayNotice> gatewayNoticeStream(String instanceId) =>
      const Stream<GatewayNotice>.empty();
  @override
  Future<void> dispose() => throw UnimplementedError();
}

void main() {
  group('Agent Providers', () {
    ProviderContainer createContainer({
      InMemoryInstanceRepo? instanceRepo,
      InMemoryAgentRepo? agentRepo,
      IGatewayClient? gatewayClient,
    }) {
      final container = ProviderContainer(
        overrides: [
          instanceRepoProvider.overrideWith(
            (ref) => instanceRepo ?? InMemoryInstanceRepo(),
          ),
          agentRepoProvider.overrideWith(
            (ref) => agentRepo ?? InMemoryAgentRepo(),
          ),
          gatewayClientProvider.overrideWith(
            (ref) => gatewayClient ?? MockGatewayClient(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('agentListProvider returns empty when no instances', () async {
      final container = createContainer();
      final data = await container.read(agentListProvider.future);
      expect(data.agents, isEmpty);
      expect(data.instanceNames, isEmpty);
    });

    test(
      'agentListProvider returns agents sorted (pinned first, then name)',
      () async {
        final agentRepo = InMemoryAgentRepo();
        final instanceRepo = InMemoryInstanceRepo();

        // Seed an instance
        await instanceRepo.save(
          Instance(
            id: 'inst-1',
            name: 'My MacBook',
            gatewayUrl: 'wss://test.com:18789',
            tokenRef: 'ref',
          ),
        );

        // Seed agents directly into repo (simulating post-sync state)
        final agentB = Agent(
          localId: 'local-b',
          remoteId: 'r-b',
          instanceId: 'inst-1',
          name: 'B虾',
          isPinned: false,
        );
        final agentA = Agent(
          localId: 'local-a',
          remoteId: 'r-a',
          instanceId: 'inst-1',
          name: 'A虾',
          isPinned: false,
        );
        final agentPinned = Agent(
          localId: 'local-p',
          remoteId: 'r-p',
          instanceId: 'inst-1',
          name: 'Z虾',
          isPinned: true,
        );
        await agentRepo.syncFromGateway('inst-1', [
          agentB,
          agentA,
          agentPinned,
        ]);

        // Mock gateway returns empty — agents are already seeded in repo
        final gateway = MockGatewayClient();

        final container = createContainer(
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
          gatewayClient: gateway,
        );

        final data = await container.read(agentListProvider.future);
        expect(data.agents.length, 3);
        expect(data.agents[0].isPinned, isTrue);
        expect(data.agents[1].name, 'A虾');
        expect(data.agents[2].name, 'B虾');
      },
    );

    test('agentListProvider builds instance name map', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'My MacBook',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'ref',
        ),
      );
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      final container = createContainer(
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        gatewayClient: MockGatewayClient(),
      );

      final data = await container.read(agentListProvider.future);
      expect(data.instanceNames['inst-1'], 'My MacBook');
    });

    test('agentListProvider returns syncErrors when gateway fails', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'My MacBook',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'ref',
        ),
      );
      // Seed cached agents — these should still be returned
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      final container = createContainer(
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        gatewayClient: _FailingGateway({'inst-1'}),
      );

      final data = await container.read(agentListProvider.future);

      expect(data.syncErrors, isNotEmpty);
      expect(data.syncErrors.containsKey('inst-1'), isTrue);
      expect(data.agents.length, 1);
      expect(data.agents.first.name, '产品虾');
    });

    test('agentListProvider returns empty syncErrors on success', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'My MacBook',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'ref',
        ),
      );

      final container = createContainer(
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        gatewayClient: _FailingGateway({}),
      );

      final data = await container.read(agentListProvider.future);

      expect(data.syncErrors, isEmpty);
    });
  });
}
