/// Agent 不存在异常
/// 当通过 localId 查找 Agent 但记录不存在时抛出
class AgentNotFoundError implements Exception {
  final String agentId;
  const AgentNotFoundError(this.agentId);

  @override
  String toString() => 'Agent not found: $agentId';
}
