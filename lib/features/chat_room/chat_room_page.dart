import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';
import 'package:claw_hub/features/chat_room/widgets/streaming_bubble.dart';
import 'package:claw_hub/features/chat_room/widgets/thinking_indicator.dart';
import 'package:claw_hub/features/chat_room/widgets/tool_call_card.dart';
import 'package:claw_hub/features/chat_room/widgets/quick_command_bar.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/ui_kit/connection_banner.dart';

/// 聊天页 (P0 MVP Phase 5)
/// 消息列表 + 输入栏 + 实时消息接收 + Markdown 渲染 + 状态反馈
///
/// Thin UI layer — all orchestration lives in [ChatViewModel].
///
/// Smart Back (US-011): Uses [source] to ensure the back button returns to the
/// correct origin tab. When [source] is 'claws', back returns to Claws tab;
/// when 'messages', back returns to Messages tab.
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

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  /// Smart back navigation (US-011).
  ///
  /// Pops from the current branch navigator if possible. Falls back to
  /// switching to the source tab using `StatefulShellRoute` branch index.
  void _handleBack() {
    if (mounted && context.canPop()) {
      context.pop();
    } else if (mounted) {
      // Fallback: navigate to source tab root
      final source = widget.source;
      if (source == 'messages') {
        context.go(AppRoutes.messages);
      } else {
        // Default and 'claws' both go to claws tab
        context.go(AppRoutes.claws);
      }
    }
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = (instanceId: widget.instanceId, agentId: widget.agentId);
    // ref.watch triggers rebuild whenever ChatSessionState changes —
    // no manual addListener / setState bridge needed.
    final session = ref.watch(chatViewModelProvider(params));
    // .notifier gives us the ChatViewModel for calling action methods.
    final vm = ref.read(chatViewModelProvider(params).notifier);
    final agent = vm.agent;

    // 预计算 Agent 颜色
    final agentColor = agent != null
        ? ColorExtension.fromHex(agent.themeColor)
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          title: agent != null
              ? GestureDetector(
                  onTap: () {
                    // Navigate to agent profile
                    context.push(
                      AppRoutes.agentProfileWithParams(
                        agent.localId,
                        source: widget.source,
                      ),
                    );
                  },
                  child: Row(
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
                                // Connection status dot
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _connectionDotColor(
                                      session.connectionState,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
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
                  ),
                )
              : const Text('Chat'),
          actions: [
            if (agent != null)
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  context.push(
                    AppRoutes.agentProfileWithParams(
                      agent.localId,
                      source: widget.source,
                    ),
                  );
                },
              ),
          ],
        ),
        body: Column(
          children: [
            // Disconnect / connecting banner
            ConnectionBanner(connectionState: session.connectionState),

            // Timeout banner
            if (session.thinkingState == ThinkingState.timeout)
              MaterialBanner(
                content: const Text('虾思考时间较长，可能正在处理复杂任务。'),
                backgroundColor: AppColors.statusConnecting.withAlpha(30),
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
              ),

            // Message list
            Expanded(
              child: switch (session.messages) {
                LoadInProgress() => const LoadingSkeleton(count: 3),
                LoadError(:final error) => Center(
                  child: Text('Failed to load messages: $error'),
                ),
                LoadData(:final value) when value.isEmpty => _buildEmptyState(
                  theme,
                ),
                LoadData(:final value) => _buildMessageList(
                  value,
                  session.toolCalls,
                  agent?.displayName ?? 'Agent',
                  theme,
                ),
              },
            ),

            // Streaming bubble — show live text as it arrives
            if (session.streamingText.isNotEmpty)
              StreamingBubble(
                text: session.streamingText,
                agentName: agent?.displayName ?? 'Agent',
              )
            // Thinking indicator — show dots while waiting for first text
            else if (session.thinkingState == ThinkingState.thinking)
              const ThinkingIndicator(),

            // Quick command bar
            if (agent != null && agent.quickCommands.isNotEmpty)
              QuickCommandBar(
                commands: agent.quickCommands,
                onCommandTap: (payload) => vm.send(payload),
              ),

            ChatInputBar(onSend: (text) => vm.send(text)),
          ],
        ),
      ), // Scaffold
    ); // PopScope
  }

  Color _connectionDotColor(GatewayConnectionState state) {
    return switch (state) {
      GatewayConnectionState.connected => AppColors.statusOnline,
      GatewayConnectionState.connecting ||
      GatewayConnectionState.authenticating ||
      GatewayConnectionState.recovering ||
      GatewayConnectionState.pairingRequired => AppColors.statusConnecting,
      GatewayConnectionState.disconnected ||
      GatewayConnectionState.authFailed => AppColors.statusOffline,
    };
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
    Map<String, ToolCall> toolCalls,
    String agentName,
    ThemeData theme,
  ) {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final tc = toolCalls[message.clientId];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MessageBubble(message: message, agentName: agentName),
            if (tc != null) ToolCallCard(toolCall: tc),
          ],
        );
      },
    );
  }
}
