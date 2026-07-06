import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/features/chat_room/widgets/tool_call_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Message _msg({
    required String clientId,
    required MessageRole role,
    String content = '',
    int logicalClock = 0,
  }) => Message(
    clientId: clientId,
    conversationId: 'conv-1',
    agentId: 'agent-1',
    role: role,
    content: content,
    type: MessageType.text,
    status: MessageStatus.delivered,
    logicalClock: logicalClock,
    timestamp: 1718000000000 + logicalClock,
  );

  group('groupToolResultsByOwner', () {
    test('attaches toolResult to the following agent message', () {
      final messages = [
        _msg(clientId: 'user', role: MessageRole.user, logicalClock: 1),
        _msg(clientId: 'tool', role: MessageRole.toolResult, logicalClock: 2),
        _msg(clientId: 'agent', role: MessageRole.agent, logicalClock: 3),
      ];

      final grouped = groupToolResultsByOwner(messages);

      expect(grouped.ownedIds, contains('tool'));
      expect(grouped.byOwner['agent'], hasLength(1));
      expect(grouped.byOwner['agent']!.first.clientId, 'tool');
    });

    // 回归:toolResult 后面紧跟 userPlaceholder/system/user 时,不应把工具卡
    // 挂到这些非 agent 消息上;否则 agent 回复会缺少工具卡。
    test('does NOT attach toolResult to userPlaceholder', () {
      final messages = [
        _msg(clientId: 'user', role: MessageRole.user, logicalClock: 1),
        _msg(clientId: 'tool', role: MessageRole.toolResult, logicalClock: 2),
        _msg(
          clientId: 'placeholder',
          role: MessageRole.userPlaceholder,
          logicalClock: 3,
        ),
        _msg(clientId: 'agent', role: MessageRole.agent, logicalClock: 4),
      ];

      final grouped = groupToolResultsByOwner(messages);

      expect(grouped.byOwner.containsKey('placeholder'), isFalse);
      expect(grouped.byOwner['agent'], hasLength(1));
      expect(grouped.byOwner['agent']!.first.clientId, 'tool');
    });

    test('does NOT attach toolResult to system message', () {
      final messages = [
        _msg(clientId: 'tool', role: MessageRole.toolResult, logicalClock: 1),
        _msg(clientId: 'system', role: MessageRole.system, logicalClock: 2),
        _msg(clientId: 'agent', role: MessageRole.agent, logicalClock: 3),
      ];

      final grouped = groupToolResultsByOwner(messages);

      expect(grouped.byOwner.containsKey('system'), isFalse);
      expect(grouped.byOwner['agent'], hasLength(1));
      expect(grouped.byOwner['agent']!.first.clientId, 'tool');
    });

    test('does NOT attach toolResult to user message', () {
      final messages = [
        _msg(clientId: 'tool', role: MessageRole.toolResult, logicalClock: 1),
        _msg(clientId: 'user', role: MessageRole.user, logicalClock: 2),
        _msg(clientId: 'agent', role: MessageRole.agent, logicalClock: 3),
      ];

      final grouped = groupToolResultsByOwner(messages);

      expect(grouped.byOwner.containsKey('user'), isFalse);
      expect(grouped.byOwner['agent'], hasLength(1));
      expect(grouped.byOwner['agent']!.first.clientId, 'tool');
    });

    test('orphan toolResult at end is not owned', () {
      final messages = [
        _msg(clientId: 'agent', role: MessageRole.agent, logicalClock: 1),
        _msg(clientId: 'tool', role: MessageRole.toolResult, logicalClock: 2),
      ];

      final grouped = groupToolResultsByOwner(messages);

      expect(grouped.ownedIds, isEmpty);
      expect(grouped.byOwner, isEmpty);
    });
  });

  group('ToolCallCard expansion state', () {
    Widget wrap(ToolCall tc) => MaterialApp(
      home: Scaffold(body: ToolCallCard(toolCall: tc)),
    );

    ToolCall tc({required String output}) => ToolCall(
      id: 'tc-1',
      messageId: 'msg-1',
      toolName: 'exec',
      status: ToolCallStatus.success,
      outputResult: output,
      endedAt: 0,
    );

    // 折叠阈值改按「行数」判断(>3 行)而非字符数,原因:R1 回归——
    // gateway_event_processor.dart delta 阶段对 Map/非 String 输出走 jsonEncode,
    // 把 50 字符的 `{"ok":true}` 编码成 12 字符(短 Map)或把 100 字符的 stdout
    // 编码成 ~140 字符(JSON 形态),原 120 字符阈值会被误触发。改按行数后:
    // - jsonEncode 出来的单行 JSON(pretty-print 后 3-5 行)走 Flutter 的
    //   `maxLines:3 + ellipsis` 自然裁剪,无需额外截断逻辑。
    // - 多行 shell stdout(>3 行)折叠成 3 行 + "展开全部"。
    // - 单行长字符串(罕见,如 500 字符单行错误消息)让 maxLines 自然换行,
    //   不会被字符阈值误判。
    String _multiLine(int n) => List.generate(n, (i) => 'line $i').join('\n');

    testWidgets('multi-line output can be expanded and collapsed', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(tc(output: _multiLine(50))));
      expect(find.text('展开全部 ▼'), findsOneWidget);

      await tester.tap(find.text('展开全部 ▼'));
      await tester.pumpAndSettle();
      expect(find.text('收起 ▲'), findsOneWidget);

      await tester.tap(find.text('收起 ▲'));
      await tester.pumpAndSettle();
      expect(find.text('展开全部 ▼'), findsOneWidget);
    });

    // 回归:输出从多行(长)变单行(短)时,若 _expanded 不重置,卡片保持展开但
    // 失去折叠入口。
    testWidgets('expanded state resets when output goes multi→single-line', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(tc(output: _multiLine(50))));
      await tester.tap(find.text('展开全部 ▼'));
      await tester.pumpAndSettle();
      expect(find.text('收起 ▲'), findsOneWidget);

      // 网关给出单行更短的最终输出。
      await tester.pumpWidget(wrap(tc(output: 'short')));
      await tester.pumpAndSettle();

      expect(find.text('收起 ▲'), findsNothing);
      expect(find.text('展开全部 ▼'), findsNothing);
      expect(find.text('short'), findsOneWidget);
      // 关键断言:短输出时 maxLines 应回到 3(折叠态),而不是因 _expanded 残留
      // 保持 null(展开态)导致用户无法收起。
      final textWidget = tester.widget<Text>(find.text('short'));
      expect(textWidget.maxLines, 3);
    });

    // R1:delta 阶段把 Map/非 String 输出走 jsonEncode,旧阈值用字符数会把
    // 200 字符的单行 JSON 误判为 long。改行数后,单行 JSON 永远不会被折叠。
    testWidgets('single-line JSON output (>120 chars) is NOT collapsed', (
      tester,
    ) async {
      // 模拟 gateway_event_processor 的 jsonEncode 产物:单行 JSON 字符串,
      // 长度 > 120(超过旧 120 字符阈值)。
      final jsonOutput =
          '{"data":{"files":["a.txt","b.txt","c.txt","d.txt","e.txt"]'
          ',"meta":"x","size":1024,"lines":50,"encoding":"utf-8",'
          '"hash":"abc123def456"}}';
      expect(jsonOutput.length, greaterThan(120));
      expect(jsonOutput.split('\n').length, 1);

      await tester.pumpWidget(wrap(tc(output: jsonOutput)));

      expect(find.text('展开全部 ▼'), findsNothing);
      expect(find.text(jsonOutput), findsOneWidget);
    });

    // R1 配套:didUpdateWidget 必须用同一行数判定,否则旧 heuristic 会
    // 在"单行长 JSON → 多行短 stdout" 转换时错误地保留 _expanded=true,
    // 导致短 stdout 显示在 maxLines=null 的展开态里,布局爆炸。
    testWidgets('expanded state resets when multi-line→single-line JSON', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(tc(output: _multiLine(50))));
      await tester.tap(find.text('展开全部 ▼'));
      await tester.pumpAndSettle();
      expect(find.text('收起 ▲'), findsOneWidget);

      // 切到单行长 JSON(200 字符,旧 heuristic 判 long,新 heuristic 判短)。
      final jsonOutput = '{"data":{"ok":true}}' * 10; // ~200 chars, single line
      await tester.pumpWidget(wrap(tc(output: jsonOutput)));
      await tester.pumpAndSettle();

      expect(find.text('收起 ▲'), findsNothing);
      expect(find.text('展开全部 ▼'), findsNothing);
      final textWidget = tester.widget<Text>(find.text(jsonOutput));
      expect(textWidget.maxLines, 3);
    });
  });
}
