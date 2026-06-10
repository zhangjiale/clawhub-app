import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// Agent Profile 头部组件
///
/// 展示大头像、名称、描述、在线状态和所属实例。
/// 完全参数化 — 不依赖任何 Provider。
class ProfileHeader extends StatelessWidget {
  final Agent agent;
  final Instance? instance;

  const ProfileHeader({
    super.key,
    required this.agent,
    this.instance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOnline = instance?.healthStatus.isConnectable ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          // Avatar with theme color border
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ColorExtension.fromHex(agent.themeColor),
                width: 4,
              ),
            ),
            child: EmojiAvatar(
              displayName: agent.displayName,
              themeColor: agent.themeColor,
              radius: 36,
            ),
          ),
          const SizedBox(height: 12),
          // Name + pin badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  agent.displayName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (agent.isPinned) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '已置顶',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Description
          if (agent.description != null && agent.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              agent.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          // Status row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppColors.statusOnline
                      : AppColors.statusOffline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                isOnline ? '在线' : '离线',
                style: TextStyle(
                  fontSize: 12,
                  color: isOnline
                      ? AppColors.statusOnline
                      : AppColors.statusOffline,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '·',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 12),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  instance?.name ?? '未知实例',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
