import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/ui_kit/status_icon.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 消息气泡组件
/// 用户消息右对齐蓝色气泡，Agent 消息左对齐并支持 Markdown 渲染
class MessageBubble extends StatelessWidget {
  final Message message;
  final String agentName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.agentName,
  });

  bool get _isUser => message.role == MessageRole.user;

  String get _displayContent {
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

  Color _bubbleColor(ThemeData theme) {
    if (_isUser) return AppColors.primaryBlue;
    return theme.colorScheme.surfaceContainerHighest;
  }

  Color _textColor(ThemeData theme) {
    if (_isUser) return Colors.white;
    return theme.colorScheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: _isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!_isUser) ...[
            // Agent avatar
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary.withAlpha(40),
              child: Text(
                agentName.characters.first,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: _isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!_isUser)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      agentName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _bubbleColor(theme),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(_isUser ? 16 : 4),
                      bottomRight: Radius.circular(_isUser ? 4 : 16),
                    ),
                    border: message.status == MessageStatus.failed
                        ? Border.all(color: AppColors.messageFailed, width: 1.5)
                        : null,
                  ),
                  child: _isUser
                      ? Text(
                          _displayContent,
                          style: TextStyle(color: _textColor(theme)),
                        )
                      : _buildMarkdownContent(theme),
                ),
              ],
            ),
          ),
          if (_isUser) ...[
            const SizedBox(width: 4),
            StatusIcon(status: message.status, size: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildMarkdownContent(ThemeData theme) {
    return MarkdownBody(
      data: _displayContent,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: _textColor(theme), fontSize: 15),
        h1: TextStyle(
          color: _textColor(theme),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h2: TextStyle(
          color: _textColor(theme),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h3: TextStyle(
          color: _textColor(theme),
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        strong: TextStyle(
          color: _textColor(theme),
          fontWeight: FontWeight.bold,
        ),
        em: TextStyle(
          color: _textColor(theme),
          fontStyle: FontStyle.italic,
        ),
        a: TextStyle(
          color: AppColors.primaryBlue,
          decoration: TextDecoration.underline,
        ),
        code: TextStyle(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          color: AppColors.statusConnecting,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? Colors.black.withAlpha(60)
              : Colors.grey.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.dividerColor.withAlpha(80),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppColors.primaryBlue.withAlpha(150),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
        tableBorder: TableBorder.all(
          color: theme.dividerColor.withAlpha(100),
        ),
        tableHead: TextStyle(
          color: _textColor(theme),
          fontWeight: FontWeight.bold,
        ),
        tableBody: TextStyle(color: _textColor(theme)),
        listBullet: TextStyle(color: _textColor(theme)),
      ),
    );
  }
}
