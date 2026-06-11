import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// Agent card — matching ComponentSpec Section 2.4.
///
/// Layout: [48×48 avatar + status dot] [name + desc info] [time + chevron]
/// Card: 16px radius, surface background, no left border strip.
class AgentCard extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;
  final bool isOnline;
  final int? lastActiveAt;

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
    return Container(
      margin: const EdgeInsets.only(
        left: XiaSpacing.s6,
        right: XiaSpacing.s6,
        bottom: XiaSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: XiaSpacing.s5,
            vertical: XiaSpacing.s4,
          ),
          child: Row(
            children: [
              // Avatar with online status dot
              Stack(
                children: [
                  EmojiAvatar(
                    displayName: agent.displayName,
                    themeColor: agent.themeColor,
                    radius: 24, // 48×48
                    borderRadius: XiaRadius.md,
                    fontSize: 24,
                  ),
                  // Status dot (8×8, 2px border matching surface)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? XiaColors.green : XiaColors.text4,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: XiaColors.surface,
                          width: 2,
                        ),
                        boxShadow: isOnline ? XiaShadow.onlineGlow : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: XiaSpacing.s4),
              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      agent.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        height: 1.3,
                        color: XiaColors.text1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (agent.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        agent.description!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: XiaColors.text3,
                          height: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: XiaSpacing.s1),
              // Time + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _lastActiveText,
                    style: const TextStyle(
                      fontSize: 11,
                      color: XiaColors.text4,
                      letterSpacing: 0.2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const Icon(
                Icons.chevron_right,
                color: XiaColors.text4,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
