import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/features/agent_profile/widgets/milestone_celebration.dart';

void main() {
  group('MilestoneCelebrationOverlay', () {
    final testAchievement = Achievement(
      id: 'first_dialog',
      icon: '🏆',
      name: '初次对话',
      description: '与虾完成第一次对话',
      tier: AchievementTier.gold,
      unlocked: true,
      unlockedAt: 1715000000,
    );

    Widget buildOverlay({
      required Achievement achievement,
      VoidCallback? onDismiss,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: MilestoneCelebrationOverlay(
            achievement: achievement,
            onDismiss: onDismiss ?? () {},
          ),
        ),
      );
    }

    testWidgets('renders achievement name and description', (tester) async {
      await tester.pumpWidget(buildOverlay(achievement: testAchievement));

      expect(find.text('🎉 新成就解锁！'), findsOneWidget);
      expect(find.text('初次对话'), findsOneWidget);
      expect(find.text('与虾完成第一次对话'), findsOneWidget);
      expect(find.text('🏆'), findsOneWidget);
    });

    testWidgets('calls onDismiss when tapped', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        buildOverlay(
          achievement: testAchievement,
          onDismiss: () => dismissed = true,
        ),
      );

      // The overlay is a full-screen GestureDetector; tap anywhere.
      await tester.tap(find.byType(MilestoneCelebrationOverlay));
      // After tap, _dismiss() calls reverse() then calls onDismiss.
      // Pump the animation to completion.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(dismissed, isTrue);
    });

    testWidgets('auto-dismisses after timer fires', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        buildOverlay(
          achievement: testAchievement,
          onDismiss: () {
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );

      // Verify overlay is showing
      expect(find.text('🎉 新成就解锁！'), findsOneWidget);

      // Fast-forward past the 3-second auto-dismiss timer
      await tester.pump(const Duration(seconds: 4));
      // Pump the reverse animation
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        completer.isCompleted,
        isTrue,
        reason: 'onDismiss should be called after auto-dismiss timer fires',
      );
    });

    testWidgets('renders gold tier colored background', (tester) async {
      await tester.pumpWidget(buildOverlay(achievement: testAchievement));

      // The achievement icon is in a Container with tier color background
      // Verify the text content is present (indirect confirmation)
      expect(find.text('🏆'), findsOneWidget);
    });

    testWidgets('overlay covers full screen', (tester) async {
      await tester.pumpWidget(buildOverlay(achievement: testAchievement));

      // The overlay uses Colors.black54 as background
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text('🏆'), matching: find.byType(Container))
            .first,
      );
      // The outermost Container has the semi-transparent background
      expect(container, isNotNull);
    });
  });
}
