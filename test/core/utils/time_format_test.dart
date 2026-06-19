import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/utils/time_format.dart';

void main() {
  group('formatRelativeTime', () {
    test('returns empty string for non-positive timestamp', () {
      expect(formatRelativeTime(0), '');
      expect(formatRelativeTime(-1), '');
      expect(formatRelativeTime(-1000000), '');
    });

    test('returns "刚刚" for timestamps within 1 minute', () {
      final now = DateTime.now();
      final justNow = now.subtract(const Duration(seconds: 30));
      expect(formatRelativeTime(justNow.millisecondsSinceEpoch), '刚刚');
    });

    test('returns "X分钟前" for timestamps within 1 hour', () {
      final now = DateTime.now();
      final fiveMinAgo = now.subtract(const Duration(minutes: 5));
      expect(formatRelativeTime(fiveMinAgo.millisecondsSinceEpoch), '5分钟前');
    });

    test('returns "X小时前" for timestamps within 1 day', () {
      final now = DateTime.now();
      final threeHoursAgo = now.subtract(const Duration(hours: 3));
      expect(formatRelativeTime(threeHoursAgo.millisecondsSinceEpoch), '3小时前');
    });

    test('returns "X天前" for timestamps within 7 days', () {
      final now = DateTime.now();
      final twoDaysAgo = now.subtract(const Duration(days: 2));
      expect(formatRelativeTime(twoDaysAgo.millisecondsSinceEpoch), '2天前');
    });

    test('returns "MM/DD" for timestamps older than 7 days', () {
      final now = DateTime.now();
      final tenDaysAgo = now.subtract(const Duration(days: 10));
      final result = formatRelativeTime(tenDaysAgo.millisecondsSinceEpoch);
      // Format: MM/DD
      final date = tenDaysAgo;
      final expected =
          '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      expect(result, expected);
    });

    // -----------------------------------------------------------------------
    // Bug fix: future timestamps (server clock skew) no longer show "刚刚"
    // -----------------------------------------------------------------------
    test('returns "MM/DD" for future timestamps (server clock ahead)', () {
      final now = DateTime.now();
      final fiveMinFuture = now.add(const Duration(minutes: 5));
      final result = formatRelativeTime(fiveMinFuture.millisecondsSinceEpoch);
      // Should use the date format, not "刚刚"
      expect(result, isNot('刚刚'));
      final expected =
          '${fiveMinFuture.month.toString().padLeft(2, '0')}/${fiveMinFuture.day.toString().padLeft(2, '0')}';
      expect(result, expected);
    });

    test('future timestamps always show date, not relative time', () {
      final oneHourFuture = DateTime.now().add(const Duration(hours: 1));
      final oneDayFuture = DateTime.now().add(const Duration(days: 1));
      final oneWeekFuture = DateTime.now().add(const Duration(days: 8));

      for (final ts in [oneHourFuture, oneDayFuture, oneWeekFuture]) {
        final result = formatRelativeTime(ts.millisecondsSinceEpoch);
        expect(result, isNot('刚刚'));
        expect(result, isNot(contains('分钟前')));
        expect(result, isNot(contains('小时前')));
        expect(result, isNot(contains('天前')));
      }
    });
  });
}
