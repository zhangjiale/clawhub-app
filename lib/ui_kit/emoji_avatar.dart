import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Universal avatar widget with configurable border radius.
///
/// Renders either:
/// - A custom image (when [avatarImage] is provided, e.g. [FileImage])
/// - A fallback text avatar (first character of [displayName] on a colored background)
///
/// Design spec: avatars use rounded rectangles (not circles):
/// - Agent cards / message lists: radius 12 ([XiaRadius.md])
/// - Chat header: radius 8 ([XiaRadius.sm])
/// - Agent detail: radius 16 ([XiaRadius.lg])
///
/// [avatarImage] accepts any [ImageProvider] — callers are responsible for
/// constructing the appropriate provider (e.g. [FileImage], [MemoryImage],
/// [NetworkImage]). This decouples the widget from [dart:io] and the local
/// filesystem.
class EmojiAvatar extends StatelessWidget {
  final String displayName;
  final String themeColor;
  final double radius;
  final double borderRadius;
  final double fontSize;

  /// Optional image provider for a custom avatar image.
  ///
  /// When non-null, an [Image] widget attempts to display the avatar using
  /// this provider. If loading fails, the text-based fallback is shown via
  /// [errorBuilder] (no sync disk I/O).
  ///
  /// Callers that read avatar files from disk should pass a [FileImage].
  /// Callers with in-memory bytes should pass a [MemoryImage].
  final ImageProvider? avatarImage;

  /// Optional color override for the background.
  ///
  /// When non-null, this color replaces [themeColor] as the background,
  /// AND the text color is computed from this color (not from [themeColor]).
  /// This guarantees consistent contrast — e.g. when [ConversationTile]
  /// passes a muted gray background, the text stays readable.
  final Color? backgroundColor;

  const EmojiAvatar({
    super.key,
    required this.displayName,
    required this.themeColor,
    this.radius = 24,
    this.borderRadius = XiaRadius.md,
    this.fontSize = 24,
    this.avatarImage,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // Pre-build text fallback once — frameBuilder may fire every frame
    // during async image loading, so reusing the same widget instance
    // avoids redundant widget tree reconstruction.
    final textFallback = _buildTextAvatar();

    if (avatarImage != null) {
      return _buildImageAvatar(textFallback);
    }
    return textFallback;
  }

  /// Renders the custom image avatar.
  ///
  /// Uses [Image] with the caller-provided [avatarImage], with both
  /// [frameBuilder] and [errorBuilder] falling back to [textFallback]
  /// (pre-built in [build]). This avoids sync disk I/O in build while
  /// also preventing a blank flash during async loading.
  Widget _buildImageAvatar(Widget textFallback) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(
        image: avatarImage!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (!wasSynchronouslyLoaded && frame == null) {
            // Still loading — show pre-built text fallback to avoid blank flash
            return textFallback;
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) => textFallback,
      ),
    );
  }

  /// Renders the fallback text avatar (first character + colored background).
  Widget _buildTextAvatar() {
    final bgColor = backgroundColor ?? ColorExtension.fromHex(themeColor);
    // Always compute text color from the actual background color,
    // NOT from themeColor — so backgroundColor overrides stay readable.
    final textColor = bgColor.contrastingTextColor();
    final firstChar = displayName.isNotEmpty
        ? displayName.characters.first
        : '?';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        firstChar,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}
