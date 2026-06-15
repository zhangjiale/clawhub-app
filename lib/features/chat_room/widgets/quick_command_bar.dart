import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// Quick command bar — horizontally scrollable capsule pills.
/// Matching ComponentSpec Section 4.4.
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

    return Padding(
      padding: const EdgeInsets.only(bottom: XiaSpacing.s3),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: XiaSpacing.s6),
          itemCount: commands.length,
          separatorBuilder: (_, __) => const SizedBox(width: XiaSpacing.s2),
          itemBuilder: (context, index) {
            final cmd = commands[index];
            return _QuickCmdPill(
              label: cmd.label,
              onTap: () => onCommandTap(cmd.payload),
            );
          },
        ),
      ),
    );
  }
}

/// Single quick-command pill with press feedback.
/// Spec: scale(0.95) + bg surface2→accentMuted, 200ms ease.
class _QuickCmdPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickCmdPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      scale: 0.95,
      pressedColor: XiaColors.accentMuted,
      normalColor: XiaColors.surface2,
      borderRadius: BorderRadius.circular(XiaRadius.full),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s4,
          vertical: XiaSpacing.s2,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: XiaColors.accent,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}
