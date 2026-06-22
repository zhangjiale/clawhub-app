import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/clear_all_result.dart';

void main() {
  group('ClearAllResult', () {
    test('full success: both flags true', () {
      const result = ClearAllResult(dbCleared: true, avatarsCleared: true);
      expect(result.dbCleared, isTrue);
      expect(result.avatarsCleared, isTrue);
      expect(result.allSucceeded, isTrue);
      expect(result.partialFailure, isFalse);
    });

    test('avatar-only failure: partialFailure true', () {
      const result = ClearAllResult(dbCleared: true, avatarsCleared: false);
      expect(result.allSucceeded, isFalse);
      expect(result.partialFailure, isTrue);
    });

    test('full failure', () {
      const result = ClearAllResult(dbCleared: false, avatarsCleared: false);
      expect(result.allSucceeded, isFalse);
      expect(
        result.partialFailure,
        isFalse,
        reason: 'no partial when DB failed',
      );
    });

    test('equality uses all fields', () {
      expect(
        const ClearAllResult(dbCleared: true, avatarsCleared: true),
        equals(const ClearAllResult(dbCleared: true, avatarsCleared: true)),
      );
      expect(
        const ClearAllResult(dbCleared: true, avatarsCleared: true),
        isNot(
          equals(const ClearAllResult(dbCleared: true, avatarsCleared: false)),
        ),
      );
    });
  });
}
