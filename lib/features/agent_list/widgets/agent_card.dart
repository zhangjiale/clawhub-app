import 'dart:io';

import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// Agent card — V2 ComponentSpec Section 2.4.
///
/// V2: [36×36 avatar + status dot] [name + desc info]
/// Card: 10px radius, surface bg + 1px hairline border.
/// Press feedback: scale(0.97) + bg surface2, 150ms ease.
/// Status dot uses 2px bg-color border (V2 §2.4.1).
///
/// **Animation (B5)**: 250ms slideUp opacity enter via [StaggeredEnterItem],
/// with 30ms incremental delay based on [index] (max 210ms).
class AgentCard extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;
  final bool isOnline;
  final int? lastActiveAt;
  final int index; // B5: for staggered enter delay

  const AgentCard({
    super.key,
    required this.agent,
    required this.onTap,
    this.isOnline = false,
    this.lastActiveAt,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    return StaggeredEnterItem(
      index: index,
      child: PressFeedback(
        scale: 0.97,
        pressedColor: XiaColors.surface2,
        normalColor: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
        margin: const EdgeInsets.only(
          left: XiaSpacing.pagePaddingH,
          right: XiaSpacing.pagePaddingH,
          bottom: XiaSpacing.s2, // V2: 6px
        ),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: XiaColors.border),
            borderRadius: BorderRadius.circular(XiaRadius.lg),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: XiaSpacing.s4, // V2: 12px
            vertical: 10, // V2: 10px
          ),
          child: Row(
            children: [
              // Avatar with online status dot
              Stack(
                children: [
                  EmojiAvatar(
                    displayName: agent.displayName,
                    themeColor: agent.themeColor,
                    avatarImage: agent.avatarUrl != null
                        ? FileImage(File(agent.avatarUrl!))
                        : null,
                    radius: 18, // V2: 36×36
                    borderRadius: XiaRadius.md,
                    fontSize: 16,
                  ),
                  // Status dot (V2 §2.4.1: 10×10, 2px bg border, green glow)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isOnline ? XiaColors.green : XiaColors.text4,
                        shape: BoxShape.circle,
                        border: Border.all(color: XiaColors.bg, width: 2),
                        boxShadow: isOnline ? XiaShadow.onlineGlow : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10), // V2: 10
              // Name + description (name row + time inline per V2 §2.4.2)
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
                            style: const TextStyle(
                              fontSize: XiaTypography.agentName, // 15
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              height: 1.3,
                              color: XiaColors.text1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: XiaSpacing.s3),
                        Text(
                          _lastActiveText(lastActiveAt),
                          style: const TextStyle(
                            fontSize: XiaTypography.timestamp, // 10
                            color: XiaColors.text3,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (agent.description != null &&
                              agent.description!.isNotEmpty)
                          ? agent.description!
                          : '暂无简介',
                      style: const TextStyle(
                        fontSize: 12, // V2: 12
                        color: XiaColors.text3,
                        height: 1.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // V2: chevron removed (spec §2.4 — only press feedback)
            ],
          ),
        ),
      ),
    );
  }

  static String _lastActiveText(int? lastActiveAt) {
    if (lastActiveAt == null) return 'Never';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - lastActiveAt;
    if (diff < 60) return 'Just now';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    if (diff < 86400) return '${diff ~/ 3600}h ago';
    if (diff < 604800) return '${diff ~/ 86400}d ago';
    return '${diff ~/ 604800}w ago';
  }
}
