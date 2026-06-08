import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/async_state.dart';

/// 聊天页 (P0 MVP Phase 5)
/// 消息列表 + 输入栏 + 实时消息接收
///
/// Thin UI layer — all orchestration lives in [ChatViewModel].
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
  ChatViewModel? _vm;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _vm = ref.read(chatViewModelProvider((
      instanceId: widget.instanceId,
      agentId: widget.agentId,
    )));
    _vm!.addListener(_onVmChanged);
  }

  void _onVmChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm?.removeListener(_onVmChanged);
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = _vm!;
    final agent = vm.agent;

    // 预计算 Agent 颜色，避免 build 热路径重复解析
    final agentColor = agent != null
        ? ColorExtension.fromHex(agent.themeColor)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: agent != null
            ? Row(
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
                        Text(
                          agent.displayName,
                          style: theme.textTheme.titleSmall,
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
              )
            : const Text('Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: vm.messagesNotifier,
              builder: (context, state, _) => switch (state) {
                LoadInProgress() => const LoadingSkeleton(count: 3),
                LoadError(:final error) =>
                  Center(child: Text('Failed to load messages: $error')),
                LoadData(:final value) when value.isEmpty =>
                  Center(
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
                  ),
                LoadData(:final value) =>
                  ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: value.length,
                    itemBuilder: (context, index) {
                      final message = value[index];
                      return MessageBubble(
                        message: message,
                        agentName: agent?.displayName ?? 'Agent',
                      );
                    },
                  ),
              },
            ),
          ),
          ChatInputBar(onSend: (text) => vm.send(text)),
        ],
      ),
    );
  }
}
