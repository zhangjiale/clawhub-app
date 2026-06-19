/// Shared relative-time formatting for UI display.
///
/// Returns human-readable Chinese relative time strings:
/// - "刚刚" (within 1 minute)
/// - "X分钟前" (within 1 hour)
/// - "X小时前" (within 1 day)
/// - "X天前" (within 7 days)
/// - "MM/DD" (older — zero-padded month/day)
///
/// Returns empty string for non-positive [timestampMs].
String formatRelativeTime(int timestampMs) {
  if (timestampMs <= 0) return '';
  final now = DateTime.now();
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final diff = now.difference(dt);

  // 未来时间戳（服务器时钟超前）：直接显示时间，不显示"刚刚"
  if (diff.isNegative) {
    return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
  if (diff.inDays < 1) return '${diff.inHours}小时前';
  if (diff.inDays < 7) return '${diff.inDays}天前';

  return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
}
