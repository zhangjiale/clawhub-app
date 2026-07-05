import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/utils/copy_with_nullable.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/domain/usecases/merge_inbound_message.dart';
import 'package:claw_hub/features/_shared/agent_reactive_state.dart';
import 'package:claw_hub/features/chat_room/viewmodels/preview_updater.dart';
import 'package:claw_hub/features/chat_room/viewmodels/streaming_lifecycle.dart';

/// The agent's thinking/waiting state — mutually exclusive states that
/// replace the previous (isThinking, timeout) boolean pair.
enum ThinkingState {
  /// No message in flight; agent is idle.
  idle,

  /// User sent a message; waiting for the agent to reply.
  thinking,

  /// Agent has been thinking for >60s without a reply.
  timeout,
}

// ============================================================
// SECTION 1: State types (ChatSessionState + ThinkingState)
// ============================================================

/// Single immutable snapshot of the chat session, replacing the 5
/// independent [ValueNotifier]s that previously scattered across the
/// ViewModel.
///
/// Bundles messages, thinking state, connection state, and tool calls
/// so the UI observes one cohesive source of truth instead of juggling
/// multiple notifiers.
class ChatSessionState {
  final LoadState<List<Message>> messages;
  final ThinkingState thinkingState;
  final GatewayConnectionState connectionState;
  final Map<String, ToolCall> toolCalls;
  final String streamingText;

  /// 该实例的 outbox 计数（PENDING + FAILED 消息数）。
  /// 仅在 init / send / 连接状态变化 / outbox flush 时刷新，
  /// 不绑定 _loadMessages 以避免每次消息变化都查 DB。
  final int outboxCount;

  /// 非 null 时表示 retryMessage 因前置条件未满足而跳过，
  /// UI 层应展示此消息并调用 [ChatViewModel.clearRetryFeedback] 清除。
  /// 例如："实例离线，请等待自动重发"、"Agent 已被删除，无法重试"。
  final String? retryFeedback;

  /// 从搜索页跳转时置为目标的 clientId，UI 层据此高亮对应气泡。
  /// 使用 [CopyWithSentinel] 以支持显式清空（null 表示清空高亮）。
  final String? highlightedMessageId;

  /// 高亮消息对应的搜索关键词（用于 MessageBubble 内容高亮）。
  /// 使用 [CopyWithSentinel] 以支持显式清空。
  final String? highlightedQuery;

  /// Monotonic counter bumped whenever [_agent] changes in a content-visible
  /// way (post [Agent.contentEquals] filter). UI reads `vm.agent` directly for
  /// the actual values; this field exists to drive Riverpod's `ref.watch`
  /// rebuild when content changes bypass identity-only `Agent.==` dedup
  /// (nickname / themeColor / quickCommands / tombstone transitions).
  ///
  /// 替换了之前的 `agentRevision`（无差别 bump，包括 seed-event 重放）。
  /// 现在只有真实内容变更才会 bump，seed event 被 contentEquals 过滤掉。
  final int contentRevision;

  /// US-021 AC9: 一次性关闭信号。`send()` 检测到 agent tombstoned 时
  /// (cached 或 tombstone-suspect recheck 路径) 置 true,UI 层
  /// ref.listen 触发 Navigator.pop() 回上一页面。一旦置 true 不再重置
  /// —— pop 后 VM 在路由栈上的 listener 自然释放,残留 true 状态无害
  /// (VM 不会在其他地方被观察)。默认 false,不影响现有 ==/hashCode
  /// 之外的对比语义。
  final bool closeRequested;

  const ChatSessionState({
    this.messages = const LoadInProgress(),
    this.thinkingState = ThinkingState.idle,
    this.connectionState = GatewayConnectionState.disconnected,
    this.toolCalls = const {},
    this.streamingText = '',
    this.outboxCount = 0,
    this.retryFeedback,
    this.highlightedMessageId,
    this.highlightedQuery,
    this.contentRevision = 0,
    this.closeRequested = false,
  });

