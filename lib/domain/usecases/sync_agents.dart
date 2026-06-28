import '../models/agent.dart';
import '../models/enums.dart';
import '../repositories/i_agent_repo.dart';
import '../repositories/i_instance_repo.dart';
import '../../core/acl/i_gateway_client.dart';
import '../../core/i_logger.dart';

/// 由 SyncAgentsUseCase 返回的聚合数据
class AgentListData {
  final List<Agent> agents;
  final Map<String, String> instanceNames; // instanceId → instanceName
  final Map<String, HealthStatus> instanceStatuses; // instanceId → healthStatus

  /// Per-instance sync errors.
  /// Non-empty when one or more Gateway fetches failed and the UI
  /// should show a stale-data warning.
  final Map<String, String> syncErrors; // instanceId → errorMessage

  const AgentListData({
    required this.agents,
    required this.instanceNames,
    required this.instanceStatuses,
    this.syncErrors = const {},
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
  final ILogger? _logger;

  SyncAgentsUseCase({
    required this._instanceRepo,
    required this._agentRepo,
    required this._gatewayClient,
    this._logger,
  });

  /// 同步所有实例的 Agent 列表并返回聚合结果
  Future<AgentListData> execute() async {
    final instances = await _instanceRepo.getAll();

    final instanceNames = <String, String>{};
    final instanceStatuses = <String, HealthStatus>{};
    final syncErrors = <String, String>{};
    for (final instance in instances) {
      instanceNames[instance.id] = instance.name;
      instanceStatuses[instance.id] = instance.healthStatus;

      try {
        final remoteAgents = await _gatewayClient.fetchAgents(instance.id);
        await _agentRepo.syncFromGateway(instance.id, remoteAgents);
      } catch (error, stackTrace) {
        // Distinguish "not yet connected" from genuine failures.
        // When the connection is still authenticating (race with
        // ConnectionOrchestrator), the error is transient — auto-sync
        // will populate the DB shortly.  Don't record it as a syncError.
        if (error is NotConnectedException) {
          // Transient: ConnectionOrchestrator will sync when ready.
          continue;
        }
        // Surface the error via syncErrors so the UI can show a stale-data
        // warning while still displaying cached results from the local DB.
        syncErrors[instance.id] = error.toString();
        // Log the full error with stack trace via injected logger —
        // the caller receives only error messages, but the logger
        // preserves diagnostic detail for debugging.
        _logger?.error(
          'SyncAgents failed for instance ${instance.id}: $error',
          stackTrace,
        );
      }
    }

    final agents = await _agentRepo.getAll();
    return AgentListData(
      agents: agents,
      instanceNames: instanceNames,
      instanceStatuses: instanceStatuses,
      syncErrors: syncErrors,
    );
  }
}
