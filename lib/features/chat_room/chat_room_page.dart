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
import 'package:claw_hub/core/utils/gateway_media_url.dart';
import 'package:claw_hub/core/i_attachment_picker_service.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/attachment_pick_result.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/settings/providers/clear_cache_guard.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';
import 'package:claw_hub/features/chat_room/widgets/attachment_sheet.dart';
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
import 'package:claw_hub/ui_kit/placeholders/agent_removed_placeholder.dart';
import 'package:claw_hub/ui_kit/toast.dart';

/// 把一条 Gateway 诊断事件格式化为用户可见的 toast 文案。
///
/// 顶层纯函数（非 widget 方法）以便单元测试直接断言文案契约——
/// 锁住视觉契约（含 size/limit 字节数），不依赖 golden 基建。
///
/// sealed union 穷尽：未来新增 `RateLimitNotice` / `QuotaExceededNotice`
/// 等子类型时，编译器强制在此 switch 补分支（缺即编译错），避免漏处理。
String formatGatewayNotice(GatewayNotice notice) => switch (notice) {
  LargePayloadNotice(:final size, :final limit) =>
    '消息过大被网关拒收（$size / $limit 字节），请缩短内容后重试',
  // F-4: 在途缓冲满是瞬态、不可由用户缓解（等在途请求收完即恢复），
  // 故文案只定性 + 安抚「自动重试」，不暴露 buffered/attempted/max 字节
  // 数（用户看不懂也无从操作）。消息本身已被 SendMessageUseCase 标
  // FAILED，OutboxProcessor 会在缓冲排空后自动重发 —— 不丢数据。
  BufferOverflowNotice() => '网关繁忙，消息未能发送，将自动重试',
};

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

  // Review #14: 搜索高亮只在消息首载时应用一次。clearHighlight() 把
  // highlightedMessageId 置 null 后 ref.listen 会再次触发（null != highlightId），
  // 旧逻辑会无限重新应用高亮 → 渐隐计时器永远重置，高亮永不消失。该标志在
  // 首次应用后置 true，阻止 clearHighlight 的状态变化重新触发 loadHighlightWindow。
  bool _didApplyHighlight = false;

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
    if (instance == null) {
      // 实例在用户进入 chat 后被删除（race：删除按钮和重试按钮几乎同时按下）。
      // 之前静默无反应，让用户以为按钮死了 / 应用卡了。
      // 现在打日志 + 弹 toast，让用户知道实例已不存在并返回。
      debugPrint(
        '[ChatRoom] retry tap no-op: instance ${widget.instanceId} not found',
      );
      if (mounted) {
        // Toast 跨 frame 安全：在 build 期间不能 push 新路由/SnackBar，
        // 但 XiaToast 自身有 addPostFrameCallback 包裹，这里直接调用即可。
        XiaToast.show(context, '实例不存在或已被删除');
      }
      return;
    }
    if (!mounted) return;
    await ref.read(connectionOrchestratorProvider).reconnect(instance);
  }

  /// "+" 附件入口：相册/拍照用 [IAttachmentPickerService.pickImage]，
  /// 文件用 [IAttachmentPickerService.pickFile]。
  ///
  /// 选到文件后调 [ChatViewModel.sendImage]/[ChatViewModel.sendFile]，
  /// metadata 含 fileName/mimeType/size。字节读取与 base64 由 ACL 在发送时完成。
  ///
  /// 平台调用下沉到 [IAttachmentPickerService]（Law 2：widget 只渲染 UI）。
  /// 异步 gap 后校验 mounted；用户取消（pick 返回 null）静默忽略。
  ///
  /// 选择/读取失败统一以 `on Exception` 捕获并 toast——覆盖三类原本会逃逸为
  /// 未处理异步异常的失败（'+' 按钮无反馈）：
  /// - PlatformException：相机权限拒绝 / file_picker 平台错误（review #10）
  /// - FileSystemException：iOS 沙盒回收临时文件 / Android 13+ 撤销 SAF URI，
  ///   `File.length()` 在 pick 返回后抛出（#11）
  /// - MissingPluginException：Proguard 裁剪的 Android 变体 / web 回退，
  ///   `image_picker`/`file_picker` 找不到平台实现（#12）
  ///
  /// 用 `on Exception` 而非逐类型 catch：三者都实现 Exception，widget 无需
  /// 按平台类型分支——统一 toast + 日志即可。Error 子类（OutOfMemoryError 等）
  /// 不被捕获，继续上抛。
  Future<void> _handlePickAttachment(
    AttachmentKind kind,
    ChatViewModel vm,
    IAttachmentPickerService pickerService,
  ) async {
    AttachmentPickResult? result;
    try {
      if (kind == AttachmentKind.file) {
        result = await pickerService.pickFile();
      } else {
        final source = kind == AttachmentKind.camera
            ? ImageSource.camera
            : ImageSource.gallery;
        result = await pickerService.pickImage(source: source);
      }
    } on Exception catch (e) {
      debugPrint('[ChatRoom] attachment pick failed: $e');
      if (mounted) {
        XiaToast.show(context, '无法选择附件，请检查权限或重试');
      }
      return;
    }
    if (result == null) return; // 用户取消
    if (!mounted) return;
    final Map<String, dynamic> metadata = {
      'fileName': result.fileName,
      'mimeType': result.mimeType,
      'size': result.size,
    };
    if (kind == AttachmentKind.file) {
      await vm.sendFile(result.path, metadata: metadata);
    } else {
      await vm.sendImage(result.path, metadata: metadata);
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
    // US-021 AC8: agent 已被 Gateway 删除（tombstoned）时不进入聊天界面。
    // Step 3: 直接读 vm.agent.isRemoved —— 不再依赖 session 的 tombstone 标志字段
    // 字段。看似绕过 ref.watch，但 [_setAgent] 会同步 bump
    // session.contentRevision，state 变化经 ref.watch 触发本 build 重建，
    // build() 中 vm.agent getter 拿到的是最新 _agent（含最新 isRemoved）。
    // US-021 v1.2: 迁移到 AgentRemovedPlaceholder widget，与 AgentProfilePage /
    // AgentConfigPage 共用同一份占位页（避免三处文案/样式 drift）。
    if (agent.isTombstoned) {
      return AgentRemovedPlaceholder(
        agentName: agent?.displayName,
        source: widget.source,
        onBack: _handleBack,
      );
    }
    // 历史同步是否被截断（US-016 AC-2）—— 重连后 catch-up 撞翻页上限时为 true。
    // .select() 限定重建范围：仅当本实例的截断状态变化时才重建此 Widget，
    // 其他实例的 catch-up 完成不会触发无关 ChatRoomPage 重建。
    final historyTruncated = ref.watch(
      catchUpTruncatedProvider.select((s) => s.contains(widget.instanceId)),
    );

    // #1: Gateway HTTP base URL + device token — resolves Agent reply images
    // (relative /api/chat/media/outgoing/... URLs) to authenticated absolute
    // URLs. null while the FutureProvider loads (instance/token from secure
    // storage); the page rebuilds to AsyncData once resolved.
    final mediaAuth = ref
        .watch(gatewayMediaAuthProvider(widget.instanceId))
        .valueOrNull;

    // 预计算 Agent 颜色 — 不再需要（EmojiAvatar 自身处理）

    // C2: Auto-scroll, retry-feedback timer, tombstone back navigation,
    // and search-result highlight — all driven by a single listen on
    // [chatViewModelProvider] to avoid registering multiple callbacks for the
    // same state stream.
    ref.listen(chatViewModelProvider(params), (prev, next) {
      final notifier = ref.read(chatViewModelProvider(params).notifier);

      void scheduleScroll() {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }

      // 1. Auto-scroll
      if (prev?.messages != next.messages) scheduleScroll();
      if (next.thinkingState == ThinkingState.thinking &&
          prev?.thinkingState != ThinkingState.thinking) {
        scheduleScroll();
      }
      if (next.streamingText.isNotEmpty &&
          (prev?.streamingText.isEmpty ?? true)) {
        scheduleScroll();
      }

      // 2. Auto-dismiss retryFeedback after 3 seconds.
      if (next.retryFeedback != null &&
          prev?.retryFeedback != next.retryFeedback) {
        _retryFeedbackTimer?.cancel();
        _retryFeedbackTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) notifier.clearRetryFeedback();
        });
      }

      // 3. US-021 AC9: tombstoned agent -> pop page.
      if (next.closeRequested && prev?.closeRequested != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleBack();
        });
      }

      // 4. Apply search-result highlight when messages first load.
      final highlightId = widget.highlightMessageId;
      final highlightQ = widget.highlightQuery;
      if (highlightId != null &&
          highlightQ != null &&
          !_didApplyHighlight &&
          next.messages is LoadData &&
          next.highlightedMessageId != highlightId) {
        // 标记已应用：clearHighlight() 之后 highlightedMessageId 变 null，
        // 本条件会再次成立（null != highlightId），若无此标志会无限重新应用。
        _didApplyHighlight = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          notifier.loadHighlightWindow(highlightId, highlightQ);
          _highlightFadeTimer?.cancel();
          _highlightFadeTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) notifier.clearHighlight();
          });
        });
      }
    });

    // Finding #9 修复: Gateway 诊断事件改走单独的 gatewayNoticeProvider
    // (StreamProvider.family<GatewayNotice, String>),不经 ChatSessionState
    // ——之前 gatewayNoticeSeq / lastGatewayNotice 字段被刻意排除在
    // ChatSessionState.== 之外,导致 StateNotifier.state setter 去重
    // (copyWith 后新 state == 旧 state) -> 不 emit stateChanges ->
    // Riverpod 不感知 -> ref.listen(.select((s)=>(seq,notice))) callback
    // 永不触发 -> toast 永不显示(生产 bug:用户发超大消息/网关缓冲满时无提示)。
    //
    // gatewayNoticeProvider 直接订阅 gatewayClient.gatewayNoticeStream,
    // emit notice -> AsyncData(notice) -> 本 ref.listen callback 触发 ->
    // formatGatewayNotice 派生文案 -> XiaToast.show。
    //
    // post-frame 回调避免在 build() 阶段调 Overlay.of(context);同一 notice
    // 再次进入 build 时(StreamProvider 状态未变)不会重复触发。
    ref.listen<AsyncValue<GatewayNotice>>(
      gatewayNoticeProvider(widget.instanceId),
      (prev, next) {
        final notice = next.value;
        final prevNotice = prev?.value;
        if (notice != null && notice != prevNotice) {
          final message = formatGatewayNotice(notice);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              XiaToast.show(context, message);
            }
          });
        }
      },
    );

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
                      // US-021: agent may become null after a hard-delete while
                      // messages are still LoadData (watchById sets _agent=null
                      // but does not reset the message list). Keep the safe
                      // fallback instead of `agent!`, which threw
                      // NullCheckFailureError in that race.
                      agent?.displayName ?? 'Agent',
                      theme,
                      session.highlightedMessageId,
                      mediaAuth,
                    ),
                  },
                ),

                // Streaming bubble — show live text as it arrives
                if (session.streamingText.isNotEmpty)
                  StreamingBubble(
                    text: session.streamingText,
                    // Same null-safety guard as the message list: streaming
                    // text can outlive the agent when it is hard-deleted.
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

                ChatInputBar(
                  onSend: (text) => vm.send(text),
                  onPickAttachment: (kind) => _handlePickAttachment(
                    kind,
                    vm,
                    ref.read(attachmentPickerServiceProvider),
                  ),
                ),
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
    GatewayMediaAuth? mediaAuth,
  ) {
    final params = (instanceId: widget.instanceId, agentId: widget.agentId);

    // 历史 toolResult 消息挂到它**前一条** user 消息(该 turn 的触发者)
    // 下面渲染 —— exec 卡片紧跟 user 气泡,在 user 和 agent 之间(和实时路
    // 径一致:实时路径在 ChatViewModel._sendCore 把 sessionKey→userClientId
    // 映射写进 VM,ToolCall listener 直接 self-key 到 user 消息)。没 owner
    // 的 toolResult(会话最早一条)退回独立行渲染。
    final grouped = groupToolResultsByOwner(messages);
    final toolResultsByOwner = grouped.byOwner;
    final ownedToolResultIds = grouped.ownedIds;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: XiaSpacing.s2),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        // 被 owner 认领的 toolResult → 不独立渲染(在 owner 气泡下渲染)。
        if (message.role == MessageRole.toolResult &&
            ownedToolResultIds.contains(message.clientId)) {
          return const SizedBox.shrink();
        }
        // 孤儿 toolResult(后面没有非 toolResult 消息)→ 独立渲染。
        if (message.role == MessageRole.toolResult) {
          // 优先用 live ToolCall(按 toolCallId 取),保留 running 态;无 live
          // 则用历史 toolResult 重建。归别的消息所有的 live 卡跳过避免重复。
          final toolCallId = message.metadata?['toolCallId'] as String?;
          final live = toolCallId != null ? toolCalls[toolCallId] : null;
          if (live != null) {
            // live 卡归本消息所有 -> 在此渲染(保留 running 态)。
            // 否则它已挂在别的消息(如 agent 回复)下,跳过避免重复。
            if (live.messageId == message.clientId) {
              return ToolCallCard(toolCall: live);
            }
            return const SizedBox.shrink();
          }
          return ToolCallCard(toolCall: toolCallFromMessage(message));
        }
        // live ToolCalls 归本消息所有(按 messageId == message.clientId 过滤)。
        // 一个 turn 可含多个工具调用 -> 全部渲染,与重载路径
        // groupToolResultsByOwner 的 1:N 基数对齐(修「实时 1 张、重启多张」)。
        final liveTools = toolCalls.values
            .where((tc) => tc.messageId == message.clientId)
            .toList();
        final historyTools = (toolResultsByOwner[message.clientId] ?? const [])
            // 同 toolCallId 的 live 卡已存在时,跳过历史卡,避免与 live 卡
            // 重复渲染。toolCalls 现以 toolCallId 为 key,直接 containsKey。
            .where(
              (ht) =>
                  !(ht.metadata?['toolCallId'] is String &&
                      toolCalls.containsKey(ht.metadata!['toolCallId'])),
            )
            .toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MessageBubble(
              message: message,
              agentName: agentName,
              index: index,
              isHighlighted: highlightedMessageId == message.clientId,
              mediaAuth: mediaAuth,
              onRetry: message.status == MessageStatus.failed
                  ? () => ref
                        .read(chatViewModelProvider(params).notifier)
                        .retryMessage(message.clientId)
                  : null,
            ),
            for (final tc in liveTools) ToolCallCard(toolCall: tc),
            for (final ht in historyTools)
              ToolCallCard(toolCall: toolCallFromMessage(ht)),
          ],
        );
      },
    );
  }
}
