/// 纯函数:从升序日 bucket 列表计算"从最近一天向前数的连续活跃天数"。
///
/// **重要**:输入 `dayBuckets` 与 `todayBucket` 必须使用**相同的单位**
/// (毫秒 day-index `timestamp / 86400000`,或秒 day-index `timestamp / 86400`)。
///
/// **历史 bug**:`DriftAchievementRepo._computeStreak` 早期版本 SQL 用
/// 毫秒 day-index (`timestamp / 86400000`),但 `todayBucket` 用
/// `now ~/ 86400` (秒) — 两者永远不等,导致 `currentStreak` 永远 0。
/// 修复后,`todayBucket` 与 SQL 统一为**毫秒**单位。
///
/// **算法**:
/// - 列表空 → 0
/// - 最新一天 = 今天 → 起点 = 今天
/// - 最新一天 = 昨天 → 起点 = 昨天(允许"今天还没发"的情况)
/// - 最新一天比昨天更早 → 连续断开,只算最近 1 天
/// - 从起点向前回溯,遇到 gap 停止
int computeCurrentStreak(List<int> dayBuckets, {required int todayBucket}) {
  if (dayBuckets.isEmpty) return 0;

  int expectedBucket;
  if (dayBuckets.last == todayBucket) {
    expectedBucket = todayBucket;
  } else if (dayBuckets.last == todayBucket - 1) {
    // Most recent message was yesterday — valid streak anchor
    expectedBucket = todayBucket - 1;
  } else {
    // Gap > 1 day from today — streak is broken, just count the
    // single most-recent day
    return 1;
  }

  int streak = 0;
  for (var i = dayBuckets.length - 1; i >= 0; i--) {
    if (dayBuckets[i] == expectedBucket) {
      streak++;
      expectedBucket--;
    } else if (dayBuckets[i] < expectedBucket) {
      // Gap found — streak broken
      break;
    }
  }

  return streak;
}
