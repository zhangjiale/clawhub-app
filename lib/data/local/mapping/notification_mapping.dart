import 'package:claw_hub/domain/models/pending_notification.dart';

import '../database/database.dart' as db;

/// Maps between Drift-generated [db.PendingNotification] rows and the domain
/// [PendingNotification] model (US-018).
///
/// data 层保持 drift-pure：仅依赖 drift 行类型 (db 命名空间) 与 domain 模型。
/// 命名碰撞 (drift 行类与 domain 类同名 PendingNotification) 靠 `db` 前缀消歧。
class PendingNotificationMapper {
  const PendingNotificationMapper._();

  /// Convert a Drift row to a domain [PendingNotification].
  /// delivered 是 0/1 整数，转 bool。
  static PendingNotification toDomain(db.PendingNotification row) {
    return PendingNotification(
      id: row.id,
      agentId: row.agentId,
      instanceId: row.instanceId,
      agentName: row.agentName,
      summary: row.summary,
      createdAt: row.createdAt,
      messageServerId: row.messageServerId,
      delivered: row.delivered == 1,
    );
  }
}
