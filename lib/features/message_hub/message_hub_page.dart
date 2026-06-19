import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/features/message_hub/providers/message_hub_providers.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/message_hub/widgets/conversation_tile.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 消息页 (P0 MVP Phase 6)
///
/// 展示所有有过对话记录的会话列表，按最后消息时间降序排列。
/// 点击进入对应 Agent 的聊天页，返回时回到本页（智能返回栈）。
class MessageHubPage extends ConsumerStatefulWidget {
  const MessageHubPage({super.key});

  @override
  ConsumerState<MessageHubPage> createState() => _MessageHubPageState();
}

class _MessageHubPageState extends ConsumerState<MessageHubPage> {
  @override
  void initState() {
    super.initState();
    // Ensure initial load happens after first frame (avoids build-during-build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(conversationListProvider);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(conversationListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(conversationListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: XiaSpacing.s2),
            child: HeaderButton(
              icon: Icons.search,
              tooltip: '搜索消息',
              onPressed: () =>
                  context.push(AppRoutes.searchWithParams(source: 'messages')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: XiaSpacing.s2),
            child: HeaderButton(
              icon: Icons.settings_outlined,
              tooltip: '设置',
              onPressed: () => context.push(AppRoutes.settings),
            ),
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const LoadingSkeleton(count: 5),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(XiaSpacing.s7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: XiaSpacing.s3),
                Text(
                  'Failed to load messages',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: XiaSpacing.s2),
                FilledButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          if (data.previews.isEmpty) {
            return const EmptyState(
              icon: Icon(Icons.chat_bubble_outline),
              title: '还没有消息',
              subtitle: '去虾列表找一只虾开始聊天吧',
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: data.previews.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                indent: 76, // Align with text (16 padding + 48 avatar + 12 gap)
              ),
              itemBuilder: (context, index) {
                final preview = data.previews[index];
                return ConversationTile(
                  preview: preview,
                  onTap: () {
                    context.push(
                      AppRoutes.chatWithParams(
                        preview.agent.localId,
                        preview.agent.instanceId,
                        source: 'messages',
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
