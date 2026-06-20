import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'achievement_item.dart';

/// Achievement list — shows all 8 achievements (locked + unlocked).
///
/// Empty state is shown only when the list is truly empty (shouldn't happen
/// in practice since there are always 8 preset definitions).
class AchievementList extends StatelessWidget {
  final List<Achievement> achievements;

  const AchievementList({super.key, required this.achievements});

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) {
      return const EmptyState(
        icon: Text('🏆', style: TextStyle(fontSize: 48)),
        title: '暂无成就',
        subtitle: '继续与虾互动，解锁更多成就',
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: achievements.length,
      itemBuilder: (context, index) {
        final achievement = achievements[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: XiaSpacing.s3),
          child: StaggeredEnterItem(
            index: index,
            child: AchievementItem(achievement: achievement),
          ),
        );
      },
    );
  }
}
