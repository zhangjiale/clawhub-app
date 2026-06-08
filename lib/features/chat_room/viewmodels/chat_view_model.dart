import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
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
///
/// Exposes a reactive [messagesNotifier] for the message list body and
/// extends [ChangeNotifier] so the owning widget can rebuild when
/// [agent] transitions from null → loaded.
///
/// The widget observes [messagesNotifier] and calls [send]; nothing else leaks out.
class ChatViewModel extends ChangeNotifier {
  final IAgentRepo _agentRepo;
  final IConversationRepo _conversationRepo;
  final IMessageRepo _messageRepo;
  final IGatewayClient _gatewayClient;
  final SendMessageUseCase _sendMessageUseCase;
  final String instanceId;
  final String agentId;

  StreamSubscription<Message>? _messageSubscription;
  Agent? _agent;

  /// Reactive messages notifier — the single source of truth for the UI.
  final ValueNotifier<LoadState<List<Message>>> messagesNotifier =
      ValueNotifier(const LoadInProgress());

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
  ///
  /// Called once by the provider that owns this ViewModel's lifecycle.
  /// Safe to call even if the widget is already unmounted — errors from history
  /// or stream failures are handled internally.
  Future<void> init() async {
    // 1. Look up the agent
    _agent = await _agentRepo.getById(agentId);
    notifyListeners(); // agent 从 null 变为已加载，触发 widget rebuild

    // 2. Get or create conversation (idempotent)
    await _conversationRepo.getOrCreate(instanceId, agentId);

    // 3. Load local messages immediately (fast path)
    await _loadMessages();

    // 4. Fetch message history from Gateway (best-effort)
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

    // 5. Subscribe to real-time messages
    _messageSubscription = _gatewayClient
        .messageStream(instanceId)
        .listen(
          (msg) async {
            await _messageRepo.insert(msg);
            await _loadMessages();
          },
          onError: (error, stackTrace) {
            debugPrint(
              'Message stream error for $instanceId: $error\n$stackTrace',
            );
            // Stream error (e.g. WebSocket disconnect) — silently continue;
            // the connection manager handles reconnection independently.
          },
        );
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
    messagesNotifier.dispose();
    super.dispose();
  }
}
