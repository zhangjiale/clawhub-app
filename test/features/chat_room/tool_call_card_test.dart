import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/tool_call_card.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('ToolCallCard', () {
    Widget buildCard(ToolCall toolCall) {
      return MaterialApp(
        home: Scaffold(body: ToolCallCard(toolCall: toolCall)),
      );
    }

    // ---- pending ----

    testWidgets('shows tool name', (tester) async {
      await tester.pumpWidget(
        buildCard(
          ToolCall(id: 'tc-1', messageId: 'msg-1', toolName: 'ReadFile'),
        ),
      );

      expect(find.text('ReadFile'), findsOneWidget);
    });

    testWidgets('shows "Pending..." text and spinner when pending', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-1',
            messageId: 'msg-1',
            toolName: 'ReadFile',
            status: ToolCallStatus.pending,
          ),
        ),
      );

      expect(find.text('Pending...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // ---- running ----

    testWidgets('shows "Running..." text and spinner when running', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-2',
            messageId: 'msg-2',
            toolName: 'WriteFile',
            status: ToolCallStatus.running,
          ),
        ),
      );

      expect(find.text('Running...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // ---- success ----

    testWidgets('shows check icon and "✅ Completed" when success', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-3',
            messageId: 'msg-3',
            toolName: 'Bash',
            status: ToolCallStatus.success,
          ),
        ),
      );

      expect(find.text('✅ Completed'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows output result when success has output', (tester) async {
      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-4',
            messageId: 'msg-4',
            toolName: 'Bash',
            status: ToolCallStatus.success,
            outputResult: '{"exitCode": 0}',
          ),
        ),
      );

      expect(find.text('{"exitCode": 0}'), findsOneWidget);
    });

    // ---- failed ----

    testWidgets('shows error icon and "❌ Failed" when failed', (tester) async {
      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-5',
            messageId: 'msg-5',
            toolName: 'Bash',
            status: ToolCallStatus.failed,
          ),
        ),
      );

      expect(find.text('❌ Failed'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    // ---- _truncateOutput (tested via rendered output) ----

    testWidgets('truncates long output to 120 chars', (tester) async {
      final longOutput = 'x' * 200;
      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-6',
            messageId: 'msg-6',
            toolName: 'Bash',
            status: ToolCallStatus.success,
            outputResult: longOutput,
          ),
        ),
      );

      final expected = '${'x' * 120}...';
      expect(find.text(expected), findsOneWidget);
    });

    testWidgets('does not truncate output within 120 chars', (tester) async {
      const shortOutput = 'hello world';
      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-7',
            messageId: 'msg-7',
            toolName: 'Bash',
            status: ToolCallStatus.success,
            outputResult: shortOutput,
          ),
        ),
      );

      expect(find.text('hello world'), findsOneWidget);
    });
  });

  // ───── toolCallFromMessage: 历史路径(退出再进来)把 toolResult Message 转成
  // ToolCall,复用 ToolCallCard 渲染,保证和实时路径长得一致。
  group('toolCallFromMessage', () {
    Message mkMessage({
      String? content = 'drwxr-xr-x ...',
      Map<String, dynamic>? metadata = const {
        'toolName': 'exec',
        'isError': false,
      },
      String? serverId = 'srv-1',
    }) => Message(
      clientId: 'c1',
      serverId: serverId,
      conversationId: 'conv1',
      agentId: 'a1',
      role: MessageRole.toolResult,
      content: content,
      type: MessageType.text,
      logicalClock: 1,
      timestamp: 1718000000000,
      status: MessageStatus.delivered,
      metadata: metadata,
    );

    test('converts toolResult Message to a completed ToolCall', () {
      final tc = toolCallFromMessage(mkMessage());
      expect(tc.id, 'srv-1');
      expect(tc.messageId, 'c1');
      expect(tc.toolName, 'exec');
      expect(tc.status, ToolCallStatus.success);
      expect(tc.outputResult, 'drwxr-xr-x ...');
      expect(tc.endedAt, 1718000000000);
    });

    test('maps metadata.isError=true to failed status', () {
      final tc = toolCallFromMessage(
        mkMessage(metadata: const {'toolName': 'exec', 'isError': true}),
      );
      expect(tc.status, ToolCallStatus.failed);
    });

    test('falls back toolName to "tool" when metadata missing', () {
      final tc = toolCallFromMessage(mkMessage(metadata: null));
      expect(tc.toolName, 'tool');
    });

    test('falls back id to clientId when serverId is null', () {
      final tc = toolCallFromMessage(mkMessage(serverId: null));
      expect(tc.id, 'c1');
    });

    test('null content maps to null outputResult', () {
      final tc = toolCallFromMessage(mkMessage(content: null));
      expect(tc.outputResult, isNull);
    });
  });
}
