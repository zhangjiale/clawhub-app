import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';

void main() {
  group('DI Providers', () {
    test('mockGatewayClientProvider returns MockGatewayClient', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final client = container.read(mockGatewayClientProvider);
      expect(client, isA<MockGatewayClient>());
    });

    test('instanceRepoProvider returns InMemoryInstanceRepo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final repo = container.read(instanceRepoProvider);
      expect(repo, isA<InMemoryInstanceRepo>());
    });

    test('agentRepoProvider returns InMemoryAgentRepo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final repo = container.read(agentRepoProvider);
      expect(repo, isA<InMemoryAgentRepo>());
    });

    test('messageRepoProvider returns InMemoryMessageRepo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final repo = container.read(messageRepoProvider);
      expect(repo, isA<InMemoryMessageRepo>());
    });

    test('conversationRepoProvider returns InMemoryConversationRepo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final repo = container.read(conversationRepoProvider);
      expect(repo, isA<InMemoryConversationRepo>());
    });

    test('gatewayClientProvider and mockGatewayClientProvider are same instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final asGateway = container.read(gatewayClientProvider);
      final asMock = container.read(mockGatewayClientProvider);
      expect(identical(asGateway, asMock), isTrue);
    });

    test('use case providers resolve correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sendMessage = container.read(sendMessageUseCaseProvider);
      expect(sendMessage, isNotNull);

      final saveInstance = container.read(saveInstanceUseCaseProvider);
      expect(saveInstance, isNotNull);
    });
  });
}
