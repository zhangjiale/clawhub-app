import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Universal emoji/first-character avatar with configurable border radius.
///
/// Design spec: avatars use rounded rectangles (not circles):
/// - Agent cards / message lists: radius 12 ([XiaRadius.md])
/// - Chat header: radius 8 ([XiaRadius.sm])
/// - Agent detail: radius 16 ([XiaRadius.lg])
class EmojiAvatar extends StatelessWidget {
  final String displayName;
  final String themeColor;
  final double radius;
  final double borderRadius;
  final double fontSize;

  const EmojiAvatar({
    super.key,
    required this.displayName,
    required this.themeColor,
    this.radius = 24,
    this.borderRadius = XiaRadius.md,
    this.fontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final color = ColorExtension.fromHex(themeColor);
    final firstChar =
        displayName.isNotEmpty ? displayName.characters.first : '';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        firstChar,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: color.contrastingTextColor(),
        ),
      ),
    );
  }
}
