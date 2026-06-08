import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/message_hub/providers/message_hub_providers.dart';
import 'package:claw_hub/features/message_hub/widgets/conversation_tile.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  final testAgent = Agent(
    localId: 'local-1',
    remoteId: 'r-1',
    instanceId: 'inst-1',
    name: '产品虾',
    themeColor: '#6c5ce7',
    description: '产品规划',
  );

  final testConversation = Conversation(
    agentId: 'local-1',
    instanceId: 'inst-1',
    lastMessagePreview: '你好，有什么可以帮你的？',
    lastMessageTime: DateTime.now().millisecondsSinceEpoch - 300000, // 5 min ago
    unreadCount: 0,
  );

  group('ConversationTile', () {
    testWidgets('shows agent name and preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationTile(
              preview: ConversationPreview(
                conversation: testConversation,
                agent: testAgent,
                instanceName: 'My MacBook',
                healthStatus: HealthStatus.unknown,
              ),
            ),
          ),
        ),
      );

      expect(find.text('产品虾'), findsOneWidget);
      expect(
        find.text('你好，有什么可以帮你的？'),
        findsOneWidget,
      );
    });

    testWidgets('truncates long previews to 40 chars', (tester) async {
      final longPreview = '这是一条非常非常非常非常非常非常非常非常长的消息预览文本测试数据';
      final conv = Conversation(
        agentId: 'local-1',
        instanceId: 'inst-1',
        lastMessagePreview: longPreview,
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationTile(
              preview: ConversationPreview(
                conversation: conv,
                agent: testAgent,
                instanceName: 'My MacBook',
                healthStatus: HealthStatus.unknown,
              ),
            ),
          ),
        ),
      );

      final displayed =
          tester.widget<Text>(find.textContaining('这是一条')).data;
      expect(displayed!.length, lessThanOrEqualTo(41)); // 40 chars + … = 41
    });

    testWidgets('shows unread badge when count > 0', (tester) async {
      final conv = Conversation(
        agentId: 'local-1',
        instanceId: 'inst-1',
        lastMessagePreview: 'hello',
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
        unreadCount: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationTile(
              preview: ConversationPreview(
                conversation: conv,
                agent: testAgent,
                instanceName: 'My MacBook',
                healthStatus: HealthStatus.unknown,
              ),
            ),
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows 99+ for large unread counts', (tester) async {
      final conv = Conversation(
        agentId: 'local-1',
        instanceId: 'inst-1',
        lastMessagePreview: 'hello',
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
        unreadCount: 150,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationTile(
              preview: ConversationPreview(
                conversation: conv,
                agent: testAgent,
                instanceName: 'My MacBook',
                healthStatus: HealthStatus.unknown,
              ),
            ),
          ),
        ),
      );

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('hides unread badge when count is 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationTile(
              preview: ConversationPreview(
                conversation: testConversation,
                agent: testAgent,
                instanceName: 'My MacBook',
                healthStatus: HealthStatus.unknown,
              ),
            ),
          ),
        ),
      );

      // No red badge should be present — check for the badge widget absence
      expect(find.text('0'), findsNothing);
    });

    testWidgets('shows muted icon when conversation is muted', (tester) async {
      final conv = Conversation(
        agentId: 'local-1',
        instanceId: 'inst-1',
        lastMessagePreview: 'hello',
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
        isMuted: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationTile(
              preview: ConversationPreview(
                conversation: conv,
                agent: testAgent,
                instanceName: 'My MacBook',
                healthStatus: HealthStatus.unknown,
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.volume_off), findsOneWidget);
    });

    testWidgets('shows placeholder text for empty preview', (tester) async {
      final conv = Conversation(
        agentId: 'local-1',
        instanceId: 'inst-1',
        lastMessagePreview: null,
        lastMessageTime: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationTile(
              preview: ConversationPreview(
                conversation: conv,
                agent: testAgent,
                instanceName: 'My MacBook',
                healthStatus: HealthStatus.unknown,
              ),
            ),
          ),
        ),
      );

      expect(find.text('开始对话吧'), findsOneWidget);
    });

    testWidgets('tapping tile calls onTap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationTile(
              preview: ConversationPreview(
                conversation: testConversation,
                agent: testAgent,
                instanceName: 'My MacBook',
                healthStatus: HealthStatus.unknown,
              ),
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('产品虾'));
      expect(tapped, isTrue);
    });
  });
}
