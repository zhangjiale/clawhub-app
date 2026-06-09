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

  // 总消息数（批量查询，避免 N+1）
  final agentIds = agents.map((a) => a.localId).toList();
  final counts = await messageRepo.getMessageCountsByAgent(agentIds);
  final totalMessages = counts.values.fold<int>(0, (sum, c) => sum + c);

  return StatsData(
    activeInstances: activeInstances,
    totalInstances: instances.length,
    onlineAgents: onlineAgents,
    totalAgents: agents.length,
    totalMessages: totalMessages,
  );
});
