import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';
import 'package:claw_hub/app/di/providers.dart';

/// Agent 列表 Provider — 薄委托层，实际编排逻辑在 [SyncAgentsUseCase] 中。
///
/// 从所有已连接实例拉取 Agent，同步到本地仓库后返回排序列表及实例名映射。
///
/// 通过 [agentSyncTickerProvider] 接收 ConnectionOrchestrator 的
/// auto-sync 完成通知：当 WebSocket 连接后 agents.list 返回数据并写入 DB，
/// ticker 递增 → 本 provider 自动重建 → UI 刷新。
final agentListProvider = FutureProvider<AgentListData>((ref) async {
  // Watch the sync ticker: ConnectionOrchestrator auto-sync increments this
  // after agents are written to DB, triggering a UI refresh.
  ref.watch(agentSyncTickerProvider);
  final useCase = ref.watch(syncAgentsUseCaseProvider);
  return useCase.execute();
});
