/// Agent 不存在异常
/// 当通过 localId 查找 Agent 但记录不存在时抛出
class AgentNotFoundError implements Exception {
  final String agentId;
  const AgentNotFoundError(this.agentId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentNotFoundError && other.agentId == agentId;

  @override
  int get hashCode => agentId.hashCode;

  @override
  String toString() => 'Agent not found: $agentId';
}

/// Agent 已被 Gateway 端删除（tombstoned）异常。
/// 当向一个已被移除的 Agent 发送消息时抛出。
class AgentRemovedError implements Exception {
  final String agentId;
  const AgentRemovedError(this.agentId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentRemovedError && other.agentId == agentId;

  @override
  int get hashCode => agentId.hashCode;

  @override
  String toString() => 'Agent has been removed: $agentId';
}
