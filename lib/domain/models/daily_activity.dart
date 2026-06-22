/// 虾单日活动数据点(US-019 成长面板时间线)
///
/// 表示某虾在某 UTC 日的消息数,用于 30 天时间线柱状图。
///
/// **day-bucket 单位**:与 [getActiveDayBucketsForAgent] 一致,使用
/// **毫秒** day-index(`timestamp / 86400000`),非 Unix 秒。
///
/// **空日**:无消息的天不在数据库中存在,UI 层需要在 repo 之上
/// 自行填充(纯 Dart loop,无 DB 压力)。这样 SQL 聚合只查有数据的天,
/// Dart 侧补全日历连续性。
class DailyActivity {
  final String agentId;

  /// UTC calendar day index since epoch, in **milliseconds** units
  /// (e.g. 19600 = 2023-09-15 UTC, since 19600 * 86_400_000 ms
  /// = 1,694,736,000,000 ms since epoch).
  final int dayBucket;

  /// 该日消息总数(>= 0)。
  final int messageCount;

  const DailyActivity({
    required this.agentId,
    required this.dayBucket,
    required this.messageCount,
  });

  DailyActivity copyWith({String? agentId, int? dayBucket, int? messageCount}) {
    return DailyActivity(
      agentId: agentId ?? this.agentId,
      dayBucket: dayBucket ?? this.dayBucket,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyActivity &&
          runtimeType == other.runtimeType &&
          agentId == other.agentId &&
          dayBucket == other.dayBucket &&
          messageCount == other.messageCount;

  @override
  int get hashCode => Object.hash(agentId, dayBucket, messageCount);

  @override
  String toString() =>
      'DailyActivity(agentId: $agentId, '
      'dayBucket: $dayBucket, messageCount: $messageCount)';

  /// 把毫秒 day-index 转成 UTC `DateTime`。
  ///
  /// 公式:`dayBucket * 86_400_000` 毫秒 = 距 1970-01-01 UTC 的天数。
  /// 返回值是当日 00:00:00 UTC,UI 可按本地时区再渲染。
  static DateTime formatBucketAsDate(int dayBucket) {
    return DateTime.fromMillisecondsSinceEpoch(
      dayBucket * 86400000,
      isUtc: true,
    );
  }
}
