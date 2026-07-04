import 'package:claw_hub/domain/utils/copy_with_sentinel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CopyWithSentinel', () {
    test('instance is a singleton', () {
      expect(CopyWithSentinel.instance, same(CopyWithSentinel.instance));
    });
  });

  group('copyWithNullable', () {
    test('returns current when value is sentinel', () {
      const current = 'current';
      expect(copyWithNullable(CopyWithSentinel.instance, current), current);
    });

    test('returns new value when provided', () {
      expect(copyWithNullable('new', 'current'), 'new');
    });

    test('returns null when explicitly passed null', () {
      expect(copyWithNullable(null, 'current'), isNull);
    });
  });
}
