import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';

/// Stats grid — 3×2 data cards matching ComponentSpec Section 5.3.
///
/// [stats] provides all 6 values.  When [stats] is null, all fields show
/// `'--'` except the message count which falls back to [fallbackMessageCount]
/// (the ViewModel always loads the message count independently).
class StatsGrid extends StatelessWidget {
  final AgentStats? stats;

  /// Fallback message count shown when [stats] is null.
  /// The profile page loads this via a separate query, so it's always
  /// available even if the stats pipeline fails.
  final int? fallbackMessageCount;

  const StatsGrid({super.key, required this.stats, this.fallbackMessageCount});

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem(label: '对话', value: _num((s) => s.totalDialogs)),
      _StatItem(label: '消息', value: _messageCount()),
      _StatItem(label: '工具', value: _num((s) => s.totalToolCalls)),
      _StatItem(label: '天数', value: _num((s) => s.activeDays)),
      _StatItem(label: '连续', value: _num((s) => s.currentStreak)),
      _StatItem(label: '首聊', value: _date((s) => s.firstDialogDate)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: XiaSpacing.s5),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.6,
          crossAxisSpacing: XiaSpacing.s2, // V2: 8 → 6
          mainAxisSpacing: XiaSpacing.s2,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.md), // V2: 8
              border: Border.all(color: XiaColors.border),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: XiaTypography.statValue, // V2: 18
                      fontWeight: FontWeight.w700,
                      color: XiaColors.text1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: XiaColors.text3,
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

  String _formatDate(int? unixSeconds) {
    if (unixSeconds == null) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    return '${dt.month}/${dt.day}';
  }

  String _num(int Function(AgentStats) getter) =>
      stats != null ? _formatNumber(getter(stats!)) : '--';

  String _date(int? Function(AgentStats) getter) =>
      stats != null ? _formatDate(getter(stats!)) : '--';

  /// Message count with fallback — always available even when stats is null.
  String _messageCount() {
    if (stats != null) return _formatNumber(stats!.totalMessages);
    if (fallbackMessageCount != null) {
      return _formatNumber(fallbackMessageCount!);
    }
    return '--';
  }
}

class _StatItem {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});
}
