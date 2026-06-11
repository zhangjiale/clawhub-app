import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Global empty state component matching design spec.
///
/// Icon: 48px, text4 color, opacity 0.7.
/// Title: 17px, weight 600, text2 color.
/// Description: 14px, text3 color, line-height 1.6.
/// Padding: 48 vertical / 24 horizontal (s9/s6).
class EmptyState extends StatelessWidget {
  final IconData icon;
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
            Opacity(
              opacity: 0.7,
              child: Icon(icon, size: 48, color: XiaColors.text4),
            ),
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
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
