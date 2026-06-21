import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// InlineStats — V2 ComponentSpec §2.2 row of compact metrics.
///
/// Replaces V1 StatsBar (3 cards) with single-line layout:
/// `[●] 2/3 · 5/8 在线 · 142 消息`
///
/// Each metric: optional dot + value (text1/w600) + unit (text2).
/// Separators: middle dot `·` in text4.
class InlineStats extends StatelessWidget {
  final List<InlineStatItem> items;

  const InlineStats({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: XiaSpacing.s2),
            child: Text(
              '·',
              style: TextStyle(fontSize: 12, color: XiaColors.text4),
            ),
          ),
        );
      }
      children.add(items[i]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        XiaSpacing.pagePaddingH,
        6,
        XiaSpacing.pagePaddingH,
        0,
      ),
      child: Row(children: children),
    );
  }
}

/// Single inline metric item: optional status dot + value + unit label.
class InlineStatItem extends StatelessWidget {
  final String value;
  final String? unit;
  final bool showStatusDot;
  final bool isOnline;

  const InlineStatItem({
    super.key,
    required this.value,
    this.unit,
    this.showStatusDot = false,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showStatusDot) ...[
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: isOnline ? XiaColors.green : XiaColors.text4,
              shape: BoxShape.circle,
              boxShadow: isOnline ? XiaShadow.onlineGlow : null,
            ),
          ),
        ],
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: XiaColors.text1,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: 2),
          Text(
            unit!,
            style: const TextStyle(
              fontSize: 13,
              color: XiaColors.text2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}
