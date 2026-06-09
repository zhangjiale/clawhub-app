import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';
import 'package:claw_hub/features/chat_room/widgets/thinking_indicator.dart';
import 'package:claw_hub/features/chat_room/widgets/tool_call_card.dart';
import 'package:claw_hub/features/chat_room/widgets/quick_command_bar.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/async_state.dart';

/// 聊天页 (P0 MVP Phase 5)
/// 消息列表 + 输入栏 + 实时消息接收 + Markdown 渲染 + 状态反馈
///
/// Thin UI layer — all orchestration lives in [ChatViewModel].
class ChatRoomPage extends ConsumerStatefulWidget {
  final String agentId;
  final String instanceId;
  final String? source;

  const ChatRoomPage({
    super.key,
    required this.agentId,
    required this.instanceId,
    this.source,
  });

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  ScrollController? _scrollController;
  ChatViewModel? _vm;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _vm = ref.read(chatViewModelProvider((
      instanceId: widget.instanceId,
      agentId: widget.agentId,
    )));
    _vm!.addListener(_onVmChanged);
  }

  void _onVmChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm?.removeListener(_onVmChanged);
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = _vm!;
    final agent = vm.agent;

    // 预计算 Agent 颜色
    final agentColor = agent != null
        ? ColorExtension.fromHex(agent.themeColor)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: agent != null
            ? Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: agentColor,
                    foregroundColor: agentColor!.contrastingTextColor(),
                    child: Text(
                      agent.displayName.characters.first,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                agent.displayName,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Connection status dots
                            ValueListenableBuilder<GatewayConnectionState>(
                              valueListenable: vm.connectionStateNotifier,
                              builder: (context, connState, _) {
                                return Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _connectionDotColor(connState),
                                    shape: BoxShape.circle,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        if (agent.description != null)
                          Text(
                            agent.description!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              )
            : const Text('Chat'),
      ),
      body: Column(
        children: [
          // Disconnect banner
          ValueListenableBuilder<GatewayConnectionState>(
            valueListenable: vm.connectionStateNotifier,
            builder: (context, connState, _) {
              if (connState == GatewayConnectionState.disconnected ||
                  connState == GatewayConnectionState.authFailed) {
                return _buildBanner(
                  theme,
                  '连接已断开，正在重连...',
                  AppColors.statusOffline,
                  Icons.wifi_off,
                );
              }
              if (connState == GatewayConnectionState.connecting ||
                  connState == GatewayConnectionState.recovering) {
                return _buildBanner(
                  theme,
                  '正在连接...',
                  AppColors.statusConnecting,
                  Icons.sync,
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // Timeout banner
          ValueListenableBuilder<bool>(
            valueListenable: vm.timeoutNotifier,
            builder: (context, isTimedOut, _) {
              if (!isTimedOut) return const SizedBox.shrink();
              return MaterialBanner(
                content: const Text('虾思考时间较长，可能正在处理复杂任务。'),
                backgroundColor:
                    AppColors.statusConnecting.withAlpha(30),
                leading: const Icon(
                  Icons.hourglass_top,
                  color: AppColors.statusConnecting,
                ),
                actions: [
                  TextButton(
                    onPressed: () => vm.dismissTimeout(),
                    child: const Text('取消等待'),
                  ),
                  TextButton(
                    onPressed: () => vm.continueWaiting(),
                    child: const Text('继续等待'),
                  ),
                ],
              );
            },
          ),

          // Message list
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: vm.messagesNotifier,
              builder: (context, state, _) => switch (state) {
                LoadInProgress() => const LoadingSkeleton(count: 3),
                LoadError(:final error) =>
                  Center(child: Text('Failed to load messages: $error')),
                LoadData(:final value) when value.isEmpty =>
                  _buildEmptyState(theme),
                LoadData(:final value) =>
                  _buildMessageList(
                    value, vm, agent?.displayName ?? 'Agent', theme),
              },
            ),
          ),

          // Thinking indicator (when waiting for agent reply)
          ValueListenableBuilder<bool>(
            valueListenable: vm.isThinkingNotifier,
            builder: (context, isThinking, _) {
              if (!isThinking) return const SizedBox.shrink();
              return const ThinkingIndicator();
            },
          ),

          // Quick command bar
          if (agent != null && agent!.quickCommands.isNotEmpty)
            QuickCommandBar(
              commands: agent!.quickCommands,
              onCommandTap: (payload) => vm.send(payload),
            ),

          ChatInputBar(onSend: (text) => vm.send(text)),
        ],
      ),
    );
  }

  Color _connectionDotColor(GatewayConnectionState state) {
    return switch (state) {
      GatewayConnectionState.connected => AppColors.statusOnline,
      GatewayConnectionState.connecting ||
      GatewayConnectionState.authenticating ||
      GatewayConnectionState.recovering =>
        AppColors.statusConnecting,
      GatewayConnectionState.disconnected ||
      GatewayConnectionState.authFailed =>
        AppColors.statusOffline,
    };
  }

  Widget _buildBanner(
    ThemeData theme,
    String message,
    Color color,
    IconData icon,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withAlpha(25),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Send a message to start',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    List<Message> messages,
    ChatViewModel vm,
    String agentName,
    ThemeData theme,
  ) {
    return ValueListenableBuilder<Map<String, ToolCall>>(
      valueListenable: vm.toolCallsNotifier,
      builder: (context, toolCalls, _) {
        // Build interleaved list: messages + tool call cards
        final items = <Widget>[];
        for (final message in messages) {
          items.add(
            MessageBubble(message: message, agentName: agentName),
          );
          // Show tool call card if this message has one
          final tc = toolCalls[message.clientId];
          if (tc != null) {
            items.add(ToolCallCard(toolCall: tc));
          }
        }

        return ListView(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: items,
        );
      },
    );
  }
}
