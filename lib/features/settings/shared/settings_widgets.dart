import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Format hour + minute as "HH:MM".
///
/// Used by [SettingsPage] and [DoNotDisturbPage] for DND time display.
String formatHHmm(int hour, int minute) {
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Human-readable connectivity label based on target platform.
///
/// Uses Flutter's [defaultTargetPlatform] instead of dart:io [Platform]
/// so callers stay portable and testable.
///
/// For runtime network state (online/offline, WiFi vs cellular),
/// use `connectivity_plus` — this function is only a static platform hint.
String connectivityLabel() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return '移动网络 / WiFi';
    case TargetPlatform.fuchsia:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return '局域网 / WiFi';
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

/// Shared divider for settings pages.
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      color: XiaColors.border,
      indent: XiaSpacing.s5,
      endIndent: XiaSpacing.s5,
    );
  }
}

/// Read-only info row used by settings detail pages.
///
/// Renders an emoji + label on the left and a value on the right.
class SettingsInfoRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final bool isLast;

  const SettingsInfoRow({
    super.key,
    required this.emoji,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s5,
        vertical: XiaSpacing.s4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$emoji  $label',
            style: const TextStyle(
              fontSize: XiaTypography.body,
              color: XiaColors.text1,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: XiaTypography.body,
              color: XiaColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle row with emoji, label, subtitle, and [Switch.adaptive].
///
/// Used by notification, DND, and biometric settings pages.
class SettingsToggleRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool isLast;

  const SettingsToggleRow({
    super.key,
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s5,
        vertical: XiaSpacing.s4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$emoji  $label',
                  style: TextStyle(
                    fontSize: XiaTypography.body,
                    color: enabled ? XiaColors.text1 : XiaColors.text4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: XiaColors.text4),
                ),
              ],
            ),
          ),
          const SizedBox(width: XiaSpacing.s4),
          Switch.adaptive(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}
