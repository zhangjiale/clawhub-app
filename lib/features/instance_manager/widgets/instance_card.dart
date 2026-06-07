import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 实例卡片组件
/// 显示实例名称、Gateway URL、健康状态指示点
class InstanceCard extends StatelessWidget {
  final Instance instance;
  final VoidCallback onTap;

  const InstanceCard({
    super.key,
    required this.instance,
    required this.onTap,
  });

  Color _healthColor(HealthStatus status) {
    return switch (status) {
      HealthStatus.online => AppColors.statusOnline,
      HealthStatus.offline => AppColors.statusOffline,
      HealthStatus.connecting => AppColors.statusConnecting,
      HealthStatus.expectedOffline => AppColors.statusExpectedOffline,
      HealthStatus.unknown => AppColors.statusUnknown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Health status dot
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _healthColor(instance.healthStatus),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              // Name + URL
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instance.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      instance.gatewayUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
