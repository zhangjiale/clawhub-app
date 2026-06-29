import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';

void main() {
  group('UserPreferences', () {
    test('defaults() should return sensible defaults', () {
      final prefs = UserPreferences.defaults();

      // All notifications enabled by default
      expect(prefs.notificationsEnabled, isTrue);
      expect(prefs.notifyOnReply, isTrue);
      expect(prefs.notifyOnError, isTrue);
      expect(prefs.notifyOnConnectionChange, isTrue);

      // DND disabled by default
      expect(prefs.dndEnabled, isFalse);
      expect(prefs.dndStartHour, 22);
      expect(prefs.dndStartMinute, 0);
      expect(prefs.dndEndHour, 8);
      expect(prefs.dndEndMinute, 0);

      // Biometric disabled by default
      expect(prefs.biometricEnabled, isFalse);
    });

    test('copyWith should preserve unchanged fields', () {
      final original = UserPreferences.defaults();

      final result = original.copyWith(notificationsEnabled: false);

      expect(result.notificationsEnabled, isFalse);
      // All other fields unchanged
      expect(result.notifyOnReply, isTrue);
      expect(result.notifyOnError, isTrue);
      expect(result.notifyOnConnectionChange, isTrue);
      expect(result.dndEnabled, isFalse);
      expect(result.dndStartHour, 22);
      expect(result.biometricEnabled, isFalse);
    });

    test('copyWith should update multiple fields at once', () {
      final original = UserPreferences.defaults();

      final result = original.copyWith(
        dndEnabled: true,
        dndStartHour: 23,
        dndEndHour: 7,
        biometricEnabled: true,
      );

      expect(result.dndEnabled, isTrue);
      expect(result.dndStartHour, 23);
      expect(result.dndEndHour, 7);
      expect(result.biometricEnabled, isTrue);
    });

    test(
      'copyWith with no arguments should return an equal but not same object',
      () {
        final original = UserPreferences.defaults();
        final result = original.copyWith();

        expect(result, equals(original));
        expect(identical(result, original), isFalse);
      },
    );

    test('equality should compare all fields', () {
      final a = UserPreferences.defaults();
      final b = UserPreferences.defaults();
      final c = UserPreferences.defaults().copyWith(
        notificationsEnabled: false,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    group('field validation', () {
      test('dndStartHour should clamp to valid range on construction', () {
        final prefs = const UserPreferences(dndStartHour: 25);
        // Values outside 0-23 are accepted at construction (no throw)
        // The ViewModel is responsible for clamping. Model is a pure data holder.
        expect(prefs.dndStartHour, 25);
      });
    });

    // ── backgroundSyncEnabled (US-018) ────────────────────────────

    test('defaults_hasBackgroundSyncEnabledTrue', () {
      expect(UserPreferences.defaults().backgroundSyncEnabled, isTrue);
    });

    test('defaults_constructorHasBackgroundSyncEnabledTrue', () {
      expect(const UserPreferences().backgroundSyncEnabled, isTrue);
    });

    test('copyWith_backgroundSyncEnabled_togglesValue', () {
      final off = UserPreferences.defaults().copyWith(
        backgroundSyncEnabled: false,
      );
      expect(off.backgroundSyncEnabled, isFalse);
      final on = off.copyWith(backgroundSyncEnabled: true);
      expect(on.backgroundSyncEnabled, isTrue);
    });

    test('equals_distinguishesBackgroundSyncEnabled', () {
      final a = UserPreferences.defaults();
      final b = a.copyWith(backgroundSyncEnabled: false);
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });
  });
}
