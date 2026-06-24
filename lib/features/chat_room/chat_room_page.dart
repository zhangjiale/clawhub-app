import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/router/smart_back.dart';
import 'package:claw_hub/app/theme/agent_theme.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/settings/providers/clear_cache_guard.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';
import 'package:claw_hub/features/chat_room/widgets/outbox_warning_banner.dart';
import 'package:claw_hub/features/chat_room/widgets/streaming_bubble.dart';
import 'package:claw_hub/features/chat_room/widgets/thinking_indicator.dart';
import 'package:claw_hub/features/chat_room/widgets/tool_call_card.dart';
import 'package:claw_hub/features/chat_room/widgets/quick_command_bar.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/ui_kit/connection_banner.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/ui_kit/status_banner.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

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
  final String? highlightMessageId;
  final String? highlightQuery;

  const ChatRoomPage({
    super.key,
    required this.agentId,
    required this.instanceId,
    this.source,
    this.highlightMessageId,
    this.highlightQuery,
  });

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  ScrollController? _scrollController;
  // C4: Swipe-back tracking
  bool _swipeFromLeft = false;
  // Cancellable timers — replaced Future.delayed so back navigation
  // immediately releases the State (no closure-captured retention).
  Timer? _retryFeedbackTimer;
  Timer? _highlightFadeTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // C2: Auto-scroll on page open
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _retryFeedbackTimer?.cancel();
    _highlightFadeTimer?.cancel();
    _scrollController?.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController?.hasClients ?? false) {
      _scrollController?.animateTo(
        0,
        duration: const Duration(milliseconds: 60),
        curve: XiaMotion.ease,
      );
    }
  }

  void _handleBack() {
    if (mounted) smartBack(context, source: widget.source);
  }

  /// 用户点击"重连耗尽"横幅的重试入口（US-016 AC-3）。
  ///
  /// 拉取实例后触发手动重连。`orchestrator.reconnect` 内部会重置重连计数器
  /// 并把 FSM 从 reconnectExhausted 终态拉回 connecting/connected，banner 随
  /// connectionState 流的下一帧自动消失。
  ///
  /// 用 ref.read（事件回调，无需重建）；异步 gap 后校验 mounted 防止 dispose
  /// 后调用。orchestrator 自带 2s 防抖，快速连点不会重复建连。
  Future<void> _handleRetry() async {
    final instance = await ref
        .read(instanceRepoProvider)
        .getById(widget.instanceId);
    if (instance != null && mounted) {
      await ref.read(connectionOrchestratorProvider).reconnect(instance);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = (instanceId: widget.instanceId, agentId: widget.agentId);
    // ref.watch triggers rebuild whenever ChatSessionState changes —
    // no manual addListener / setState bridge needed.
    //
    // Major #1 修复: clearAll 进行中 family builder 抛 [ClearedDuringClearError]
    // (由 clearCacheActionProvider 设置的 guard 触发)。捕获取消本次导航，
    // 提示用户并回到上一个 tab。
    final ChatSessionState session;
    try {
      session = ref.watch(chatViewModelProvider(params));
    } on ClearedDuringClearError {
      // 必须转发 source —— 否则 smartBack 在无 back stack 时会落回默认
      // AppRoutes.claws tab，破坏 Smart Back Stack 不变量。对比
      // agent_profile_page.dart:54 的处理（已正确转发）。
      handleClearedDuringClear(context, source: widget.source);
      return const Scaffold(body: SizedBox.shrink());
    }
    // .notifier gives us the ChatViewModel for calling action methods.
    final vm = ref.read(chatViewModelProvider(params).notifier);
    final agent = vm.agent;
    // US-021 AC8: agent 已被 Gateway 删除（tombstoned）时不进入聊天界面 ——
    // 渲染"已移除"占位页并提示，用户点返回离开。agent 为 null（init 未完成）
    // 时跳过，等加载完再判断。与 send() 的 AC9 重查互补：AC8 拦"打开已删除
    // agent"，AC9 拦"停留期间被删"。
    if (agent != null && agent.isRemoved) {
      return Scaffold(
        appBar: AppBar(
          leading: XiaBackButton(onPressed: _handleBack),
          title: const Text('虾已移除'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline, size: 48, color: XiaColors.red),
                const SizedBox(height: 16),
                const Text(
                  '该 Agent 已从 Gateway 移除',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  agent.displayName,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    // 历史同步是否被截断（US-016 AC-2）—— 重连后 catch-up 撞翻页上限时为 true。
    // .select() 限定重建范围：仅当本实例的截断状态变化时才重建此 Widget，
    // 其他实例的 catch-up 完成不会触发无关 ChatRoomPage 重建。
    final historyTruncated = ref.watch(
      catchUpTruncatedProvider.select((s) => s.contains(widget.instanceId)),
    );

    // 预计算 Agent 颜色 — 不再需要（EmojiAvatar 自身处理）

    // C2: Auto-scroll — listen for state changes that should trigger scroll
    ref.listen(chatViewModelProvider(params), (prev, next) {
      void scheduleScroll() {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }

      // Scroll when messages change (after send)
      if (prev?.messages != next.messages) scheduleScroll();
      // Scroll when thinking indicator appears
      if (next.thinkingState == ThinkingState.thinking &&
          prev?.thinkingState != ThinkingState.thinking) {
        scheduleScroll();
      }
      // Scroll when streaming starts
      if (next.streamingText.isNotEmpty &&
          (prev?.streamingText.isEmpty ?? true)) {
        scheduleScroll();
      }
    });

    // Auto-dismiss retryFeedback after 3 seconds so the banner doesn't
    // persist indefinitely. Uses a cancellable Timer so back navigation
    // releases State immediately.
    ref.listen(chatViewModelProvider(params), (prev, next) {
      if (next.retryFeedback != null &&
          prev?.retryFeedback != next.retryFeedback) {
        _retryFeedbackTimer?.cancel();
        _retryFeedbackTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            ref
                .read(chatViewModelProvider(params).notifier)
                .clearRetryFeedback();
          }
        });
      }
    });

    // Apply search-result highlight when messages first load, then auto-fade.
    ref.listen(chatViewModelProvider(params), (prev, next) {
      final highlightId = widget.highlightMessageId;
      final highlightQ = widget.highlightQuery;
      if (highlightId == null || highlightQ == null) return;
      // Only fire once: when messages first transition to LoadData and the
      // highlight hasn't been set yet.
      if (next.messages is LoadData &&
          next.highlightedMessageId != highlightId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(chatViewModelProvider(params).notifier)
              .loadHighlightWindow(highlightId, highlightQ);
          _highlightFadeTimer?.cancel();
          _highlightFadeTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) {
              ref.read(chatViewModelProvider(params).notifier).clearHighlight();
            }
          });
        });
      }
    });

    // Compute agent-themed colors *before* the Theme widget so the AppBar
    // (which is constructed using this build method's context, not a child
    // context) can use the correct values.
    final agentPrimaryColor = agent != null
        ? ColorExtension.fromHex(agent.themeColor)
        : null;
    final agentPrimaryMuted = agentPrimaryColor?.withAlpha(26);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Theme(
        data: theme.copyWith(
          extensions: agentPrimaryColor != null
              ? [
                  ...theme.extensions.values,
                  AgentTheme(primary: agentPrimaryColor),
                ]
              : theme.extensions.values.toList(),
        ),
        child: Scaffold(
          appBar: AppBar(
            backgroundColor:
                agentPrimaryMuted ?? XiaColors.accent.withAlpha(26),
            leading: XiaBackButton(onPressed: _handleBack),
            title: agent != null
                ? PressFeedback(
                    onTap: () {
                      context.push(
                        AppRoutes.agentProfileWithParams(
                          agent.localId,
                          source: widget.source,
                        ),
                      );
                    },
                    builder: (child, isPressed) => AnimatedOpacity(
                      opacity: isPressed ? 0.6 : 1.0,
                      duration: XiaMotion.durationFast,
                      curve: XiaMotion.ease,
                      child: child,
                    ),
                    child: Row(
                      children: [
                        EmojiAvatar(
                          displayName: agent.displayName,
                          themeColor: agent.themeColor,
                          avatarImage: agent.avatarUrl != null
                              ? FileImage(File(agent.avatarUrl!))
                              : null,
                          radius: 20, // 40×40
                          borderRadius: XiaRadius.sm,
                          fontSize: 18,
                        ),
                        const SizedBox(width: XiaSpacing.s3),
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
                Padding(
                  padding: const EdgeInsets.only(right: XiaSpacing.s2),
                  child: HeaderButton(
                    icon: Icons.more_vert,
                    onPressed: () {
                      context.push(
                        AppRoutes.agentProfileWithParams(
                          agent.localId,
                          source: widget.source,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          body: GestureDetector(
            // C4: Swipe-back — right swipe >80px from left edge <40px
            onHorizontalDragStart: (details) {
              if (details.localPosition.dx < 40) _swipeFromLeft = true;
            },
            onHorizontalDragEnd: (details) {
              if (_swipeFromLeft &&
                  details.primaryVelocity != null &&
                  details.primaryVelocity! > 800) {
                _handleBack();
              }
              _swipeFromLeft = false;
            },
            onHorizontalDragCancel: () => _swipeFromLeft = false,
            child: Column(
              children: [
                // Outbox warning banner (US-015 AC3) — 排在 ConnectionBanner 之上，
                // 因为 outbox 堆积可能与连接异常并发出现，警告条更紧急。
                OutboxWarningBanner(outboxCount: session.outboxCount),

                // Disconnect / connecting banner
                ConnectionBanner(
                  connectionState: session.connectionState,
                  onRetry: _handleRetry,
                ),

                // History-sync truncation banner (US-016 AC-2) — catch-up
                // 撞翻页上限时展示，提示用户更早历史未同步。
                if (historyTruncated)
                  const StatusBanner(
                    message: '历史消息较多，仅同步了最近部分',
                    foregroundColor: XiaColors.accent,
                    backgroundColor: XiaColors.accentMuted,
                    icon: Icons.history,
                  ),

                // Retry feedback banner (US-015 AC2) — shown when retryMessage
                // skips due to preconditions (offline, agent deleted, etc.).
                // Auto-dismissed after 3 seconds by the listener below.
                if (session.retryFeedback != null)
                  StatusBanner(
                    message: session.retryFeedback!,
                    foregroundColor: XiaColors.accent,
                    backgroundColor: XiaColors.accentMuted,
                    icon: Icons.error_outline,
                  ),

                // Timeout banner
                if (session.thinkingState == ThinkingState.timeout)
                  MaterialBanner(
                    content: const Text('虾思考时间较长，可能正在处理复杂任务。'),
                    backgroundColor: AppColors.statusConnecting.withAlpha(26),
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
                    LoadError(:final error) => LoadErrorView(
                      error: error,
                      title: 'Failed to load messages',
                      onRetry: () => vm.retry(),
                    ),
                    LoadData(:final value) when value.isEmpty =>
                      _buildEmptyState(theme),
                    LoadData(:final value) => _buildMessageList(
                      value,
                      session.toolCalls,
                      agent?.displayName ?? 'Agent',
                      theme,
                      session.highlightedMessageId,
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
          ), // GestureDetector (C4 swipe)
        ), // Scaffold
      ), // Theme
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
      GatewayConnectionState.authFailed ||
      GatewayConnectionState.reconnectExhausted => AppColors.statusOffline,
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
          const SizedBox(height: XiaSpacing.s3),
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
    String? highlightedMessageId,
  ) {
    final params = (instanceId: widget.instanceId, agentId: widget.agentId);
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: XiaSpacing.s2),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final tc = toolCalls[message.clientId];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MessageBubble(
              message: message,
              agentName: agentName,
              index: index,
              isHighlighted: highlightedMessageId == message.clientId,
              onRetry: message.status == MessageStatus.failed
                  ? () => ref
                        .read(chatViewModelProvider(params).notifier)
                        .retryMessage(message.clientId)
                  : null,
            ),
            if (tc != null) ToolCallCard(toolCall: tc),
          ],
        );
      },
    );
  }
}
