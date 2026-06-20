import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/achievement.dart';

/// Single achievement card — shows icon, name, description, and lock/unlock status.
class AchievementItem extends StatelessWidget {
  final Achievement achievement;

  const AchievementItem({super.key, required this.achievement});

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierBackground(achievement.tier);
    final textColor = achievement.unlocked ? XiaColors.text1 : XiaColors.text3;

    return Container(
      decoration: BoxDecoration(
        color: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.md),
      ),
      padding: const EdgeInsets.all(XiaSpacing.s4),
      child: Row(
        children: [
          // Tier-colored icon container
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tierColor,
              borderRadius: BorderRadius.circular(XiaRadius.sm),
            ),
            alignment: Alignment.center,
            child: Text(achievement.icon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: XiaSpacing.s3),
          // Name + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  achievement.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: XiaSpacing.s1),
                Text(
                  achievement.description,
                  style: const TextStyle(fontSize: 12, color: XiaColors.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: XiaSpacing.s3),
          // Unlock status icon
          if (achievement.unlocked)
            const Icon(Icons.check_circle, color: XiaColors.green, size: 20)
          else
            const Icon(Icons.lock_outline, color: XiaColors.text4, size: 20),
        ],
      ),
    );
  }

  Color _tierBackground(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.gold:
        return XiaColors.yellow.withOpacity(0.15);
      case AchievementTier.silver:
        return const Color(0xFFC0C0C0).withOpacity(0.15);
      case AchievementTier.bronze:
        return XiaColors.accentMuted.withOpacity(0.15);
    }
  }
}
