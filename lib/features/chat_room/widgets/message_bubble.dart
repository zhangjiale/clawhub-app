import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:claw_hub/app/theme/agent_theme.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/ui_kit/status_icon.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/xia_markdown_styles.dart';

/// Message bubble — matching V2 ComponentSpec Section 4.2.2.
///
/// User: sapphire bg (#4F83FF), white text, right-aligned, 14px radius with
///       4px bottom-right corner (speech tail).
/// Agent: surface2 bg, text1, left-aligned, 14px radius with
///        4px bottom-left corner, hairline border (no shadow).
///
/// **Animation (B3)**: 250ms opacity(0→1) + translateY(10px→0) enter
/// animation via [StaggeredEnterItem] based on [index].
class MessageBubble extends StatelessWidget {
  final Message message;
  final String agentName;
  final int index; // B3: for staggered enter delay
  final VoidCallback? onRetry; // US-015 AC2: retry FAILED messages
  final bool isHighlighted; // search-result highlight

  const MessageBubble({
    super.key,
    required this.message,
    required this.agentName,
    this.index = 0,
    this.onRetry,
    this.isHighlighted = false,
  });

  bool get _isUser => message.role == MessageRole.user;

  /// 失败消息且 [onRetry] 可用时，渲染可点击的"状态图标 + 重试"组合；
  /// 否则渲染普通 [StatusIcon]。
  Widget _buildStatusIndicator() {
    if (message.status != MessageStatus.failed || onRetry == null) {
      return StatusIcon(status: message.status, size: 14);
    }
    return Tooltip(
      message: '重试发送',
      child: GestureDetector(
        onTap: onRetry,
        behavior: HitTestBehavior.opaque, // larger hit area
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusIcon(status: message.status, size: 14),
              const SizedBox(width: 2),
              const Icon(Icons.refresh, size: 12, color: XiaColors.red),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StaggeredEnterItem(
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.pagePaddingH,
          vertical: 4,
        ),
        child: Row(
          mainAxisAlignment: _isUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: _isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: _isUser
                          ? AgentTheme.of(context).primary
                          : isHighlighted
                          ? XiaColors.accent.withAlpha(38)
                          : XiaColors.surface2,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(XiaRadius.xl),
                        topRight: const Radius.circular(XiaRadius.xl),
                        bottomLeft: Radius.circular(
                          _isUser ? XiaRadius.xl : XiaRadius.xs,
                        ),
                        bottomRight: Radius.circular(
                          _isUser ? XiaRadius.xs : XiaRadius.xl,
                        ),
                      ),
                      // V2: removed boxShadow (replaced by hairline border).
                      // 高亮边框优先于失败边框 —— 搜索结果高亮是用户主动导航的目标，
                      // 即使消息发送失败，用户仍需看到"这就是你搜的那条"的视觉反馈。
                      border: isHighlighted
                          ? Border.all(color: XiaColors.accent, width: 2)
                          : message.status == MessageStatus.failed
                          ? Border.all(color: XiaColors.red, width: 1)
                          : _isUser
                          ? null
                          : Border.all(color: XiaColors.border),
                    ),
                    child: _buildContent(message),
                  ),
                  // Message time
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 3,
                      left: XiaSpacing.s1,
                      right: XiaSpacing.s1,
                    ),
                    child: Text(
                      _formatTime(message.timestamp),
                      style: const TextStyle(
                        fontSize: XiaTypography.timestamp, // V2: 10
                        color: XiaColors.text4,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isUser) ...[const SizedBox(width: 4), _buildStatusIndicator()],
          ],
        ),
      ),
    );
  }

  static String _displayContent(Message message) {
    if (message.content != null && message.content!.isNotEmpty) {
      return message.content!;
    }
    return switch (message.type) {
      MessageType.image => '[图片]',
      MessageType.file => '[文件]',
      MessageType.toolCall => '[工具调用]',
      MessageType.text => '',
    };
  }

  /// 按消息类型分派渲染:image/file 走专用 widget,text/toolCall 走原有文本/Markdown。
  Widget _buildContent(Message message) {
    switch (message.type) {
      case MessageType.image:
        return _buildImageContent(message);
      case MessageType.file:
        return _buildFileContent(message);
      case MessageType.text:
      case MessageType.toolCall:
        final text = _displayContent(message);
        if (_isUser) {
          return Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
            ),
          );
        }
        return _buildMarkdownContent(text);
    }
  }

  /// 图片消息:Agent 回图(imageUrl)走网络图,用户发送(imagePath)走本地文件,
  /// 均可带 caption(Agent 回图的 content 即 caption;用户图从 metadata.caption 取)。
  Widget _buildImageContent(Message message) {
    final imageUrl = message.imageUrl;
    final imagePath = message.imagePath;
    final Image? image = imageUrl != null
        ? Image.network(
            imageUrl,
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _BrokenImage(),
          )
        : imagePath != null
        ? Image.file(
            File(imagePath),
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _BrokenImage(),
          )
        : null;
    if (image == null) {
      return Text(
        '[图片]',
        style: TextStyle(
          color: _isUser ? Colors.white : XiaColors.text2,
          fontSize: 14,
        ),
      );
    }
    // caption:用户图从 metadata.caption;Agent 回图从 content(图片说明文本)。
    final caption =
        message.caption ??
        (imageUrl != null &&
                message.content != null &&
                message.content!.isNotEmpty
            ? message.content
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(XiaRadius.lg),
          child: image,
        ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              caption,
              style: TextStyle(
                color: _isUser ? Colors.white : XiaColors.text1,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  /// 文件消息:文件名 + 大小的卡片样式。无任何文件数据(无路径无文件名)时
  /// 回退 `[文件]` 占位文本(兼容旧占位契约)。
  Widget _buildFileContent(Message message) {
    final filePath = message.filePath;
    final name = message.fileName;
    if (filePath == null && name == null) {
      return Text(
        '[文件]',
        style: TextStyle(
          color: _isUser ? Colors.white : XiaColors.text2,
          fontSize: 14,
        ),
      );
    }
    final size = message.fileSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.insert_drive_file_outlined,
          color: _isUser ? Colors.white : XiaColors.accent,
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
                  color: _isUser ? Colors.white : XiaColors.text1,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (size != null)
                Text(
                  _formatSize(size),
                  style: TextStyle(
                    color: _isUser ? Colors.white70 : XiaColors.text3,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static String _formatTime(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static Widget _buildMarkdownContent(String data) {
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: XiaMarkdownStyles.message,
    );
  }
}

/// 图片加载失败占位(本地文件被清理或网络图 404)。
class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 120,
      color: XiaColors.surface3,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: XiaColors.text4, size: 32),
          const SizedBox(height: 4),
          Text('图片不可用', style: TextStyle(color: XiaColors.text4, fontSize: 12)),
        ],
      ),
    );
  }
}
