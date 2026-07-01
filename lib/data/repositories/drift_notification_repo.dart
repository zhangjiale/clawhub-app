import 'package:claw_hub/domain/models/pending_notification.dart';
import 'package:claw_hub/domain/repositories/i_notification_repo.dart';

import '../local/database/database.dart' as db;
import '../local/mapping/notification_mapping.dart';

/// Drift/SQLite implementation of [INotificationRepo] (US-018 AC-3).
///
/// 持久化 DND 静默队列。去重依赖 `beforeOpen` 中创建的部分唯一索引
/// `pending_notifications_by_server` (WHERE message_server_id IS NOT NULL)：
/// - 有 serverId 的消息：`(instance_id, message_server_id)` 唯一，
///   INSERT ... ON CONFLICT DO NOTHING 自动忽略重复。
/// - 无 serverId 的消息：不入约束，总是插入，由 dispatcher 内存 LRU 兜底。
class DriftNotificationRepo implements INotificationRepo {
  final db.AppDatabase _database;

  DriftNotificationRepo(this._database);

  @override
  Future<int> enqueue(PendingNotification notification) async {
    // customInsert 通过 last_insert_rowid() 返回新行 rowid。
    // 命中 ON CONFLICT DO NOTHING (未真正插入) 时，返回值是该连接上一次
    // 成功插入的 rowid，而非 0 —— 因此调用方不应依赖返回值判断是否去重，
    // 需以 [countPending] / [getPending] 为准 (见 INotificationRepo.enqueue 文档)。
    return _database.insertPendingNotification(
      notification.agentId,
      notification.instanceId,
      notification.agentName,
      notification.summary,
      notification.createdAt,
      notification.messageServerId,
    );
  }

  @override
  Future<List<int>> enqueueBatch(
    List<PendingNotification> notifications,
  ) async {
    // Empty → no-op (avoids empty VALUES SQL clause; interface contract).
    if (notifications.isEmpty) return const <int>[];

    // Single transaction across all inserts (US-018): one round-trip to
    // sqlite (full block commit) instead of N individual fsyncs. The
    // partial UNIQUE index `pending_notifications_by_server` enforces
    // (instance_id, message_server_id) dedup server-side via
    // ON CONFLICT DO NOTHING, matching single-row [enqueue]'s contract.
    // This is a sequence rather than a single multi-row INSERT because
    // the drift generated code maps `insertPendingNotification` to a
    // typed customInsert; refactoring to `batch(insertAll)` would
    // require a generated query rewrite and codegen — accepted N+1
    // measured on cold storage vs the codegen churn is a wash, but the
    // transaction collapses fsync cost which is the dominant latency
    // contributor on flash storage.
    return _database.transaction(() async {
      final ids = <int>[];
      for (final n in notifications) {
        // iron-law-allow: Law6 -- drift codegen maps insertPendingNotification to a typed customInsert, blocking a single multi-row INSERT without a generated-query rewrite; the transaction collapses the dominant fsync cost (see rationale above).
        final id = await _database.insertPendingNotification(
          n.agentId,
          n.instanceId,
          n.agentName,
          n.summary,
          n.createdAt,
          n.messageServerId,
        );
        ids.add(id);
      }
      return ids;
    });
  }

  @override
  Future<List<PendingNotification>> getPending() async {
    final rows = await _database.getPendingNotifications().get();
    // Law 6: 一次性 map 整批，不逐条 await。
    return rows.map(PendingNotificationMapper.toDomain).toList(growable: false);
  }

  @override
  Future<void> markDelivered(int id) async {
    await _database.markPendingDelivered(id);
  }

  @override
  Future<int> markDeliveredBatch(List<int> ids) async {
    // 空列表 → drift $expandVar 对空 IN 子句生成非法 SQL，显式短路。
    if (ids.isEmpty) return 0;
    return _database.markPendingDeliveredBatch(ids);
  }

  @override
  Future<int> clearDelivered() async {
    // customUpdate 返回受影响行数。
    return _database.deleteDeliveredNotifications();
  }

  @override
  Future<int> countPending() async {
    return _database.countPendingNotifications().getSingle();
  }
}
