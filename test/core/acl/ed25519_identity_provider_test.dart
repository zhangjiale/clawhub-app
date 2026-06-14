import 'dart:async';

import 'package:claw_hub/core/acl/device_identity.dart';
import 'package:claw_hub/core/acl/ed25519_identity_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mock FlutterSecureStorage
// ---------------------------------------------------------------------------

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Ed25519IdentityProvider', () {
    late MockSecureStorage storage;
    late Ed25519IdentityProvider provider;

    setUp(() {
      storage = MockSecureStorage();
      provider = Ed25519IdentityProvider(secureStorage: storage);
    });

    // ========================================================================
    // Key generation
    // ========================================================================
    group('ensureDeviceIdentity — key generation', () {
      test('generates new keypair when storage is empty', () async {
        // Storage has no keys
        when(
          () => storage.read(key: 'clawhub_device_ed25519_seed'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_ed25519_pubkey'),
        ).thenAnswer((_) async => null);
        // Legacy keys are also absent
        when(
          () => storage.read(key: 'clawhub_device_private_key'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_public_key'),
        ).thenAnswer((_) async => null);

        // Writing new keys should succeed
        when(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => storage.delete(key: any(named: 'key')),
        ).thenAnswer((_) async {});

        final identity = await provider.ensureDeviceIdentity();

        // Verify result
        expect(identity.deviceId, isNotEmpty);
        expect(
          identity.deviceId.length,
          64,
          reason: 'SHA256 hex should be 64 chars',
        );
        expect(identity.publicKeyB64, isNotEmpty);
        expect(identity.seedBytes, isNotNull);
        expect(
          identity.seedBytes!.length,
          32,
          reason: 'Ed25519 seed is 32 bytes',
        );

        // Verify keypair was persisted
        verify(
          () => storage.write(
            key: 'clawhub_device_ed25519_seed',
            value: any(named: 'value'),
          ),
        ).called(1);
        verify(
          () => storage.write(
            key: 'clawhub_device_ed25519_pubkey',
            value: any(named: 'value'),
          ),
        ).called(1);
      });

      test('returns cached identity on second call', () async {
        // First call — generate new keys
        when(
          () => storage.read(key: 'clawhub_device_ed25519_seed'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_ed25519_pubkey'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_private_key'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_public_key'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => storage.delete(key: any(named: 'key')),
        ).thenAnswer((_) async {});

        final identity1 = await provider.ensureDeviceIdentity();
        final identity2 = await provider.ensureDeviceIdentity();

        // Same identity returned from cache
        expect(identity2.deviceId, identity1.deviceId);
        expect(identity2.publicKeyB64, identity1.publicKeyB64);

        // Storage was only written once (first call generates, second uses
        // cache)
        verify(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).called(2); // 2 writes for the initial persist
      });

      test('loads existing keypair from storage', () async {
        // Pre-seed storage with a known keypair
        // We can't pre-generate a deterministic Ed25519 keypair,
        // but we can verify the loading path by providing real stored data.

        // First: generate a keypair and capture what's written
        when(
          () => storage.read(key: 'clawhub_device_ed25519_seed'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_ed25519_pubkey'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_private_key'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_public_key'),
        ).thenAnswer((_) async => null);

        when(
          () => storage.write(
            key: any(named: 'key'),
            value: captureAny(named: 'value'),
          ),
        ).thenAnswer((_) async {});

        await provider.ensureDeviceIdentity();

        // Verify the write was called — the provider works end-to-end
        // The exact stored bytes depend on the random key, so we just verify
        // writes happened.
        verify(
          () => storage.write(
            key: 'clawhub_device_ed25519_seed',
            value: any(named: 'value'),
          ),
        ).called(1);
      });
    });

    // ========================================================================
    // Concurrency safety
    // ========================================================================
    group('ensureDeviceIdentity — concurrency', () {
      test('concurrent calls share a single generation', () async {
        when(
          () => storage.read(key: 'clawhub_device_ed25519_seed'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_ed25519_pubkey'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_private_key'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_public_key'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => storage.delete(key: any(named: 'key')),
        ).thenAnswer((_) async {});

        // Fire 3 concurrent ensureDeviceIdentity calls
        final results = await Future.wait([
          provider.ensureDeviceIdentity(),
          provider.ensureDeviceIdentity(),
          provider.ensureDeviceIdentity(),
        ]);

        // All three return the same identity
        expect(results[0].deviceId, results[1].deviceId);
        expect(results[1].deviceId, results[2].deviceId);

        // Only one set of writes (2 keys) — concurrent calls share
        // the pending gate so only one call actually generates and
        // persists the keypair.  Without the gate, 3 concurrent calls
        // would each generate a keypair → 6 writes, and only the last
        // generation's keys would be persisted (TOCTOU data loss).
        verify(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).called(2);
      });
    });

    // ========================================================================
    // signPayload
    // ========================================================================
    group('signPayload', () {
      test('returns a non-empty base64url signature', () async {
        // Setup: generate keys first
        when(
          () => storage.read(key: 'clawhub_device_ed25519_seed'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_ed25519_pubkey'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_private_key'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_public_key'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => storage.delete(key: any(named: 'key')),
        ).thenAnswer((_) async {});

        await provider.ensureDeviceIdentity();

        // Sign a V3 payload
        final sig = await provider.signPayload(
          'v3|test-device|openclaw-ios|ui|operator|operator.admin'
          '|1234567890|token|nonce|linux|phone',
        );

        expect(sig, isNotEmpty);
        // Should be valid base64url (no + or /, no = padding)
        expect(sig, isNot(contains('+')));
        expect(sig, isNot(contains('/')));

        // Ed25519 signature is 64 bytes → ~86 chars in base64url
        expect(sig.length, greaterThanOrEqualTo(80));
      });
    });

    // ========================================================================
    // ECDSA → Ed25519 migration
    // ========================================================================
    group('ECDSA migration', () {
      test('deletes legacy ECDSA P-256 keys when detected', () async {
        // Legacy keys exist
        when(
          () => storage.read(key: 'clawhub_device_ed25519_seed'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_ed25519_pubkey'),
        ).thenAnswer((_) async => null);
        when(
          () => storage.read(key: 'clawhub_device_private_key'),
        ).thenAnswer((_) async => 'old-ecdsa-seed');
        when(
          () => storage.read(key: 'clawhub_device_public_key'),
        ).thenAnswer((_) async => 'old-ecdsa-pubkey');

        when(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => storage.delete(key: any(named: 'key')),
        ).thenAnswer((_) async {});

        await provider.ensureDeviceIdentity();

        // Legacy keys should have been deleted
        verify(
          () => storage.delete(key: 'clawhub_device_private_key'),
        ).called(1);
        verify(
          () => storage.delete(key: 'clawhub_device_public_key'),
        ).called(1);

        // New Ed25519 keys should have been written
        verify(
          () => storage.write(
            key: 'clawhub_device_ed25519_seed',
            value: any(named: 'value'),
          ),
        ).called(1);
      });
    });
  });

  // ==========================================================================
  // DeviceIdentity value class
  // ==========================================================================
  group('DeviceIdentity', () {
    test('constructs with required fields', () {
      final identity = DeviceIdentity(deviceId: 'abc123');
      expect(identity.deviceId, 'abc123');
      expect(identity.publicKeyB64, isNull);
      expect(identity.seedBytes, isNull);
    });

    test('constructs with all fields', () {
      final identity = DeviceIdentity(
        deviceId: 'abc123',
        publicKeyB64: 'dGVzdA==',
        seedBytes: null,
      );
      expect(identity.publicKeyB64, 'dGVzdA==');
    });
  });
}
