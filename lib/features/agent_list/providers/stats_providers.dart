import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';

/// 统计数据
class StatsData {
  final int activeInstances;
  final int totalInstances;
  final int onlineAgents;
  final int totalAgents;
  final int totalMessages;

  const StatsData({
    required this.activeInstances,
    required this.totalInstances,
    required this.onlineAgents,
    required this.totalAgents,
    required this.totalMessages,
  });

  static const empty = StatsData(
    activeInstances: 0,
    totalInstances: 0,
    onlineAgents: 0,
    totalAgents: 0,
    totalMessages: 0,
  );
}

/// 统计 Provider
/// 从实例、Agent、消息仓库聚合统计数据
final statsProvider = FutureProvider<StatsData>((ref) async {
  final instances = await ref.watch(instanceRepoProvider).getAll();
  final agents = await ref.watch(agentRepoProvider).getAll();
  final messageRepo = ref.watch(messageRepoProvider);

  // 活跃实例数（online 或 unknown 状态）
  final activeInstances =
      instances.where((i) => i.healthStatus.isConnectable).length;

  // 在线实例 ID 集合
  final onlineInstanceIds = instances
      .where((i) => i.healthStatus.isConnectable)
      .map((i) => i.id)
      .toSet();

  // 在线 Agent 数（所属实例在线）
  final onlineAgents =
      agents.where((a) => onlineInstanceIds.contains(a.instanceId)).length;

  // 总消息数（累加所有 Agent）
  int totalMessages = 0;
  for (final agent in agents) {
    totalMessages += await messageRepo.getMessageCount(agent.localId);
  }

  return StatsData(
    activeInstances: activeInstances,
    totalInstances: instances.length,
    onlineAgents: onlineAgents,
    totalAgents: agents.length,
    totalMessages: totalMessages,
  );
});
