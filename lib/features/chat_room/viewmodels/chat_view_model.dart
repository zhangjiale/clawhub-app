import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
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
          highlightedQuery == other.highlightedQuery;

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
class ChatViewModel extends StateNotifier<ChatSessionState> {
  final IAgentRepo _agentRepo;
  final IConversationRepo _conversationRepo;
  final IMessageRepo _messageRepo;
  final IInstanceRepo _instanceRepo;
  final IGatewayClient _gatewayClient;
  final SendMessageUseCase _sendMessageUseCase;
  final IAchievementChecker _achievementChecker;
  final String instanceId;
  final String agentId;

  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<GatewayConnectionState>? _connectionSubscription;
  StreamSubscription<ToolCall>? _toolCallSubscription;
  StreamSubscription<StreamingEvent>? _streamingSubscription;
  StreamSubscription<int>? _outboxCountSubscription;
  Timer? _timeoutTimer;
  Timer? _stallTimer;

  /// Overall response timer — starts once on [send], never reset by deltas.
  /// Guarantees the user sees a timeout even when the Gateway trickles data
  /// indefinitely (every delta resets [_timeoutTimer], so without this
  /// separate timer, the user could wait forever).
  Timer? _overallTimeoutTimer;

  /// Streaming text accumulator — buffers delta text and publishes
  /// incrementally through [ChatSessionState.streamingText].
  ///
  /// [StringBuffer.write] is amortized O(1) per append, replacing the
  /// O(n²) `state.streamingText + event.text` pattern (see #12).
  final StringBuffer _streamBuffer = StringBuffer();

  /// How many code-units of [_streamBuffer] have been published to state.
  /// Reset to 0 on each new send generation.  Used for incremental
  /// publishing — only the diff since last flush is new allocation.
  int _lastPublishedLength = 0;

  /// Debounce timer for throttled state writes.
  Timer? _flushTimer;
  Agent? _agent;

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

  /// 是否正在接收流式回复增量（首个 [StreamingDelta] 到达后置 true，
  /// [StreamingDone]/回复到达/流错误后置 false）。
  ///
  /// 用途：clear-cache tick 触发的 [reloadMessages] 在此期间跳过——
  /// 清缓存后 DB 已空，若流式中重载会让 `state.messages` 闪空；
  /// 流式文本累积在独立的 `_streamBuffer`/`streamingText`，不受影响。
  /// 流式结束（最终回复落库）后，messageStream 监听器会调
  /// [_loadMessages] 自然刷新到含新回复的列表。
  bool _isStreaming = false;

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
  /// 决定是否触发温和刷新（流式中跳过）。
  bool get isStreaming => _isStreaming;

  /// 激活时，实时消息监听器跳过 `_loadMessages()` 以避免覆盖高亮锚定窗口。
  /// 由 [loadHighlightWindow] 设置，在 [clearHighlight] 或 2 秒后清除。
  bool _highlightActive = false;

  /// Called when stats should be refreshed (message sent or received).
  VoidCallback? onStatsChanged;

  // ============================================================
  // SECTION 2: Constructor + field wiring
  // ============================================================

  ChatViewModel({
    required IAgentRepo agentRepo,
    required IConversationRepo conversationRepo,
    required IMessageRepo messageRepo,
    required IInstanceRepo instanceRepo,
    required IGatewayClient gatewayClient,
    required SendMessageUseCase sendMessageUseCase,
    required IAchievementChecker achievementChecker,
    required this.instanceId,
    required this.agentId,
    this.flushDelay = const Duration(milliseconds: 150),
  }) : _agentRepo = agentRepo,
       _conversationRepo = conversationRepo,
       _messageRepo = messageRepo,
       _instanceRepo = instanceRepo,
       _gatewayClient = gatewayClient,
       _sendMessageUseCase = sendMessageUseCase,
       _achievementChecker = achievementChecker,
       super(const ChatSessionState());

