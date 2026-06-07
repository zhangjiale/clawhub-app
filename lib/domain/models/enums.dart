/// 实例健康状态
/// 对齐: 架构 vFinal 5.1 (ACL 状态机), 5.6 (网络环境感知)
enum HealthStatus {
  unknown(0),
  online(1),
  offline(2),
  connecting(3),
  expectedOffline(4);

  const HealthStatus(this.value);
  final int value;

  static HealthStatus fromInt(int value) {
    return HealthStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => throw ArgumentError('Invalid HealthStatus value: $value'),
    );
  }

  int toInt() => value;

  /// 该状态下是否应该尝试连接
  /// unknown 是新建实例的默认状态，语义上应允许尝试连接
  bool get isConnectable =>
      this == HealthStatus.online || this == HealthStatus.unknown;
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
