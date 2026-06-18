/// 消息生命周期状态机 (7 状态完整版)
/// 对齐: 架构设计 vFinal 5.3 节
///
/// 状态流转:
/// DRAFT --> PENDING --> SENDING --> SENT --> DELIVERED
///              |           |          |
///              v           v          v
///           FAILED <---- FAILED    FAILED
///              |           |          |
///              v           v          v
///           SENDING    EXPIRED    EXPIRED
///
/// - DRAFT: 草稿（用户正在编辑，尚未发送）
/// - PENDING: 已点击发送，等待网络可用
/// - SENDING: 已通过 WebSocket 发出，等待 Gateway ACK
/// - SENT: 已送达网关，serverId 已绑定
/// - DELIVERED: Agent 已读/处理（终态）
/// - FAILED: 发送失败，可重试
/// - EXPIRED: 超时放弃，不可重试（终态）
enum MessageStatus {
  draft(0),
  pending(1),
  sending(2),
  sent(3),
  delivered(4),
  failed(5),
  expired(6);

  const MessageStatus(this.value);
  final int value;

  /// 从整数反序列化
  static MessageStatus fromInt(int value) {
    return MessageStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => throw ArgumentError('Invalid MessageStatus value: $value'),
    );
  }

  /// 序列化为整数（用于数据库存储）
  int toInt() => value;

  /// 是否可以从当前状态流转到目标状态
  bool canTransitionTo(MessageStatus target) {
    if (this == target) return true; // 同状态允许（如 PENDING 重试后仍是 PENDING）
    if (isTerminal) return false;
    return _allowedTransitions[this]?.contains(target) ?? false;
  }

  /// 是否为终态（不可再流转）
  bool get isTerminal => this == delivered || this == expired;

  /// 是否可以重试发送
  bool get isRetryable => this == failed;

  static final Map<MessageStatus, Set<MessageStatus>> _allowedTransitions = {
    MessageStatus.draft: {MessageStatus.pending},
    MessageStatus.pending: {
      MessageStatus.sending,
      MessageStatus.failed,
      MessageStatus.expired,
    },
    MessageStatus.sending: {
      MessageStatus.sent,
      MessageStatus.failed,
      MessageStatus.expired,
    },
    MessageStatus.sent: {MessageStatus.delivered},
    MessageStatus.failed: {MessageStatus.sending, MessageStatus.expired},
    MessageStatus.delivered: <MessageStatus>{}, // 终态
    MessageStatus.expired: <MessageStatus>{}, // 终态
  };
}
