import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/features/agent_profile/widgets/achievement_list.dart';

void main() {
  group('AchievementList', () {
    Widget buildList({required List<Achievement> achievements}) {
      return MaterialApp(
        home: Scaffold(body: AchievementList(achievements: achievements)),
      );
    }

    /// Create a standard set of 8 achievements matching the preset definitions.
    List<Achievement> _allPresetAchievements() {
      return [
        const Achievement(
          id: 'first_dialog',
          icon: '🏆',
          name: '初次对话',
          description: '与虾完成第一次对话',
          tier: AchievementTier.gold,
          unlocked: false,
        ),
        const Achievement(
          id: 'hundred_dialogs',
          icon: '💬',
          name: '百次对话',
          description: '累计完成100次对话',
          tier: AchievementTier.gold,
          unlocked: false,
        ),
        const Achievement(
          id: 'thousand_dialogs',
          icon: '👑',
          name: '千次对话',
          description: '累计完成1000次对话',
          tier: AchievementTier.gold,
          unlocked: false,
        ),
        const Achievement(
          id: 'streak_7',
          icon: '🔥',
          name: '连续活跃7天',
          description: '连续7天与虾对话',
          tier: AchievementTier.silver,
          unlocked: false,
        ),
        const Achievement(
          id: 'streak_30',
          icon: '🌟',
          name: '月度伙伴',
          description: '连续30天与虾对话',
          tier: AchievementTier.gold,
          unlocked: false,
        ),
        const Achievement(
          id: 'tool_50',
          icon: '🛠️',
          name: '工具达人',
          description: '虾累计使用工具50次',
          tier: AchievementTier.bronze,
          unlocked: false,
        ),
        const Achievement(
          id: 'tool_200',
          icon: '⚙️',
          name: '工具大师',
          description: '虾累计使用工具200次',
          tier: AchievementTier.gold,
          unlocked: false,
        ),
        const Achievement(
          id: 'msg_1000',
          icon: '💎',
          name: '千条消息',
          description: '累计发送和接收1000条消息',
          tier: AchievementTier.silver,
          unlocked: false,
        ),
      ];
    }

    testWidgets('renders all 8 achievements', (tester) async {
      final achievements = _allPresetAchievements();
      await tester.pumpWidget(buildList(achievements: achievements));
      // StaggeredEnterItem creates one-shot timers (maxDelay 200ms
      // + duration 350ms). pumpAndSettle drains them all.
      await tester.pumpAndSettle();

      expect(find.text('🏆'), findsOneWidget);
      expect(find.text('初次对话'), findsOneWidget);
      expect(find.text('👑'), findsOneWidget);
      expect(find.text('千次对话'), findsOneWidget);
      expect(find.text('💎'), findsOneWidget);
      expect(find.text('千条消息'), findsOneWidget);
    });

    testWidgets('shows unlocked status for unlocked achievements', (
      tester,
    ) async {
      final achievements = _allPresetAchievements();
      // Mark first_dialog as unlocked
      achievements[0] = achievements[0].copyWith(
        unlocked: true,
        unlockedAt: 1715000000,
      );

      await tester.pumpWidget(buildList(achievements: achievements));
      await tester.pump(const Duration(seconds: 1));

      // Should have exactly 1 check_circle (the unlocked one) and 7 lock_outline
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(7));
    });

    testWidgets('shows empty state when list is empty', (tester) async {
      await tester.pumpWidget(buildList(achievements: const []));

      expect(find.text('暂无成就'), findsOneWidget);
      expect(find.text('继续与虾互动，解锁更多成就'), findsOneWidget);
    });
  });
}
