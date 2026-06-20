import '../models/pending_notification.dart';

/// DND 静默队列仓库抽象接口 (US-018 AC-3)
///
/// 持久化免打扰时段被静默的通知条目，DND 结束后由
/// [NotificationDispatcher] 批量读取并汇总推送。
///
/// 纯 domain 接口 (Law 1)，无 Flutter / drift 依赖。
/// Drift 实现在 data/repositories/drift_notification_repo.dart。
abstract class INotificationRepo {
  /// 入队一条静默通知，返回分配的主键 id (>0)。
  ///
  /// 实现负责处理 serverId 去重约束 (部分唯一索引)：
  /// 若 (instanceId, messageServerId) 已存在且 serverId 非空，
  /// 实现应忽略插入 (ON CONFLICT DO NOTHING) 而非抛异常。
  /// 注意：冲突时返回值可能是上次成功插入的 rowid 而非 0，
  /// 调用方若需确认是否真正插入应以 [countPending] / 查询为准，
  /// 不依赖返回值判断去重。
  Future<int> enqueue(PendingNotification notification);

  /// 取所有未投递 (delivered=false) 的条目，按 createdAt 升序。
  Future<List<PendingNotification>> getPending();

  /// 标记单条为已投递。
  Future<void> markDelivered(int id);

  /// 批量标记多条为已投递 (Law 6：单条 SQL，避免 N+1)。
  /// 空列表应为 no-op。返回受影响行数。
  Future<int> markDeliveredBatch(List<int> ids);

  /// 清除所有已投递条目，返回清除条数。
  Future<int> clearDelivered();

  /// 未投递条目计数 (供 UI / 调试用)。
  Future<int> countPending();
}