  ChatSessionState copyWith({
    LoadState<List<Message>>? messages,
    ThinkingState? thinkingState,
    GatewayConnectionState? connectionState,
    Map<String, ToolCall>? toolCalls,
    String? streamingText,
    int? outboxCount,
    // retryFeedback 可空，需区分 "未传参"（保留旧值）与 "显式传 null"（清空），
    // 复用项目统一的 [CopyWithSentinel] 工具（与 AgentProfileState 对齐）。
    Object? retryFeedback = CopyWithSentinel.instance,
    Object? highlightedMessageId = CopyWithSentinel.instance,
    Object? highlightedQuery = CopyWithSentinel.instance,
    int? contentRevision,
    bool? closeRequested,
  }) {
    return ChatSessionState(
      messages: messages ?? this.messages,
      thinkingState: thinkingState ?? this.thinkingState,
      connectionState: connectionState ?? this.connectionState,
      toolCalls: toolCalls ?? this.toolCalls,
      streamingText: streamingText ?? this.streamingText,
      outboxCount: outboxCount ?? this.outboxCount,
      retryFeedback: copyWithNullable(retryFeedback, this.retryFeedback),
      highlightedMessageId: copyWithNullable(
        highlightedMessageId,
        this.highlightedMessageId,
      ),
      highlightedQuery: copyWithNullable(
        highlightedQuery,
        this.highlightedQuery,
      ),
      contentRevision: contentRevision ?? this.contentRevision,
      closeRequested: closeRequested ?? this.closeRequested,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatSessionState &&
          thinkingState == other.thinkingState &&
          connectionState == other.connectionState &&
          messages == other.messages &&
          toolCalls == other.toolCalls &&
          streamingText == other.streamingText &&
          outboxCount == other.outboxCount &&
          retryFeedback == other.retryFeedback &&
          highlightedMessageId == other.highlightedMessageId &&
          highlightedQuery == other.highlightedQuery &&
          contentRevision == other.contentRevision &&
          closeRequested == other.closeRequested;

  @override
  int get hashCode => Object.hash(
    thinkingState,
    connectionState,
    messages,
    toolCalls,
    streamingText,
    outboxCount,
    retryFeedback,
    highlightedMessageId,
    highlightedQuery,
    contentRevision,
    closeRequested,
  );
}

/// ChatViewModel — deep module behind a single-seam interface.
///
/// Owns all chat orchestration:
/// - Agent lookup
/// - Conversation creation (idempotent)
/// - Message history fetch from Gateway
/// - Real-time message stream subscription
/// - Message sending via SendMessageUseCase
/// - Connection state tracking (for disconnect banner)
/// - Waiting/thinking state (for loading animation)
/// - Timeout detection (>60s without reply)
///
/// Extends [StateNotifier] so the UI observes one cohesive
/// [ChatSessionState] via Riverpod's [ref.watch] — no manual
/// listener or setState bridge needed.
class ChatViewModel extends StateNotifier<ChatSessionState>
    with AgentReactiveState {
  final IAgentRepo _agentRepo;
  final IConversationRepo _conversationRepo;
  final IMessageRepo _messageRepo;
  final IInstanceRepo _instanceRepo;
  final IGatewayClient _gatewayClient;
  final SendMessageUseCase _sendMessageUseCase;
  final ILogger _logger;

  /// 入站消息合并用例（Bug #2：历史/实时回传的 user 消息去重）。
  /// 仅依赖 [_messageRepo]，故在内部构造，无需外部注入（避免改动所有
  /// ChatViewModel 测试构造点）。两条入站路径（实时流 + 历史拉取）统一走
  /// [_mergeUseCase.merge] 替代裸 [_messageRepo.insert]，按身份/内容去重。
  /// `late` 不能省 —— Dart 不允许在非 late 的字段初始化器里访问 `this._messageRepo`。
  late final MergeInboundMessageUseCase _mergeUseCase =
      MergeInboundMessageUseCase(messageRepo: _messageRepo);
  final IAchievementChecker _achievementChecker;
  final String instanceId;
  final String agentId;

  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<GatewayConnectionState>? _connectionSubscription;
  StreamSubscription<ToolCall>? _toolCallSubscription;
  StreamSubscription<int>? _outboxCountSubscription;
  Timer? _timeoutTimer;

  /// Bug 2 修复: 标记 [_initStreamsAndHistory] 是否已完成。
  /// - tombstone init 后为 false（早退未订阅）
  /// - refreshAgent 检测到 tombstone→alive 转换时调一次 [_initStreamsAndHistory]，
  ///   之后保持 true 直到 [_teardownSubscriptions]
  bool _streamsInitialized = false;

  /// 仅供测试: 暴露 [_streamsInitialized] 状态用于断言 stream 订阅是否建立。
  /// 生产代码请走 [init] / [refreshAgent] / [send] 等公共方法。
  @visibleForTesting
  bool get streamsInitializedForTesting => _streamsInitialized;

  /// Overall response timer — starts once on [send], never reset by deltas.
  /// Guarantees the user sees a timeout even when the Gateway trickles data
  /// indefinitely (every delta resets [_timeoutTimer], so without this
  /// separate timer, the user could wait forever).
  Timer? _overallTimeoutTimer;

  /// 流式文本累积器 + 节流器(PR-B,spec 2026-07-04)。抽自原 _streamingSubscription
  /// / _streamBuffer / _lastPublishedLength / _flushTimer / _stallTimer / _isStreaming
  /// + _startStreaming / _scheduleFlush / _flushToState / _flushImmediately。VM 经
  /// 回调注入 state 写入与 thinking 超时联动([_onDeltaActivity] 重 arm 60s
  /// _timeoutTimer,[_onStreamError] 取消之)。构造纯存参无副作用。
  late final StreamingLifecycle _streaming = StreamingLifecycle(
    flushDelay: flushDelay,
    onStreamingTextChanged: (t) =>
        _updateState((s) => s.copyWith(streamingText: t)),
    onDeltaActivity: _onDeltaActivity,
    onStreamError: _onStreamError,
    logger: _logger,
  );

  /// 响应式 agent 订阅 —— _init() 中订阅 watchById(agentId) stream，
  /// 任何 DB 写入（本地保存 / Gateway sync）触发 emit 后自动同步 _agent，
  /// UI 经 vm.agent getter 立即看到最新值（quickCommands / nickname 等）。
  /// 仿现有 7 个 stream subscription 模式。
  ///
  /// **双保险设计（重要：不要简化其中一条）**：
  /// - watchById stream = **同实例** DB 写入响应式 SSOT（修本 spec bug）
  /// - agentSyncTickerProvider = **跨实例** tombstone 显式触发（BUG B/C 修复）
  ///
  /// 两条路径不冲突：watchById 缺失时 ticker 可作为 tombstone fallback；
  /// ticker 缺失时 watchById 已能驱动本地写响应式刷新。
  /// 删除任一条都会让对应场景失效。修改前请先阅读设计文档：
  /// docs/superpowers/specs/2026-06-25-chatvm-agent-reactivity-design.md §6.7
  StreamSubscription<Agent?>? _agentSubscription;

  /// Configurable flush delay for streaming text state updates.
  ///
  /// Defaults to 150ms to match [StreamingBubble]'s MarkdownBody debounce.
  /// Set to [Duration.zero] in tests for synchronous assertions.
  @visibleForTesting
  final Duration flushDelay;

  /// Cached future for [init] so [send] can await initialization if the
  /// user sends a message before [init] completes.
  Future<void>? _initFuture;

  /// Guards against a race in [send]: when the message stream listener
  /// delivers the agent reply and calls [_stopThinking] during
  /// `await _loadMessages()`, [send] would unconditionally re-enter
  /// thinking state.  This flag is set before the await and cleared
  /// by the listener, so [send] can skip [_startThinking] when the
  /// reply already arrived.
  bool _awaitingReply = false;

  /// BUG C 修复:ticker 命中本实例后置 true,提醒 [send] 在下次发消息时
  /// 重查 agent (因为 sync 刚发生,缓存可能已 stale)。send 消费后清零。
  ///
  /// tombstone 仅由 [syncFromGateway] 写入,而 syncFromGateway 必触发
  /// AgentsSyncedEvent → ticker listener → 此标志。因此无 ticker fire 时
  /// 缓存的 tombstone 状态与 DB 一致,可安全复用,无需冗余 getById。
  bool _tombstoneSuspect = false;

  /// 标记连接状态订阅收到的「首个事件」。
  ///
  /// `_init()` 在订阅前已执行 `_loadMessages()`。对已处于 connected 的实例，
  /// [ReplayableConnectionState] 会向新订阅者同步下沉一个合成的 connected
  /// seed —— 若不抑制，该 seed 会在每次冷启动已连接聊天时触发一次冗余的
  /// `reloadMessages()`（重复 Drift `getByConversation` 查询），正是种子层想
  /// 避免的回归。真实的 `connecting → connected` 转换首个事件是 connecting，
  /// 会先消费本标记，故其后的 connected 仍照常重载（拾取 OutboxProcessor
  /// 的 PENDING→SENT 后台冲刷）。
  bool _isInitialConnectionEvent = true;

  /// 是否正在流式接收回复。供 [chatViewModelProvider] 的 tick 监听器
  /// 决定是否触发温和刷新（流式中跳过）。委托 [_streaming]。
  bool get isStreaming => _streaming.isStreaming;

  /// 激活时，实时消息监听器跳过 `_loadMessages()` 以避免覆盖高亮锚定窗口。
  /// 由 [loadHighlightWindow] 设置，在 [clearHighlight] 或 2 秒后清除。
  bool _highlightActive = false;

  /// 消息中心预览合并器(PR-A,spec 2026-07-04)。抽自原 _pendingPreviewMessage
  /// + _previewCoalesceTimer + _scheduleConversationPreviewUpdate。onFlush 绑定
  /// [_updateConversationPreview](时间戳 guard + generatePreview + updateLastMessage)。
  late final PreviewUpdater _preview = PreviewUpdater(
    onFlush: (m) => _updateConversationPreview(m),
    isMounted: () => mounted,
  );

  Timer? _messageReloadCoalesceTimer;

  /// Called when stats should be refreshed (message sent or received).
  VoidCallback? onStatsChanged;

  // ============================================================
  // SECTION 2: Constructor + field wiring
  // ============================================================

  ChatViewModel({
    required this._agentRepo,
    required this._conversationRepo,
    required this._messageRepo,
    required this._instanceRepo,
    required this._gatewayClient,
    required this._sendMessageUseCase,
    required this._achievementChecker,
    required this.instanceId,
    required this.agentId,
    this.flushDelay = const Duration(milliseconds: 150),
    ILogger? logger,
  }) : _logger = logger ?? const DebugPrintLogger(),
       super(const ChatSessionState());

  /// The loaded agent — 由 [AgentReactiveState] mixin 提供 (Finding #8 重构)。
  /// 写入走后调 `setAgent(...)`；null 转换与内容变更触发 [onAgentUpdated]。
  /// UI 通过 `vm.agent` getter 直接读最新 _agent（含 tombstone 状态）。
  // (agent getter 由 mixin 暴露)

  /// [AgentReactiveState] mixin 钩子：写入新 agent 后 bump ChatSessionState
  /// 的 contentRevision，驱动 Riverpod ref.watch 触发本 build 重建。
  /// 守卫逻辑（contentEquals 过滤同内容 emit）由 mixin 内的 [setAgent] 负责。
  @override
  void onAgentUpdated() {
    _updateState((s) => s.copyWith(contentRevision: s.contentRevision + 1));
  }

  /// Finding #3: gate `ref.watch` rebuilds on value equality, not identity.
  ///
  /// Riverpod's [StateNotifierProvider] consults
  /// [StateNotifier.updateShouldNotify] (default `!identical(old, current)`)
  /// — NOT `==` — to decide whether consumers' `build()` rebuilds. Because
  /// [copyWith] always returns a new object, `identical()` is always false,
  /// so the default would rebuild on every state set.
  ///
  /// Delegating to `!=` skips rebuilds when [_updateState] produces a
  /// value-equal state (e.g. a no-op transform), while any real content
  /// change (messages / thinkingState / contentRevision / …) still rebuilds.
  ///
  /// This does NOT reintroduce the model-equals-identity-blindspot problem
  /// (that was about `Agent.==` being identity-only and suppressing content
  /// rebuilds); `ChatSessionState.==` is a full content comparison intended
  /// as the rebuild gate.
  ///
  /// Finding #9: Gateway notice 不再走 ChatSessionState（已移除
  /// `gatewayNoticeSeq` / `lastGatewayNotice` 字段）——toast 改由
  /// `gatewayNoticeProvider` (StreamProvider) 直接驱动，不经过本 state。
  @override
  bool updateShouldNotify(ChatSessionState old, ChatSessionState current) =>
      old != current;

  late final String _conversationId = Conversation.generateId(
    instanceId,
    agentId,
  );

  /// Initialise: load agent, create conversation, fetch history, subscribe to stream.
  ///
  /// Uses `??=` so multiple callers (provider + [send]) can safely await the
  /// same future without re-triggering initialisation.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      // 1. Look up the agent
      final agent = await _agentRepo.getById(agentId);
      setAgent(agent);
      if (agent == null) {
        // agent 行不存在（硬删除 / 从未创建）——推 LoadError + closeRequested
        // 让 chat_room_page 立即 smartBack 回上一页，不静默早退（#4）。
        _rejectMissingAgent();
        return;
      }
      // US-021: tombstoned agent 同样早退 —— 不订阅 stream、不创建 dangling
      // conversation 行、不加载消息历史。占位页（AC8）正确显示的同时
      // 避免:(a) 浪费 5 个 stream 订阅资源,(b) revive 后 _initFuture 已
      // cache 导致无法干净重订阅,(c) DB 中残留幽灵 conversation 行。
      // Bug 2 修复: revive 路径由 [refreshAgent] 检测 tombstone→alive 转换
      // 后调一次 [_initStreamsAndHistory]，避开 _initFuture 缓存。
      if (agent.isRemoved) {
        _logger.info(
          '[ChatViewModel] Agent tombstoned: agentId=$agentId, '
          'instanceId=$instanceId — short-circuit init.',
        );
        return;
      }

      await _initStreamsAndHistory(agent);
    } catch (error, stackTrace) {
      _logger.error(
        '[ChatViewModel] init failed for $instanceId/$agentId: $error',
        stackTrace,
      );
      // Tear down any subscriptions that were set up before the failure
      // so a subsequent retry() or send() starts from a clean slate.
      _teardownSubscriptions();
      // Clear the cached future so the next init() / send() call will
      // retry instead of instantly returning the failed future.
      _initFuture = null;
      // Surface LoadError so the UI shows a retry button (LoadErrorView.onRetry
      // → vm.retry()). Without this, a cold-start init failure leaves the page
      // on LoadInProgress forever with no recovery affordance — retry() resets
      // _initFuture but there's no button to tap.
      _updateState(
        (s) => s.copyWith(messages: LoadError('聊天初始化失败：$error', stackTrace)),
      );
      // Signal to send() that the agent is unavailable.
      // setAgent(null) 同步清掉 _agent 缓存 + bump contentRevision，UI
      // 重建后 vm.agent.isTombstoned = false，回退到 LoadError 而
      // 不是上一轮的 tombstone 占位页。
      setAgent(null);
    }
  }

