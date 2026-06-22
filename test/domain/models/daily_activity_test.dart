import 'package:claw_hub/domain/models/daily_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyActivity', () {
    const sample = DailyActivity(
      agentId: 'a-1',
      dayBucket: 19600, // ≈ 2023-09-16 UTC
      messageCount: 5,
    );

    test('all fields are accessible', () {
      expect(sample.agentId, 'a-1');
      expect(sample.dayBucket, 19600);
      expect(sample.messageCount, 5);
    });

    test('equality is value-based', () {
      const other = DailyActivity(
        agentId: 'a-1',
        dayBucket: 19600,
        messageCount: 5,
      );
      expect(sample, equals(other));
      expect(sample.hashCode, other.hashCode);
    });

    test('inequality on any field', () {
      expect(sample.copyWith(agentId: 'a-2'), isNot(equals(sample)));
      expect(sample.copyWith(dayBucket: 19601), isNot(equals(sample)));
      expect(sample.copyWith(messageCount: 6), isNot(equals(sample)));
    });

    test('copyWith with no args returns equal instance', () {
      expect(sample.copyWith(), equals(sample));
    });

    group('formatBucketAsDate', () {
      test('returns UTC DateTime for millisecond day-index', () {
        // 19600 ms-days after 1970-01-01 UTC — compute expected
        // independently via the same arithmetic the impl uses, so the
        // test stays correct if the formula ever changes.
        final date = DailyActivity.formatBucketAsDate(19600);
        final expected = DateTime.utc(
          1970,
          1,
          1,
        ).add(const Duration(days: 19600));
        expect(date.isUtc, isTrue);
        expect(date.year, expected.year);
        expect(date.month, expected.month);
        expect(date.day, expected.day);
        expect(date.hour, 0);
        expect(date.minute, 0);
      });

      test('day 0 returns epoch', () {
        final date = DailyActivity.formatBucketAsDate(0);
        expect(date.isUtc, isTrue);
        expect(date.year, 1970);
        expect(date.month, 1);
        expect(date.day, 1);
      });
    });
  });
}
