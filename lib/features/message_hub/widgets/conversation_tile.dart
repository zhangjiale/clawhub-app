import 'dart:io';

import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/message_hub/providers/message_hub_providers.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// Conversation list row — V2 ComponentSpec Section 3.2.
///
/// V2: 36×36 avatar (was 48×48), hairline border-bottom separator (V2 §3.2),
/// padding 10/16, red unread badge (#F87171), time text4, name 14/w600.
class ConversationTile extends StatelessWidget {
  final ConversationPreview preview;
  final VoidCallback? onTap;

  const ConversationTile({super.key, required this.preview, this.onTap});

  @override
  Widget build(BuildContext context) {
    final conv = preview.conversation;
    final agent = preview.agent;

    final hasUnread = conv.unreadCount > 0;
    final rawPreview = conv.lastMessagePreview ?? '';
    final isUser = conv.lastMessageRole == MessageRole.user;
    final previewText = _truncate(isUser ? '你: $rawPreview' : rawPreview);

    return PressFeedback(
      pressedColor: XiaColors.surface,
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: XiaColors.border)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.pagePaddingH, // V2: 16
          vertical: 10, // V2: 10
        ),
        child: Row(
          children: [
            // V2: 36×36 avatar
            Stack(
              children: [
                EmojiAvatar(
                  displayName: agent.displayName,
                  themeColor: agent.themeColor,
                  avatarImage: agent.avatarUrl != null
                      ? FileImage(File(agent.avatarUrl!))
                      : null,
                  backgroundColor: conv.isMuted ? XiaColors.surface2 : null,
                  radius: 18, // V2: 36×36
                  borderRadius: XiaRadius.md,
                  fontSize: 16,
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color:
                          preview.healthStatus == HealthStatus.online ||
                              preview.healthStatus == HealthStatus.connecting
                          ? XiaColors.green
                          : XiaColors.text4,
                      shape: BoxShape.circle,
                      border: Border.all(color: XiaColors.bg, width: 2),
                      boxShadow: preview.healthStatus == HealthStatus.online
                          ? XiaShadow.onlineGlow
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10), // V2: 10
            // Name + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          agent.displayName,
                          style: TextStyle(
                            fontSize: 14, // V2: 14
                            fontWeight: hasUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: XiaColors.text1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conv.isMuted)
                        const Icon(
                          Icons.volume_off,
                          size: 14,
                          color: XiaColors.text3,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText.isEmpty ? '暂无消息' : previewText,
                    style: TextStyle(
                      fontSize: 12, // V2: 12
                      color: hasUnread ? XiaColors.text1 : XiaColors.text3,
                      fontWeight: hasUnread
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: XiaSpacing.s2),
            // Time + unread badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatRelativeTime(conv.lastMessageTime),
                  style: const TextStyle(
                    fontSize: XiaTypography.timestamp, // V2: 10
                    color: XiaColors.text4,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (hasUnread) ...[
                  const SizedBox(height: 4),
                  _UnreadBadge(count: conv.unreadCount),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Truncate preview to 38 characters per V2 §3.2.2.
  static String _truncate(String text) {
    if (text.length <= 38) return text;
    return '${text.substring(0, 38)}…';
  }

  static String _formatRelativeTime(int timestampMs) {
    if (timestampMs <= 0) return '';
    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMs = now - timestampMs;
    final diffSeconds = diffMs ~/ 1000;

    if (diffSeconds < 60) return '刚刚';
    final diffMinutes = diffSeconds ~/ 60;
    if (diffMinutes < 60) return '$diffMinutes分钟前';
    final diffHours = diffMinutes ~/ 60;
    if (diffHours < 24) return '$diffHours小时前';
    final diffDays = diffHours ~/ 24;
    if (diffDays < 7) return '$diffDays天前';

    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

/// V2 unread badge — red (#F87171) capsule, min 16×16, padding 0/5.
class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
      decoration: const BoxDecoration(
        color: AppColors.unreadBadge, // V2: red #F87171
        borderRadius: BorderRadius.all(Radius.circular(XiaRadius.full)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
