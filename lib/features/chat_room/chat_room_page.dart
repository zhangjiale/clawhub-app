import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';

/// 聊天页 (P0 MVP Phase 5)
/// 消息列表 + 输入栏 + 实时消息接收
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
  StreamSubscription<Message>? _messageSubscription;
  Agent? _agent;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initChat();
  }

  Future<void> _initChat() async {
    // Look up the agent
    final agentRepo = ref.read(agentRepoProvider);
    _agent = await agentRepo.getById(widget.agentId);
    if (!mounted) return;
    setState(() {});

    // Get or create conversation
    final conversationRepo = ref.read(conversationRepoProvider);
    await conversationRepo.getOrCreate(widget.instanceId, widget.agentId);

    // Fetch message history
    final gatewayClient = ref.read(gatewayClientProvider);
    final messageRepo = ref.read(messageRepoProvider);
    try {
      final history = await gatewayClient.fetchMessageHistory(
        instanceId: widget.instanceId,
        agentId: _agent?.remoteId ?? '',
      );
      for (final msg in history.messages) {
        await messageRepo.insert(msg);
      }
      if (mounted) {
        ref.read(chatRefreshProvider.notifier).state++;
      }
    } catch (_) {
      // History fetch failed — proceed with local messages
    }

    // Subscribe to real-time messages
    _messageSubscription = gatewayClient
        .messageStream(widget.instanceId)
        .listen((msg) async {
      await messageRepo.insert(msg);
      if (mounted) {
        ref.read(chatRefreshProvider.notifier).state++;
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (_agent == null) return;

    final useCase = ref.read(sendMessageUseCaseProvider);
    await useCase.execute(
      instanceId: widget.instanceId,
      agent: _agent!,
      content: text,
      type: MessageType.text,
    );

    // Refresh UI
    ref.read(chatRefreshProvider.notifier).state++;
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _scrollController?.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final intValue = int.parse(cleaned, radix: 16);
    return Color(intValue | 0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversationId = Conversation.generateId(
      widget.instanceId,
      widget.agentId,
    );
    final messagesAsync = ref.watch(chatMessagesProvider(conversationId));

    return Scaffold(
      appBar: AppBar(
        title: _agent != null
            ? Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _parseColor(_agent!.themeColor),
                    foregroundColor:
                        _parseColor(_agent!.themeColor).contrastingTextColor(),
                    child: Text(
                      _agent!.displayName.characters.first,
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
                        Text(
                          _agent!.displayName,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (_agent!.description != null)
                          Text(
                            _agent!.description!,
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
          Expanded(
            child: messagesAsync.when(
              loading: () => const LoadingSkeleton(count: 3),
              error: (err, _) => Center(
                child: Text('Failed to load messages: $err'),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 48, color: theme.colorScheme.outline),
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

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    return MessageBubble(
                      message: message,
                      agentName: _agent?.displayName ?? 'Agent',
                    );
                  },
                );
              },
            ),
          ),
          ChatInputBar(onSend: _sendMessage),
        ],
      ),
    );
  }
}
