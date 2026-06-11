import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/toast.dart';

/// Chat input bar — matching ComponentSpec Section 4.5.
///
/// Layout: [Plus btn 40×40] [TextField 16px radius] [Send btn 40×40]
class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;

  const ChatInputBar({super.key, required this.onSend});

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
    XiaToast.show(context, '附件功能开发中');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      color: XiaColors.bg,
      padding: EdgeInsets.fromLTRB(
        XiaSpacing.s6,
        XiaSpacing.s3,
        XiaSpacing.s6,
        XiaSpacing.s3 + bottomInset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Plus button
          _SmallButton(
            icon: Icons.add,
            onPressed: _showAttachmentOptions,
          ),
          const SizedBox(width: XiaSpacing.s3),
          // Input field
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                color: XiaColors.text1,
                fontSize: 15,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: '写点什么...',
                filled: true,
                fillColor: XiaColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(XiaRadius.lg),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: XiaSpacing.s5,
                  vertical: XiaSpacing.s3,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: XiaSpacing.s3),
          // Send button
          Opacity(
            opacity: _hasText ? 1.0 : 0.3,
            child: _SmallButton(
              icon: Icons.send,
              onPressed: _hasText ? _send : null,
              accent: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool accent;

  const _SmallButton({
    required this.icon,
    this.onPressed,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: accent ? XiaColors.accent : XiaColors.surface2,
        borderRadius: BorderRadius.circular(XiaRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(XiaRadius.md),
          onTap: onPressed,
          child: Icon(
            icon,
            color: accent ? Colors.white : XiaColors.text3,
            size: 20,
          ),
        ),
      ),
    );
  }
}
