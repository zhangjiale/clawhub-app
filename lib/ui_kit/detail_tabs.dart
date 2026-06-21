import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// DetailTabs — V2 §5.3 detail page 2-tab switcher.
///
/// Active state: text accent + w600 + 2px accent underline.
/// Inactive: text3 + w500.
/// Press: opacity 0.6 via [PressFeedback], 150ms ease.
class DetailTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const DetailTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: XiaColors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _DetailTab(
                label: tabs[i],
                isActive: i == selectedIndex,
                onTap: () => onTabSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// Stateless tab — reuses [PressFeedback] for press state.
class _DetailTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DetailTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      scale: 1.0,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      builder: (child, isPressed) =>
          Opacity(opacity: isPressed ? 0.6 : 1.0, child: child),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: XiaSpacing.s3),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Centered tab label.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: XiaSpacing.s5),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive ? XiaColors.accent : XiaColors.text3,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
            // 2px accent underline (overlap parent border by 1px).
            if (isActive)
              Positioned(
                bottom: -1,
                child: Container(
                  width: 60,
                  height: 2,
                  decoration: BoxDecoration(
                    color: XiaColors.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
