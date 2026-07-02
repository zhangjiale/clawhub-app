import '../../domain/models/models.dart';
import 'gateway_protocol.dart';

export 'gateway_protocol.dart'
    show LargePayloadNotice, BufferOverflowNotice, GatewayNotice;

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

  /// Gap #6: 统一诊断事件流（sealed union，spec §2.7 `payload.large`
  /// 及后续诊断事件）。
  ///
  /// 当客户端触发 Gateway 诊断条件（如单帧超过 `policy.maxPayload`）时，
  /// Gateway 主动发出 `payload.large` 等事件；本流将解析后的
  /// [GatewayNotice]（[LargePayloadNotice] 为首个子类型）转发给上层，
  /// UI 按 runtime type 派生文案并展示用户提示。新增诊断事件只需加
  /// sealed 子类型 + parser 分支，调用方与本接口均不变。
  ///
  /// 默认实现返回空流 — MockGatewayClient 与早期实现不需要处理诊断事件。
  Stream<GatewayNotice> gatewayNoticeStream(String instanceId) =>
      const Stream<GatewayNotice>.empty();

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

/// Gap #2: 请求体超过 `policy.maxPayload` 时由 [ConnectionManager.sendRequest]
/// 抛出。客户端在序列化前守门（spec §2.2 + §3.5），避免 OOM。
///
/// 此类异常不可恢复 — 调用方应缩小请求负载后重试，或提示用户精简内容。
class PayloadTooLargeException implements Exception {
  final String message;

  /// 实际负载字节数（UTF-8 编码后）。
  final int actualSize;

  /// 当时生效的 maxPayload 上限。
  final int maxSize;

  const PayloadTooLargeException({
    required this.message,
    required this.actualSize,
    required this.maxSize,
  });

  @override
  String toString() =>
      'PayloadTooLargeException: $message (actual=$actualSize, max=$maxSize)';
}

/// Gap #2 (buffer half): 在途请求总字节数已达 `policy.maxBufferedBytes` 上限，
/// 下一个 [ConnectionManager.sendRequest] 调用会抛出此异常。
///
/// 实现策略为 reject-new（与 [PayloadTooLargeException] 保持一致的 fail-fast）：
/// 不 drop oldest、不阻塞 await，而是直接抛异常。**该异常是瞬时可重试的** ——
/// 在途请求收完响应 / 释放缓冲后重试即可成功，不会丢失消息（调用方标 FAILED，
/// OutboxProcessor 会在缓冲排空后自动重发）。
///
/// F-4: WS 客户端在 [sendMessage] 中捕获本异常后向 `gatewayNoticeStream`
/// 发出 [BufferOverflowNotice]，UI 层据此展示「网关繁忙，将自动重试」toast。
class BufferOverflowException implements Exception {
  final String message;

  /// 抛出时已经处于在途状态的字节数（即其他未完成请求的累计负载）。
  final int bufferedBytes;

  /// 本次尝试发送的负载字节数。
  final int attemptedSize;

  /// 当时生效的 maxBufferedBytes 上限。
  final int maxSize;

  const BufferOverflowException({
    required this.message,
    required this.bufferedBytes,
    required this.attemptedSize,
    required this.maxSize,
  });

  @override
  String toString() =>
      'BufferOverflowException: $message '
      '(buffered=$bufferedBytes, attempted=$attemptedSize, max=$maxSize)';
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
