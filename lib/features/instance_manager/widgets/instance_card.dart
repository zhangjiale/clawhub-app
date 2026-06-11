import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Instance card — matching ComponentSpec Section 7.2.
///
/// Layout: [44×44 icon] [name + url + status] [action buttons]
class InstanceCard extends StatelessWidget {
  final Instance instance;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const InstanceCard({
    super.key,
    required this.instance,
    required this.onTap,
    this.onDelete,
  });

  Color _healthColor(HealthStatus status) {
    return switch (status) {
      HealthStatus.online => XiaColors.green,
      HealthStatus.offline => XiaColors.text4,
      HealthStatus.connecting => XiaColors.yellow,
      HealthStatus.expectedOffline => XiaColors.text4,
      HealthStatus.unknown => XiaColors.text4,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(XiaSpacing.s5),
          child: Row(
            children: [
              // Instance icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: XiaColors.surface2,
                  borderRadius: BorderRadius.circular(XiaRadius.md),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.dns,
                  size: 22,
                  color: XiaColors.text2,
                ),
              ),
              const SizedBox(width: XiaSpacing.s4),
              // Name + URL + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instance.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: XiaColors.text1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      instance.gatewayUrl,
                      style: const TextStyle(
                        fontSize: 13,
                        color: XiaColors.text3,
                        letterSpacing: -0.3,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: XiaSpacing.s1),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _healthColor(instance.healthStatus),
                            shape: BoxShape.circle,
                            boxShadow: instance.healthStatus ==
                                    HealthStatus.online
                                ? XiaShadow.onlineGlow
                                : null,
                          ),
                        ),
                        const SizedBox(width: XiaSpacing.s1),
                        Text(
                          instance.healthStatus == HealthStatus.online
                              ? '在线'
                              : '离线',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                instance.healthStatus == HealthStatus.online
                                    ? XiaColors.green
                                    : XiaColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Action buttons
              Row(
                children: [
                  _ActionBtn(icon: Icons.refresh, onTap: () {}),
                  if (onDelete != null) ...[
                    const SizedBox(width: XiaSpacing.s2),
                    _ActionBtn(
                      icon: Icons.delete_outline,
                      onTap: onDelete,
                      danger: true,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  const _ActionBtn({required this.icon, this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: danger ? XiaColors.redMuted : XiaColors.surface2,
        borderRadius: BorderRadius.circular(XiaRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(XiaRadius.sm),
          onTap: onTap,
          child: Icon(
            icon,
            size: 16,
            color: danger ? XiaColors.red : XiaColors.text3,
          ),
        ),
      ),
    );
  }
}