  /// Bug 2 修复: 把 [_init] 中 tombstone early-return 之后的 stream / history
  /// 订阅代码抽到这里。两条调用路径:
  ///
  /// 1. [_init] 在确认 agent alive 后调一次（首启动）
  /// 2. [refreshAgent] 检测到 tombstone→alive 转换时调一次（复活）
  ///
  /// 之所以单独抽出，是因为 [_init] 走 _initFuture 缓存，tombstone 早退后
  /// 第二次调 init() 不会重跑；而 refreshAgent 不经 _initFuture 缓存，必须
  /// 显式触发订阅。两条路径的代码完全一致 —— 抽出避免漂移。
  ///
  /// 失败时异常上抛至 [_init] 的外层 catch（清 _initFuture + setAgent(null)
  /// + 推 LoadError 供 retry），由其统一 _teardownSubscriptions 防半订阅状态。
  /// 成功末尾 [_streamsInitialized] = true，让 refreshAgent 后续不再
  /// 重复触发（alive→alive 是 no-op）。
  Future<void> _initStreamsAndHistory(Agent activeAgent) async {
    // 2. Get or create conversation (idempotent)
    await _conversationRepo.getOrCreate(instanceId, agentId);

    // 3. Load local messages immediately (fast path)
    await _loadMessages();

    // ★ 3.5 订阅 agent 响应式 stream
    // [setAgent] 内部 [Agent.contentEquals] 守卫过滤掉 Drift
    // `.watchSingleOrNull()` 的 seed event（与已有 [_agent] 内容完全相同），
    // 避免 contentRevision 在 init 同步阶段被误增（旧逻辑 revision 从 1
    // 跳到 2，对应一次无意义的 UI rebuild）。null 转换（tombstone / 复活）
    // 和真实内容变更（nickname / themeColor / quickCommands）正确放行。
    // 包装在 try 中：mocktail 未 stub 的 watchById 可能返回 null，
    // 真实实现 (InMemory / Drift) 不会。失败只丢响应式刷新，
    // 不影响其余 6 个 stream 订阅。
    try {
      _agentSubscription = _agentRepo
          .watchById(agentId)
          .listen(
            setAgent,
            onError: (error, stackTrace) {
              // Law 8: catch 必有日志
              _logger.error(
                '[ChatViewModel] watchById error for $agentId: '
                '$error',
                stackTrace,
              );
            },
          );
    } catch (error, stackTrace) {
      // Law 8: catch 必有日志
      _logger.error(
        '[ChatViewModel] watchById subscribe failed for $agentId: '
        '$error',
        stackTrace,
      );
    }

    // 4. Subscribe to connection state
    _connectionSubscription = _gatewayClient
        .connectionStateStream(instanceId)
        .listen(
          (state) {
            final wasInitial = _isInitialConnectionEvent;
            _isInitialConnectionEvent = false;
            _updateState((s) => s.copyWith(connectionState: state));
            // 连接断开/恢复路径必须重置 _streaming.isStreaming —— 否则一次中途
            // 网关掉线（无 StreamingDone）会让 reloadMessages 在
            // `if (_streaming.isStreaming) return;` 处永远早退，导致
            // cacheClearedTickProvider++ 后聊天列表保留旧的（清理前）快照。
            // Streaming 终态（StreamingDone / agent Message / send / onError
            // / dispose）已经在各自路径处理；这里只覆盖「连接层异常」
            // 这个原本没被任何路径覆盖的边界。
            if (state != GatewayConnectionState.connected &&
                state != GatewayConnectionState.connecting &&
                state != GatewayConnectionState.authenticating &&
                _streaming.isStreaming) {
              _streaming.onConnectionLost();
              _timeoutTimer?.cancel();
              _timeoutTimer = null;
            }
            // 连接状态变化时刷新消息列表 —
            // OutboxProcessor 可能在后台冲刷，将 PENDING 推进到 SENT；
            // 这些状态变更通过 messageStream 不会传达（DB 直接更新），
            // 故 connected 后重载一次消息列表以反映最新状态。
            // outbox 计数不再在此刷新 —— 由 _outboxCountSubscription 自动驱动。
            if (state == GatewayConnectionState.connected) {
              if (wasInitial) {
                // 合成 connected seed：_init() 刚执行过 _loadMessages()，
                // 再 reload 是每次冷启动已连接聊天都会浪费一次 Drift 查询的
                // 回归。跳过；真实 connecting→connected 转换会照常重载。
              } else {
                unawaited(reloadMessages());
              }
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            // Symmetry with the message/tool/outbox/agent listeners (review #4):
            // without this, a connectionStateStream error vanishes to the zone
            // and the subscription may auto-cancel, freezing the connection
            // banner on the last known state with no diagnostic trail.
            _logger.error(
              '[ChatViewModel] connection state stream error for $instanceId: '
              '$error',
              stackTrace,
            );
          },
        );

    // 5. Subscribe to real-time streams BEFORE history fetch — broadcast
    //    StreamControllers have no replay, so events arriving during the
    //    history-fetch RTT (100-2000ms) are permanently lost if we
    //    subscribe after.  (Same pattern documented in ConnectionOrchestrator
    //    lines 224-227.)

    // 5a. Real-time messages
    _messageSubscription = _gatewayClient
        .messageStream(instanceId)
        .listen(
          (msg) async {
            // Guard: messageStream is per-instance and carries messages
            // for ALL agents in that instance.  Only process messages
            // that belong to this ViewModel's agent — otherwise the
            // unconditional conversationId overwrite below would misroute
            // another agent's reply into this conversation (causing the
            // message to "appear in the wrong chat" and "disappear" from
            // its rightful owner).
            //
            // msg.agentId is empty only when the Gateway omits it (legacy
            // v3 fallback); in that case we process the message rather
            // than silently dropping it.
            final agentRemoteId = activeAgent.remoteId;
            if (msg.agentId.isNotEmpty && msg.agentId != agentRemoteId) {
              return;
            }

            // Normalise conversationId to the canonical SHA-256 hash.
            //
            // The ACL may construct messages with a raw conversationId
            // (e.g. 'agent:remoteId') when the Gateway uses v3 protocol
            // (agent.lifecycle fallback) or when chat.final arrives
            // without a message object.  Those raw IDs violate the
            // FOREIGN KEY constraint on messages.conversation_id
            // (references conversations.id) and cause a silent insert
            // failure.  See schema.drift:79.
            //
            // Overriding with _conversationId guarantees the FK
            // constraint is satisfied and the message routes to the
            // correct conversation for _loadMessages() below.
            //
            // Also override logicalClock when the Gateway's value is
            // incompatible with the client's timestamp-based counter.
            // SendMessageUseCase starts at DateTime.now().millisecondsSinceEpoch;
            // a Gateway clock < year-2020 epoch would sort all agent messages
            // after all user messages in the DESC-ordered list, breaking
            // chronological display.
            //
            // Uses the shared counter from SendMessageUseCase to guarantee
            // strict monotonic ordering across both user-sent and agent-received
            // messages, even when they arrive within the same millisecond.
            final fixedMsg = msg.copyWith(
              conversationId: _conversationId,
              logicalClock: msg.logicalClock < 1577836800000
                  ? _sendMessageUseCase.nextLogicalClock()
                  : msg.logicalClock,
            );
            try {
              await _mergeUseCase.merge(fixedMsg, softMatch: false);
            } catch (error, stackTrace) {
              // iron-law-allow: Law8 — 兜底:即使 clearAll 保留骨架,任何
              // FK/约束冲突也不应静默吞掉后续逻辑。旧实现异常会中断
              // _updateConversationPreview 与 _loadMessages,使消息列表
              // 卡在空状态。记日志后 return,等下一条消息正常处理。
              _logger.error(
                '[ChatViewModel] message merge failed for '
                '${fixedMsg.clientId}: $error',
                stackTrace,
              );
              return;
            }
            // 同步会话预览 —— 让消息中心展示「真正的最后一条消息」。
            // 此前 updateLastMessage 仅在用户发送时被调用，导致预览永远
            // 停留在「我」的最后一条消息，掩盖了 Agent 的最新回复。
            // 这里用与 SendMessageUseCase 相同的预览规则，保证两侧一致。
            _preview.schedule(fixedMsg);
            // 高亮激活期间跳过全量重载 — loadHighlightWindow 设置的有界窗口优先。
            if (!_highlightActive) {
              _scheduleMessagesReload();
            }
            if (fixedMsg.role == MessageRole.agent) {
              // Clear streaming text when the final message lands —
              // eliminates the race window between StreamingDone and
              // Message arrival on independent broadcast controllers.
              _awaitingReply = false;
              _streaming.onReplyArrived();
              _stopThinking();
              // Re-key the turn's ToolCall from sessionKey → clientId so
              // the page's `toolCalls[message.clientId]` lookup finds it.
              _rekeyToolCallForMessage(fixedMsg);
              onStatsChanged?.call();
              // Fire-and-forget achievement evaluation — deferred to
              // agent reply arrival so stats include the latest message
              // and don't contend with concurrent streaming inserts.
              _achievementChecker.check(agentId);
            }
          },
          onError: (error, stackTrace) {
            _logger.error(
              'Message stream error for $instanceId: $error',
              stackTrace,
            );
          },
        );

    // 5b. Tool call events
    _toolCallSubscription = _gatewayClient
        .toolCallStream(instanceId)
        .listen(
          (tc) {
            final current = Map<String, ToolCall>.from(state.toolCalls);
            current[tc.messageId] = tc;
            _updateState((s) => s.copyWith(toolCalls: current));
          },
          onError: (error, stackTrace) {
            _logger.error(
              'Tool call stream error for $instanceId: $error',
              stackTrace,
            );
          },
        );

    // 5c. Streaming deltas — subscription is recreated on each send()
    //     so stale events from a previous response never contaminate
    //     the current buffer (no generation-guard needed).
    _streaming.start(
      _gatewayClient.streamingDeltaStream(instanceId),
      activeAgent.remoteId,
    );

    // 5d. (Finding #9 修复) Gateway 诊断事件 notice 不再由 VM 订阅 ——
    // 改由 gatewayNoticeProvider (StreamProvider) 订阅,UI 经
    // ref.listen(gatewayNoticeProvider) 直接消费。VM 不参与 notice 流。
    //
    // “先订阅再 fetchHistory”不变量由 chatViewModelProvider create body
    // 的 ref.listen(gatewayNoticeProvider(params.instanceId), (_, _) {})
    // 早订阅保证（在 vm.init() 之前执行）——broadcast stream 无 replay,
    // fetch RTT 期间 notice 不会丢。见 chat_providers.dart create body。

    // 6. Fetch message history from Gateway (best-effort).
    //    Placed AFTER real-time subscriptions so that events arriving
    //    during the fetch RTT are captured, not lost.
    final remoteId = activeAgent.remoteId;
    try {
      final history = await _gatewayClient.fetchMessageHistory(
        instanceId: instanceId,
        agentId: remoteId,
      );
      // 循环外预取一次近期消息列表,传给每条 merge() 用作软匹配 candidate。
      // —— Bug #4 (Law 6) 修复:之前每条 merge() 内部都触发一次
      // getByConversation(limit:50),N 条历史 = N 次相同查询(标准 N+1)。
      // 与 MessageCatchUpService.catchUp(line 184)同款优化。
      final recent = await _messageRepo.getByConversation(
        _conversationId,
        limit: 50,
      );

      // per-insert try/catch: 与 messageStream 路径(line 368-379)对称,
      // 防止 clearAll 保留骨架后,任何一条历史消息的 FK/约束冲突中断整
      // 个循环,导致 _loadMessages 永不调用,后续消息(N+1..end)静默跳过。
      for (final msg in history.messages) {
        // Normalise to canonical SHA-256 conversationId, matching
        // the live stream listener at line ~247.  _parseMessage
        // defaults to '' when the Gateway omits the field, which
        // violates the FK constraint on messages.conversation_id.
        final fixedMsg = msg.copyWith(conversationId: _conversationId);
        try {
          // 用 mergeWithStatus 以传入 recent(merge() 不暴露该参数)。
          // 这里丢弃 wasNew —— history 路径不需要区分是否新增,
          // dedupeConversation 已覆盖清理历史重复的职责。
          await _mergeUseCase.mergeWithStatus(
            fixedMsg,
            softMatch: true,
            recent: recent,
          );
        } catch (error, stackTrace) {
          // iron-law-allow: Law8 — 历史拉取的逐条兜底,与 messageStream
          // 路径一致,单条 FK 冲突不应中断整批导入。
          _logger.error(
            '[ChatViewModel] history merge failed for '
            '${fixedMsg.clientId}: $error',
            stackTrace,
          );
        }
      }
      // Bug #2 补强: 清理历史遗留的重复行。旧 CatchUp(身份去重)在过往重启中
      // 累积了重复消息;merge 已停止新增,这里删除已存在的重复。幂等 —— 无
      // 重复时为 no-op。放在历史合并之后、_loadMessages 之前,使首屏即干净。
      try {
        final deleted = await _messageRepo.dedupeConversation(_conversationId);
        if (deleted > 0) {
          _logger.info(
            '[ChatViewModel] dedupeConversation removed $deleted duplicate '
            'rows for $_conversationId',
          );
        }
      } catch (error, stackTrace) {
        _logger.error(
          '[ChatViewModel] dedupeConversation failed for '
          '$_conversationId: $error',
          stackTrace,
        );
      }
      await _loadMessages();
    } catch (error, stackTrace) {
      _logger.error(
        'History fetch failed for $instanceId/$remoteId: $error',
        stackTrace,
      );
    }

    // 7. outbox 计数 —— SSOT stream 驱动（取代散落的 _loadOutboxCount 轮询）。
    //    bootstrap 一次拿初始值（await 保证 init 返回时 state 已就绪），
    //    之后任何影响 outbox 的 DB 写入由 watchOutboxCount 自动推送。
    final initCount = await _messageRepo.getOutboxCountByInstance(instanceId);
    _updateState((s) => s.copyWith(outboxCount: initCount));
    _outboxCountSubscription = _messageRepo
        .watchOutboxCount(instanceId)
        .listen(
          (count) => _updateState((s) => s.copyWith(outboxCount: count)),
          onError: (Object error, StackTrace stack) {
            _logger.error(
              '[ChatViewModel] outbox count stream error for $instanceId: '
              '$error',
              stack,
            );
          },
        );

    _streamsInitialized = true;
  }

  // ============================================================
  // SECTION 3: Send + thinking state management
  // ============================================================

  /// send() tombstone 拒绝的统一出口 —— 写入 [LoadError] + 置
  /// [ChatSessionState.closeRequested] 让 chat_room_page 触发
  /// smartBack。两条 guard 分支 (cached / tombstone-suspect recheck)
  /// 共享此出口,保证 UX 文案与 state 形状一致。
  void _rejectTombstonedSend(String reason) {
    _updateState(
      (s) => s.copyWith(
        messages: LoadError(
          'Agent has been removed from the Gateway. '
          'Please go back and try again.',
          StackTrace.current,
        ),
        closeRequested: true,
      ),
    );
    _logger.error(
      '[ChatViewModel] send() blocked: agent $agentId $reason '
      'in instance $instanceId.',
    );
  }

  /// agent 行不存在（getById 返回 null —— 硬删除 / 从未创建）的统一出口。
  ///
  /// 与 [_rejectTombstonedSend] 对称：tombstone 是「远端软删」（行还在，
  /// isRemoved=true），missing 是「本地行不存在」。两者都推 LoadError +
  /// [ChatSessionState.closeRequested] 让 chat_room_page 触发 smartBack 回
  /// 上一页。
  ///
  /// 不清 _initFuture、不调 _teardownSubscriptions：agent 已不在，重试只会
  /// 再次拿到 null，重试入口对用户无意义。#4：之前 [_init] 在 agent==null 时
  /// 静默早退（只 log + return），state 永久停在 LoadInProgress，无任何恢复
  /// 入口；[send] 的 agent==null 分支早就有这套 LoadError+closeRequested，
  /// init 没对齐。
  void _rejectMissingAgent() {
    _updateState(
      (s) => s.copyWith(
        messages: LoadError(
          'Agent not found. '
          'It may have been removed. Please go back and try again.',
          StackTrace.current,
        ),
        closeRequested: true,
      ),
    );
    _logger.error(
      '[ChatViewModel] agent $agentId not found in instance $instanceId.',
    );
  }

  /// Send a text message.
  ///
  /// If [init] hasn't completed yet, awaits it first so the user's message
  /// is never silently dropped.  If the agent doesn't exist (or init failed),
  /// surfaces a [LoadError] so the UI can show a meaningful message.
  Future<void> send(String text) =>
      _sendCore(content: text, type: MessageType.text);

  /// 发送图片消息。[path] 为本地文件路径,[metadata] 至少含 fileName/mimeType/size,
  /// 可选 caption。实际字节读取与 base64 编码由 ACL 层 sendMessage 在发送时完成,
  /// DB 只存路径(避免大 blob 污染 SQLite)。
  Future<void> sendImage(
    String path, {
    required Map<String, dynamic> metadata,
  }) => _sendCore(content: path, type: MessageType.image, metadata: metadata);

  /// 发送文件消息。[path] 为本地文件路径。
  Future<void> sendFile(
    String path, {
    required Map<String, dynamic> metadata,
  }) => _sendCore(content: path, type: MessageType.file, metadata: metadata);

  /// send / sendImage / sendFile 的共用发送体。
  /// [content] 文本消息为正文,图片/文件消息为本地文件路径。
  Future<void> _sendCore({
    required String content,
    required MessageType type,
    Map<String, dynamic>? metadata,
  }) async {
    // Tear down the old streaming subscription so stale deltas/done
    // events from a previous response never contaminate the new buffer.
    // A fresh subscription is created below after init() succeeds.
    _streaming.resetForSend();
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    await init();

    if (agent == null) {
      // init 的 agent==null 分支已推过 LoadError+closeRequested；这里是
      // 安全网（init 未跑 / agent 在 init 后被清空），行为一致。
      _rejectMissingAgent();
      return;
    }

    // US-021: 缓存的 _agent 已被 init 标记为 tombstoned → 早退。
    // init 在 agent.isRemoved 时已短退 (line 329-335),后续 send 看到
    // _agent.isRemoved=true 不应继续发消息,直接 LoadError + 关闭信号。
    if (agent!.isRemoved) {
      _rejectTombstonedSend('tombstoned (cached from init)');
      return;
    }

    // BUG C 修复 (Law 6): 仅在 [_tombstoneSuspect] 为 true 时才重查
    // agent。无 ticker fire 时 init 时刻的 _agent 缓存与 DB 一致
    // (tombstone 仅由 syncFromGateway 写入,而 sync 必触发 ticker),
    // 复用缓存避免每发一次都 getById 一次 (N send = N 冗余 read)。
    if (_tombstoneSuspect) {
      final freshAgent = await _agentRepo.getById(agentId);
      _tombstoneSuspect = false;
      if (freshAgent == null || freshAgent.isRemoved) {
        _rejectTombstonedSend(
          '${freshAgent == null ? "not found" : "tombstoned"} '
          'after tombstone-suspect refresh',
        );
        return;
      }
      setAgent(freshAgent);
    }

    // Start a fresh streaming subscription for this send — any stale
    // events from the previous subscription were already cancelled above.
    _streaming.start(
      _gatewayClient.streamingDeltaStream(instanceId),
      agent!.remoteId,
    );

    _awaitingReply = true;

    final sentMessage = await _sendMessageUseCase.execute(
      instanceId: instanceId,
      agent: agent!,
      content: content,
      type: type,
      metadata: metadata,
    );

    await _loadMessages();

    // Only start "thinking" state when the message was successfully sent
    // AND the agent reply hasn't already arrived during _loadMessages().
    // - FAILED: the Gateway rejected or couldn't reach the message;
    //   no agent reply will ever arrive, so thinking would spin forever.
    // - PENDING: the instance is offline; the message is waiting in the
    //   outbox and will be retried later.
    if (sentMessage.status == MessageStatus.sent && _awaitingReply) {
      _startThinking();
      // Overall timeout — fires regardless of delta activity, preventing
      // a Gateway that trickles one char every 59s from keeping the user
      // waiting indefinitely.  Longer than the per-delta 60s timer because
      // it never resets: it covers the entire request lifecycle.
      _overallTimeoutTimer?.cancel();
      _overallTimeoutTimer = Timer(const Duration(seconds: 120), () {
        _updateState((s) => s.copyWith(thinkingState: ThinkingState.timeout));
      });
    }

    // outbox 计数由 _outboxCountSubscription 自动驱动，无需在此手动刷新。
    // 离线时新消息进入 PENDING，写库后 stream 自动推送新计数到 OutboxWarningBanner。
    //
    // onStatsChanged and achievement check are deferred to the message
    // stream listener (agent reply arrival) — the user's own send doesn't
    // change stats from the dashboard perspective, and deferring avoids
    // DB contention with concurrent streaming message inserts.
  }

  /// Dismiss the timeout banner and cancel waiting.
  void dismissTimeout() {
    _stopThinking();
  }

  /// Continue waiting — dismiss the timeout banner and restart the timer.
  void continueWaiting() {
    _startThinking();
  }

  /// delta 到达时由 [_streaming] 回调 —— 重新 arm 60s 活动 _timeoutTimer
  /// (覆盖 [_startThinking] 的 arm 与每 delta 的重 arm,统一入口防值漂移)。
  /// _timeoutTimer 留在 VM(thinking 状态机内聚,Option A)。
  void _onDeltaActivity() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      _updateState((s) => s.copyWith(thinkingState: ThinkingState.timeout));
    });
  }

  /// 流错误时由 [_streaming] 回调 —— 取消 60s _timeoutTimer 与 120s
  /// _overallTimeoutTimer,避免错误后误触 timeout banner。
  void _onStreamError() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _overallTimeoutTimer?.cancel();
    _overallTimeoutTimer = null;
  }

  void _startThinking() {
    _onDeltaActivity();
    _updateState((s) => s.copyWith(thinkingState: ThinkingState.thinking));
  }

  void _stopThinking() {
    _timeoutTimer?.cancel();
    _overallTimeoutTimer?.cancel();
    _updateState((s) => s.copyWith(thinkingState: ThinkingState.idle));
  }

  /// Reload messages from the repository and push to the notifier.
  Future<void> _loadMessages() async {
    try {
      final messages = await _messageRepo.getByConversation(_conversationId);
      _updateState((s) => s.copyWith(messages: LoadData(messages)));
    } catch (error, stackTrace) {
      _logger.error(
        '[ChatViewModel] _loadMessages failed for $_conversationId: '
        '$error',
        stackTrace,
      );
      _updateState((s) => s.copyWith(messages: LoadError(error, stackTrace)));
    }
  }

  /// 更新会话预览，使其反映「真正的最后一条消息」。
  ///
  /// [SendMessageUseCase.execute] 只在用户发送时更新预览；Agent 回复经
  /// 消息流到达时，若不在此同步刷新 [Conversation.lastMessageRole/Preview/
  /// Time/Id]，消息中心的列表会永远停留在用户最后一条消息上（缺陷：预览
  /// 与实际聊天尾端不一致）。
  ///
  /// 预览文本与用户侧共用 [_sendMessageUseCase.generatePreview]，确保
  /// 「你:」前缀、Markdown 去除、截断等规则两侧完全一致。
  ///
  /// 一道护栏（避免把预览写坏）：
  /// - 仅当新消息不早于当前会话尾端时才覆盖 [Conversation.lastMessageTime]。
  ///   messageStream 是广播流，乱序/重发的旧事件会触发本方法；若无此护栏，
  ///   一条迟到的旧消息会把会话在列表里「拉回过去」（lastMessageTime 驱动
  ///   消息中心的 DESC 排序）。
  ///
  /// toolCall 过滤由上游 [PreviewUpdater.schedule] 统一承担（它是本方法唯一
  /// 调用方，经 `onFlush` 回调进入），故此处不再重复 guard。
  Future<void> _updateConversationPreview(Message message) async {
    try {
      // 护栏：乱序/重发旧消息不得回卷 lastMessageTime。
      final current = await _conversationRepo.getById(_conversationId);
      if (current != null &&
          message.timestamp < current.lastMessageTime &&
          message.clientId != current.lastMessageId) {
        return;
      }

      final preview = _sendMessageUseCase.generatePreview.execute(
        role: message.role,
        type: message.type,
        content: message.content,
      );
      await _conversationRepo.updateLastMessage(
        conversationId: _conversationId,
        messageId: message.clientId,
        preview: preview,
        timestamp: message.timestamp,
        role: message.role,
      );
    } catch (error, stackTrace) {
      // 预览更新失败不应影响消息渲染本身 —— 仅记日志，列表会在下次
      // 用户发送或重载时自然刷新。
      _logger.error(
        '[ChatViewModel] updateLastMessage failed for $_conversationId: '
        '$error',
        stackTrace,
      );
    }
  }

  void _scheduleMessagesReload() {
    _messageReloadCoalesceTimer?.cancel();
    _messageReloadCoalesceTimer = Timer(Duration.zero, () {
      if (!mounted || _highlightActive) return;
      unawaited(_loadMessages());
    });
  }

  /// Re-key the turn's ToolCall from `sessionKey` → [msg.clientId] so the
  /// page's `toolCalls[message.clientId]` lookup (chat_room_page
  /// `_buildMessageList`) finds it. The processor tags agent messages with
  /// `metadata['sessionKey']`; ToolCalls arrive keyed by the same sessionKey
  /// (`ToolCall.messageId = event.sessionKey`). Without this re-key the keys
  /// live in different namespaces and ToolCallCard never renders
  /// (review #1, Option C).
  ///
  /// 已知限制：tool call 必须在 final 消息之前到达才能被重键。tool call 迟到
  /// （final 之后才到）不会被重键 → 不渲染。常见时序（tool → final）已覆盖。
  void _rekeyToolCallForMessage(Message msg) {
    final sk = msg.metadata?['sessionKey'];
    if (sk is! String) return;
    final tc = state.toolCalls[sk];
    if (tc == null) return;
    final rekeyed = Map<String, ToolCall>.from(state.toolCalls)
      ..remove(sk)
      ..[msg.clientId] = tc.copyWith(messageId: msg.clientId);
    _updateState((s) => s.copyWith(toolCalls: rekeyed));
  }

  /// 重载消息列表。供 [chatViewModelProvider] 响应
  /// [outboxFlushTickerProvider]（OutboxProcessor 后台冲刷完成信号）时调用，
  /// 替代重建 ViewModel。
  ///
  /// 仅重载消息列表 —— outbox 计数由 [_outboxCountSubscription] 自动驱动。
  /// 冲刷产生的状态变更（PENDING → SENDING → SENT）不经 messageStream，
  /// 故需要这个 fire-once 信号触发重载以反映最终 SENT 状态。
  /// （完整移除此信号需方案 A 全量的 watchByConversation，留待后续迭代。）
  ///
  /// **流式期间跳过**：clear-cache tick 在流式进行中触发时，若重载会读到
  /// 已清空的 DB 让 `state.messages` 闪空。流式文本在独立缓冲区不受影响；
  /// 流式结束（最终回复落库）后 messageStream 监听器会调 [_loadMessages]
  /// 自然刷新。[_streaming].isStreaming 由首个 delta 置 true、StreamingDone/回复到达
  /// 置 false。
  Future<void> reloadMessages() async {
    if (_streaming.isStreaming) return;
    await _loadMessages();
  }

  /// US-021 AC8 响应式入口：重查 agent 最新状态并同步 [ChatSessionState]。
  ///
  /// 由 provider 侧 `ref.listen(agentSyncTickerProvider)` 在 agents 同步
  /// 完成后调用。用户在 ChatRoom 停留期间，后台 [syncFromGateway] 可能
  /// 把 agent tombstone（远端删除）或复活（远端重新出现）—— 此方法走
  /// `setAgent` 路径更新 _agent 缓存 + bump contentRevision，UI 重建
  /// 后读 vm.agent.isRemoved 触发 AC8 占位页。
  ///
  /// US-021 v1.2 简化：去掉 `if (initFuture == null) return;` 早退守卫和
  /// `await initFuture` 等待逻辑。refreshAgent 直接独立 fetch agent —— 与
  /// init() 的 fetch 完全独立（init 走 tombstone 短路路径，refreshAgent
  /// 走 ticker 驱动路径），两者并发时最后一次写入生效，`setAgent`
  /// 保证 state 反映最终结果。`initFuture` 守卫是过度防御 —— ticker 监听器
  /// 只在 provider body 中注册，provider body 必先调 `vm.init()`，所以
  /// 实际不会到达 initFuture == null 路径。简化后代码更清晰,边界路径行为
  /// 也更可预测（即使 init 尚未完成也会 fetch 并同步 tombstone 状态）。
  Future<void> refreshAgent() async {
    try {
      setAgent(await _agentRepo.getById(agentId));
    } catch (e, st) {
      _logger.error('[ChatViewModel] refreshAgent getById failed: $e', st);
      return;
    }
    // Bug 2 修复: tombstone→alive 复活路径。如果 [_streamsInitialized] 仍
    // 为 false（说明之前的 [_init] 在 tombstone 上早退），且当前 agent 已
    // 复活，立即补建 6 个 stream 订阅。否则 ChatRoom 显示正常聊天但流全断，
    // 用户收不到入站 agent 回复和连接状态驱动的 reload。
    final currentAgent = agent;
    if (!_streamsInitialized &&
        currentAgent != null &&
        !currentAgent.isRemoved) {
      // 复活路径：_initStreamsAndHistory 失败不再被内部 catch 吞掉（该 catch
      // 已移除，异常上抛以让 _init 外层 catch 清 _initFuture）。本路径不经
      // _init，必须自行捕获，防止异常冒泡到 ticker listener（best-effort
      // 复活：失败留 _streamsInitialized=false，下次 ticker 再试）。
      try {
        await _initStreamsAndHistory(currentAgent);
      } catch (e, st) {
        _logger.error(
          '[ChatViewModel] revive _initStreamsAndHistory failed for '
          '$agentId: $e',
          st,
        );
        _teardownSubscriptions();
      }
    }
  }

  /// BUG C 修复入口:在 ticker 命中本实例时同时设 tombstone-suspect 标志
  /// 并执行 refreshAgent。
  ///
  /// [_tombstoneSuspect] 在 [send] 中被消费后清零。语义：
  /// - 标志置 true → 缓存可能已 stale（sync 刚发生），send 需重查
  /// - 标志置 false → 缓存仍是 init 时刻的快照,send 复用 _agent 即可
  ///
  /// 此方法与 [refreshAgent] 拆开的目的是:让 provider 层的 ticker listener
  /// 在调 refreshAgent 前"声明"下次 send 需要重查,语义边界清晰。
  Future<void> markTombstoneSuspectAndRefresh() async {
    _tombstoneSuspect = true;
    await refreshAgent();
  }

  // ============================================================
  // SECTION 4: Retry + highlight + connection recovery
  // ============================================================

  /// 重试一条 FAILED 消息（US-015 AC2 手动重试入口）。
  ///
  /// 通过 [SendMessageUseCase.retry] 走统一的发送路径，与 [OutboxProcessor]
  /// 共用 CAS 防竞争逻辑，避免同一消息被重复发送。
  ///
  /// 前置检查：
  /// - 消息存在且为 FAILED 状态
  /// - 实例存在且可连接（离线时跳过，等待 OutboxProcessor 自动处理）
  /// - Agent 存在（可能已被删除）
  ///
  /// 当前置条件未满足时，通过 [ChatSessionState.retryFeedback] 向 UI
  /// 传递可读的跳过原因，避免静默失败。
  Future<void> retryMessage(String clientId) async {
    final message = await _messageRepo.getByClientId(clientId);
    if (message == null || !message.isRetryable) {
      _updateState((s) => s.copyWith(retryFeedback: '该消息无法重试'));
      return;
    }

    final instance = await _instanceRepo.getById(instanceId);
    if (instance == null || !instance.healthStatus.isConnectable) {
      _updateState((s) => s.copyWith(retryFeedback: '实例离线，请等待自动重发'));
      return;
    }

    final agent = await _agentRepo.getById(agentId);
    if (agent == null || agent.isRemoved) {
      setAgent(agent);
      _updateState((s) => s.copyWith(retryFeedback: 'Agent 已被删除，无法重试'));
      return;
    }

    try {
      final result = await _sendMessageUseCase.retry(
        clientId: clientId,
        instanceId: instanceId,
        agentRemoteId: agent.remoteId,
        expectedStatus: message.status, // 显式传入，避免默认值 FAILED 与未来 PENDING 可重试冲突
      );
      if (!result.sentNow && result.message.status == MessageStatus.failed) {
        _updateState((s) => s.copyWith(retryFeedback: '重试失败，请稍后再试'));
      }
    } catch (error, stackTrace) {
      // retry 内部已尝试标记 FAILED；这里只防止异常冒泡。
      _logger.error(
        '[ChatViewModel] retryMessage failed for $clientId: $error',
        stackTrace,
      );
      _updateState((s) => s.copyWith(retryFeedback: '重试异常，请稍后再试'));
    }

    await reloadMessages();
  }

  /// 清除 [ChatSessionState.retryFeedback]（UI 展示后调用）。
  void clearRetryFeedback() {
    _updateState((s) => s.copyWith(retryFeedback: null));
  }

  void _updateState(ChatSessionState Function(ChatSessionState) transform) {
    if (!mounted) return;
    state = transform(state);
  }

  /// Retry initialization after a previous failure.
  ///
  /// Call this from the UI's retry button (e.g. [LoadErrorView.onRetry]).
  /// Load the anchor window around a target message and mark it as highlighted.
  ///
  /// Used when navigating from search results — replaces the current message
  /// list with a bounded window (5 before + 10 after) centered on
  /// [targetClientId], and stores the highlight so [MessageBubble] can
  /// render the accent background.
  Future<void> loadHighlightWindow(
    String targetClientId,
    String highlightQuery,
  ) async {
    _highlightActive = true;
    try {
      final messages = await _messageRepo.getAnchorWindow(
        _conversationId,
        targetClientId: targetClientId,
        before: 5,
        after: 10,
      );
      _updateState(
        (s) => s.copyWith(
          messages: LoadData(messages),
          highlightedMessageId: targetClientId,
          highlightedQuery: highlightQuery,
        ),
      );
    } catch (error, stackTrace) {
      _logger.error(
        '[ChatViewModel] loadHighlightWindow failed '
        'for target=$targetClientId: $error',
        stackTrace,
      );
      // Fallback: just highlight without scrolling — regular load still
      // shows the message if it's in the page.
      _updateState(
        (s) => s.copyWith(
          highlightedMessageId: targetClientId,
          highlightedQuery: highlightQuery,
        ),
      );
    }
  }

  /// Clear the search-result highlight from the message bubble.
  void clearHighlight() {
    _highlightActive = false;
    _updateState(
      (s) => s.copyWith(highlightedMessageId: null, highlightedQuery: null),
    );
    // 恢复完整消息列表（高亮期间实时消息的全量重载被跳过以保护锚定窗口）
    reloadMessages();
  }

  /// Resets all state and re-runs agent lookup, history fetch, and stream
  /// subscriptions from scratch.  Safe to call even if init succeeded.
  Future<void> retry() async {
    _teardownSubscriptions();
    _initFuture = null;
    setAgent(null);
    _updateState(
      (s) => s.copyWith(messages: const LoadInProgress(), streamingText: ''),
    );
    await init();
  }

  /// Release resources. Call when the chat room is permanently closed.
  // ============================================================
  // SECTION 5: Dispose / teardown
  // ============================================================

  @override
  void dispose() {
    _teardownSubscriptions();
    super.dispose();
  }

  /// Cancel all stream subscriptions and timers without touching
  /// [_initFuture] or [_agent] — safe for both retry and dispose paths.
  void _teardownSubscriptions() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _toolCallSubscription?.cancel();
    _toolCallSubscription = null;
    _streaming.cancel();
    _outboxCountSubscription?.cancel();
    _outboxCountSubscription = null;
    _agentSubscription?.cancel(); // ★ 新增
    _agentSubscription = null; // ★ 新增
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _overallTimeoutTimer?.cancel();
    _overallTimeoutTimer = null;
    _preview.dispose();
    _messageReloadCoalesceTimer?.cancel();
    _messageReloadCoalesceTimer = null;
    // Bug 2 修复: 同步 [_streamsInitialized] 让 refreshAgent 知道
    // 下次 tombstone→alive 转换时需要重新订阅。
    _streamsInitialized = false;
    // Reset the connection-event seed guard so a subsequent retry()/init()
    // correctly skips the synthetic connected seed from
    // ReplayableConnectionState and avoids a redundant reloadMessages().
    _isInitialConnectionEvent = true;
  }
}
