import '../models/agent.dart';
import '../repositories/i_agent_repo.dart';
import '../repositories/i_instance_repo.dart';
import '../../core/acl/i_gateway_client.dart';

/// 由 SyncAgentsUseCase 返回的聚合数据
class AgentListData {
  final List<Agent> agents;
  final Map<String, String> instanceNames; // instanceId → instanceName

  const AgentListData({
    required this.agents,
    required this.instanceNames,
  });
}

/// 同步 Agent 列表用例
/// 对齐: PRD 3.2 (Agent 列表与选择)
///
/// 从所有实例拉取远程 Agent 列表，同步到本地仓库，
/// 返回排序后的 Agent 列表及实例名称映射。
class SyncAgentsUseCase {
  final IInstanceRepo _instanceRepo;
  final IAgentRepo _agentRepo;
  final IGatewayClient _gatewayClient;

  SyncAgentsUseCase({
    required IInstanceRepo instanceRepo,
    required IAgentRepo agentRepo,
    required IGatewayClient gatewayClient,
  })  : _instanceRepo = instanceRepo,
        _agentRepo = agentRepo,
        _gatewayClient = gatewayClient;

  /// 同步所有实例的 Agent 列表并返回聚合结果
  Future<AgentListData> execute() async {
    final instances = await _instanceRepo.getAll();

    final instanceNames = <String, String>{};
    for (final instance in instances) {
      instanceNames[instance.id] = instance.name;
      try {
        final remoteAgents = await _gatewayClient.fetchAgents(instance.id);
        await _agentRepo.syncFromGateway(instance.id, remoteAgents);
      } catch (_) {
        // Skip instances that fail to connect — show what we have locally
      }
    }

    final agents = await _agentRepo.getAll();
    return AgentListData(agents: agents, instanceNames: instanceNames);
  }
}
