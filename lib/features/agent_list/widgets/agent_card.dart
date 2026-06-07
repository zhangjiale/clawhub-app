import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Agent 卡片组件
/// 对齐: InstanceCard 模式，显示头像圆、名称、描述、置顶状态
class AgentCard extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;

  const AgentCard({
    super.key,
    required this.agent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ColorExtension.fromHex(agent.themeColor);
    final firstChar = agent.displayName.characters.first;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar circle with theme color
              CircleAvatar(
                backgroundColor: color,
                foregroundColor: color.contrastingTextColor(),
                child: Text(
                  firstChar,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            agent.displayName,
                            style: theme.textTheme.titleMedium,
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
