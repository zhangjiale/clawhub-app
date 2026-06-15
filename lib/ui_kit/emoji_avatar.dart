import 'dart:io';

import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Universal avatar widget with configurable border radius.
///
/// Renders either:
/// - A custom image (when [avatarUrl] points to an existing file)
/// - A fallback text avatar (first character of [displayName] on a colored background)
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

  /// Optional local file path to a custom avatar image.
  ///
  /// When non-null, an [Image.file] widget attempts to display the avatar.
  /// If the file doesn't exist or fails to load, the text-based fallback
  /// is shown via [frameBuilder]/[errorBuilder] (no sync disk I/O).
  final String? avatarUrl;

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
    this.avatarUrl,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // Image path → render image file.
    // No existsSync() pre-check: FileImage + errorBuilder handles missing
    // files gracefully without blocking the UI thread on sync disk I/O.
    if (avatarUrl != null) {
      return _buildImageAvatar();
    }
    return _buildTextAvatar();
  }

  /// Renders the custom image avatar.
  ///
  /// Uses [Image.file] with both [frameBuilder] and [errorBuilder] falling
  /// back to [_buildTextAvatar]. This avoids [File.existsSync] (sync disk
  /// I/O in build) while also preventing a blank flash during async loading.
  Widget _buildImageAvatar() {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.file(
        File(avatarUrl!),
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (!wasSynchronouslyLoaded && frame == null) {
            // Still loading — show text fallback to avoid blank flash
            return _buildTextAvatar();
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) => _buildTextAvatar(),
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
