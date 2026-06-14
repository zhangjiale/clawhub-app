import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
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

  const ChatSessionState({
    this.messages = const LoadInProgress(),
    this.thinkingState = ThinkingState.idle,
    this.connectionState = GatewayConnectionState.disconnected,
    this.toolCalls = const {},
    this.streamingText = '',
  });

  ChatSessionState copyWith({
    LoadState<List<Message>>? messages,
    ThinkingState? thinkingState,
    GatewayConnectionState? connectionState,
    Map<String, ToolCall>? toolCalls,
    String? streamingText,
  }) {
    return ChatSessionState(
      messages: messages ?? this.messages,
      thinkingState: thinkingState ?? this.thinkingState,
      connectionState: connectionState ?? this.connectionState,
      toolCalls: toolCalls ?? this.toolCalls,
      streamingText: streamingText ?? this.streamingText,
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
          streamingText == other.streamingText;

  @override
  int get hashCode => Object.hash(
    thinkingState,
    connectionState,
    messages,
    toolCalls,
    streamingText,
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
  final IGatewayClient _gatewayClient;
  final SendMessageUseCase _sendMessageUseCase;
  final String instanceId;
  final String agentId;

  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<GatewayConnectionState>? _connectionSubscription;
  StreamSubscription<ToolCall>? _toolCallSubscription;
  StreamSubscription<StreamingEvent>? _streamingSubscription;
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

  /// Monotonically increasing counter — incremented on each [send].
  /// The streaming listener captures its value and drops deltas from
  /// stale generations, preventing response A's deltas from leaking
  /// into response B's accumulated text when the user sends a follow-up
  /// message before the agent finishes replying to the first.
  int _sendGeneration = 0;

  /// Configurable flush delay for streaming text state updates.
  ///
  /// Defaults to 150ms to match [StreamingBubble]'s MarkdownBody debounce.
  /// Set to [Duration.zero] in tests for synchronous assertions.
  @visibleForTesting
  final Duration flushDelay;

  /// Cached future for [init] so [send] can await initialization if the
  /// user sends a message before [init] completes.
  Future<void>? _initFuture;

  /// Called when stats should be refreshed (message sent or received).
  VoidCallback? onStatsChanged;

  ChatViewModel({
    required IAgentRepo agentRepo,
    required IConversationRepo conversationRepo,
    required IMessageRepo messageRepo,
    required IGatewayClient gatewayClient,
    required SendMessageUseCase sendMessageUseCase,
    required this.instanceId,
    required this.agentId,
    this.flushDelay = const Duration(milliseconds: 150),
  }) : _agentRepo = agentRepo,
       _conversationRepo = conversationRepo,
       _messageRepo = messageRepo,
       _gatewayClient = gatewayClient,
       _sendMessageUseCase = sendMessageUseCase,
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
            _updateState((s) => s.copyWith(connectionState: state));
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
              await _messageRepo.insert(msg);
              await _loadMessages();
              if (msg.role == MessageRole.agent) {
                // Clear streaming text when the final message lands —
                // eliminates the race window between StreamingDone and
                // Message arrival on independent broadcast controllers.
                _updateState((s) => s.copyWith(streamingText: ''));
                _stopThinking();
                onStatsChanged?.call();
              }
            },
            onError: (error, stackTrace) {
              debugPrint(
                'Message stream error for $instanceId: $error\n$stackTrace',
              );
            },
          );

      // 5b. Tool call events
      _toolCallSubscription = _gatewayClient.toolCallStream(instanceId).listen((
        tc,
      ) {
        final current = Map<String, ToolCall>.from(state.toolCalls);
        current[tc.messageId] = tc;
        _updateState((s) => s.copyWith(toolCalls: current));
      });

      // 5c. Streaming deltas (filtered by agentId)
      // Capture remoteId locally — _agent is guaranteed non-null at this
      // point (early return above), but a retry() could race the closure.
      final agentRemoteId = _agent!.remoteId;
      _streamingSubscription = _gatewayClient
          .streamingDeltaStream(instanceId)
          .listen(
            (event) {
              // Snapshot the send generation at callback entry.  Used below to
              // guard StreamingDone so a stale "done" from a previous send()
              // does not clear text accumulated by a newer send().
              final myGen = _sendGeneration;
              // Route to the correct agent — ignore events for other agents
              if (event is StreamingDelta && event.agentId == agentRemoteId) {
                // Cap at 50KB to prevent unbounded growth (DoS / Gateway bug).
                if (_streamBuffer.length < 50 * 1024) {
                  _streamBuffer.write(event.text);
                  _scheduleFlush();
                }
                // Reset thinking timer on each delta arrival
                _timeoutTimer?.cancel();
                _timeoutTimer = Timer(const Duration(seconds: 60), () {
                  _updateState(
                    (s) => s.copyWith(thinkingState: ThinkingState.timeout),
                  );
                });
                // Reset stall timeout on each delta
                _stallTimer?.cancel();
                _stallTimer = Timer(const Duration(seconds: 30), () {
                  _updateState((s) => s.copyWith(streamingText: ''));
                });
              } else if (event is StreamingDone &&
                  event.agentId == agentRemoteId) {
                // Only clear text if the generation hasn't changed — prevents
                // a stale StreamingDone from response A from wiping text that
                // belongs to response B (concurrent send interleaving guard).
                if (myGen == _sendGeneration) {
                  _flushImmediately();
                  _stallTimer?.cancel();
                  _updateState((s) => s.copyWith(streamingText: ''));
                }
              }
            },
            onError: (error, stackTrace) {
              _flushImmediately();
              _stallTimer?.cancel();
              _timeoutTimer?.cancel();
              _updateState((s) => s.copyWith(streamingText: ''));
              debugPrint(
                'Streaming stream error for $instanceId: $error\n$stackTrace',
              );
            },
          );
      // 6. Fetch message history from Gateway (best-effort).
      //    Placed AFTER real-time subscriptions so that events arriving
      //    during the fetch RTT are captured, not lost.
      final remoteId = _agent!.remoteId;
      try {
        final history = await _gatewayClient.fetchMessageHistory(
          instanceId: instanceId,
          agentId: remoteId,
        );
        for (final msg in history.messages) {
          await _messageRepo.insert(msg);
        }
        await _loadMessages();
      } catch (error, stackTrace) {
        debugPrint(
          'History fetch failed for $instanceId/$remoteId: $error\n$stackTrace',
        );
      }
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

  /// Send a text message.
  ///
  /// If [init] hasn't completed yet, awaits it first so the user's message
  /// is never silently dropped.  If the agent doesn't exist (or init failed),
  /// surfaces a [LoadError] so the UI can show a meaningful message.
  Future<void> send(String text) async {
    // Reset streaming state and bump generation — prevents stale partial
    // text from a disconnected or concurrent stream contaminating the new
    // response.  The streaming listener captures the generation and drops
    // deltas from previous sends.
    _sendGeneration++;
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

    final sentMessage = await _sendMessageUseCase.execute(
      instanceId: instanceId,
      agent: _agent!,
      content: text,
      type: MessageType.text,
    );

    await _loadMessages();

    // Only start "thinking" state when the message was successfully sent.
    // - FAILED: the Gateway rejected or couldn't reach the message;
    //   no agent reply will ever arrive, so thinking would spin forever.
    // - PENDING: the instance is offline; the message is waiting in the
    //   outbox and will be retried later.
    if (sentMessage.status == MessageStatus.sent) {
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

    onStatsChanged?.call();
  }

  /// Dismiss the timeout banner and cancel waiting.
  void dismissTimeout() {
    _stopThinking();
  }

  /// Continue waiting — dismiss the timeout banner and restart the timer.
  void continueWaiting() {
    _startThinking();
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
      _updateState((s) => s.copyWith(messages: LoadError(error, stackTrace)));
    }
  }

  void _updateState(ChatSessionState Function(ChatSessionState) transform) {
    state = transform(state);
  }

  /// Retry initialization after a previous failure.
  ///
  /// Call this from the UI's retry button (e.g. [LoadErrorView.onRetry]).
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
