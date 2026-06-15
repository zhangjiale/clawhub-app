import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/message_hub/message_hub_page.dart';
import 'package:claw_hub/features/message_hub/providers/message_hub_providers.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('MessageHubPage', () {
    testWidgets('shows empty state when no conversations', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationListProvider.overrideWith(
              (ref) async => const ConversationListData(previews: []),
            ),
          ],
          child: const MaterialApp(home: MessageHubPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有消息'), findsOneWidget);
      expect(find.text('去虾列表找一只虾开始聊天吧'), findsOneWidget);
    });

    testWidgets('shows conversation tiles when data exists', (tester) async {
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
      );
      final conversation = Conversation(
        agentId: 'local-1',
        instanceId: 'inst-1',
        lastMessagePreview: '你好，有什么可以帮你的？',
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationListProvider.overrideWith(
              (ref) async => ConversationListData(
                previews: [
                  ConversationPreview(
                    conversation: conversation,
                    agent: agent,
                    instanceName: 'My MacBook',
                    healthStatus: HealthStatus.unknown,
                  ),
                ],
              ),
            ),
          ],
          child: const MaterialApp(home: MessageHubPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('产品虾'), findsOneWidget);
      expect(find.text('你好，有什么可以帮你的？'), findsOneWidget);
    });

    testWidgets('shows multiple conversation tiles', (tester) async {
      final agent1 = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
      );
      final agent2 = Agent(
        localId: 'local-2',
        remoteId: 'r-2',
        instanceId: 'inst-1',
        name: '代码虾',
        themeColor: '#0984e3',
      );
      final now = DateTime.now().millisecondsSinceEpoch;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationListProvider.overrideWith(
              (ref) async => ConversationListData(
                previews: [
                  ConversationPreview(
                    conversation: Conversation(
                      agentId: 'local-1',
                      instanceId: 'inst-1',
                      lastMessagePreview: '产品相关的讨论',
                      lastMessageTime: now,
                    ),
                    agent: agent1,
                    instanceName: 'My MacBook',
                    healthStatus: HealthStatus.unknown,
                  ),
                  ConversationPreview(
                    conversation: Conversation(
                      agentId: 'local-2',
                      instanceId: 'inst-1',
                      lastMessagePreview: '代码已更新',
                      lastMessageTime: now - 60000,
                    ),
                    agent: agent2,
                    instanceName: 'My MacBook',
                    healthStatus: HealthStatus.unknown,
                  ),
                ],
              ),
            ),
          ],
          child: const MaterialApp(home: MessageHubPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('产品虾'), findsOneWidget);
      expect(find.text('代码虾'), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationListProvider.overrideWith(
              (ref) async => throw Exception('Connection failed'),
            ),
          ],
          child: const MaterialApp(home: MessageHubPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Failed to load messages'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
