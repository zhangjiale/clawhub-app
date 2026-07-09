import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/tool_call_card.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/tokens.dart';

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

    testWidgets('card maxWidth = 88% of screen width', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Scaffold(
              body: ToolCallCard(
                toolCall: ToolCall(
                  id: 'tc-width',
                  messageId: 'msg-width',
                  toolName: 'ReadFile',
                ),
              ),
            ),
          ),
        ),
      );
      final found = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints != null &&
            w.decoration is BoxDecoration,
      );
      expect(found, findsOneWidget);
      final card = tester.widget<Container>(found);
      expect(
        card.constraints!.maxWidth,
        400 * XiaLayout.agentBubbleMaxWidthRatio,
      );
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

    testWidgets('caps multi-line output at 3 lines + ellipsis', (tester) async {
      // R1:折叠不再按字符截断(120 字符 substring),改用 _isLongOutput 行数
      // 判定 + Flutter maxLines:3 + ellipsis。50 行输出 → 渲染成 3 行 + "…",
      // 而非 120 字符 substring。
      final multiLineOutput = List.generate(50, (i) => 'line $i').join('\n');
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-6',
            messageId: 'msg-6',
            toolName: 'Bash',
            status: ToolCallStatus.success,
            outputResult: multiLineOutput,
          ),
        ),
      );

      // "展开全部 ▼" 出现说明 isLong=true,触发了 maxLines:3 折叠。
      expect(find.text('展开全部 ▼'), findsOneWidget);
      // Text widget 的 maxLines 应为 3(非 null,否则就是展开态)。
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      final outputText = textWidgets.firstWhere(
        (t) => (t.data ?? '').startsWith('line 0'),
      );
      expect(outputText.maxLines, 3);
      expect(outputText.overflow, TextOverflow.ellipsis);
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

    // 折叠/展开:多行长输出默认折叠(>3 行),点开看完整,再点收起。
    // R1:折叠判定改行数,此处用多行输出确保 isLong=true。
    testWidgets('taps to expand multi-line output, taps again to collapse', (
      tester,
    ) async {
      final multiLineOutput = List.generate(50, (i) => 'line $i').join('\n');
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildCard(
          ToolCall(
            id: 'tc-exp',
            messageId: 'msg-exp',
            toolName: 'Bash',
            status: ToolCallStatus.success,
            outputResult: multiLineOutput,
          ),
        ),
      );

      // Collapsed: "展开全部" hint 出现,full output 不应作为单一 Text 子节点
      // 出现(会被 maxLines:3 裁剪)。
      expect(find.text('展开全部 ▼'), findsOneWidget);

      // Tap the toggle to expand.
      await tester.tap(find.text('展开全部 ▼'));
      await tester.pumpAndSettle();

      // Expanded: "收起" hint + full output 可作为单一 Text 子节点访问。
      expect(find.text(multiLineOutput), findsOneWidget);
      expect(find.text('收起 ▲'), findsOneWidget);

      // Tap again to collapse.
      await tester.tap(find.text('收起 ▲'));
      await tester.pumpAndSettle();
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

    test('toolResult attaches to the previous user message (the trigger)', () {
      // Bug fix (review: exec card position): toolResults now attach to the
      // previous user message (the turn's trigger) so ToolCallCard renders
      // below the user bubble (between user and agent in the reverse-list
      // view). Pre-fix the owner was the next agent message, which placed
      // the exec card below the agent bubble.
      final grouped = groupToolResultsByOwner([
        msg(clientId: 'u1', role: MessageRole.user, logicalClock: 1),
        msg(clientId: 't1', role: MessageRole.toolResult, logicalClock: 2),
        msg(clientId: 'a1', role: MessageRole.agent, logicalClock: 3),
      ]);
      expect(grouped.byOwner['u1']?.map((m) => m.clientId).toList(), ['t1']);
      expect(
        grouped.byOwner['a1'],
        isNull,
        reason: 'agent must not own the toolResult (that was the bug)',
      );
      expect(grouped.ownedIds, {'t1'});
    });

    test('multiple toolResults after one user message all attach to it', () {
      final grouped = groupToolResultsByOwner([
        msg(clientId: 'u1', role: MessageRole.user, logicalClock: 1),
        msg(clientId: 't1', role: MessageRole.toolResult, logicalClock: 2),
        msg(clientId: 't2', role: MessageRole.toolResult, logicalClock: 3),
        msg(clientId: 'a1', role: MessageRole.agent, logicalClock: 4),
      ]);
      expect(grouped.byOwner['u1']?.map((m) => m.clientId).toList(), [
        't1',
        't2',
      ]);
      expect(grouped.ownedIds, {'t1', 't2'});
    });

    test('toolResult with no preceding user message is orphan (not owned)', () {
      // Pre-fix the orphan case was "no following non-toolResult" — that
      // was tested by reversing the list. With the new owner semantics
      // (previous user), the orphan case is "no preceding user message"
      // — a toolResult at the very top of the conversation, e.g. from a
      // pre-existing tool-only turn or a catch-up replay edge.
      final grouped = groupToolResultsByOwner([
        msg(clientId: 't1', role: MessageRole.toolResult, logicalClock: 1),
        msg(clientId: 'u1', role: MessageRole.user, logicalClock: 2),
      ]);
      expect(grouped.byOwner, isEmpty);
      expect(grouped.ownedIds, isEmpty);
    });

    test('order-independent: groups by logicalClock even if list is DESC', () {
      final grouped = groupToolResultsByOwner([
        msg(clientId: 'a1', role: MessageRole.agent, logicalClock: 3),
        msg(clientId: 't1', role: MessageRole.toolResult, logicalClock: 2),
        msg(clientId: 'u1', role: MessageRole.user, logicalClock: 1),
      ]);
      expect(grouped.byOwner['u1']?.map((m) => m.clientId).toList(), ['t1']);
      expect(grouped.ownedIds, {'t1'});
    });

    test('consecutive toolResults after one user message all attach to it '
        '(including across agent reply in middle)', () {
      // Edge: two user messages with toolResults in between, plus an
      // agent reply between them. Each toolResult should attach to its
      // immediately preceding user message.
      final grouped = groupToolResultsByOwner([
        msg(clientId: 'u1', role: MessageRole.user, logicalClock: 1),
        msg(clientId: 't1', role: MessageRole.toolResult, logicalClock: 2),
        msg(clientId: 'a1', role: MessageRole.agent, logicalClock: 3),
        msg(clientId: 'u2', role: MessageRole.user, logicalClock: 4),
        msg(clientId: 't2', role: MessageRole.toolResult, logicalClock: 5),
        msg(clientId: 'a2', role: MessageRole.agent, logicalClock: 6),
      ]);
      expect(grouped.byOwner['u1']?.map((m) => m.clientId).toList(), ['t1']);
      expect(grouped.byOwner['u2']?.map((m) => m.clientId).toList(), ['t2']);
      expect(grouped.ownedIds, {'t1', 't2'});
    });
  });
}
