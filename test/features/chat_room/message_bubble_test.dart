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
          body: MessageBubble(message: message, agentName: agentName),
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

    testWidgets('agent message does NOT show avatar', (tester) async {
      await tester.pumpWidget(buildBubble(agentMessage));
      // Per design spec 4.2.2: agent messages have no avatar in the bubble —
      // the avatar only appears in the AppBar header (Section 4.1.2).
      expect(find.text('产品虾'), findsNothing);
      expect(find.text('产'), findsNothing);
    });

    testWidgets('agent message shows timestamp below bubble', (tester) async {
      await tester.pumpWidget(buildBubble(agentMessage));
      // Each message now includes a formatted time like "HH:MM"
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'^\d{2}:\d{2}$').hasMatch(w.data ?? ''),
        ),
        findsOneWidget,
      );
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
      final imgMsg = userMessage.copyWith(type: MessageType.image, content: '');
      await tester.pumpWidget(buildBubble(imgMsg));
      expect(find.text('[图片]'), findsOneWidget);
    });

    testWidgets('file type shows placeholder text', (tester) async {
      final fileMsg = userMessage.copyWith(type: MessageType.file, content: '');
      await tester.pumpWidget(buildBubble(fileMsg));
      expect(find.text('[文件]'), findsOneWidget);
    });

    // ───── regression: chat history 把 userPlaceholder 误分类为 user 后,user 气泡
    // ━━━━━ 被上传占位文本占满。见 PR 描述 §2。(toolResult 的渲染测试移至
    // ━━━━━ tool_call_card_test.dart 的 toolCallFromMessage 组 —— 历史路径改用
    // ━━━━━ ToolCallCard,不再走 MessageBubble。)

    testWidgets('userPlaceholder renders as inline strip, NOT user bubble', (
      tester,
    ) async {
      final placeholderMsg = Message(
        clientId: 'p1',
        serverId: 'sp1',
        conversationId: 'conv1',
        agentId: 'agent1',
        role: MessageRole.userPlaceholder,
        content: '[User sent media without caption]',
        type: MessageType.file,
        logicalClock: 4,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: MessageStatus.sent,
        metadata: const {
          'mediaPaths': ['/tmp/foo.txt'],
        },
      );
      await tester.pumpWidget(buildBubble(placeholderMsg, agentName: '日程虾'));
      // 占位 body 文本不该作为用户气泡渲染。
      expect(find.text('[User sent media without caption]'), findsNothing);
      // 应该看到脟耕的「文件已上传」提示。
      expect(find.text('📎 文件已上传'), findsOneWidget);
    });

    testWidgets(
      'system role renders content as a centered notice (NOT dropped)',
      (tester) async {
        final sysMsg = Message(
          clientId: 's1',
          conversationId: 'conv1',
          agentId: 'agent1',
          role: MessageRole.system,
          content: 'system notice',
          type: MessageType.text,
          logicalClock: 5,
          status: MessageStatus.delivered,
        );
        await tester.pumpWidget(buildBubble(sysMsg, agentName: '日程虾'));
        // system 消息不再凭空消失(SizedBox.shrink)——渲染成居中淡灰小条,内容可见。
        expect(find.text('system notice'), findsOneWidget);
      },
    );

    testWidgets('system role with empty content renders nothing', (
      tester,
    ) async {
      final sysMsg = Message(
        clientId: 's2',
        conversationId: 'conv1',
        agentId: 'agent1',
        role: MessageRole.system,
        content: '',
        type: MessageType.text,
        logicalClock: 6,
        status: MessageStatus.delivered,
      );
      await tester.pumpWidget(buildBubble(sysMsg, agentName: '日程虾'));
      expect(find.byType(Text), findsNothing);
    });
  });
}
