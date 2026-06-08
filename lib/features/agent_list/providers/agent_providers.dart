import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';
import 'package:claw_hub/app/di/providers.dart';

/// Agent 列表 Provider — 薄委托层，实际编排逻辑在 [SyncAgentsUseCase] 中。
///
/// 从所有已连接实例拉取 Agent，同步到本地仓库后返回排序列表及实例名映射。
final agentListProvider = FutureProvider<AgentListData>((ref) async {
  final useCase = ref.watch(syncAgentsUseCaseProvider);
  return useCase.execute();
});