  /// The loaded agent (null until [init] completes).
  Agent? get agent => _agent;

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
      _agent = await _agentRepo.getById(agentId);
      if (_agent == null) {
        debugPrint(
          '[ChatViewModel] Agent not found: agentId=$agentId, '
          'instanceId=$instanceId — chat unavailable.',
        );
        // Early return: without an agent, streaming/message routing is
        // impossible (requires agentId for filtering).  The UI will show
        // LoadError via [send()] if the user attempts to send.
        return;
      }

      // 2. Get or create conversation (idempotent)
      await _conversationRepo.getOrCreate(instanceId, agentId);

      // 3. Load local messages immediately (fast path)
      await _loadMessages();

      // 4. Subscribe to connection state
      _connectionSubscription = _gatewayClient
          .connectionStateStream(instanceId)
          .listen((state) {
            final wasInitial = _isInitialConnectionEvent;
            _isInitialConnectionEvent = false;
            _updateState((s) => s.copyWith(connectionState: state));
            // 连接断开/恢复路径必须重置 _isStreaming —— 否则一次中途
            // 网关掉线（无 StreamingDone）会让 reloadMessages 在
            // `if (_isStreaming) return;` 处永远早退，导致
            // cacheClearedTickProvider++ 后聊天列表保留旧的（清理前）快照。
            // Streaming 终态（StreamingDone / agent Message / send / onError
            // / dispose）已经在各自路径处理；这里只覆盖「连接层异常」
            // 这个原本没被任何路径覆盖的边界。
            if (state != GatewayConnectionState.connected &&
                state != GatewayConnectionState.connecting &&
                state != GatewayConnectionState.authenticating &&
                _isStreaming) {
              _isStreaming = false;
              _streamBuffer.clear();
              _lastPublishedLength = 0;
              _stallTimer?.cancel();
              _stallTimer = null;
              _timeoutTimer?.cancel();
              _timeoutTimer = null;
              _updateState((s) => s.copyWith(streamingText: ''));
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
          });

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
              final agentRemoteId = _agent?.remoteId;
              if (agentRemoteId != null &&
                  msg.agentId.isNotEmpty &&
                  msg.agentId != agentRemoteId) {
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
                await _messageRepo.insert(fixedMsg);
              } catch (error, stackTrace) {
                // iron-law-allow: Law8 — 兜底:即使 clearAll 保留骨架,任何
                // FK/约束冲突也不应静默吞掉后续逻辑。旧实现异常会中断
                // _updateConversationPreview 与 _loadMessages,使消息列表
                // 卡在空状态。记日志后 return,等下一条消息正常处理。
                debugPrint(
                  '[ChatViewModel] message insert failed for '
                  '${fixedMsg.clientId}: $error\n$stackTrace',
                );
                return;
              }
              // 同步会话预览 —— 让消息中心展示「真正的最后一条消息」。
              // 此前 updateLastMessage 仅在用户发送时被调用，导致预览永远
              // 停留在「我」的最后一条消息，掩盖了 Agent 的最新回复。
              // 这里用与 SendMessageUseCase 相同的预览规则，保证两侧一致。
              await _updateConversationPreview(fixedMsg);
              // 高亮激活期间跳过全量重载 — loadHighlightWindow 设置的有界窗口优先。
              if (!_highlightActive) {
                await _loadMessages();
              }
              if (fixedMsg.role == MessageRole.agent) {
                // Clear streaming text when the final message lands —
                // eliminates the race window between StreamingDone and
                // Message arrival on independent broadcast controllers.
                _awaitingReply = false;
                _isStreaming = false;
                _updateState((s) => s.copyWith(streamingText: ''));
                _stopThinking();
                onStatsChanged?.call();
                // Fire-and-forget achievement evaluation — deferred to
                // agent reply arrival so stats include the latest message
                // and don't contend with concurrent streaming inserts.
                _achievementChecker.check(agentId);
              }
            },
            onError: (error, stackTrace) {
              debugPrint(
                'Message stream error for $instanceId: $error\n$stackTrace',
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
              debugPrint(
                'Tool call stream error for $instanceId: $error\n$stackTrace',
              );
            },
          );

