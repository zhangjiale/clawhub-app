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

  /// 批量入队多条静默通知（Law 6：单事务，避免逐条 round-trip）。
  ///
  /// 为什么需要这个方法：[BackgroundNotifierShared.enqueuePulled] 在背景
  /// tick 中处理一批被拉取的消息（最多 `maxMessagesPerPull`=100 条 × N
  /// Agent），逐条 [enqueue] 会在慢存储设备上累积明显的延迟，可能阻塞
  /// WorkManager 10 分钟预算。批量入队必须：
  /// - 在单个事务里完成所有插入（全成功 / 全回滚语义）
  /// - 沿用相同的 serverId 唯一索引去重（与单条 enqueue 一致）
  /// - 返回新插入的 rowid 列表（顺序与输入一致；被去重的项仍返回
  ///   对应现有 rowid，便于调用方按位对账）
  ///
  /// 空列表必须为 no-op（不允许对空 IN/VALUES 触发非法 SQL）。
  /// 调用方若需要按行去重反馈，应基于二次查询 [countPending] /
  /// [getPending]，而非依赖返回值列表。
  Future<List<int>> enqueueBatch(List<PendingNotification> notifications);

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
