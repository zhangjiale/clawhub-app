import '../../domain/models/models.dart';
import 'gateway_protocol.dart';

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

  /// 获取连接状态流（响应式）。
  ///
  /// 晚订阅者会收到最后已知状态作为初始 seed（仅在状态为 `connected` 时；
  /// 详见 `ReplayableConnectionState`）。调用方应**内联订阅** —— 不要缓存
  /// 返回的 [Stream] 对象后多次 `.listen()`：当底层处于 `connected` 时，
  /// 该 stream 实例为单订阅视图，第二次监听会抛 [StateError]。多个订阅方
  /// 应各自重新调用本方法获取独立 stream。
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

  /// 获取流式增量文本流 — chat.delta 到达时发出 [StreamingDelta]，
  /// chat.final 到达时发出 [StreamingDone]。
  ///
  /// [StreamingEvent.agentId] 用于多 Agent 场景下的精确路由，
  /// ViewModel 应只处理匹配当前 agentId 的事件。
  ///
  /// 默认实现返回空流。
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) =>
      const Stream<StreamingEvent>.empty();

  /// 获取配对信息流 — 当连接因 [GatewayConnectionState.pairingRequired]
  /// 被拒绝时，流中会发出包含 requestId 等信息的 [GatewayPairingInfo]。
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId);

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

  /// 设备未配对 — Gateway 返回 NOT_PAIRED / PAIRING_REQUIRED。
  /// 与 [authFailed] 不同：配对是可恢复的（用户在服务器审批后自动重连成功）。
  pairingRequired,

  /// 自动重连已耗尽 — 连续 N 次重连失败后停止自动重试（US-016 AC-3）。
  /// 终端状态：不再有定时器或自动重试触发。需用户手动重连。
  reconnectExhausted;

  /// 是否为终态 — 状态机不再自动产生新的重连/恢复动作。
  ///
  /// 终态只通过外部动作离开（手动重连、配对审批等）。注意 [connected]
  /// 不在此列 — 它虽是稳态，但可从 [connected] 因传输层错误回退到
  /// [recovering]，故不作为终态对待。
  bool get isTerminal => switch (this) {
    disconnected || authFailed || pairingRequired || reconnectExhausted => true,
    _ => false,
  };
}

/// 连接尚未建立时被抛出的异常，用于调用方以类型匹配替代字符串匹配。
///
/// 由 [ConnectionManager.sendRequest] 和 [WsGatewayClient._requireManager]
/// 在 WebSocket 未连接或实例未注册时抛出，代表可自动恢复的瞬态错误。
class NotConnectedException implements Exception {
  final String message;
  const NotConnectedException(this.message);
  @override
  String toString() => 'NotConnectedException: $message';
}

/// Gateway 设备配对信息 — 当连接因 PAIRING_REQUIRED 被拒绝时由 Gateway 返回。
class GatewayPairingInfo {
  /// 配对请求 ID（在服务器端执行 `openclaw devices approve <requestId>`）。
  final String requestId;

  /// 设备 ID（SHA256 of Ed25519 public key）。
  final String deviceId;

  /// 请求的角色（通常为 operator）。
  final String? requestedRole;

  /// 请求的 scope 列表。
  final List<String>? requestedScopes;

  const GatewayPairingInfo({
    required this.requestId,
    required this.deviceId,
    this.requestedRole,
    this.requestedScopes,
  });

  factory GatewayPairingInfo.fromJson(Map<String, dynamic> json) {
    return GatewayPairingInfo(
      requestId: json['requestId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      requestedRole: json['requestedRole'] as String?,
      requestedScopes: (json['requestedScopes'] as List<dynamic>?)
          ?.cast<String>(),
    );
  }
}
