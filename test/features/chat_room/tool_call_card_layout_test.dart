import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/tool_call_card.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';

/// 布局对齐回归：exec 卡 (ToolCallCard) 必须左对齐到 agent 气泡的左边缘，
/// 而不是被 36px 旧头像缩进顶到屏幕中间。
///
/// 背景：ToolCallCard 原始 MVP 实现里有 `SizedBox(width: 36)` 缩进，注释写的是
/// "Align with agent message avatar offset"——但 MessageBubble 早就没有头像了，
/// agent 气泡左边缘就在 pagePaddingH(16)。这 36px 缩进 + 78% maxW 让卡在窄屏
/// 上看起来居中，用户投诉 "exec 卡显示在中间，想挂在 agent 下面/左边"。
void main() {
  group('ToolCallCard horizontal alignment', () {
    Future<void> pumpAlignment(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final agentMsg = Message(
        clientId: 'a1',
        conversationId: 'c',
        agentId: 'a',
        role: MessageRole.agent,
        content: 'agent reply',
        type: MessageType.text,
        logicalClock: 2,
        timestamp: 2000,
        status: MessageStatus.delivered,
      );
      final tc = ToolCall(
        id: 'tc-1',
        messageId: 'a1',
        toolName: 'exec',
        status: ToolCallStatus.success,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // 复刻 chat_room_page._buildMessageList 里 agent 消息 + 工具卡的 Column。
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MessageBubble(message: agentMsg, agentName: 'Agent'),
                ToolCallCard(toolCall: tc),
              ],
            ),
          ),
        ),
      );
    }

    Finder decoratedContainerOf(Finder ancestor) => find.descendant(
      of: ancestor,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
      matchRoot: false,
    );

    testWidgets('ToolCallCard left edge aligns with agent bubble left edge', (
      tester,
    ) async {
      await pumpAlignment(tester);

      // MessageBubble 外层包了 StaggeredEnterItem，所以用 ancestor 找它内部的
      // 带 BoxDecoration 的 Container（即气泡本体）。
      final bubbleFinder = decoratedContainerOf(
        find.byType(MessageBubble),
      ).first;
      final cardFinder = decoratedContainerOf(find.byType(ToolCallCard)).first;

      final bubbleLeft = tester.getRect(bubbleFinder).left;
      final cardLeft = tester.getRect(cardFinder).left;

      // 诊断输出：失败时一眼看到实际坐标。
      // ignore: avoid_print
      print(
        'ALIGN-DIAG pagePaddingH=${XiaSpacing.pagePaddingH} '
        'bubbleLeft=$bubbleLeft cardLeft=$cardLeft',
      );

      expect(
        cardLeft,
        closeTo(bubbleLeft, 0.5),
        reason:
            'exec 卡左边缘应与 agent 气泡左边缘对齐(都在 pagePaddingH)。'
            ' 之前卡被 36px 旧头像缩进顶到中间。bubbleLeft=$bubbleLeft '
            'cardLeft=$cardLeft',
      );
    });
  });
}
