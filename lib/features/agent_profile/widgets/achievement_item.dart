import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/achievement.dart';

/// Single achievement card — V2 ComponentSpec Section 5.6.
///
/// V2: 32×32 icon (was 40×40), accent2-muted bg + 1px accent2 25% border
/// when unlocked; surface3 + opacity 0.4 when locked. Card bg surface.
class AchievementItem extends StatelessWidget {
  final Achievement achievement;

  const AchievementItem({super.key, required this.achievement});

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierBackground(achievement.tier, achievement.unlocked);
    final borderColor = achievement.unlocked
        ? XiaColors.accent2.withAlpha(64) // 25% V2 spec
        : Colors.transparent;
    final textColor = achievement.unlocked ? XiaColors.text1 : XiaColors.text3;

    return Container(
      decoration: BoxDecoration(
        color: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.md),
        border: Border.all(color: XiaColors.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s3,
        vertical: XiaSpacing.s3,
      ),
      child: Row(
        children: [
          // Tier-colored icon container (V2: 32×32, radius md=8)
          Opacity(
            opacity: achievement.unlocked ? 1.0 : 0.4,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tierColor,
                borderRadius: BorderRadius.circular(XiaRadius.md),
                border: Border.all(color: borderColor),
              ),
              alignment: Alignment.center,
              child: Text(
                achievement.icon,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: XiaSpacing.s3),
          // Name + description (V2: name 13/w600, desc 11/text3)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  achievement.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  achievement.description,
                  style: const TextStyle(fontSize: 11, color: XiaColors.text3),
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

  /// V2 tier backgrounds:
  /// - unlocked: tier-muted color regardless of tier
  /// - locked: surface3 (handled by outer Opacity)
  Color _tierBackground(AchievementTier tier, bool unlocked) {
    if (!unlocked) return XiaColors.surface3;
    switch (tier) {
      case AchievementTier.gold:
        return XiaColors.gold.withAlpha(38); // 15% alpha on V2 gold
      case AchievementTier.silver:
        return XiaColors.silver.withAlpha(38);
      case AchievementTier.bronze:
        return XiaColors.accentMuted; // 10% V2 accent
    }
  }
}
