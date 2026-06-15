import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/message_hub/providers/message_hub_providers.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// Conversation list row — matching ComponentSpec Section 3.2.
///
/// Layout: [48×48 avatar + status dot] [name + preview] [time + unread badge]
/// Press: bg→surface2, 200ms ease.
class ConversationTile extends StatelessWidget {
  final ConversationPreview preview;
  final VoidCallback? onTap;

  const ConversationTile({super.key, required this.preview, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conv = preview.conversation;
    final agent = preview.agent;

    final hasUnread = conv.unreadCount > 0;
    final rawPreview = conv.lastMessagePreview ?? '';
    final isUser = conv.lastMessageRole == MessageRole.user;
    final previewText = _truncate(isUser ? '你: $rawPreview' : rawPreview);

    return PressFeedback(
      pressedColor: XiaColors.surface2,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s6,
          vertical: XiaSpacing.s5,
        ),
        child: Row(
          children: [
            // Avatar
            _ConversationAvatar(
              agent: agent,
              isMuted: conv.isMuted,
              healthStatus: preview.healthStatus,
            ),
            const SizedBox(width: XiaSpacing.s4),
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
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: hasUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conv.isMuted)
                        Icon(
                          Icons.volume_off,
                          size: 14,
                          color: XiaColors.text3,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText.isEmpty ? '开始对话吧' : previewText,
                    style: theme.textTheme.bodySmall?.copyWith(
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
                    fontSize: 12,
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

  /// Truncate preview to 38 characters.
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

/// Conversation avatar — rounded rect with status dot.
class _ConversationAvatar extends StatelessWidget {
  final Agent agent;
  final bool isMuted;
  final HealthStatus healthStatus;

  const _ConversationAvatar({
    required this.agent,
    required this.isMuted,
    required this.healthStatus,
  });

  @override
  Widget build(BuildContext context) {
    final color = isMuted
        ? XiaColors.surface2
        : ColorExtension.fromHex(agent.themeColor);

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(XiaRadius.md),
            ),
            alignment: Alignment.center,
            child: Text(
              agent.displayName.isNotEmpty ? agent.displayName[0] : '?',
              style: TextStyle(
                color: color.contrastingTextColor(),
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color:
                    healthStatus == HealthStatus.online ||
                        healthStatus == HealthStatus.connecting
                    ? XiaColors.green
                    : XiaColors.text4,
                shape: BoxShape.circle,
                border: Border.all(color: XiaColors.surface, width: 2),
                boxShadow: healthStatus == HealthStatus.online
                    ? XiaShadow.onlineGlow
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unread badge — capsule with accent background.
class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: const BoxDecoration(
        color: XiaColors.accent,
        borderRadius: BorderRadius.all(Radius.circular(XiaRadius.full)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
