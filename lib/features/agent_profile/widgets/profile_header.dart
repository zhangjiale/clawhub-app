import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// Agent Profile header — matching ComponentSpec Section 5.2.
///
/// 72×72 avatar (borderRadius 16), 24px name, 14px description, inline status.
class ProfileHeader extends StatelessWidget {
  final Agent agent;
  final Instance? instance;

  const ProfileHeader({super.key, required this.agent, this.instance});

  @override
  Widget build(BuildContext context) {
    final isOnline = instance?.healthStatus.isConnectable ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: XiaSpacing.s6,
      ),
      child: Column(
        children: [
          // Avatar — 72×72, borderRadius 16
          EmojiAvatar(
            displayName: agent.displayName,
            themeColor: agent.themeColor,
            avatarUrl: agent.avatarUrl,
            radius: 36,
            borderRadius: XiaRadius.lg,
            fontSize: 36,
          ),
          const SizedBox(height: XiaSpacing.s4),
          // Name — 24px, weight 700
          Text(
            agent.displayName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: XiaColors.text1,
            ),
          ),
          if (agent.description != null && agent.description!.isNotEmpty) ...[
            const SizedBox(height: XiaSpacing.s1),
            Text(
              agent.description!,
              style: const TextStyle(
                fontSize: 14,
                color: XiaColors.text3,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: XiaSpacing.s3),
          // Status row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isOnline ? XiaColors.green : XiaColors.text4,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: XiaSpacing.s1),
              Text(
                isOnline ? '在线' : '离线',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isOnline ? XiaColors.green : XiaColors.text4,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '·',
                style: TextStyle(color: XiaColors.text3, fontSize: 12),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  instance?.name ?? '未知实例',
                  style: const TextStyle(fontSize: 12, color: XiaColors.text3),
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
