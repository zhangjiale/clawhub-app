/// 实例健康状态
/// 对齐: 架构 vFinal 5.1 (ACL 状态机), 5.6 (网络环境感知)
enum HealthStatus {
  unknown(0),
  online(1),
  offline(2),
  connecting(3),
  expectedOffline(4),

  /// 设备待审批配对 — Gateway 返回 PAIRING_REQUIRED。
  /// 该状态不持久化到 DB（数据库中存储为 offline），
  /// 仅通过 [pairingInfoProvider] 实时传递给 UI。
  pairingRequired(5);

  const HealthStatus(this.value);
  final int value;

  static HealthStatus fromInt(int value) {
    return HealthStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => throw ArgumentError('Invalid HealthStatus value: $value'),
    );
  }

  int toInt() => value;

  /// 该状态下是否应该尝试建连/发消息
  /// unknown 是新建实例的默认状态，语义上应允许尝试连接
  bool get isConnectable =>
      this == HealthStatus.online || this == HealthStatus.unknown;

  /// 该状态下是否应尝试发起连接（启动/恢复/手动重连时使用）。
  ///
  /// 比 [isConnectable] 范围更广：除 [expectedOffline] 外所有状态都应尝试。
  /// offline 可能是上次运行的 authFailed / pairingRequired 被落库为 offline，
  /// pairingRequired 可能在 App 关闭期间已被服务器审批通过。
  bool get shouldAttemptReconnect => this != HealthStatus.expectedOffline;
}

/// 消息角色
enum MessageRole {
  user(0),
  agent(1),
  system(2);

  const MessageRole(this.value);
  final int value;

  static MessageRole fromInt(int value) {
    return MessageRole.values.firstWhere(
      (s) => s.value == value,
      orElse: () => throw ArgumentError('Invalid MessageRole value: $value'),
    );
  }

  int toInt() => value;
}

/// 消息类型
enum MessageType {
  text(0),
  image(1),
  file(2),
  toolCall(3);

  const MessageType(this.value);
  final int value;

  static MessageType fromInt(int value) {
    return MessageType.values.firstWhere(
      (s) => s.value == value,
      orElse: () => throw ArgumentError('Invalid MessageType value: $value'),
    );
  }

  int toInt() => value;
}

/// 工具调用状态
enum ToolCallStatus {
  pending(0),
  running(1),
  success(2),
  failed(3);

  const ToolCallStatus(this.value);
  final int value;

  static ToolCallStatus fromInt(int value) {
    return ToolCallStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => throw ArgumentError('Invalid ToolCallStatus value: $value'),
    );
  }

  int toInt() => value;

  /// 是否为终态
  bool get isCompleted =>
      this == ToolCallStatus.success || this == ToolCallStatus.failed;
}
