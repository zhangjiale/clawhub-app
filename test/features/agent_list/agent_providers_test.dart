import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';

void main() {
  group('Agent Providers', () {
    ProviderContainer createContainer({
      InMemoryInstanceRepo? instanceRepo,
      InMemoryAgentRepo? agentRepo,
      MockGatewayClient? gatewayClient,
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

    test('agentListProvider returns agents sorted (pinned first, then name)', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      // Seed an instance
      await instanceRepo.save(Instance(
        id: 'inst-1', name: 'My MacBook',
        gatewayUrl: 'wss://test.com:18789', tokenRef: 'ref',
      ));

      // Seed agents directly into repo (simulating post-sync state)
      final agentB = Agent(
        localId: 'local-b', remoteId: 'r-b',
        instanceId: 'inst-1', name: 'B虾', isPinned: false,
      );
      final agentA = Agent(
        localId: 'local-a', remoteId: 'r-a',
        instanceId: 'inst-1', name: 'A虾', isPinned: false,
      );
      final agentPinned = Agent(
        localId: 'local-p', remoteId: 'r-p',
        instanceId: 'inst-1', name: 'Z虾', isPinned: true,
      );
      await agentRepo.syncFromGateway('inst-1', [agentB, agentA, agentPinned]);

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
    });

    test('agentListProvider builds instance name map', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      await instanceRepo.save(Instance(
        id: 'inst-1', name: 'My MacBook',
        gatewayUrl: 'wss://test.com:18789', tokenRef: 'ref',
      ));
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1', remoteId: 'r-1',
          instanceId: 'inst-1', name: '产品虾',
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
  });
}
