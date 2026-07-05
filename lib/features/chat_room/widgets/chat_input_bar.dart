import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'attachment_sheet.dart';

/// Chat input bar — V2 ComponentSpec §4.5.
///
/// 布局:`[+ 附件按钮] [Textarea r-xl 14px] [Send btn 36×36 circle, glow]`
/// Padding: 6/16 + safe-bottom.
///
/// "+" 按钮:反转 V2 §4.5.1"移除 Plus Button"决策 —— PRD 3.3 规则 2/8 要求
/// 图片/文件消息能力,附件入口是必要的。点击弹出 [AttachmentSheet],选择后
/// 回调 [onPickAttachment];实际 image_picker/file_picker 调用在 page 层(Law 2)。
///
/// **Performance**: the send-button subtree rebuilds via
/// [ValueListenableBuilder] listening to [_controller], so IME composition
/// does not trigger a full TextField re-layout on every keystroke.
class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;
  final ValueChanged<AttachmentKind>? onPickAttachment;

  const ChatInputBar({super.key, required this.onSend, this.onPickAttachment});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();

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
    // No setState needed — ValueListenableBuilder reacts to .clear().
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Container(
      color: XiaColors.bg,
      padding: EdgeInsets.fromLTRB(
        XiaSpacing.s5,
        XiaSpacing.s2,
        XiaSpacing.s5,
        XiaSpacing.s2 + bottomInset + safeBottom,
      ),
      child: Row(
        // center (not end) so the 36×36 send button visually aligns with the
        // input field's content area in the single-line default state. See
        // component-spec-v2 §4.5.1.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.onPickAttachment != null)
            _AttachButton(
              onTap: () => AttachmentSheet.show(
                context,
                onPick: widget.onPickAttachment!,
              ),
            ),
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: const TextStyle(
                color: XiaColors.text1,
                fontSize: 14,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: '发消息...',
                filled: true,
                fillColor: XiaColors.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(XiaRadius.xl),
                  borderSide: const BorderSide(color: XiaColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(XiaRadius.xl),
                  borderSide: const BorderSide(color: XiaColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(XiaRadius.xl),
                  borderSide: const BorderSide(
                    color: XiaColors.accent,
                    width: 1,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
              ),
            ),
          ),
          const SizedBox(width: XiaSpacing.s2),
          // Scoped rebuild: only this button redraws on text changes.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, _) {
              final enabled = value.text.trim().isNotEmpty;
              return _SendButton(enabled: enabled, onSend: _send);
            },
          ),
        ],
      ),
    );
  }
}

/// Stateless send button — reuses [PressFeedback] for press state.
/// V2: 36×36 circle, accent fill, glow when not pressed, scale 0.88 on press.
class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onSend;

  const _SendButton({required this.enabled, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: PressFeedback(
        scale: 0.88,
        onTap: enabled ? onSend : null,
        builder: (child, isPressed) => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: XiaColors.accent,
            shape: BoxShape.circle,
            boxShadow: isPressed ? null : XiaShadow.glow,
          ),
          alignment: Alignment.center,
          child: child,
        ),
        child: const Icon(Icons.send, color: Colors.white, size: 18),
      ),
    );
  }
}

/// "+" 附件按钮 —— 36×36 圆形,点击弹出 [AttachmentSheet]。
/// 仅当 [ChatInputBar.onPickAttachment] 非空时渲染。
class _AttachButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AttachButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      scale: 0.88,
      onTap: onTap,
      builder: (child, isPressed) => Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(right: XiaSpacing.s2),
        decoration: BoxDecoration(
          color: XiaColors.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: XiaColors.border),
        ),
        alignment: Alignment.center,
        child: child,
      ),
      child: const Icon(Icons.add, color: XiaColors.text2, size: 20),
    );
  }
}
