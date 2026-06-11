import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

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
            return GestureDetector(
              onTap: () => onCommandTap(cmd.payload),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: XiaSpacing.s4,
                  vertical: XiaSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: XiaColors.surface2,
                  borderRadius: BorderRadius.circular(XiaRadius.full),
                ),
                alignment: Alignment.center,
                child: Text(
                  cmd.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: XiaColors.accent,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
