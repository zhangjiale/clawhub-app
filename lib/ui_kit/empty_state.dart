import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Global empty state component — V2 §10.6.
///
/// Icon: 48px, opacity 0.6.
/// Title: 15px / w600 / text2.
/// Description: 12px / text3 / line-height 1.5.
/// Padding: 48 vertical / 32 horizontal.
///
/// **V2 (was V1 §2.6)**: 17→15 title, 14→12 description, opacity 0.7→0.6.
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
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(opacity: 0.6, child: _buildIcon()),
            const SizedBox(height: XiaSpacing.s3),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: XiaColors.text2,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12,
                  color: XiaColors.text3,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: XiaSpacing.s5),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return icon;
  }
}
