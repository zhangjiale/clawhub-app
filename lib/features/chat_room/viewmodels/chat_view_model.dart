import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/i_message_backfill_client.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/core/i_api_logger.dart';
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

// ignore_for_file: prefer_initializing_formals — `this._logger` /
// `this._apiLogger` library-private initializing formals are blocked by the
// `_` prefix (Dart 2.17+ allows them but analyzer still flags); the explicit
// `_logger = logger ?? DebugPrintLogger()` form keeps the nullable default
// contract visible at the call site.

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

  /// 可选结构化诊断 logger —— 用于把 dedup 决策写入 DiagnosticsPage。
  ///
  /// nullable 是为了让现有 ~15 个 ChatViewModel 测试构造点不传参数(为 null)
  /// 时仍能编译通过 —— 不破坏测试兼容性。生产代码在 chat_providers.dart
  /// 注入 apiLoggerProvider。null 时所有埋点走 no-op,日志路径与行为不变。
  ///
  /// 背景:「重启 App 后历史变两份」类 bug 反复复发,根因是 dedup 路径完全
  /// 黑盒(0 处 ApiLogger 调用)。本字段让 ChatViewModel 在 merge +
  /// dedupeConversation 路径上有结构化日志,后续 diagnostics 页面能直接
  /// 看到每条入站消息走了哪个 dedup 分支。完整方案见 plan:
  /// `C:\Users\NING MEI\.claude\plans\enumerated-percolating-pascal.md`
  final IApiLogger? _apiLogger;

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

  /// sessionKey → clientId of the final agent message that closed the turn.
  ///
  /// ToolCalls stream keyed by `sessionKey` (`ToolCall.messageId`); the page
  /// looks them up by `message.clientId`. When the final message lands it
  /// re-keys any *early* ToolCalls (see [_rekeyToolCallForMessage]). This map
  /// also lets a *late* ToolCall (arriving after the final message) self-key
  /// by clientId — without it, a late ToolCall would stay keyed by sessionKey
  /// forever and never render (review #14). Bounded by turn count per session
  /// and cleared on teardown.
  final Map<String, String> _sessionKeyToClientId = {};

  /// sessionKey → clientId of the user message that triggered the turn.
  ///
  /// Used by the late-ToolCall self-key path (toolCallStream listener) so a
  /// ToolCall arriving after the final agent message re-keys to the user
  /// message (the trigger), not the agent message. The agent message
  /// re-key path at [_rekeyToolCallForMessage] uses [_findTriggerUserMessage]
  /// directly and does not read this map.
  ///
  /// Why a separate map: the same ToolCall must consistently attach to ONE
  /// owner (the user message). If both the early re-key (via
  /// `_rekeyToolCallForMessage`) and the late self-key (via this map) used
  /// different lookups, the same turn could end up with the ToolCall keyed
  /// to different clientIds depending on event timing, producing a phantom
  /// duplicate or a missing card.
  final Map<String, String> _sessionKeyToUserClientId = {};

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

  /// Configurable overall-response timeout — the hard ceiling that fires
  /// regardless of delta activity, preventing a trickling gateway (one char
  /// every <60s, which keeps resetting [_timeoutTimer]) from keeping the user
  /// waiting indefinitely. Defaults to 120s; tests inject a small value to
  /// exercise the timer in real async (mirrors [flushDelay]).
  @visibleForTesting
  final Duration overallTimeoutDelay;

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

  /// chat.message.get backfill 防重入:正在拉取完整内容的 clientId 集合。
  /// 用户连点「点击加载」或重试时,只允许一个 fetchSingleMessage 在途。
  /// cleared on teardown。
  final Set<String> _loadingMessageIds = {};

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
    this.overallTimeoutDelay = const Duration(seconds: 120),
    ILogger? logger,
    IApiLogger? apiLogger,
  }) : _logger = logger ?? const DebugPrintLogger(),
       _apiLogger = apiLogger,
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
              // Review #4: cancel the overall timer too — it is armed on
              // [send], not on first delta, so without this it keeps running
              // after a mid-stream disconnect and pops a "timeout" banner on
              // an already-offline page (no delta will ever arrive). Mirrors
              // [_onStreamError], which cancels both timers on stream error.
              _overallTimeoutTimer?.cancel();
              _overallTimeoutTimer = null;
            }
            // Post-sync reload is driven by catchUpCompletedTickerProvider
            // (wired in chatViewModelProvider), which fires AFTER
            // MessageCatchUpService completes — NOT by the transport `connected`
            // event, which arrives before catch-up and caused a redundant
            // premature reload + a stale-then-fresh flash. Outbox PENDING→SENT
            // flushes are picked up by outboxFlushTickerProvider. (review #15)
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
              // 用 mergeWithStatus 而非 merge —— 拿 wasNew/wasSkipped
              // 用于诊断日志。merge() 内部就是 mergeWithStatus,只是丢了
              // 这些字段;这里改用更完整的方法零行为变化(softMatch:false
              // 等同 merge 的软匹配关闭)。
              final mergeResult = await _mergeUseCase.mergeWithStatus(
                fixedMsg,
                softMatch: false,
              );
              _logMergeDecision(mergeResult, 'realtime');
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
              // Review #6: if the agent reply itself failed to persist, stop
              // the thinking spinner + clear streaming text — pre-fix the
              // listener returned here and the spinner spun until the 60s/
              // 120s timer, misleading (the reply did arrive, it just could
              // not be saved). Mirrors the normal agent-reply path
              // (onReplyArrived + _stopThinking below).
              if (fixedMsg.role == MessageRole.agent) {
                _streaming.onReplyArrived();
                _stopThinking();
              }
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
            if (fixedMsg.role == MessageRole.agent ||
                fixedMsg.role == MessageRole.toolResult) {
              // Re-key the turn's ToolCall from sessionKey → clientId so
              // the page's `toolCalls[message.clientId]` lookup finds it.
              // 对 toolResult 也要做:纯工具结果回合(无 agent 文本回复)中,
              // live ToolCall 一直 keyed by sessionKey,不重键就会 invisible。
              _rekeyToolCallForMessage(fixedMsg);
            }
            if (fixedMsg.role == MessageRole.agent) {
              // Clear streaming text when the final message lands —
              // eliminates the race window between StreamingDone and
              // Message arrival on independent broadcast controllers.
              _awaitingReply = false;
              _streaming.onReplyArrived();
              _stopThinking();
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
            // Defensive guard: if the processor's source fallback
            // [_resolveToolMessageId] returned '' (zero sessions
            // registered for this instance when the tool event arrived,
            // e.g. a race where the very first tool event lands before
            // any send() has registered a session), the ToolCall would
            // be keyed by '' in [state.toolCalls] and silently
            // disappear from the page's `toolCalls[message.clientId]`
            // lookup. Mirror the messageStream agent guard at line 571
            // and drop with a log — never pollute state with a sentinel
            // key that no real sessionKey can match.
            if (tc.messageId.isEmpty) {
              _logger.error(
                '[ChatViewModel] tool call ${tc.id} arrived with empty '
                'messageId; dropping (no resolvable sessionKey for '
                'instance $instanceId).',
              );
              return;
            }
            final current = Map<String, ToolCall>.from(state.toolCalls);
            // Key the live ToolCall by its OWN toolCallId (tc.id), NOT by the
            // message owner. A single turn can carry multiple tool calls that
            // all resolve to the same owner -- v2026.6.10 omits per-tool
            // sessionKey, so _resolveToolMessageId's LIFO fallback returns the
            // same sessionKey for every tool in the turn. Keying by owner
            // (clientId / sessionKey) would make them overwrite each other and
            // only the last tool call would render live, while history reload
            // (toolResult message rows, 1:N via groupToolResultsByOwner) shows
            // all of them -> "1 exec card live, multiple after restart".
            //
            // The messageId FIELD records the owner so the page can group tool
            // calls by message (chat_room_page._buildMessageList filters
            // `tc.messageId == message.clientId`), matching the reload path's
            // 1-owner-to-N-cards cardinality.
            //
            // Self-key: if the owner is already known (user message clientId
            // from _sendCore, or agent clientId from a prior rekey), stamp it
            // onto messageId now. Otherwise leave messageId = sessionKey,
            // pending _rekeyToolCallForMessage when the final message lands.
            //
            // Prefer the user-message clientId over the agent-message
            // clientId: the exec card must render below the user bubble
            // (the trigger), not below the agent bubble.
            final userClientId = _sessionKeyToUserClientId[tc.messageId];
            final agentClientId = _sessionKeyToClientId[tc.messageId];
            final ownerClientId = userClientId ?? agentClientId;
            current[tc.id] = ownerClientId != null
                ? tc.copyWith(messageId: ownerClientId)
                : tc;
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
          final mergeResult = await _mergeUseCase.mergeWithStatus(
            fixedMsg,
            softMatch: true,
            recent: recent,
          );
          _logMergeDecision(mergeResult, 'history');
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
          // 结构化诊断:让 diagnostics page 看到「这条会话这次清理了 N 条」
          // —— 与 merge 决策共用 state 前缀约定 'merge:dedupeDeleted'。
          _apiLogger?.logStateChange(
            instanceId: instanceId,
            state: 'merge:dedupeDeleted',
            message: 'count=$deleted path=history conv=$_conversationId',
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

    // Record sessionKey → user message clientId so the live ToolCall and
    // the late self-key path can both re-key the turn's ToolCall under
    // the user bubble (the trigger), not the agent bubble. sessionKey is
    // deterministic from the agent's remoteId per
    // `ws_gateway_client.sendMessage` (format: 'agent:<remoteId>:main'),
    // so we can compute it here without going through the ACL.
    //
    // Why this lives in _sendCore (not _findTriggerUserClientId which
    // looks up state.messages): the user message is just inserted; the
    // _loadMessages below is async; and the agent reply can arrive on
    // the messageStream listener BEFORE this await _loadMessages
    // completes — at which point state.messages may not yet contain
    // the user row. The send-side registration is race-free because it
    // runs synchronously after the user message is persisted.
    _sessionKeyToUserClientId['agent:${agent!.remoteId}:main'] =
        sentMessage.clientId;

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
      _armOverallTimeout();
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

  /// Continue waiting — dismiss the timeout banner and restart both timers.
  ///
  /// Re-arms [_overallTimeoutTimer] (review #11) so the documented "no
  /// indefinite trickle" invariant survives a user-dismissed timeout. Pre-fix
  /// this only re-armed the 60s per-delta timer via [_startThinking], so a
  /// trickling gateway could keep the user waiting forever after one dismiss.
  void continueWaiting() {
    _startThinking();
    _armOverallTimeout();
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

  /// (Re-)arm the overall-response timeout ([_overallTimeoutTimer]).
  ///
  /// Extracted from [_sendCore] so [continueWaiting] can re-arm it after a
  /// user-dismissed timeout (review #11). Cancels any prior instance first
  /// to avoid stacking callbacks.
  void _armOverallTimeout() {
    _overallTimeoutTimer?.cancel();
    _overallTimeoutTimer = Timer(overallTimeoutDelay, () {
      _updateState((s) => s.copyWith(thinkingState: ThinkingState.timeout));
    });
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
  /// Tolerance for the preview future-skew guard (review #10). A message
  /// timestamp more than this far ahead of the client clock is treated as
  /// server clock skew (catch-up replay) and does not advance
  /// [Conversation.lastMessageTime]. 5 min accommodates real NTP drift
  /// while catching the +N-minute skew from catch-up replays.
  static const int _previewClockSkewToleranceMs = 5 * 60 * 1000;

  Future<void> _updateConversationPreview(Message message) async {
    try {
      // 护栏：乱序/重发旧消息不得回卷 lastMessageTime。
      final current = await _conversationRepo.getById(_conversationId);
      if (current != null &&
          message.timestamp < current.lastMessageTime &&
          message.clientId != current.lastMessageId) {
        return;
      }

      // Review #10: future-skew guard. A catch-up replay with a server clock
      // ahead of the client passes the rewind guard above (its timestamp is
      // greater than lastMessageTime) and would push lastMessageTime into
      // the future, freezing the conversation-list preview until a real-time
      // message with an even-larger timestamp arrives. A real message cannot
      // arrive from the future; a timestamp beyond now + tolerance is clock
      // skew — skip the preview update (the message still renders, driven by
      // logicalClock).
      final now = DateTime.now().millisecondsSinceEpoch;
      if (message.timestamp > now + _previewClockSkewToleranceMs) {
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

  /// Re-key the turn's ToolCall from `sessionKey` → the user message's
  /// clientId (the trigger for this turn) so the page's
  /// `toolCalls[message.clientId]` lookup (chat_room_page
  /// `_buildMessageList`) finds it under the user bubble — not the
  /// agent bubble. The processor tags agent messages with
  /// `metadata['sessionKey']`; ToolCalls arrive keyed by the same
  /// sessionKey (`ToolCall.messageId = event.sessionKey`). Pre-fix the
  /// ToolCall was re-keyed to the agent's clientId, which placed the
  /// exec card below the agent bubble; the expected UX is below the
  /// user bubble (between user and agent in the reverse-list view).
  ///
  /// Also records the sessionKey → user/agent clientId mappings so:
  /// - A *late* ToolCall (arriving AFTER this final message) can
  ///   self-key by user clientId via the ToolCall listener
  ///   (`_sessionKeyToUserClientId`) — otherwise it would stay keyed
  ///   by sessionKey and never render (review #14).
  /// - The agent clientId is kept as a fallback for the narrow case
  ///   where no user message precedes the agent (tool-only turn).
  ///
  /// **Cross-file contract (R2):** this function MUST be called for both
  /// [MessageRole.agent] and [MessageRole.toolResult] final messages —
  /// the chat_room_page live ToolCall lookup at `_buildMessageList`
  /// orphan-toolResult branch depends on the re-key having happened;
  /// if you narrow the callers to agent-only, orphan toolResults in
  /// pure-tool turns will render with an invisible ToolCall
  /// (`toolCalls[toolResult.clientId] == null`) and fall through to
  /// `toolCallFromMessage` reconstruction, losing any running state.
  void _rekeyToolCallForMessage(Message msg) {
    final sk = msg.metadata?['sessionKey'];
    if (sk is! String) return;
    _sessionKeyToClientId[sk] = msg.clientId;
    // Use the user-message clientId recorded at send time ([_sendCore])
    // — the user message is the trigger for the turn, and the exec card
    // must render under the user bubble, not the agent bubble. Fallback
    // to the agent's own clientId for tool-only turns with no
    // preceding user send (e.g. a background tool run that arrives
    // without a recent _sendCore registration).
    //
    // The previous heuristic — looking up `state.messages` for the
    // most recent user row with logicalClock < agentMsg.logicalClock —
    // was racy: the agent reply can arrive on the messageStream
    // listener before `_loadMessages` (scheduled in [_sendCore]) has
    // re-read the user row, so state.messages may not yet contain
    // the trigger. send-side registration in [_sendCore] is
    // race-free because it runs synchronously after the user message
    // is persisted.
    final triggerClientId = _sessionKeyToUserClientId[sk] ?? msg.clientId;
    // Re-key ALL live ToolCalls currently owned by sessionKey `sk` (could be
    // multiple in a multi-tool turn). Live tool calls are keyed by toolCallId
    // (tc.id), so we update the messageId FIELD, not the map key. Pre-fix the
    // map was keyed by owner and this did a single state.toolCalls[sk] lookup
    // -> only the survivor of the per-owner overwrite was re-keyed; the rest
    // stayed stranded on sessionKey and the page's owner lookup never found
    // them -> invisible live, visible after restart (symptom 1).
    var changed = false;
    final rekeyed = Map<String, ToolCall>.from(state.toolCalls);
    // Snapshot entries before mutating values so the iteration is safe.
    for (final entry in rekeyed.entries.toList()) {
      if (entry.value.messageId == sk) {
        rekeyed[entry.key] = entry.value.copyWith(messageId: triggerClientId);
        changed = true;
      }
    }
    if (!changed) return; // No early ToolCall to re-key; mapping recorded
    // above lets a late ToolCall self-key.
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

  /// Lazy backfill of a chat.history omitted placeholder via `chat.message.get`.
  ///
  /// 当消息因 chat.history display-normalization 被替换为占位符
  /// `[chat.history omitted: message too large]` 时，ACL mapper 置
  /// `metadata.contentOmitted = true`。UI 据此渲染「点击加载」气泡，用户点击
  /// 触发本方法拉取原始完整内容。
  ///
  /// 流程：
  /// 1. 守卫：消息存在、contentOmitted 为 true、未在拉取中。
  /// 2. 能力探测：gateway 必须实现 [IMessageBackfillClient]（真实客户端实现，
  ///    纯 IGatewayClient fake 不实现）。不支持时走 retryFeedback 降级。
  /// 3. 守卫：serverId 非空（作为 chat.message.get 的 messageId）。
  /// 4. 调 [IMessageBackfillClient.fetchSingleMessage]。
  /// 5. 成功：用真实内容 + 清除标志更新 DB 行（updateContentTypeAndMetadata，
  ///    FTS5 自动重索引使回填内容可搜索），reload。
  /// 6. 失败/null：rethrow，widget 据此展示「加载失败，点击重试」。
  Future<void> loadFullMessage(String clientId) async {
    // 1. 在当前 state 中找到该消息。
    final loaded = state.messages;
    if (loaded is! LoadData<List<Message>>) return;
    final list = loaded.value;
    Message? msg;
    for (var i = 0; i < list.length; i++) {
      if (list[i].clientId == clientId) {
        msg = list[i];
        break;
      }
    }
    if (msg == null) return; // 消息不在当前列表（已滚动出视野 / 已删）

    // 守卫：必须是 omitted 占位消息。
    if (msg.metadata?['contentOmitted'] != true) return;

    // 防重入：连点 / 重试时只允许一个 fetchSingleMessage 在途。
    if (_loadingMessageIds.contains(clientId)) return;
    _loadingMessageIds.add(clientId);
    try {
      // 2. 能力探测：gateway 不实现 IMessageBackfillClient 时降级。
      //    显式赋给强类型局部变量，避免在 try/await 跨语句下 smart-cast 失效。
      final IMessageBackfillClient backfill;
      if (_gatewayClient is IMessageBackfillClient) {
        backfill = _gatewayClient as IMessageBackfillClient;
      } else {
        _updateState((s) => s.copyWith(retryFeedback: '当前网关不支持加载完整消息'));
        return;
      }

      // 3. 守卫：需要 serverId 作为 chat.message.get 的 messageId。
      final serverId = msg.serverId;
      if (serverId == null || serverId.isEmpty) {
        _updateState((s) => s.copyWith(retryFeedback: '该消息缺少 ID，无法加载完整内容'));
        return;
      }

      // agent.remoteId 构造 sessionKey（agent:{remoteId}:main），与 chat.send 对齐。
      final activeAgent = agent;
      if (activeAgent == null) {
        _updateState((s) => s.copyWith(retryFeedback: 'Agent 信息缺失，无法加载完整内容'));
        return;
      }

      // 4. 拉取完整消息。
      final full = await backfill.fetchSingleMessage(
        instanceId: instanceId,
        agentId: activeAgent.remoteId,
        messageId: serverId,
      );
      if (full == null) {
        throw Exception(
          'chat.message.get returned null for messageId=$serverId',
        );
      }

      // 5. 用真实内容更新 DB 行，清除 contentOmitted 标志。FTS5 自动重索引。
      final cleanedMetadata = Map<String, dynamic>.from(
        full.metadata ?? const {},
      );
      cleanedMetadata.remove('contentOmitted');
      await _messageRepo.updateContentTypeAndMetadata(
        serverId,
        content: full.content,
        type: full.type,
        metadata: cleanedMetadata,
      );
      _apiLogger?.logStateChange(
        instanceId: instanceId,
        state: 'backfill:success',
        message: 'clientId=$clientId serverId=$serverId',
      );
      await _loadMessages();
    } catch (error, stackTrace) {
      _logger.error(
        '[ChatViewModel] loadFullMessage failed for $clientId: $error',
        stackTrace,
      );
      rethrow; // widget 据此展示「加载失败，点击重试」
    } finally {
      _loadingMessageIds.remove(clientId);
    }
  }

  void _updateState(ChatSessionState Function(ChatSessionState) transform) {
    if (!mounted) return;
    state = transform(state);
  }

  /// 记录一次 dedup 决策到结构化诊断日志。
  ///
  /// 诊断约定(state 前缀 `merge:`):
  /// - `merge:hit:dedup`     — 命中已有行(clientId / serverId / 软匹配)
  /// - `merge:inserted:new`  — 真新插入(Branch 4 命中,didup 全 miss)
  /// - `merge:enriched`      — serverId 命中且内容更完整,触发富化 upsert
  /// - `merge:skipped:emptyContent` — 空内容丢弃(网关历史里的空气泡)
  /// - `merge:dedupeDeleted` — dedupeConversation 清理 N 条历史重复
  ///
  /// [path] 区分实时流(`realtime`)和历史 pull(`history`)两条路径,
  /// 便于诊断「重启后历史变两份」时区分问题来自 catch-up 还是 chat init。
  ///
  /// null logger 时静默返回 —— 现有 ~15 个测试构造点不传 apiLogger,
  /// 这里确保它们继续工作。
  void _logMergeDecision(MergeResult result, String path) {
    final apiLogger = _apiLogger;
    if (apiLogger == null) return;
    final m = result.message;
    final outcome = result.wasSkipped
        ? 'skipped:emptyContent'
        : (result.wasNew ? 'inserted:new' : 'hit:dedup');
    apiLogger.logStateChange(
      instanceId: instanceId,
      state: 'merge:$outcome',
      message:
          'path=$path '
          'clientId=${m.clientId} '
          'serverId=${m.serverId ?? "-"} '
          'role=${m.role.name} '
          'conv=${m.conversationId}',
      // payloadPreview 让 diagnostics 页显示 ▼ 展开按钮 —— 「重启后多出
      // agent 消息」类 bug 的核心诊断可见性。
      payloadPreview: m.content,
    );
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
    // Drop sessionKey → clientId mappings from prior turns (review #14).
    _sessionKeyToClientId.clear();
    _sessionKeyToUserClientId.clear();
    _loadingMessageIds.clear();
  }
}
