import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 统计网格组件
///
/// 展示 Agent 的 6 项统计（3×2 布局）。
/// 当前仅 messageCount 有真实数据，其余 5 项显示 "--" 占位。
class StatsGrid extends StatelessWidget {
  final int messageCount;

  const StatsGrid({super.key, required this.messageCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = [
      _StatItem(label: '对话次数', value: '--', isPlaceholder: true),
      _StatItem(
        label: '消息总数',
        value: _formatNumber(messageCount),
        isPlaceholder: false,
      ),
      _StatItem(label: '工具调用', value: '--', isPlaceholder: true),
      _StatItem(label: '活跃天数', value: '--', isPlaceholder: true),
      _StatItem(label: '连续天数', value: '--', isPlaceholder: true),
      _StatItem(label: '首次对话', value: '--', isPlaceholder: true),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.6,
          crossAxisSpacing: 1,
          mainAxisSpacing: 1,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: item.isPlaceholder
                          ? theme.colorScheme.outline
                          : AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatNumber(int n) {
    if (n < 1000) return n.toString();
    final s = n.toString();
    final buf = StringBuffer();
    final len = s.length;
    for (var i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _StatItem {
  final String label;
  final String value;
  final bool isPlaceholder;
  const _StatItem({
    required this.label,
    required this.value,
    required this.isPlaceholder,
  });
}
