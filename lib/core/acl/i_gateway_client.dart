import '../../domain/models/models.dart';

/// Gateway 防腐层接口契约
/// 对齐: 架构 vFinal 5.1 (网关防腐层与连接状态机)
///
/// 业务层只依赖此接口，绝不直接依赖 WebSocket 实现或 OpenClaw 原生 JSON。
abstract class IGatewayClient {
  /// 连接到 Gateway（含认证流程：Token + 设备ID + 配对码）
  Future<void> connect(Instance instance);

  /// 断开连接
  Future<void> disconnect(String instanceId);

  /// 发送消息
  /// 返回 (serverId, 时间戳)
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  });

  /// 拉取 Agent 列表
  Future<List<Agent>> fetchAgents(String instanceId);

  /// 拉取会话消息历史
  /// [cursor] 同步游标，null 表示从最新开始
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  });

  /// 测试连通性
  Future<bool> testConnection(Instance instance);

  /// 获取连接状态流（响应式）
  Stream<GatewayConnectionState> connectionStateStream(String instanceId);

  /// 重置连接状态流到 [GatewayConnectionState.disconnected]，
  /// 使后续订阅者能观察到一个确定的初始事件（用于重试场景）。
  ///
  /// 实现不应关闭或替换底层控制器，只向现有流追加一个事件。
  void resetConnectionState(String instanceId);

  /// 获取消息流（响应式，实时接收 Agent 回复和工具调用）
  Stream<Message> messageStream(String instanceId);

  /// 获取工具调用状态流
  Stream<ToolCall> toolCallStream(String instanceId);

  /// 释放所有资源
  Future<void> dispose();
}

/// Gateway 连接状态
/// 重命名避免与 dart:async 中的 ConnectionState 冲突
enum GatewayConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  recovering,
  authFailed,
}
