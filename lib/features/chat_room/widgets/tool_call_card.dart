import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';

/// Tool call card — matching V2 ComponentSpec Section 4.2.3.
///
/// V2: 2px accent2 (violet) left border, surface bg, 8px radius.
class ToolCallCard extends StatefulWidget {
  final ToolCall toolCall;

  const ToolCallCard({super.key, required this.toolCall});

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(ToolCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 输出从长变短时重置展开状态,否则用户失去折叠入口。
    final wasLong = (oldWidget.toolCall.outputResult ?? '').length > 120;
    final isLong = (widget.toolCall.outputResult ?? '').length > 120;
    if (wasLong && !isLong) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = widget.toolCall;
    final hasOutput = tc.isCompleted && tc.outputResult != null;
    final output = tc.outputResult ?? '';
    final isLong = output.length > 120;
    // 折叠时截断到 120 字符(3 行);展开时显示完整输出。
    final display = !_expanded && isLong
        ? '${output.substring(0, 120)}...'
        : output;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.pagePaddingH,
        vertical: 4,
      ),
      // 卡片左边缘对齐 agent 气泡左边缘(都在 pagePaddingH)——外层 Row 的
      // mainAxisSize.max + mainAxisAlignment.start 让卡左对齐,同时占满行宽
      // 防止父 Column(crossAxisAlignment.center 默认)把窄卡居中。历史上这里
      // 有个 SizedBox(width:36) 想对齐头像缩进,但 MessageBubble 早就没有头像了,
      // 那个 36px 把卡顶到屏幕中间(用户投诉"exec 卡显示在中间")。
      child: Row(
        children: [
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
                          tc.toolName,
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
                        if (hasOutput) ...[
                          const SizedBox(height: XiaSpacing.s2),
                          GestureDetector(
                            onTap: isLong
                                ? () => setState(() => _expanded = !_expanded)
                                : null,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(XiaSpacing.s2),
                              decoration: BoxDecoration(
                                color: XiaColors.surface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    display,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: XiaColors.text1,
                                    ),
                                    maxLines: _expanded ? null : 3,
                                    overflow: _expanded
                                        ? TextOverflow.visible
                                        : TextOverflow.ellipsis,
                                  ),
                                  if (isLong) ...[
                                    const SizedBox(height: XiaSpacing.s1),
                                    Text(
                                      _expanded ? '收起 ▲' : '展开全部 ▼',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: XiaColors.accent2,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
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
    return switch (widget.toolCall.status) {
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
    return switch (widget.toolCall.status) {
      ToolCallStatus.pending => 'Pending...',
      ToolCallStatus.running => 'Running...',
      ToolCallStatus.success => '✅ Completed',
      ToolCallStatus.failed => '❌ Failed',
    };
  }
}

/// 从历史 toolResult [Message] 构造 [ToolCall],让历史路径复用 [ToolCallCard]
/// 渲染(与实时 toolCallStream → ToolCall → ToolCallCard 路径合流,避免两套
/// widget 长得不一致 —— 之前历史用 _buildToolResult 折叠卡,没对号/Completed)。
/// toolName / isError 来自 parseMessage 提取的顶层字段(metadata.toolName /
/// metadata.isError);outputResult 取 message.content。
ToolCall toolCallFromMessage(Message m) {
  final isError = m.metadata?['isError'] == true;
  return ToolCall(
    id: m.serverId ?? m.clientId,
    messageId: m.clientId,
    toolName: m.metadata?['toolName']?.toString() ?? 'tool',
    status: isError ? ToolCallStatus.failed : ToolCallStatus.success,
    outputResult: m.content,
    endedAt: m.timestamp,
  );
}

/// 把历史 toolResult 消息按 logicalClock 排序后,挂到它**后面第一条 agent
/// 回复**名下 —— 这样 toolResult 会渲染在 agent 气泡下面(和实时路径一致),
/// 而不是按时间戳卡在 user 和 agent 之间,也不会误挂到 userPlaceholder 或
/// system 消息上。
///
/// 返回 `(byOwner, ownedIds)`:
/// - `byOwner`: owner 的 clientId → 挂到它名下的 toolResult 列表(按时间顺序)。
/// - `ownedIds`: 被认领的 toolResult clientId 集合(这些不独立渲染)。
/// 没找到 owner 的 toolResult(会话最后一条)不在 ownedIds 里 → 退回独立行渲染。
({Map<String, List<Message>> byOwner, Set<String> ownedIds})
groupToolResultsByOwner(List<Message> messages) {
  final sorted = [...messages]
    ..sort((a, b) => a.logicalClock.compareTo(b.logicalClock));
  final byOwner = <String, List<Message>>{};
  final ownedIds = <String>{};
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i].role != MessageRole.toolResult) continue;
    for (var j = i + 1; j < sorted.length; j++) {
      // 只挂到 agent 回复名下;userPlaceholder/system/user 都不应拥有工具卡。
      if (sorted[j].role == MessageRole.agent) {
        byOwner.putIfAbsent(sorted[j].clientId, () => []).add(sorted[i]);
        ownedIds.add(sorted[i].clientId);
        break;
      }
    }
  }
  return (byOwner: byOwner, ownedIds: ownedIds);
}
