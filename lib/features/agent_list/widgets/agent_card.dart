import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Agent 卡片组件
/// 对齐: InstanceCard 模式，显示头像圆、名称、描述、在线状态、最后活跃时间
class AgentCard extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;
  final bool isOnline;
  final int? lastActiveAt; // 最后活跃时间戳（秒）

  const AgentCard({
    super.key,
    required this.agent,
    required this.onTap,
    this.isOnline = false,
    this.lastActiveAt,
  });

  String get _lastActiveText {
    if (lastActiveAt == null) return 'Never';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - lastActiveAt!;
    if (diff < 60) return 'Just now';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    if (diff < 86400) return '${diff ~/ 3600}h ago';
    if (diff < 604800) return '${diff ~/ 86400}d ago';
    return '${diff ~/ 604800}w ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ColorExtension.fromHex(agent.themeColor);
    final firstChar = agent.displayName.characters.first;
    final dimmed = !isOnline;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: dimmed ? 0.55 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar circle with online status dot
                Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: dimmed ? Colors.grey : color,
                      foregroundColor:
                          (dimmed ? Colors.grey : color).contrastingTextColor(),
                      child: Text(
                        firstChar,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Online status dot
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? AppColors.statusOnline
                              : AppColors.statusOffline,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // Name + description + last active
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              agent.displayName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: dimmed
                                    ? theme.colorScheme.outline
                                    : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (agent.isPinned) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.push_pin,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      if (agent.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          agent.description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Online status dot + text
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? AppColors.statusOnline
                                  : AppColors.statusOffline,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isOnline
                                  ? AppColors.statusOnline
                                  : AppColors.statusOffline,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Last active time
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _lastActiveText,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
