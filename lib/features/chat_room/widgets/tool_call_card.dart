import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/enums.dart';

/// Tool call card — matching V2 ComponentSpec Section 4.2.3.
///
/// V2: 2px accent2 (violet) left border, surface bg, 8px radius.
class ToolCallCard extends StatelessWidget {
  final ToolCall toolCall;

  const ToolCallCard({super.key, required this.toolCall});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.pagePaddingH,
        vertical: 4,
      ),
      child: Row(
        children: [
          const SizedBox(width: 36),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: XiaSpacing.s4,
                vertical: XiaSpacing.s3,
              ),
              decoration: BoxDecoration(
                color: XiaColors.surface,
                borderRadius: BorderRadius.circular(XiaRadius.md),
                border: const Border(
                  left: BorderSide(color: XiaColors.accent2, width: 2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusIcon(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          toolCall.toolName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: XiaColors.accent2,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: XiaSpacing.s1),
                        Text(
                          _statusText,
                          style: const TextStyle(
                            color: XiaColors.green,
                            fontSize: 11,
                          ),
                        ),
                        if (toolCall.isCompleted &&
                            toolCall.outputResult != null) ...[
                          const SizedBox(height: XiaSpacing.s2),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(XiaSpacing.s2),
                            decoration: BoxDecoration(
                              color: XiaColors.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _truncateOutput(toolCall.outputResult!, 120),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: XiaColors.text1,
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
          color: XiaColors.yellow,
        ),
      ),
      ToolCallStatus.success => const Icon(
        Icons.check_circle,
        size: 20,
        color: XiaColors.green,
      ),
      ToolCallStatus.failed => const Icon(
        Icons.error,
        size: 20,
        color: XiaColors.red,
      ),
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
