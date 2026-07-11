import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/message.dart';

/// "Tap to load" bubble rendered for chat.history omitted placeholders.
///
/// When `chat.history` replaces an oversized message's content with the
/// placeholder `[chat.history omitted: message too large]`, the ACL mapper
/// sets `metadata['contentOmitted'] = true`. [MessageBubble] detects that flag
/// and renders this widget instead of the normal content. The user taps to
/// lazy-fetch the full message via `chat.message.get` (ChatViewModel.
/// loadFullMessage).
///
/// Local UI state only (idle / loading / error) - this is a self-contained
/// button spinner, not business state, so a StatefulWidget is appropriate
/// (mirrors the existing `onRetry` pattern on MessageBubble). On a successful
/// backfill the parent re-renders with the flag cleared and this widget
/// unmounts; on failure it shows "加载失败，点击重试".
class MessageOmittedContent extends StatefulWidget {
  final Message message;
  final Future<void> Function() onLoad;

  const MessageOmittedContent({
    super.key,
    required this.message,
    required this.onLoad,
  });

  @override
  State<MessageOmittedContent> createState() => _MessageOmittedContentState();
}

class _MessageOmittedContentState extends State<MessageOmittedContent> {
  bool _isLoading = false;
  bool _error = false;

  Future<void> _handleTap() async {
    if (_isLoading) return; // dedup double-tap
    setState(() {
      _isLoading = true;
      _error = false;
    });
    try {
      await widget.onLoad();
      // Success: the parent rebuilds with contentOmitted cleared and this
      // widget unmounts. If we're still mounted (e.g. onLoad was a no-op
      // guard hit), reset to idle so the user can try again.
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      // loadFullMessage rethrows on fetch failure / null -> show retry.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              '加载中…',
              style: TextStyle(fontSize: 13, color: XiaColors.text3),
            ),
          ),
        ],
      );
    }
    final label = _error ? '加载失败，点击重试' : '消息过大，点击加载完整内容';
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _error ? Icons.refresh : Icons.download_outlined,
            size: 16,
            color: _error ? XiaColors.red : XiaColors.text3,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: _error ? XiaColors.red : XiaColors.text3,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
