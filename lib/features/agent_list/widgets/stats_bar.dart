import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 统计数据条组件
/// 对齐: PRD 3.2 US-005 (虾列表状态统计栏)
///
/// 横向展示 3 个统计卡片：活跃实例数、在线虾数、总消息数
class StatsBar extends StatelessWidget {
  final int activeInstances;
  final int totalInstances;
  final int onlineAgents;
  final int totalAgents;
  final int totalMessages;

  const StatsBar({
    super.key,
    required this.activeInstances,
    required this.totalInstances,
    required this.onlineAgents,
    required this.totalAgents,
    required this.totalMessages,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Instances',
              value: '$activeInstances/$totalInstances',
              icon: Icons.dns,
              color: AppColors.primaryBlue,
              theme: theme,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: 'Online',
              value: '$onlineAgents/$totalAgents',
              icon: Icons.pets,
              color: AppColors.statusOnline,
              theme: theme,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              label: 'Messages',
              value: _formatCount(totalMessages),
              icon: Icons.chat_bubble_outline,
              color: AppColors.statusConnecting,
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final ThemeData theme;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
