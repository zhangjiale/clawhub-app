import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Stats bar — three equal-width stat chips matching ComponentSpec Section 2.2.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        XiaSpacing.s6,
        0,
        XiaSpacing.s6,
        XiaSpacing.s5,
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              emoji: '🖥',
              value: '$activeInstances',
              unit: '/$totalInstances',
              label: '活跃实例',
            ),
          ),
          const SizedBox(width: XiaSpacing.s3),
          Expanded(
            child: _StatChip(
              emoji: '🦐',
              value: '$onlineAgents',
              unit: '/$totalAgents',
              label: '在线虾',
            ),
          ),
          const SizedBox(width: XiaSpacing.s3),
          Expanded(
            child: _StatChip(
              emoji: '💬',
              value: _formatCount(totalMessages),
              unit: '',
              label: '总消息数',
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}

class _StatChip extends StatelessWidget {
  final String emoji;
  final String value;
  final String unit;
  final String label;

  const _StatChip({
    required this.emoji,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s3,
        vertical: XiaSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: XiaSpacing.s3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: XiaColors.text1,
                      letterSpacing: -0.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                      height: 1,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    Text(
                      unit,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: XiaColors.text3,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: XiaColors.text3,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
