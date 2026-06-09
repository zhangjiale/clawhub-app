import 'package:flutter/material.dart';

/// 统计数据条组件
/// 对齐: PRD 3.2 US-005 (虾列表状态统计栏)
///
/// 横向可滚动的 pill 芯片，展示活跃实例数、在线虾数、总消息数
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _StatChip(
              emoji: '🖥️',
              value: '$activeInstances/$totalInstances',
              label: '活跃实例',
              theme: theme,
            ),
            const SizedBox(width: 8),
            _StatChip(
              emoji: '🦐',
              value: '$onlineAgents/$totalAgents',
              label: '在线虾',
              theme: theme,
            ),
            const SizedBox(width: 8),
            _StatChip(
              emoji: '💬',
              value: _formatCount(totalMessages),
              label: '总消息数',
              theme: theme,
            ),
          ],
        ),
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

/// 单个统计 pill 芯片
///
/// emoji 图标 + 数值/标签纵向排列，原型对齐
class _StatChip extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final ThemeData theme;

  const _StatChip({
    required this.emoji,
    required this.value,
    required this.label,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
