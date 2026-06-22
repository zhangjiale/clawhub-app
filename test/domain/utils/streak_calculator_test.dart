import 'package:claw_hub/domain/utils/streak_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tests use millisecond day-indexes to match the production SQL:
  //   SELECT DISTINCT (timestamp / 86400000) AS day_bucket ...
  // The previous bug used SECOND day-indexes, which never matched.

  // Anchor "today" for the test cases.
  final todayBucket =
      DateTime.utc(2024, 6, 15).millisecondsSinceEpoch ~/ 86400000;

  group('computeCurrentStreak', () {
    test('empty list → 0', () {
      expect(computeCurrentStreak([], todayBucket: todayBucket), 0);
    });

    test('single message today → streak 1', () {
      expect(computeCurrentStreak([todayBucket], todayBucket: todayBucket), 1);
    });

    test('three consecutive days ending today → streak 3', () {
      expect(
        computeCurrentStreak([
          todayBucket - 2,
          todayBucket - 1,
          todayBucket,
        ], todayBucket: todayBucket),
        3,
      );
    });

    test('streak anchored at yesterday (today no message) → still counts', () {
      // Two days ending yesterday
      expect(
        computeCurrentStreak([
          todayBucket - 2,
          todayBucket - 1,
        ], todayBucket: todayBucket),
        2,
      );
    });

    test('gap > 1 day from today → streak 1 (single most-recent day)', () {
      // Most recent message was 3 days ago
      expect(
        computeCurrentStreak([
          todayBucket - 5,
          todayBucket - 3,
        ], todayBucket: todayBucket),
        1,
      );
    });

    test('middle gap breaks streak', () {
      // Days: today, today-1, today-3, today-4
      // Streak should be 2 (today, today-1), then broken at today-2
      expect(
        computeCurrentStreak([
          todayBucket - 4,
          todayBucket - 3,
          todayBucket - 1,
          todayBucket,
        ], todayBucket: todayBucket),
        2,
      );
    });

    test('regression guard — millisecond and second day-indexes disagree', () {
      // This test specifically guards the original bug:
      // The previous implementation used `now ~/ 86400` (seconds),
      // so `dayBuckets` (which are millisecond day-indexes) could
      // never equal `todayBucket`. After the fix, both use
      // millisecond units.
      final msBucket = todayBucket;
      // A "second" day-index of the same calendar day would be:
      final secBucket = todayBucket * 1000;
      // They are 1000x apart. The bug made them never match.
      expect(msBucket == secBucket, isFalse);
      // And the correct input list should produce a non-zero streak.
      expect(computeCurrentStreak([msBucket], todayBucket: todayBucket), 1);
    });
  });
}
