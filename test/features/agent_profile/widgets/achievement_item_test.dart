import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/features/agent_profile/widgets/achievement_item.dart';

void main() {
  group('AchievementItem', () {
    Widget buildItem({required Achievement achievement}) {
      return MaterialApp(
        home: Scaffold(body: AchievementItem(achievement: achievement)),
      );
    }

    testWidgets('renders unlocked achievement with check icon', (tester) async {
      final achievement = Achievement(
        id: 'first_dialog',
        icon: '🏆',
        name: '初次对话',
        description: '与虾完成第一次对话',
        tier: AchievementTier.gold,
        unlocked: true,
        unlockedAt: 1715000000,
      );

      await tester.pumpWidget(buildItem(achievement: achievement));

      expect(find.text('🏆'), findsOneWidget);
      expect(find.text('初次对话'), findsOneWidget);
      expect(find.text('与虾完成第一次对话'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('renders locked achievement with lock icon', (tester) async {
      final achievement = Achievement(
        id: 'streak_30',
        icon: '🌟',
        name: '月度伙伴',
        description: '连续30天与虾对话',
        tier: AchievementTier.gold,
        unlocked: false,
      );

      await tester.pumpWidget(buildItem(achievement: achievement));

      expect(find.text('🌟'), findsOneWidget);
      expect(find.text('月度伙伴'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      // No check_circle when locked
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('renders silver tier achievement', (tester) async {
      final achievement = Achievement(
        id: 'streak_7',
        icon: '🔥',
        name: '连续活跃7天',
        description: '连续7天与虾对话',
        tier: AchievementTier.silver,
        unlocked: false,
      );

      await tester.pumpWidget(buildItem(achievement: achievement));

      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('连续活跃7天'), findsOneWidget);
    });

    testWidgets('renders bronze tier achievement', (tester) async {
      final achievement = Achievement(
        id: 'tool_50',
        icon: '🛠️',
        name: '工具达人',
        description: '虾累计使用工具50次',
        tier: AchievementTier.bronze,
        unlocked: false,
      );

      await tester.pumpWidget(buildItem(achievement: achievement));

      expect(find.text('🛠️'), findsOneWidget);
      expect(find.text('工具达人'), findsOneWidget);
    });
  });
}
