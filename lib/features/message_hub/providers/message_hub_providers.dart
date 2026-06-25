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
final conversationListProvider = FutureProvider<ConversationListData>((
  ref,
) async {
  // US-021: 订阅 sync ticker，让本 provider 在 agents 同步完成后（含
  // tombstone/复活）自动重建。与 agentListProvider 同模式。
  // 不在 providers.dart 里 ref.invalidate 是为避免 message_hub_providers
  // ↔ providers.dart 的循环 import（前者已依赖后者）。
  ref.watch(agentSyncTickerProvider);

  // 在第一个 await 前 capture 所有 repo，避免 provider dispose 后 ref.watch
  // 抛出 StateError（Riverpod 禁止 async gap 后继续使用 ref）。
  final conversationRepo = ref.watch(conversationRepoProvider);
  final agentRepo = ref.watch(agentRepoProvider);
  final instanceRepo = ref.watch(instanceRepoProvider);

  final conversations = await conversationRepo.getAllWithMessages();

  if (conversations.isEmpty) return ConversationListData(previews: const []);

  // Law 6 (批量查询)：2 次批量 IN 查询替代原先 2N 次串行 getById。两次查询
  // 用 Future.wait 并行，wall time ≈ max(T(agents), T(instances)) 而非两者之和。
  // getAllWithMessages 已按 lastMessageTime DESC 排序，按 conversations 原始
  // 顺序迭代构建 previews（getByIds 返回 Map 不保序，但我们用 conversations
  // 作为迭代源，Map 仅做 O(1) 查找）。
  final agentIds = conversations.map((c) => c.agentId).toSet().toList();
  final instanceIds = conversations.map((c) => c.instanceId).toSet().toList();
  final (agents, instances) = await (
    agentRepo.getByIds(agentIds),
    instanceRepo.getByIds(instanceIds),
  ).wait;

  final previews = <ConversationPreview>[];
  for (final conv in conversations) {
    final agent = agents[conv.agentId];
    // US-021: 跳过 tombstoned agent 的 conversation（getByIds 不过滤，故需显式
    // 检查 isRemoved）。hidden agent 的 conversation 仍显示（用户隐藏≠删历史）。
    if (agent == null || agent.isRemoved) continue;

    previews.add(
      ConversationPreview(
        conversation: conv,
        agent: agent,
        instanceName: instances[conv.instanceId]?.name ?? 'Unknown',
        healthStatus:
            instances[conv.instanceId]?.healthStatus ?? HealthStatus.unknown,
      ),
    );
  }

  return ConversationListData(previews: previews);
});
