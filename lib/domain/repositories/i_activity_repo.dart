import '../models/daily_activity.dart';

/// 虾活动聚合仓储接口(US-019 成长面板时间线)
///
/// 关注点:**按 agent 维度的活动流**,与 per-conversation 的 [IMessageRepo]
/// 分离。允许在 ViewModel 层独立 override,便于测试。
///
/// **day-bucket 单位**:毫秒(`timestamp / 86400000`)。
/// **空日策略**:有数据的天由 DB 聚合返回;无消息的空日由
/// repository 内部 Dart loop 补全,保持日历连续。
/// **窗口默认**:30 天,可在调用处覆盖。
abstract class IActivityRepo {
  /// 返回 [agentId] 过去 [days] 天(含无消息空日)的活动序列。
  ///
  /// - 长度恒为 [days]
  /// - 按 `dayBucket` **升序** 排列(最早的在 index 0,最近的在末尾)
  /// - `now` 默认 `DateTime.now().toUtc()`;测试可注入固定时间避免时区漂移
  /// - `dayBucket` 是毫秒单位 UTC day-index,详见 [DailyActivity]
  Future<List<DailyActivity>> getDailyActivity(
    String agentId, {
    int days = 30,
    DateTime? now,
  });
}