      // 5c. Streaming deltas — subscription is recreated on each send()
      //     so stale events from a previous response never contaminate
      //     the current buffer (no generation-guard needed).
      _startStreaming();
      // 6. Fetch message history from Gateway (best-effort).
      //    Placed AFTER real-time subscriptions so that events arriving
      //    during the fetch RTT are captured, not lost.
      final remoteId = _agent!.remoteId;
      try {
        final history = await _gatewayClient.fetchMessageHistory(
          instanceId: instanceId,
          agentId: remoteId,
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
            await _messageRepo.insert(fixedMsg);
          } catch (error, stackTrace) {
            // iron-law-allow: Law8 — 历史拉取的逐条兜底,与 messageStream
            // 路径一致,单条 FK 冲突不应中断整批导入。
            debugPrint(
              '[ChatViewModel] history insert failed for '
              '${fixedMsg.clientId}: $error\n$stackTrace',
            );
          }
        }
        await _loadMessages();
      } catch (error, stackTrace) {
        debugPrint(
          'History fetch failed for $instanceId/$remoteId: $error\n$stackTrace',
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
              debugPrint(
                '[ChatViewModel] outbox count stream error for $instanceId: '
                '$error\n$stack',
              );
            },
          );
    } catch (error, stackTrace) {
      debugPrint(
        '[ChatViewModel] init failed for $instanceId/$agentId: $error\n$stackTrace',
      );
      // Tear down any subscriptions that were set up before the failure
      // so a subsequent retry() or send() starts from a clean slate.
      _teardownSubscriptions();
      // Clear the cached future so the next init() / send() call will
      // retry instead of instantly returning the failed future.
      _initFuture = null;
      // Signal to send() that the agent is unavailable (shows LoadError).
      _agent = null;
    }
  }

  // ============================================================
  // SECTION 3: Send + thinking state management
  // ============================================================

  /// Send a text message.
  ///
  /// If [init] hasn't completed yet, awaits it first so the user's message
  /// is never silently dropped.  If the agent doesn't exist (or init failed),
  /// surfaces a [LoadError] so the UI can show a meaningful message.
  Future<void> send(String text) async {
    // Tear down the old streaming subscription so stale deltas/done
    // events from a previous response never contaminate the new buffer.
    // A fresh subscription is created below after init() succeeds.
    _streamingSubscription?.cancel();
    _streamingSubscription = null;
    _isStreaming = false;
    _flushTimer?.cancel();
    _streamBuffer.clear();
    _lastPublishedLength = 0;
    _stallTimer?.cancel();
    _stallTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _updateState((s) => s.copyWith(streamingText: ''));

    await init();

    if (_agent == null) {
      _updateState(
        (s) => s.copyWith(
          messages: LoadError(
            'Agent not found. '
            'It may have been removed. Please go back and try again.',
            StackTrace.current,
          ),
        ),
      );
      debugPrint(
        '[ChatViewModel] send() blocked: agent $agentId not found '
        'in instance $instanceId.',
      );
      return;
    }

    // Start a fresh streaming subscription for this send — any stale
    // events from the previous subscription were already cancelled above.
    _startStreaming();

    _awaitingReply = true;

    final sentMessage = await _sendMessageUseCase.execute(
      instanceId: instanceId,
      agent: _agent!,
      content: text,
      type: MessageType.text,
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

  /// Create a fresh streaming subscription for the current [send].
  ///
  /// Must be called AFTER [_agent] is guaranteed non-null.  Each call
  /// cancels any previous [_streamingSubscription] so that stale
  /// [StreamingDelta]/[StreamingDone] events from a prior response
  /// never contaminate the current buffer.
  void _startStreaming() {
    _streamingSubscription?.cancel();

    final agentRemoteId = _agent!.remoteId;
    _streamingSubscription = _gatewayClient
        .streamingDeltaStream(instanceId)
        .listen(
          (event) {
            if (event is StreamingDelta && event.agentId == agentRemoteId) {
              _isStreaming = true;
              if (_streamBuffer.length < 50 * 1024) {
                _streamBuffer.write(event.text);
                _scheduleFlush();
              }
              _timeoutTimer?.cancel();
              _timeoutTimer = Timer(const Duration(seconds: 60), () {
                _updateState(
                  (s) => s.copyWith(thinkingState: ThinkingState.timeout),
                );
              });
              _stallTimer?.cancel();
              _stallTimer = Timer(const Duration(seconds: 30), () {
                _updateState((s) => s.copyWith(streamingText: ''));
              });
            } else if (event is StreamingDone &&
                event.agentId == agentRemoteId) {
              _isStreaming = false;
              _flushImmediately();
              _stallTimer?.cancel();
              _updateState((s) => s.copyWith(streamingText: ''));
            }
          },
          onError: (error, stackTrace) {
            _isStreaming = false;
            _flushImmediately();
            _stallTimer?.cancel();
            _timeoutTimer?.cancel();
            _updateState((s) => s.copyWith(streamingText: ''));
            debugPrint(
              'Streaming stream error for $instanceId: $error\n$stackTrace',
            );
          },
        );
  }

  /// Schedule a throttled flush — cancels pending timer, sets new one.
  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(flushDelay, _flushToState);
  }

  /// Publish accumulated buffer text to [ChatSessionState.streamingText].
  void _flushToState() {
    final full = _streamBuffer.toString();
    if (full.length == _lastPublishedLength) return; // no new content
    _updateState((s) => s.copyWith(streamingText: full));
    _lastPublishedLength = full.length;
  }

  /// Flush immediately — used at stream termination.
  void _flushImmediately() {
    _flushTimer?.cancel();
    _flushToState();
  }

  void _startThinking() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      _updateState((s) => s.copyWith(thinkingState: ThinkingState.timeout));
    });
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
      debugPrint(
        '[ChatViewModel] _loadMessages failed for $_conversationId: '
        '$error\n$stackTrace',
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
  /// 两道护栏（避免把预览写坏）：
  /// - 仅对人类可读的消息类型生效。[MessageType.toolCall] 走专用 UI，
  ///   其预览是字面量 `[工具调用]`，若覆盖会话预览会让消息中心列表显示
  ///   无意义的「[工具调用]」而非真正的最后一句对话。
  /// - 仅当新消息不早于当前会话尾端时才覆盖 [Conversation.lastMessageTime]。
  ///   messageStream 是广播流，乱序/重发的旧事件会触发本方法；若无此护栏，
  ///   一条迟到的旧消息会把会话在列表里「拉回过去」（lastMessageTime 驱动
  ///   消息中心的 DESC 排序）。
  Future<void> _updateConversationPreview(Message message) async {
    // 护栏 1：toolCall 等非对话消息不更新预览。
    if (message.type == MessageType.toolCall) return;

    try {
      // 护栏 2：乱序/重发旧消息不得回卷 lastMessageTime。
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
      debugPrint(
        '[ChatViewModel] updateLastMessage failed for $_conversationId: '
        '$error\n$stackTrace',
      );
    }
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
  /// 自然刷新。[_isStreaming] 由首个 delta 置 true、StreamingDone/回复到达
  /// 置 false。
  Future<void> reloadMessages() async {
    if (_isStreaming) return;
    await _loadMessages();
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
    if (agent == null) {
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
      debugPrint(
        '[ChatViewModel] retryMessage failed for $clientId: $error\n$stackTrace',
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
      debugPrint(
        '[ChatViewModel] loadHighlightWindow failed '
        'for target=$targetClientId: $error\n$stackTrace',
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
    _flushTimer?.cancel();
    _streamBuffer.clear();
    _lastPublishedLength = 0;
    _initFuture = null;
    _agent = null;
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
    _streamingSubscription?.cancel();
    _streamingSubscription = null;
    _isStreaming = false;
    _outboxCountSubscription?.cancel();
    _outboxCountSubscription = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _stallTimer?.cancel();
    _stallTimer = null;
    _overallTimeoutTimer?.cancel();
    _overallTimeoutTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
