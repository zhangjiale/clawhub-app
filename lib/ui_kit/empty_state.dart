import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Global empty state component matching design spec (Section 10.6).
///
/// Icon: 48px, text4 color, opacity 0.7 (when [icon] is an IconData).
/// For emoji, pass a [Text] widget directly.
/// Title: 17px, weight 600, text2 color.
/// Description: 14px, text3 color, line-height 1.6.
/// Padding: 48 vertical / 24 horizontal (s9/s6).
///
/// **C5**: [icon] parameter changed from IconData to Widget to support
/// emoji text (🦐) as specified in the design spec.
class EmptyState extends StatelessWidget {
  final Widget icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: XiaSpacing.s9,
          horizontal: XiaSpacing.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(opacity: 0.7, child: _buildIcon()),
            const SizedBox(height: XiaSpacing.s5),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: XiaColors.text2,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: XiaSpacing.s2),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 14,
                  color: XiaColors.text3,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: XiaSpacing.s6),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    // icon is typed Widget; all callers pass either Icon(IconData) or Text.
    // The IconData switch branch was removed — it was unreachable because
    // IconData is not a Widget subtype.
    return icon;
  }
}
