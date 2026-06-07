import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/features/instance_manager/providers/instance_providers.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';

void main() {
  group('Instance Providers', () {
    ProviderContainer createContainer() {
      final container = ProviderContainer(
        overrides: [
          instanceRepoProvider.overrideWith((ref) => InMemoryInstanceRepo()),
          gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('instanceListProvider returns empty list initially', () async {
      final container = createContainer();
      final instances = await container.read(instanceListProvider.future);
      expect(instances, isEmpty);
    });

    test('instanceListProvider returns saved instances', () async {
      final container = createContainer();
      final repo = container.read(instanceRepoProvider);

      await repo.save(Instance(
        id: 'inst-1', name: 'Test Instance',
        gatewayUrl: 'wss://test.com:18789', tokenRef: 'ref',
      ));

      final instances = await container.read(instanceListProvider.future);
      expect(instances.length, 1);
      expect(instances.first.name, 'Test Instance');
    });
  });
}
