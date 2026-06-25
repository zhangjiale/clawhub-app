import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/config/platform_info.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart'
    show ClientIds, ConnectionConfig;

void main() {
  group('platformOS', () {
    // =========================================================================
    // 基本契约
    // =========================================================================

    test('returns non-empty string', () {
      final os = platformOS();
      expect(os, isNotEmpty);
    });

    test('returns lowercase identifier (matches Platform.operatingSystem)', () {
      final os = platformOS();
      // dart:io's Platform.operatingSystem always returns lowercase;
      // our function must preserve that contract.
      expect(os, equals(os.toLowerCase()));
    });

    test('does NOT contain enum name artifact "TargetPlatform"', () {
      final os = platformOS();
      // Guard against accidentally calling .name without .toLowerCase()
      // or returning the enum's toString() representation.
      expect(os, isNot(contains('TargetPlatform')));
    });

    // =========================================================================
    // 已知原生平台
    // =========================================================================

    test('returns known platform identifier on native test VM', () {
      final os = platformOS();
      // On any native Dart VM, kIsWeb is false, so we should get a
      // lowercase TargetPlatform name. The exact value depends on the
      // test host OS, but it must be one of the known Flutter platforms.
      const knownNative = [
        'android',
        'ios',
        'macos',
        'linux',
        'windows',
        'fuchsia',
      ];
      expect(
        os,
        isIn(knownNative),
        reason:
            'On native VM, platformOS() must return a known '
            'TargetPlatform name (got "$os").',
      );
    });

    test('does NOT return "web" on native test VM', () {
      final os = platformOS();
      // kIsWeb is a compile-time constant that is false on the native
      // Dart VM used by `flutter test`.  If this ever returns 'web',
      // something is wrong with the kIsWeb check.
      expect(kIsWeb, isFalse, reason: 'kIsWeb must be false on native Dart VM');
      expect(
        os,
        isNot('web'),
        reason: 'Should not return "web" when kIsWeb is false',
      );
    });

    // =========================================================================
    // 下游集成契约
    // =========================================================================

    test('ClientIds.forPlatform accepts the return value', () {
      final os = platformOS();
      // ClientIds.forPlatform must not throw for any platformOS() output
      // (the default case returns 'gateway-client').
      final clientId = ClientIds.forPlatform(os);
      expect(clientId, isNotEmpty);
    });

    test('returns value usable for deviceFamily classification', () {
      final os = platformOS();
      // Providers.dart uses this pattern:
      //   deviceFamily = os == 'ios' || os == 'android' ? 'phone' : 'desktop';
      // Verify the expression doesn't produce unexpected results:
      // - Phone platforms → 'phone'
      // - Everything else → 'desktop'
      final deviceFamily = os == 'ios' || os == 'android' ? 'phone' : 'desktop';
      const validFamilies = ['phone', 'desktop'];
      expect(deviceFamily, isIn(validFamilies));
    });

    // =========================================================================
    // Bug #1 anti-regression: deviceFamily default in ConnectionConfig
    // After Bug #1 fix, the default deviceFamily is 'phone' so that
    // buildConnectParams and buildV3SignaturePayload both use the same
    // value (preventing DEVICE_AUTH_SIGNATURE_INVALID on the server).
    // =========================================================================
    test('ConnectionConfig default deviceFamily is "phone" (Bug #1 lock)', () {
      final config = ConnectionConfig();
      expect(
        config.deviceFamily,
        'phone',
        reason:
            'Bug #1 fix: default must be "phone" so wire and signing paths '
            'always produce the same deviceFamily segment',
      );
    });
  });
}
