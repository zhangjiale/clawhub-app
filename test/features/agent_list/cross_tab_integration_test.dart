import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/features/instance_manager/providers/instance_providers.dart';

/// Integration test: Instance Create → Agent Sync → Agent List.
///
/// This test verifies the end-to-end contract that was broken:
/// after creating an instance and connecting to a Gateway,
/// agents MUST be auto-synced to the local DB and the
/// agentListProvider MUST return them.
///
/// We test at the Provider/UseCase level rather than full widget
/// tree to keep tests fast and deterministic. The widget-level
/// rendering of AgentListPage is already covered by agent_list_test.dart.
///
/// Iron Law 16.B compliance: verifies the connected → fetchAgents →
/// syncFromGateway side-effect chain through the real provider graph.
void main() {
  // Plain test() (non-widget) needs an explicit Flutter binding to
  // support rootBundle.loadString used by MockGatewayClient.loadMockData.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Instance → Agent sync contract', () {
    late ProviderContainer container;
    late InMemoryInstanceRepo instanceRepo;
    late InMemoryAgentRepo agentRepo;

    setUp(() {
      instanceRepo = InMemoryInstanceRepo();
      agentRepo = InMemoryAgentRepo();
      container = ProviderContainer(
        overrides: [
          instanceRepoProvider.overrideWith((ref) => instanceRepo),
          agentRepoProvider.overrideWith((ref) => agentRepo),
          gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> pumpEventLoop() async {
      // Allow ConnectionOrchestrator's async work to complete:
      // connect → Future() events (connecting → connected) →
      // _onConnectionStateChanged → _syncAgentsForInstance →
      // fetchAgents → syncFromGateway
      for (int i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    test('auto-sync populates agent repo after instance save', () async {
      // 1. Save instance via UseCase (triggers ConnectionOrchestrator)
      final useCase = container.read(saveInstanceUseCaseProvider);
      await useCase.execute(
        name: 'Test Server',
        gatewayUrl: 'wss://test.example.com:18789',
        token: 'test-token',
      );

      // 2. Pump event loop to allow ConnectionOrchestrator to:
      //    connect → connected → _syncAgentsForInstance → fetchAgents
      await pumpEventLoop();

      // 3. Read agents from DB — must NOT be empty
      final agents = await agentRepo.getAll();
      expect(
        agents,
        isNotEmpty,
        reason:
            'After creating an instance and connecting, '
            'ConnectionOrchestrator must auto-sync agents via fetchAgents. '
            'Before the fix, fetchAgents was never called, leaving agents '
            'empty until manual pull-to-refresh.',
      );
      expect(agents.any((a) => a.name == '默认助手'), isTrue);
      expect(agents.any((a) => a.name == '代码助手'), isTrue);
    });

    test(
      'agentListProvider returns agents after instance save + sync',
      () async {
        // 1. Create instance
        final useCase = container.read(saveInstanceUseCaseProvider);
        await useCase.execute(
          name: 'Test Server',
          gatewayUrl: 'wss://test.example.com:18789',
          token: 'test-token',
        );
        await pumpEventLoop();

        // 2. Invalidate providers (simulating the Fix #1 invalidation
        //    that happens in instance_list_page.dart)
        container.invalidate(instanceListProvider);
        container.invalidate(agentListProvider);

        // 3. Read agent list — should contain the auto-synced agents
        final data = await container.read(agentListProvider.future);
        expect(
          data.agents,
          isNotEmpty,
          reason:
              'agentListProvider must return auto-synced agents '
              'after an instance is created. Before Fix #1, the provider '
              'was not invalidated, so cached empty data was returned.',
        );
        expect(data.instanceNames.values, contains('Test Server'));
        expect(
          data.syncErrors,
          isEmpty,
          reason:
              'syncErrors must be empty because the instance is '
              'connected and fetchAgents succeeded',
        );
      },
    );

    test(
      'agent provider is refreshed by explicit invalidation on instance change',
      () async {
        // 1. Read agent list while DB is empty — should be empty
        final data1 = await container.read(agentListProvider.future);
        expect(data1.agents, isEmpty);

        // 2. Create instance — this syncs agents to DB, but provider
        //    is still cached. Without invalidation, data is stale.
        final useCase = container.read(saveInstanceUseCaseProvider);
        await useCase.execute(
          name: 'Test Server',
          gatewayUrl: 'wss://test.example.com:18789',
          token: 'test-token',
        );
        await pumpEventLoop();

        // 3. Invalidate providers (as instance_list_page.dart does)
        container.invalidate(instanceListProvider);
        container.invalidate(agentListProvider);

        // 4. Re-read — now returns fresh data
        final data2 = await container.read(agentListProvider.future);
        expect(
          data2.agents,
          isNotEmpty,
          reason:
              'After invalidation, agentListProvider must re-execute '
              'and return the auto-synced agents from the new instance. '
              'Without Fix #1, the provider would still return cached '
              'empty data from step 1.',
        );
        expect(data2.syncErrors, isEmpty);
      },
    );
  });
}
