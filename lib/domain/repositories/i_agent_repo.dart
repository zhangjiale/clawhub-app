import '../models/agent.dart';
import '../models/quick_command.dart';

/// Agent 仓库接口
/// 对齐: 架构 vFinal 5.2 (消息中心聚合)
abstract class IAgentRepo {
  /// 获取指定实例下的所有 Agent（按置顶优先、名称排序）
  Future<List<Agent>> getByInstanceId(String instanceId);

  /// 获取所有 Agent（按置顶优先、最近活跃时间排序）
  Future<List<Agent>> getAll();

  /// 根据本地 ID 获取 Agent
  Future<Agent?> getById(String localId);

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
