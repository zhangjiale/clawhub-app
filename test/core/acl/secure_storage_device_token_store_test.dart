import 'package:claw_hub/core/acl/secure_storage_device_token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mock FlutterSecureStorage
//
// Mirrors the pattern used in ed25519_identity_provider_test.dart.
// ---------------------------------------------------------------------------

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SecureStorageDeviceTokenStore', () {
    late _MockSecureStorage storage;
    late SecureStorageDeviceTokenStore store;

    setUp(() {
      storage = _MockSecureStorage();
      store = SecureStorageDeviceTokenStore(secureStorage: storage);
    });

    // ========================================================================
    // save
    // ========================================================================
    group('save', () {
      test('persists token under per-instance key', () async {
        when(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});

        await store.save('inst-1', 'dt-abc-123');

        verify(
          () => storage.write(
            key: 'clawhub_device_token_inst-1',
            value: 'dt-abc-123',
          ),
        ).called(1);
      });

      test('overwrites previous token for same instance', () async {
        when(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});

        await store.save('inst-1', 'dt-old');
        await store.save('inst-1', 'dt-new');

        // Both writes hit the same key — last write wins, consistent
        // with §4.11 device.token.rotate semantics.
        verify(
          () => storage.write(
            key: 'clawhub_device_token_inst-1',
            value: 'dt-old',
          ),
        ).called(1);
        verify(
          () => storage.write(
            key: 'clawhub_device_token_inst-1',
            value: 'dt-new',
          ),
        ).called(1);
      });

      test('uses distinct keys for distinct instances', () async {
        when(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((_) async {});

        await store.save('inst-A', 'dt-A');
        await store.save('inst-B', 'dt-B');

        verify(
          () =>
              storage.write(key: 'clawhub_device_token_inst-A', value: 'dt-A'),
        ).called(1);
        verify(
          () =>
              storage.write(key: 'clawhub_device_token_inst-B', value: 'dt-B'),
        ).called(1);
      });
    });

    // ========================================================================
    // load
    // ========================================================================
    group('load', () {
      test('returns stored token when present', () async {
        when(
          () => storage.read(key: 'clawhub_device_token_inst-1'),
        ).thenAnswer((_) async => 'dt-abc-123');

        final result = await store.load('inst-1');

        expect(result, 'dt-abc-123');
      });

      test('returns null when storage is empty (first-time pairing)', () async {
        when(
          () => storage.read(key: 'clawhub_device_token_inst-new'),
        ).thenAnswer((_) async => null);

        final result = await store.load('inst-new');

        expect(
          result,
          isNull,
          reason:
              'On first pairing, no cached deviceToken exists; '
              'connect must fall back to instance.tokenRef',
        );
      });

      test('returns null when stored value is empty string', () async {
        when(
          () => storage.read(key: 'clawhub_device_token_inst-1'),
        ).thenAnswer((_) async => '');

        final result = await store.load('inst-1');

        expect(
          result,
          isNull,
          reason:
              'Empty string is treated as absent to avoid sending '
              'an empty bearer token to the Gateway',
        );
      });
    });

    // ========================================================================
    // delete
    // ========================================================================
    group('delete', () {
      test('removes stored token', () async {
        when(
          () => storage.delete(key: any(named: 'key')),
        ).thenAnswer((_) async {});

        await store.delete('inst-1');

        verify(
          () => storage.delete(key: 'clawhub_device_token_inst-1'),
        ).called(1);
      });
    });
  });
}
