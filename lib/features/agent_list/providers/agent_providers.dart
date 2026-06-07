import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/app/di/providers.dart';

/// Provider 返回的数据结构，包含 Agent 列表和实例名称映射
class AgentListData {
  final List<Agent> agents;
  final Map<String, String> instanceNames; // instanceId → instanceName

  const AgentListData({
    required this.agents,
    required this.instanceNames,
  });
}

/// Agent 列表 Provider
/// 从所有已连接实例拉取 Agent，同步到本地仓库后返回排序列表及实例名映射
final agentListProvider = FutureProvider<AgentListData>((ref) async {
  final instanceRepo = ref.watch(instanceRepoProvider);
  final agentRepo = ref.watch(agentRepoProvider);
  final gatewayClient = ref.watch(gatewayClientProvider);

  final instances = await instanceRepo.getAll();

  // Build instance name map and fetch agents
  final instanceNames = <String, String>{};
  for (final instance in instances) {
    instanceNames[instance.id] = instance.name;
    try {
      final remoteAgents = await gatewayClient.fetchAgents(instance.id);
      await agentRepo.syncFromGateway(instance.id, remoteAgents);
    } catch (_) {
      // Skip instances that fail to connect — show what we have locally
    }
  }

  final agents = await agentRepo.getAll();
  return AgentListData(agents: agents, instanceNames: instanceNames);
});
