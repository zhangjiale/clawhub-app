import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/enums.dart';

/// 工具调用卡片
/// 显示在消息流中，展示 Agent 调用的工具名称、状态和结果
class ToolCallCard extends StatelessWidget {
  final ToolCall toolCall;

  const ToolCallCard({super.key, required this.toolCall});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 36), // Align with agent message avatar offset
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _statusColor.withAlpha(80),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status icon
                  _buildStatusIcon(),
                  const SizedBox(width: 10),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tool name
                        Text(
                          toolCall.toolName,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Status text
                        Text(
                          _statusText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _statusColor,
                          ),
                        ),
                        // Output summary (when completed)
                        if (toolCall.isCompleted &&
                            toolCall.outputResult != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _truncateOutput(toolCall.outputResult!, 120),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    return switch (toolCall.status) {
      ToolCallStatus.pending || ToolCallStatus.running => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.statusConnecting,
          ),
        ),
      ToolCallStatus.success => const Icon(
          Icons.check_circle,
          size: 20,
          color: AppColors.statusOnline,
        ),
      ToolCallStatus.failed => const Icon(
          Icons.error,
          size: 20,
          color: AppColors.statusOffline,
        ),
    };
  }

  Color get _statusColor {
    return switch (toolCall.status) {
      ToolCallStatus.pending || ToolCallStatus.running => AppColors.statusConnecting,
      ToolCallStatus.success => AppColors.statusOnline,
      ToolCallStatus.failed => AppColors.statusOffline,
    };
  }

  String get _statusText {
    return switch (toolCall.status) {
      ToolCallStatus.pending => 'Pending...',
      ToolCallStatus.running => 'Running...',
      ToolCallStatus.success => '✅ Completed',
      ToolCallStatus.failed => '❌ Failed',
    };
  }

  String _truncateOutput(String output, int maxLen) {
    if (output.length <= maxLen) return output;
    return '${output.substring(0, maxLen)}...';
  }
}
