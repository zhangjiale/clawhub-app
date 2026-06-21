import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/agent_theme.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// Quick command bar — horizontally scrollable capsule pills.
/// Matching V2 ComponentSpec Section 4.4.
///
/// V2: accent-muted bg + border-accent (30% accent) border, accent text,
/// scale(0.93) on press, 150ms ease.
class QuickCommandBar extends StatelessWidget {
  final List<QuickCommand> commands;
  final ValueChanged<String> onCommandTap;

  const QuickCommandBar({
    super.key,
    required this.commands,
    required this.onCommandTap,
  });

  @override
  Widget build(BuildContext context) {
    if (commands.isEmpty) return const SizedBox.shrink();

    final themeColor = AgentTheme.of(context).primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: XiaSpacing.s2),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: XiaSpacing.s5),
          itemCount: commands.length,
          separatorBuilder: (_, __) => const SizedBox(width: XiaSpacing.s2),
          itemBuilder: (context, index) {
            final cmd = commands[index];
            return _QuickCmdPill(
              label: cmd.label,
              themeColor: themeColor,
              onTap: () => onCommandTap(cmd.payload),
            );
          },
        ),
      ),
    );
  }
}

/// Single quick-command pill with press feedback.
/// V2: bg `accent-muted` + 1px `border-accent`, accent text,
/// scale(0.93) + bg `rgba(79,131,255,0.18)` on press.
class _QuickCmdPill extends StatelessWidget {
  final String label;
  final Color themeColor;
  final VoidCallback onTap;

  const _QuickCmdPill({
    required this.label,
    required this.themeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      scale: 0.93,
      pressedColor: themeColor.withAlpha(46), // ~18% V2 spec
      normalColor: XiaColors.accentMuted,
      borderRadius: BorderRadius.circular(XiaRadius.full),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: XiaColors.accentMuted,
          borderRadius: BorderRadius.circular(XiaRadius.full),
          border: Border.all(color: XiaColors.borderAccent, width: 1),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s4, // 12
          vertical: 5,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: themeColor,
          ),
        ),
      ),
    );
  }
}
