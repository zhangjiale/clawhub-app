import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/features/message_hub/providers/message_hub_providers.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';

void main() {
  group('Message Hub Providers', () {
    ProviderContainer createContainer({
      InMemoryInstanceRepo? instanceRepo,
      InMemoryAgentRepo? agentRepo,
      InMemoryConversationRepo? conversationRepo,
      InMemoryMessageRepo? messageRepo,
    }) {
      final container = ProviderContainer(
        overrides: [
          instanceRepoProvider.overrideWith(
            (ref) => instanceRepo ?? InMemoryInstanceRepo(),
          ),
          agentRepoProvider.overrideWith(
            (ref) => agentRepo ?? InMemoryAgentRepo(),
          ),
          conversationRepoProvider.overrideWith(
            (ref) => conversationRepo ?? InMemoryConversationRepo(),
          ),
          messageRepoProvider.overrideWith(
            (ref) => messageRepo ?? InMemoryMessageRepo(),
          ),
          gatewayClientProvider.overrideWith(
            (ref) => MockGatewayClient(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('conversationListProvider returns empty when no conversations', () async {
      final container = createContainer();
      final data = await container.read(conversationListProvider.future);
      expect(data.previews, isEmpty);
    });

    test('conversationListProvider returns sorted conversations with agent info',
        () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();
      final conversationRepo = InMemoryConversationRepo();

      // Seed instance
      await instanceRepo.save(Instance(
        id: 'inst-1',
        name: 'My MacBook',
        gatewayUrl: 'wss://test.com:18789',
        tokenRef: 'ref',
      ));

      // Seed agent
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);

      // Seed conversations
      final conv1 = Conversation(
        agentId: 'local-1',
        instanceId: 'inst-1',
        lastMessagePreview: '你好，有什么可以帮你的？',
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
      );
      await conversationRepo.getOrCreate('inst-1', 'local-1');
      await conversationRepo.updateLastMessage(
        conversationId: conv1.id,
        messageId: 'msg-1',
        preview: '你好，有什么可以帮你的？',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        role: MessageRole.agent,
      );

      final container = createContainer(
        agentRepo: agentRepo,
        instanceRepo: instanceRepo,
        conversationRepo: conversationRepo,
      );

      final data = await container.read(conversationListProvider.future);
      expect(data.previews.length, 1);
      expect(data.previews.first.agent.name, '产品虾');
      expect(data.previews.first.instanceName, 'My MacBook');
      expect(
        data.previews.first.conversation.lastMessagePreview,
        '你好，有什么可以帮你的？',
      );
    });

    test('conversationListProvider skips conversations with missing agents',
        () async {
      final conversationRepo = InMemoryConversationRepo();

      // Seed conversation for a non-existent agent
      final conv = Conversation(
        agentId: 'missing-agent',
        instanceId: 'inst-1',
        lastMessagePreview: 'test',
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
      );
      // Directly insert into store via getOrCreate which creates the entry
      await conversationRepo.getOrCreate('inst-1', 'missing-agent');
      await conversationRepo.updateLastMessage(
        conversationId: conv.id,
        messageId: 'msg-1',
        preview: 'test',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        role: MessageRole.agent,
      );

      final container = createContainer(
        conversationRepo: conversationRepo,
      );

      final data = await container.read(conversationListProvider.future);
      // Missing agent — skipped
      expect(data.previews, isEmpty);
    });

    test('conversationListProvider includes unread count', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();
      final conversationRepo = InMemoryConversationRepo();

      await instanceRepo.save(Instance(
        id: 'inst-1',
        name: 'My MacBook',
        gatewayUrl: 'wss://test.com:18789',
        tokenRef: 'ref',
      ));

      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      final conv = Conversation(
        agentId: 'local-1',
        instanceId: 'inst-1',
        lastMessagePreview: 'hello',
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
        unreadCount: 3,
      );
      await conversationRepo.getOrCreate('inst-1', 'local-1');
      await conversationRepo.incrementUnread(conv.id, count: 3);
      await conversationRepo.updateLastMessage(
        conversationId: conv.id,
        messageId: 'msg-1',
        preview: 'hello',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        role: MessageRole.agent,
      );

      final container = createContainer(
        agentRepo: agentRepo,
        instanceRepo: instanceRepo,
        conversationRepo: conversationRepo,
      );

      final data = await container.read(conversationListProvider.future);
      expect(data.previews.length, 1);
      expect(data.previews.first.conversation.unreadCount, 3);
    });
  });
}
