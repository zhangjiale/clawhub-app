import '../../core/acl/i_gateway_client.dart';

/// 实例连接编排器生命周期事件。
///
/// 收编 [ConnectionOrchestrator] 历史上累积的离散回调字段
/// （`_onAgentsSynced` / `_onPairingInfoCb` / `_onInstanceConnected`）。
/// 新增生命周期关注点时只加 sealed 子类型，不扩构造函数签名 ——
/// 旧模式每加一个关注点就多一个可空回调参数，构造函数签名无上限增长。
///
/// 放在 `app/connection/` 而非 `core/`：事件类型是编排器的产出，
/// 不是跨层基础设施；`domain/` 不引用此文件（Law 1 合规）。
sealed class InstanceEvent {
  const InstanceEvent();
}

/// Agent 同步完成信号 — 触发 agentListProvider 刷新。
///
/// 对齐旧 `_onAgentsSynced` 回调。
class AgentsSyncedEvent extends InstanceEvent {
  const AgentsSyncedEvent();
}

/// 配对信息变更（需要审批 / 审批完成 / 断开时清除）。
///
/// `info == null` 表示清除该实例的配对信息（断开连接场景）。
/// 对齐旧 `_onPairingInfoCb` 回调。
class PairingInfoChangedEvent extends InstanceEvent {
  final String instanceId;
  final GatewayPairingInfo? info;

  const PairingInfoChangedEvent({required this.instanceId, this.info});
}

/// 实例连接成功（agent 同步完成后触发）— 用于 [OutboxProcessor] 冲刷。
///
/// 对齐旧 `_onInstanceConnected` 回调。故意在 agent sync 之后触发：
/// [OutboxProcessor] 需要 [IAgentRepo.getById] 能查到 agent.remoteId，
/// 否则离线期间发送的消息会被静默跳过。
class InstanceConnectedEvent extends InstanceEvent {
  final String instanceId;

  const InstanceConnectedEvent(this.instanceId);
}

/// 自动重连已耗尽（US-016 AC-3）。
///
/// 当 [ConnectionManager] 连续 N 次重连失败后发出。
/// provider 层将 instanceId 加入 [reconnectExhaustedProvider] 的 Set，
/// UI 层 watch 该 provider 展示"无法连接到虾"重试提示。
///
/// 当同一 instanceId 后续重连成功时，[InstanceConnectedEvent] 触发，
/// provider 层从 Set 中移除该 id 以清除提示。
class ReconnectExhaustedEvent extends InstanceEvent {
  final String instanceId;
  const ReconnectExhaustedEvent(this.instanceId);
}
