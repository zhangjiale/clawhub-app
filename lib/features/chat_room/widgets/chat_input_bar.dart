import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 聊天输入栏
/// 固定底部，多行输入，发送按钮
class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;

  const ChatInputBar({
    super.key,
    required this.onSend,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  void _showAttachmentOptions() {
    // Placeholder: attachment picker (image/file/camera)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('附件功能：图片/文件/拍照 (开发中)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomInset),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withAlpha(50)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // [+] 圆形按钮 — 附件入口
          _CircularButton(
            icon: Icons.add,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            iconColor: theme.colorScheme.onSurfaceVariant,
            onPressed: _showAttachmentOptions,
          ),
          const SizedBox(width: 8),
          // 消息输入框
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '输入消息...',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          // 发送按钮 — 圆形实心
          _CircularButton(
            icon: Icons.send,
            backgroundColor: _hasText
                ? AppColors.primaryBlue
                : theme.colorScheme.surfaceContainerHighest,
            iconColor:
                _hasText ? Colors.white : theme.colorScheme.outline,
            onPressed: _hasText ? _send : null,
          ),
        ],
      ),
    );
  }
}

/// 36×36 圆形按钮，用于输入栏 [+] 和发送钮
class _CircularButton extends StatelessWidget {
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback? onPressed;

  const _CircularButton({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }
}
