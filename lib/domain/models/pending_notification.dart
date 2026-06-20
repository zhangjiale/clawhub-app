/// DND 静默队列条目 (US-018 AC-3)
///
/// 当通知命中免打扰时段时，不立即发出，而是作为 [PendingNotification]
/// 入队持久化；DND 结束后由 [NotificationDispatcher] 批量汇总推送。
///
/// 纯 domain 模型 (Law 1)，无 Flutter / drift 依赖。Drift 行 ↔ 本模型的
/// 映射在 data/local/mapping/notification_mapping.dart 中完成。
class PendingNotification {
  /// 自增主键 (Drift rowid)；新建未持久化时为 0。
  final int id;

  final String agentId;
  final String instanceId;
  final String agentName;

  /// 通知摘要 (已截断至 ≤50 字)，用于汇总时展示。
  final String summary;

  /// 创建时间 (Unix 秒)，用于排序与过期清理。
  final int createdAt;

  /// Gateway 消息 ID，用于跨重启去重；可能为 null (无 serverId 的消息)。
  final String? messageServerId;

  /// 是否已汇总投递。已投递的条目可被 [INotificationRepo.clearDelivered] 清理。
  final bool delivered;

  const PendingNotification({
    required this.id,
    required this.agentId,
    required this.instanceId,
    required this.agentName,
    required this.summary,
    required this.createdAt,
    this.messageServerId,
    this.delivered = false,
  });

  PendingNotification copyWith({
    int? id,
    String? agentId,
    String? instanceId,
    String? agentName,
    String? summary,
    int? createdAt,
    String? messageServerId,
    bool? delivered,
  }) {
    return PendingNotification(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      instanceId: instanceId ?? this.instanceId,
      agentName: agentName ?? this.agentName,
      summary: summary ?? this.summary,
      createdAt: createdAt ?? this.createdAt,
      messageServerId: messageServerId ?? this.messageServerId,
      delivered: delivered ?? this.delivered,
    );
  }

  /// 去重键 — `instanceId:messageServerId`，仅当 serverId 非空时有意义。
  ///
  /// 无 serverId 的消息返回 null，调用方需用 clientId 兜底去重
  /// (内存 LRU 集合，不入 DB 约束)。
  String? get dedupKey =>
      messageServerId == null ? null : '$instanceId:$messageServerId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingNotification &&
          id == other.id &&
          agentId == other.agentId &&
          instanceId == other.instanceId &&
          agentName == other.agentName &&
          summary == other.summary &&
          createdAt == other.createdAt &&
          messageServerId == other.messageServerId &&
          delivered == other.delivered;

  @override
  int get hashCode => Object.hash(
    id,
    agentId,
    instanceId,
    agentName,
    summary,
    createdAt,
    messageServerId,
    delivered,
  );

  @override
  String toString() =>
      'PendingNotification(id: $id, agentId: $agentId, instanceId: $instanceId, '
      'agentName: $agentName, summary: $summary, delivered: $delivered, '
      'serverId: $messageServerId)';
}
