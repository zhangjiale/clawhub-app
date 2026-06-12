import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// A slim, full-width status banner for one-line messages with an icon.
///
/// Three concrete usages in the app:
/// - [ConnectionBanner] — connection-state alerts (disconnected / connecting)
/// - Agent-list stale-data warning (cloud-off icon, yellow tint)
///
/// Any page needing a one-line status bar with an icon should reuse this
/// component rather than inlining its layout.
class StatusBanner extends StatelessWidget {
  final String message;
  final Color foregroundColor;
  final Color backgroundColor;
  final IconData icon;

  const StatusBanner({
    super.key,
    required this.message,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: XiaSpacing.s2,
      ),
      color: backgroundColor,
      child: Row(
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: XiaSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(
                color: foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
