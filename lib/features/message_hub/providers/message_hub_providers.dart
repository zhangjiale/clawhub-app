import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/di/providers.dart';

/// 单条对话预览（Converation + Agent + 实例名 + 在线状态）
class ConversationPreview {
  final Conversation conversation;
  final Agent agent;
  final String instanceName;
  final HealthStatus healthStatus;

  const ConversationPreview({
    required this.conversation,
    required this.agent,
    required this.instanceName,
    required this.healthStatus,
  });
}

/// 对话列表聚合数据
class ConversationListData {
  final List<ConversationPreview> previews;

  const ConversationListData({required this.previews});
}

/// 对话列表 Provider — 获取所有有消息的会话并按最后消息时间降序返回。
///
/// 调用方通过 [ref.invalidate(conversationListProvider)] 触发刷新，
/// 不再依赖旧的 int 计数器 hack。
final conversationListProvider =
    FutureProvider<ConversationListData>((ref) async {
  final conversations =
      await ref.watch(conversationRepoProvider).getAllWithMessages();

  final previews = <ConversationPreview>[];
  for (final conv in conversations) {
    final agent = await ref.watch(agentRepoProvider).getById(conv.agentId);
    if (agent == null) continue;

    final instance =
        await ref.watch(instanceRepoProvider).getById(conv.instanceId);

    previews.add(ConversationPreview(
      conversation: conv,
      agent: agent,
      instanceName: instance?.name ?? 'Unknown',
      healthStatus: instance?.healthStatus ?? HealthStatus.unknown,
    ));
  }

  return ConversationListData(previews: previews);
});
