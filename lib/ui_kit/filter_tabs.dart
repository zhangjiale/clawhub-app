import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// FilterTabs — V2 §8.2 / §10.2 horizontal pill-shaped filter chips.
///
/// Active state: bg accent-muted, text accent, 1px border-accent border.
/// Inactive: transparent bg, text3, transparent border.
/// Press: scale(0.95) via [PressFeedback], 150ms ease.
class FilterTabs extends StatelessWidget {
  /// Plain string labels (kept simple — wraps in a private index).
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const FilterTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        XiaSpacing.s5,
        4,
        XiaSpacing.s5,
        XiaSpacing.s3,
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            _FilterChip(
              label: tabs[i],
              isActive: i == selectedIndex,
              onTap: () => onTabSelected(i),
            ),
            if (i < tabs.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// Stateless pill — reuses [PressFeedback] for press state.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      scale: 0.95,
      onTap: onTap,
      builder: (child, _) => AnimatedContainer(
        duration: XiaMotion.durationFast,
        curve: XiaMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? XiaColors.accentMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(XiaRadius.full),
          border: Border.all(
            color: isActive ? XiaColors.borderAccent : Colors.transparent,
          ),
        ),
        child: child,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isActive ? XiaColors.accent : XiaColors.text3,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
