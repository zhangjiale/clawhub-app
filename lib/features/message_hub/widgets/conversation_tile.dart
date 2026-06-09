import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/message_hub/providers/message_hub_providers.dart';

/// 对话列表行组件
///
/// 展示一条对话预览：头像、名称、最后消息预览、时间、未读角标。
/// 对齐: US-010 AC-2/AC-3
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

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar
            _ConversationAvatar(
              agent: agent,
              isMuted: conv.isMuted,
              healthStatus: preview.healthStatus,
            ),
            const SizedBox(width: 12),
            // Center: name + preview
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
                          color: theme.colorScheme.outline,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText.isEmpty ? '开始对话吧' : previewText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasUnread
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.outline,
                      fontWeight:
                          hasUnread ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right: time + unread badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatRelativeTime(conv.lastMessageTime),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
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

  /// 截断预览文本到 40 字符
  static String _truncate(String text) {
    if (text.length <= 40) return text;
    return '${text.substring(0, 40)}…';
  }

  /// 相对时间格式化
  /// - < 1 分钟: "刚刚"
  /// - < 60 分钟: "X分钟前"
  /// - < 24 小时: "X小时前"
  /// - < 7 天: "X天前"
  /// - 其他: "MM/dd"
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

/// 对话头像 — 首字符 + Agent 主题色背景 + 在线状态圆点
class _ConversationAvatar extends StatelessWidget {
  final Agent agent;
  final bool isMuted;
  final HealthStatus healthStatus;

  const _ConversationAvatar({
    required this.agent,
    required this.isMuted,
    required this.healthStatus,
  });

  Color _statusDotColor() {
    switch (healthStatus) {
      case HealthStatus.online:
      case HealthStatus.connecting:
        return Colors.green;
      case HealthStatus.offline:
      case HealthStatus.expectedOffline:
      case HealthStatus.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isMuted
        ? theme.colorScheme.surfaceContainerHighest
        : ColorExtension.fromHex(agent.themeColor);

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: color,
            child: Text(
              agent.displayName.isNotEmpty ? agent.displayName[0] : '?',
              style: TextStyle(
                color: color.contrastingTextColor(),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Online status dot
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _statusDotColor(),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 未读角标 — 红色圆形数字
class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: const BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
