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

    testWidgets('long output can be expanded and collapsed', (tester) async {
      final longOutput = 'a' * 200;
      await tester.pumpWidget(wrap(tc(output: longOutput)));
      expect(find.text('展开全部 ▼'), findsOneWidget);

      await tester.tap(find.text('展开全部 ▼'));
      await tester.pumpAndSettle();
      expect(find.text('收起 ▲'), findsOneWidget);

      await tester.tap(find.text('收起 ▲'));
      await tester.pumpAndSettle();
      expect(find.text('展开全部 ▼'), findsOneWidget);
    });

    // 回归:输出从长变短时,若 _expanded 不重置,卡片会保持展开但失去折叠入口。
    testWidgets('expanded state resets when output becomes short', (
      tester,
    ) async {
      final longOutput = 'a' * 200;
      await tester.pumpWidget(wrap(tc(output: longOutput)));
      await tester.tap(find.text('展开全部 ▼'));
      await tester.pumpAndSettle();
      expect(find.text('收起 ▲'), findsOneWidget);

      // 网关给出更短的最终输出。
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
  });
}
