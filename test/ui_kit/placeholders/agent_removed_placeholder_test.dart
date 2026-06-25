// US-021 v1.1: AgentRemovedPlaceholder widget 测试。
// 验证 3 个分支：(1) 显示 agent name，(2) agentName=null 隐藏 name 行，
// (3) onBack 回调被调用。US-021 v1.2 移除 onBack=null 的 smartBack 兜底
// （dead code —— 所有调用点都显式传 onBack）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/placeholders/agent_removed_placeholder.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

void main() {
  group('AgentRemovedPlaceholder', () {
    testWidgets('shows agent name when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AgentRemovedPlaceholder(agentName: '产品虾', onBack: () {}),
        ),
      );
      expect(find.text('产品虾'), findsOneWidget);
      expect(find.text('该 Agent 已从 Gateway 移除'), findsOneWidget);
    });

    testWidgets('omits agent name row when agentName is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: AgentRemovedPlaceholder(onBack: () {})),
      );
      expect(find.text('该 Agent 已从 Gateway 移除'), findsOneWidget);
      // agentName=null 时，body 里只该有"该 Agent 已从 Gateway 移除"一个 Text
      // （AppBar title '虾已移除' 独立于此校验）。
      final bodyTexts = tester.widgetList<Text>(
        find.descendant(of: find.byType(Scaffold), matching: find.byType(Text)),
      );
      // AppBar title ('虾已移除') + body 该 Agent message = 2; agent name
      // 不在。
      expect(
        bodyTexts.length,
        2,
        reason: 'AppBar title + 该 Agent 消息；agentName=null 时无 name 行',
      );
    });

    testWidgets('back button invokes provided onBack callback', (tester) async {
      var invoked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AgentRemovedPlaceholder(
            source: 'messages',
            onBack: () => invoked = true,
          ),
        ),
      );

      await tester.tap(find.byType(XiaBackButton));
      await tester.pumpAndSettle();

      expect(invoked, isTrue, reason: '返回按钮应调用传入的 onBack');
    });

    // US-021 v1.2: onBack 现为 required,所有调用点（chat_room_page /
    // agent_profile_page / agent_config_page）都显式传入。如果未来有人忘
    // 传，编译期会立刻报错,无需运行时兜底。
  });
}
