import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:flutter/material.dart';

/// Renders the file-attachment portion of a chat message bubble.
///
/// Extracted from [MessageBubble._buildFileContent] (P1): isolated in its
/// own widget + wrapped in [RepaintBoundary] so a rebuild of MessageBubble
/// doesn't reconstruct the file card or invalidate its paint layer.
///
/// Law 2 compliant: pure rendering, no platform/IO calls.
class MessageFileContent extends StatelessWidget {
  final Message message;
  final bool isUser;

  const MessageFileContent({
    super.key,
    required this.message,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final filePath = message.filePath;
    final name = message.fileName;
    if (filePath == null && name == null) {
      return Text(
        '[文件]',
        style: TextStyle(
          color: isUser ? Colors.white : XiaColors.text2,
          fontSize: 14,
        ),
      );
    }
    final size = message.fileSize;
    return RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            color: isUser ? Colors.white : XiaColors.accent,
            size: 28,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name ?? '文件',
                  style: TextStyle(
                    color: isUser ? Colors.white : XiaColors.text1,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (size != null)
                  Text(
                    _formatSize(size),
                    style: TextStyle(
                      color: isUser ? Colors.white70 : XiaColors.text3,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
