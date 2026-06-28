import '../models/agent.dart';
import '../models/quick_command.dart';

/// Agent 仓库接口
/// 对齐: 架构 vFinal 5.2 (消息中心聚合)
abstract class IAgentRepo {
  /// 获取指定实例下的所有 Agent（按置顶优先、名称排序）
  ///
  /// 默认过滤 tombstoned (removed_at) 和 hidden (hidden_at) agent。若需要
  /// 获取包含 tombstoned/hidden 的全部 agent，请使用 [getAllByInstanceId]。
  Future<List<Agent>> getByInstanceId(String instanceId);

  /// 获取指定实例下的所有 Agent（不过滤 tombstoned/hidden）。
  ///
  /// 用于 host 切换警告等需要统计全部本地 agent 的场景。
  Future<List<Agent>> getAllByInstanceId(String instanceId);

  /// 获取所有 Agent（按置顶优先、最近活跃时间排序）
  Future<List<Agent>> getAll();

  /// 根据本地 ID 获取 Agent
  Future<Agent?> getById(String localId);

  /// 批量根据本地 ID 获取 Agent（替代 N+1 查询）。
  /// 返回 `Map<localId, Agent>`，未找到的 ID 不出现在结果中。
  /// 传入空列表时返回空 Map（不查询数据库）。
  Future<Map<String, Agent>> getByIds(List<String> localIds);

  /// 根据复合键 (instanceId, remoteId) 查找
  Future<Agent?> findByCompositeKey(String instanceId, String remoteId);

  /// 批量保存/更新 Agent（用于 Gateway 同步）
  Future<List<Agent>> syncFromGateway(
    String instanceId,
    List<Agent> remoteAgents,
  );

  /// 更新本地个性化配置（头像、昵称、主题色）
  Future<Agent> updateLocalProfile(
    String localId, {
    String? nickname,
    String? avatarUrl,
    String? themeColor,
  });

  /// Atomically update profile fields and quick commands in a single
  /// transaction.  Guarantees all-or-nothing — if any write fails, none
  /// of the changes are persisted.
  Future<void> updateFullProfile(
    String localId, {
    String? nickname,
    String? avatarUrl,
    String? themeColor,
    List<QuickCommand>? quickCommands,
  });

  /// 响应式订阅指定 agent 的数据变化。
  ///
  /// Drift 实现基于 `agents` 表的 `.watchSingleOrNull()`，**Drift typed update**
  /// 触发的 commit 会 emit 新值（updateFullProfile / updateLocalProfile /
  /// clearAvatar / togglePin / `syncFromGateway` 的 upsert 路径）。
  ///
  /// **重要限制**：`syncFromGateway` 的 tombstone / revive 步骤走
  /// `customStatement`（SQLite 批量 UPDATE 避免 N+1），**不**触发 Drift
  /// reactivity — watchById 订阅者不会收到 tombstone 翻转通知。当前通过
  /// `agentSyncTickerProvider` 驱动的 `ChatViewModel.refreshAgent` 双保险
  /// 弥补此 gap；未来若给 agents 表加新的 `.watch()` stream 消费者，需评估
  /// 是否要改 Drift typed update 以保证订阅一致性。
  ///
  /// InMemory 实现基于 `StreamController.broadcast` + 手动 emit（仿
  /// InMemoryMessageRepo._messagesChanged）。
  ///
  /// 订阅时立即 emit 当前行（seed event），后续每次 Drift 触发的 commit
  /// emit 一次。tombstoned agent（removed_at != null）正常 emit，由调用方
  /// 判断 isRemoved。不存在的 localId 立即 emit null 并保持 open（等待后续
  /// 创建）。
  Stream<Agent?> watchById(String localId);

  /// 清除头像 — 将 avatarUrl 显式置为 null。
  ///
  /// 与 [updateLocalProfile] 不同：后者对 null 参数使用"跳过此列"语义，
  /// 本方法保证数据库中的 avatarUrl 被设为 NULL。
  Future<void> clearAvatar(String localId);

  /// 切换置顶状态
  Future<Agent> togglePin(String localId);

  /// 删除实例下所有 Agent
  Future<void> deleteByInstanceId(String instanceId);
}
