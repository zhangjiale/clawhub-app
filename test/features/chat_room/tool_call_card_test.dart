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

    // 折叠/展开:长输出默认截断,点开看完整,再点收起。
    testWidgets('taps to expand long output, taps again to collapse', (
      tester,
    ) async {
      final longOutput = 'x' * 200;
      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-exp',
            messageId: 'msg-exp',
            toolName: 'Bash',
            status: ToolCallStatus.success,
            outputResult: longOutput,
          ),
        ),
      );

      // Collapsed: truncated to 120 chars + "展开全部" hint.
      expect(find.text('${'x' * 120}...'), findsOneWidget);
      expect(find.text('展开全部 ▼'), findsOneWidget);
      expect(find.text(longOutput), findsNothing);

      // Tap the output to expand.
      await tester.tap(find.text('${'x' * 120}...'));
      await tester.pumpAndSettle();

      // Expanded: full output + "收起" hint.
      expect(find.text(longOutput), findsOneWidget);
      expect(find.text('收起 ▲'), findsOneWidget);
      expect(find.text('${'x' * 120}...'), findsNothing);

      // Tap again to collapse.
      await tester.tap(find.text(longOutput));
      await tester.pumpAndSettle();
      expect(find.text('${'x' * 120}...'), findsOneWidget);
      expect(find.text('展开全部 ▼'), findsOneWidget);
    });

    testWidgets('short output shows fully with no expand hint', (tester) async {
      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-short',
            messageId: 'msg-short',
            toolName: 'Bash',
            status: ToolCallStatus.success,
            outputResult: 'short',
          ),
        ),
      );
      expect(find.text('short'), findsOneWidget);
      expect(find.text('展开全部 ▼'), findsNothing);
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

  group('groupToolResultsByOwner', () {
    Message msg({
      required String clientId,
      required MessageRole role,
      required int logicalClock,
    }) => Message(
      clientId: clientId,
      conversationId: 'conv',
      agentId: 'a',
      role: role,
      content: 'x',
      type: MessageType.text,
      logicalClock: logicalClock,
      timestamp: logicalClock,
      status: MessageStatus.delivered,
    );

    test('toolResult attaches to the next non-toolResult message', () {
      final grouped = groupToolResultsByOwner([
        msg(clientId: 'u1', role: MessageRole.user, logicalClock: 1),
        msg(clientId: 't1', role: MessageRole.toolResult, logicalClock: 2),
        msg(clientId: 'a1', role: MessageRole.agent, logicalClock: 3),
      ]);
      expect(grouped.byOwner['a1']?.map((m) => m.clientId).toList(), ['t1']);
      expect(grouped.ownedIds, {'t1'});
    });

    test('multiple toolResults before one agent message all attach to it', () {
      final grouped = groupToolResultsByOwner([
        msg(clientId: 'u1', role: MessageRole.user, logicalClock: 1),
        msg(clientId: 't1', role: MessageRole.toolResult, logicalClock: 2),
        msg(clientId: 't2', role: MessageRole.toolResult, logicalClock: 3),
        msg(clientId: 'a1', role: MessageRole.agent, logicalClock: 4),
      ]);
      expect(grouped.byOwner['a1']?.map((m) => m.clientId).toList(), [
        't1',
        't2',
      ]);
      expect(grouped.ownedIds, {'t1', 't2'});
    });

    test(
      'toolResult with no following non-toolResult is orphan (not owned)',
      () {
        final grouped = groupToolResultsByOwner([
          msg(clientId: 'a1', role: MessageRole.agent, logicalClock: 1),
          msg(clientId: 't1', role: MessageRole.toolResult, logicalClock: 2),
        ]);
        expect(grouped.byOwner, isEmpty);
        expect(grouped.ownedIds, isEmpty);
      },
    );

    test('order-independent: groups by logicalClock even if list is DESC', () {
      final grouped = groupToolResultsByOwner([
        msg(clientId: 'a1', role: MessageRole.agent, logicalClock: 3),
        msg(clientId: 't1', role: MessageRole.toolResult, logicalClock: 2),
        msg(clientId: 'u1', role: MessageRole.user, logicalClock: 1),
      ]);
      expect(grouped.byOwner['a1']?.map((m) => m.clientId).toList(), ['t1']);
      expect(grouped.ownedIds, {'t1'});
    });
  });
}
