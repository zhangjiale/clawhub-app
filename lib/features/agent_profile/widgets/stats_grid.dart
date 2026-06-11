import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Stats grid — 3×2 data cards matching ComponentSpec Section 5.3.
class StatsGrid extends StatelessWidget {
  final int messageCount;

  const StatsGrid({super.key, required this.messageCount});

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem(label: '对话', value: '--'),
      _StatItem(label: '消息', value: _formatNumber(messageCount)),
      _StatItem(label: '工具', value: '--'),
      _StatItem(label: '天数', value: '--'),
      _StatItem(label: '连续', value: '--'),
      _StatItem(label: '首聊', value: '--'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: XiaSpacing.s6),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.6,
          crossAxisSpacing: XiaSpacing.s3,
          mainAxisSpacing: XiaSpacing.s3,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.md),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: XiaColors.text1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: XiaSpacing.s1),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: XiaColors.text3,
                      letterSpacing: 0.3,
                      fontWeight: FontWeight.w500,
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
  const _StatItem({required this.label, required this.value});
}
