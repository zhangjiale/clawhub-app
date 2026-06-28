import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// SettingsSection — V2 §9.2/§9.5 grouped container with uppercase title.
///
/// Title: 11px / w600 / 0.8 letter-spacing / uppercase / text3.
/// Container: surface bg + 10px radius + 1px hairline border.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              XiaSpacing.s5,
              0,
              XiaSpacing.s5,
              6,
            ),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: XiaColors.text3,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.lg),
              border: Border.all(color: XiaColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: XiaSpacing.s5),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: XiaColors.border,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// SettingsRow — V2 §9.3 single tappable row inside [SettingsSection].
class SettingsRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final TextStyle? labelStyle;

  const SettingsRow({
    super.key,
    required this.label,
    this.value,
    this.onTap,
    this.trailing,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s5,
        vertical: 11,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style:
                  labelStyle ??
                  const TextStyle(fontSize: 14, color: XiaColors.text1),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: XiaSpacing.s2),
            Text(
              value!,
              style: const TextStyle(fontSize: 13, color: XiaColors.text3),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 14, color: XiaColors.text4),
          ],
          ?trailing,
        ],
      ),
    );

    if (onTap == null) return content;
    // Reuse the existing PressFeedback (no scale animation — pure bg swap).
    return PressFeedback(
      scale: 1.0,
      pressedColor: XiaColors.surface2,
      normalColor: Colors.transparent,
      onTap: onTap,
      child: content,
    );
  }
}
