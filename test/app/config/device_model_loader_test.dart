import 'package:claw_hub/app/config/device_model_loader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // device_info_plus is a concrete class that calls platform channels —
  // not directly mockable in unit tests. We test the platform short-circuit
  // branches (Web / desktop) and the no-throw guarantee. The iOS/Android
  // happy paths are covered by integration tests and manual verification.
  group('loadDeviceModelIdentifier', () {
    tearDown(() {
      // Clear any platform override from the previous test.
      debugDefaultTargetPlatformOverride = null;
    });

    test('returns null on macOS desktop', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final result = await loadDeviceModelIdentifier();
      expect(result, isNull);
    });

    test('returns null on Windows desktop', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final result = await loadDeviceModelIdentifier();
      expect(result, isNull);
    });

    test('returns null on Linux desktop', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final result = await loadDeviceModelIdentifier();
      expect(result, isNull);
    });

    test(
      'does not throw on Android (best-effort, returns null without device_info_plus platform channel)',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        // No platform channel set up — device_info_plus will throw PlatformException.
        // The loader must swallow it and return null (Law 8 best-effort).
        final result = await loadDeviceModelIdentifier();
        expect(result, anyOf(isNull, isA<String>()));
      },
    );

    test('does not throw on iOS (best-effort)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final result = await loadDeviceModelIdentifier();
      expect(result, anyOf(isNull, isA<String>()));
    });
  });
}
