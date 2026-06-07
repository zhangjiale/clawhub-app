import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('MessageBubble', () {
    final userMessage = Message(
      clientId: 'c1',
      conversationId: 'conv1',
      agentId: 'agent1',
      role: MessageRole.user,
      content: 'Hello, Agent!',
      type: MessageType.text,
      logicalClock: 1,
      status: MessageStatus.sent,
    );

    final agentMessage = Message(
      clientId: 'c2',
      serverId: 's2',
      conversationId: 'conv1',
      agentId: 'agent1',
      role: MessageRole.agent,
      content: 'Hi! How can I help?',
      type: MessageType.text,
      logicalClock: 2,
      status: MessageStatus.delivered,
    );

    Widget buildBubble(Message message, {String agentName = '产品虾'}) {
      return MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            agentName: agentName,
          ),
        ),
      );
    }

    testWidgets('renders user message content', (tester) async {
      await tester.pumpWidget(buildBubble(userMessage));
      expect(find.text('Hello, Agent!'), findsOneWidget);
    });

    testWidgets('renders agent message content', (tester) async {
      await tester.pumpWidget(buildBubble(agentMessage));
      expect(find.text('Hi! How can I help?'), findsOneWidget);
    });

    testWidgets('user message has no agent name', (tester) async {
      await tester.pumpWidget(buildBubble(userMessage));
      expect(find.text('产品虾'), findsNothing);
    });

    testWidgets('agent message shows agent name', (tester) async {
      await tester.pumpWidget(buildBubble(agentMessage));
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('user message shows status icon', (tester) async {
      await tester.pumpWidget(buildBubble(userMessage));
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('failed message shows error icon', (tester) async {
      final failedMsg = userMessage.copyWith(status: MessageStatus.failed);
      await tester.pumpWidget(buildBubble(failedMsg));
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('image type shows placeholder text', (tester) async {
      final imgMsg = userMessage.copyWith(
        type: MessageType.image,
        content: '',
      );
      await tester.pumpWidget(buildBubble(imgMsg));
      expect(find.text('[图片]'), findsOneWidget);
    });

    testWidgets('file type shows placeholder text', (tester) async {
      final fileMsg = userMessage.copyWith(
        type: MessageType.file,
        content: '',
      );
      await tester.pumpWidget(buildBubble(fileMsg));
      expect(find.text('[文件]'), findsOneWidget);
    });
  });
}
