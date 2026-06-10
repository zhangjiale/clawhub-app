import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 通用 Emoji/首字符头像组件
///
/// 显示 displayName 的首字符，背景为 themeColor，可配置半径。
/// 在 ChatRoomPage AppBar 和 AgentProfilePage 的 ProfileHeader 中复用。
class EmojiAvatar extends StatelessWidget {
  final String displayName;
  final String themeColor;
  final double radius;

  const EmojiAvatar({
    super.key,
    required this.displayName,
    required this.themeColor,
    this.radius = 36,
  });

  @override
  Widget build(BuildContext context) {
    final color = ColorExtension.fromHex(themeColor);
    final firstChar = displayName.isNotEmpty ? displayName.characters.first : '';

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundColor: color.contrastingTextColor(),
      child: Text(
        firstChar,
        style: TextStyle(
          fontSize: radius * 0.55,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
