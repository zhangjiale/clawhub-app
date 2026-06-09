import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

/// 快捷指令栏
/// 横向可滚动的指令标签，点击后自动发送
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

    final theme = Theme.of(context);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withAlpha(30),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: commands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cmd = commands[index];
          return ActionChip(
            label: Text(
              cmd.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: AppColors.primaryBlue.withAlpha(20),
            side: BorderSide(
              color: AppColors.primaryBlue.withAlpha(60),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
            onPressed: () => onCommandTap(cmd.payload),
          );
        },
      ),
    );
  }
}
