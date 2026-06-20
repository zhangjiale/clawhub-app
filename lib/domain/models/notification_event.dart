/// 推送通知领域事件 (US-018)
///
/// 描述"可通知"的应用事件。由 [NotificationDispatcher] 消费消息流 /
/// 连接状态流后构造，再交由 [EvaluateNotificationUseCase] 判定是否真正发出通知。
///
/// 本文件为纯 domain 模型 (Law 1)，不依赖 Flutter / drift / riverpod，
/// 也不依赖 core/acl 的 [GatewayConnectionState] —— 连接状态用本文件自有的
/// [NotificationConnectionState] 表达，由上层 (coordinator) 完成
/// `GatewayConnectionState → NotificationConnectionState` 的映射。
sealed class NotificationEvent {
  const NotificationEvent();
}

/// 连接状态的领域级抽象 —— 仅保留通知判定关心的三态。
///
/// 上层 (app/notifications/notification_coordinator.dart) 负责把
/// `core/acl` 的 `GatewayConnectionState` 折叠为本枚举：
/// - `connected` → [online]
/// - `connecting` / `authenticating` / `recovering` → [reconnecting]
/// - `disconnected` / `authFailed` / `pairingRequired` / `reconnectExhausted`
///   → [offline]
enum NotificationConnectionState {
  online,
  reconnecting,
  offline;

  /// 是否在线 — 仅 [online] 为 true。
  bool get isOnline => this == online;
}

/// Agent 回复完成事件。
class ReplyEvent extends NotificationEvent {
  final String agentId;
  final String instanceId;
  final String agentName;

  /// 消息内容预览 (已截断至通知摘要长度上限，由 usecase 进一步处理)。
  final String contentPreview;

  /// Gateway 分配的消息 ID，用于跨重连 catch-up 去重；可能为 null。
  final String? messageServerId;

  /// 本地客户端消息 ID，去重兜底。
  final String messageClientId;

  const ReplyEvent({
    required this.agentId,
    required this.instanceId,
    required this.agentName,
    required this.contentPreview,
    this.messageServerId,
    required this.messageClientId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplyEvent &&
          agentId == other.agentId &&
          instanceId == other.instanceId &&
          agentName == other.agentName &&
          contentPreview == other.contentPreview &&
          messageServerId == other.messageServerId &&
          messageClientId == other.messageClientId;

  @override
  int get hashCode => Object.hash(
    agentId,
    instanceId,
    agentName,
    contentPreview,
    messageServerId,
    messageClientId,
  );

  @override
  String toString() =>
      'ReplyEvent(agentId: $agentId, instanceId: $instanceId, '
      'agentName: $agentName, preview: $contentPreview, '
      'serverId: $messageServerId, clientId: $messageClientId)';
}

/// Agent 执行出错事件。
class ErrorEvent extends NotificationEvent {
  final String agentId;
  final String instanceId;
  final String agentName;

  /// 错误摘要 (已截断)。
  final String errorSummary;

  const ErrorEvent({
    required this.agentId,
    required this.instanceId,
    required this.agentName,
    required this.errorSummary,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorEvent &&
          agentId == other.agentId &&
          instanceId == other.instanceId &&
          agentName == other.agentName &&
          errorSummary == other.errorSummary;

  @override
  int get hashCode => Object.hash(agentId, instanceId, agentName, errorSummary);

  @override
  String toString() =>
      'ErrorEvent(agentId: $agentId, instanceId: $instanceId, '
      'agentName: $agentName, summary: $errorSummary)';
}

/// 实例连接状态变化事件。
class ConnectionChangeEvent extends NotificationEvent {
  final String instanceId;
  final String instanceName;
  final NotificationConnectionState fromState;
  final NotificationConnectionState toState;

  const ConnectionChangeEvent({
    required this.instanceId,
    required this.instanceName,
    required this.fromState,
    required this.toState,
  });

  /// 是否为"掉线"——从在线变为非在线，是用户最关心的连接变化通知场景。
  bool get isOnlineDrop => fromState.isOnline && !toState.isOnline;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionChangeEvent &&
          instanceId == other.instanceId &&
          instanceName == other.instanceName &&
          fromState == other.fromState &&
          toState == other.toState;

  @override
  int get hashCode => Object.hash(instanceId, instanceName, fromState, toState);

  @override
  String toString() =>
      'ConnectionChangeEvent(instanceId: $instanceId, '
      'instanceName: $instanceName, $fromState → $toState)';
}
