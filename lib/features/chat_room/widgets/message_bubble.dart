import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/ui_kit/status_icon.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Message bubble — matching ComponentSpec Section 4.2.2.
///
/// User: coral bg (#C27C68), white text, right-aligned, 20px radius with
///       8px bottom-right corner (speech tail).
/// Agent: surface bg, text1, left-aligned, 20px radius with
///        8px bottom-left corner, shadow-s.
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: 4,
      ),
      child: Row(
        mainAxisAlignment:
            _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!_isUser) ...[
            // Agent mini avatar (28×28, borderRadius 8)
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(XiaRadius.sm),
                color: XiaColors.accentMuted,
              ),
              alignment: Alignment.center,
              child: Text(
                agentName.characters.first,
                style: const TextStyle(
                  fontSize: 12,
                  color: XiaColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: XiaSpacing.s2),
          ],
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
                    horizontal: XiaSpacing.s5,
                    vertical: XiaSpacing.s3,
                  ),
                  decoration: BoxDecoration(
                    color: _isUser ? XiaColors.accent : XiaColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(XiaRadius.xl),
                      topRight: const Radius.circular(XiaRadius.xl),
                      bottomLeft: Radius.circular(
                        _isUser ? XiaRadius.xl : XiaRadius.sm,
                      ),
                      bottomRight: Radius.circular(
                        _isUser ? XiaRadius.sm : XiaRadius.xl,
                      ),
                    ),
                    boxShadow: _isUser ? null : XiaShadow.s,
                    border: message.status == MessageStatus.failed
                        ? Border.all(color: XiaColors.red, width: 1.5)
                        : null,
                  ),
                  child: _isUser
                      ? Text(
                          _displayContent,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.6,
                          ),
                        )
                      : _buildMarkdownContent(),
                ),
                // Message time
                Padding(
                  padding: const EdgeInsets.only(
                    top: XiaSpacing.s1,
                    left: XiaSpacing.s1,
                    right: XiaSpacing.s1,
                  ),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: const TextStyle(
                      fontSize: 11,
                      color: XiaColors.text4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
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

  String _formatTime(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildMarkdownContent() {
    return MarkdownBody(
      data: _displayContent,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(
          color: XiaColors.text1,
          fontSize: 15,
          height: 1.6,
        ),
        h1: const TextStyle(
          color: XiaColors.text1,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h2: const TextStyle(
          color: XiaColors.text1,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h3: const TextStyle(
          color: XiaColors.text1,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        strong: const TextStyle(
          color: XiaColors.text1,
          fontWeight: FontWeight.bold,
        ),
        em: const TextStyle(
          color: XiaColors.text1,
          fontStyle: FontStyle.italic,
        ),
        a: const TextStyle(
          color: XiaColors.accent,
          decoration: TextDecoration.underline,
        ),
        code: const TextStyle(
          backgroundColor: XiaColors.codeBlockBg,
          color: XiaColors.accent,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: XiaColors.surface2,
          borderRadius: BorderRadius.circular(XiaRadius.md),
        ),
        codeblockPadding: const EdgeInsets.all(XiaSpacing.s4),
        blockquoteDecoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: XiaColors.accent, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: XiaSpacing.s3),
        tableBorder: TableBorder.all(color: XiaColors.divider),
        tableHead: const TextStyle(
          color: XiaColors.text1,
          fontWeight: FontWeight.bold,
        ),
        tableBody: const TextStyle(color: XiaColors.text1),
        listBullet: const TextStyle(color: XiaColors.text1),
      ),
    );
  }
}
