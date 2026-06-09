import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';

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
/// Exposes reactive notifiers so the widget observes and calls [send].
class ChatViewModel extends ChangeNotifier {
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
  Timer? _timeoutTimer;
  Agent? _agent;

  /// Reactive messages notifier — the single source of truth for the UI.
  final ValueNotifier<LoadState<List<Message>>> messagesNotifier =
      ValueNotifier(const LoadInProgress());

  /// Whether the agent is currently "thinking" (user sent a message, no reply yet).
  final ValueNotifier<bool> isThinkingNotifier = ValueNotifier(false);

  /// Current connection state.
  final ValueNotifier<GatewayConnectionState> connectionStateNotifier =
      ValueNotifier(GatewayConnectionState.disconnected);

  /// Whether a timeout occurred (agent took >60s to reply).
  final ValueNotifier<bool> timeoutNotifier = ValueNotifier(false);

  /// Tool calls keyed by messageId.
  final ValueNotifier<Map<String, ToolCall>> toolCallsNotifier =
      ValueNotifier({});

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
  })  : _agentRepo = agentRepo,
        _conversationRepo = conversationRepo,
        _messageRepo = messageRepo,
        _gatewayClient = gatewayClient,
        _sendMessageUseCase = sendMessageUseCase;

  /// The loaded agent (null until [init] completes).
  Agent? get agent => _agent;

  late final String _conversationId =
      Conversation.generateId(instanceId, agentId);

  /// Initialise: load agent, create conversation, fetch history, subscribe to stream.
  Future<void> init() async {
    // 1. Look up the agent
    _agent = await _agentRepo.getById(agentId);
    notifyListeners();

    // 2. Get or create conversation (idempotent)
    await _conversationRepo.getOrCreate(instanceId, agentId);

    // 3. Load local messages immediately (fast path)
    await _loadMessages();

    // 4. Subscribe to connection state
    _connectionSubscription = _gatewayClient
        .connectionStateStream(instanceId)
        .listen((state) {
      connectionStateNotifier.value = state;
    });

    // 5. Fetch message history from Gateway (best-effort)
    if (_agent != null) {
      try {
        final history = await _gatewayClient.fetchMessageHistory(
          instanceId: instanceId,
          agentId: _agent!.remoteId,
        );
        for (final msg in history.messages) {
          await _messageRepo.insert(msg);
        }
        await _loadMessages();
      } catch (_) {
        // History fetch failed — local messages already shown; proceed silently.
      }
    }

    // 6. Subscribe to real-time messages
    _messageSubscription = _gatewayClient
        .messageStream(instanceId)
        .listen(
          (msg) async {
            await _messageRepo.insert(msg);
            await _loadMessages();
            // Agent replied — stop thinking + cancel timeout
            if (msg.role == MessageRole.agent) {
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

    // 7. Subscribe to tool call events
    _toolCallSubscription = _gatewayClient
        .toolCallStream(instanceId)
        .listen((tc) {
      final current = Map<String, ToolCall>.from(toolCallsNotifier.value);
      current[tc.messageId] = tc;
      toolCallsNotifier.value = current;
    });
  }

  /// Send a text message.
  Future<void> send(String text) async {
    if (_agent == null) return;

    await _sendMessageUseCase.execute(
      instanceId: instanceId,
      agent: _agent!,
      content: text,
      type: MessageType.text,
    );

    await _loadMessages();

    // Start "thinking" state
    _startThinking();

    onStatsChanged?.call();
  }

  /// Dismiss the timeout banner and cancel waiting.
  void dismissTimeout() {
    timeoutNotifier.value = false;
    _stopThinking();
  }

  /// Continue waiting — dismiss the timeout banner and restart the timer.
  void continueWaiting() {
    timeoutNotifier.value = false;
    _startThinking();
  }

  void _startThinking() {
    isThinkingNotifier.value = true;
    timeoutNotifier.value = false;
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      timeoutNotifier.value = true;
      isThinkingNotifier.value = false;
    });
  }

  void _stopThinking() {
    isThinkingNotifier.value = false;
    _timeoutTimer?.cancel();
  }

  /// Reload messages from the repository and push to the notifier.
  Future<void> _loadMessages() async {
    try {
      final messages = await _messageRepo.getByConversation(_conversationId);
      messagesNotifier.value = LoadData(messages);
    } catch (error, stackTrace) {
      messagesNotifier.value = LoadError(error, stackTrace);
    }
  }

  /// Release resources. Call when the chat room is permanently closed.
  @override
  void dispose() {
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _toolCallSubscription?.cancel();
    _timeoutTimer?.cancel();
    messagesNotifier.dispose();
    isThinkingNotifier.dispose();
    connectionStateNotifier.dispose();
    timeoutNotifier.dispose();
    toolCallsNotifier.dispose();
    super.dispose();
  }
}
