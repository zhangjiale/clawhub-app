import 'dart:io';

import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// Agent Profile header — V2 §5.2.
///
/// V2: 56×56 avatar (was 72×72), radius lg=10, name 18/w700 (was 24),
/// description 13/text3, status row 11/text3 inline.
class ProfileHeader extends StatelessWidget {
  final Agent agent;
  final Instance? instance;

  const ProfileHeader({super.key, required this.agent, this.instance});

  @override
  Widget build(BuildContext context) {
    final isOnline = instance?.healthStatus.isConnectable ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s5, // V2: 16
        vertical: 16, // V2: 16
      ),
      child: Column(
        children: [
          // V2: 56×56 avatar (was 72×72), radius lg=10
          EmojiAvatar(
            displayName: agent.displayName,
            themeColor: agent.themeColor,
            avatarImage: agent.avatarUrl != null
                ? FileImage(File(agent.avatarUrl!))
                : null,
            radius: 28,
            borderRadius: XiaRadius.lg,
            fontSize: 24,
          ),
          const SizedBox(height: XiaSpacing.s3),
          // V2: name 18/w700
          Text(
            agent.displayName,
            style: const TextStyle(
              fontSize: XiaTypography.detailName, // 18
              fontWeight: FontWeight.w700,
              color: XiaColors.text1,
            ),
          ),
          if (agent.description != null && agent.description!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              agent.description!,
              style: const TextStyle(
                fontSize: 13, // V2: 13
                color: XiaColors.text3,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          // V2: status row inline (11/text3)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: isOnline ? XiaColors.green : XiaColors.text4,
                  shape: BoxShape.circle,
                  boxShadow: isOnline ? XiaShadow.onlineGlow : null,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                isOnline ? '在线' : '离线',
                style: TextStyle(
                  fontSize: 11,
                  color: isOnline ? XiaColors.green : XiaColors.text4,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '·',
                style: TextStyle(color: XiaColors.text4, fontSize: 11),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  instance?.name ?? '未知实例',
                  style: const TextStyle(fontSize: 11, color: XiaColors.text4),
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
