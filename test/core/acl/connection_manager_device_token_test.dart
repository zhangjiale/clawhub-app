import 'dart:convert';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_device_token_store.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake IDeviceTokenStore
//
// Minimal in-memory map implementation.  Used to verify ConnectionManager's
// read/write contract without touching FlutterSecureStorage.
// ---------------------------------------------------------------------------

class _FakeDeviceTokenStore implements IDeviceTokenStore {
  final Map<String, String> _store = {};
  final List<String> savedInstances = [];
  final List<String> deletedInstances = [];

  /// Pre-populate the store to simulate a previously-paired device.
  void seed(String instanceId, String deviceToken) {
    _store[instanceId] = deviceToken;
  }

  @override
  Future<void> save(String instanceId, String deviceToken) async {
    _store[instanceId] = deviceToken;
    savedInstances.add(instanceId);
  }

  @override
  Future<String?> load(String instanceId) async {
    final value = _store[instanceId];
    if (value == null || value.isEmpty) return null;
    return value;
  }

  @override
  Future<void> delete(String instanceId) async {
    _store.remove(instanceId);
    deletedInstances.add(instanceId);
  }
}

// ---------------------------------------------------------------------------
// Mock dependencies (signPayload stub)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Helper: extract auth.token from a sent connect frame.
  String extractAuthToken(String sentFrame) {
    final decoded = jsonDecode(sentFrame) as Map<String, dynamic>;
    final params = decoded['params'] as Map<String, dynamic>;
    final auth = params['auth'] as Map<String, dynamic>;
    return auth['token'] as String;
  }

  group('ConnectionManager deviceToken integration (差距 #1)', () {
    // ========================================================================
    // SAVE on hello-ok
    // ========================================================================
    group('hello-ok with auth.deviceToken', () {
      test('persists deviceToken to store on successful hello-ok', () async {
        final ws = ControllableWebSocket.create();
        final tokenStore = _FakeDeviceTokenStore();

        final cm = ConnectionManager(
          instanceId: 'inst-1',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'pairing-code-xyz',
          deviceId: 'test-device',
          config: ConnectionConfig(),
          webSocketFactory: (_) => ws.channel,
          deviceTokenStore: tokenStore,
        );

        cm.connect();
        await pumpMicrotasks();
        ws.completeHandshake();
        await pumpMicrotasks();

        // Receive challenge → send connect request
        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);

        // Server returns hello-ok with a deviceToken
        ws.simulateServerFrame(helloOkWithDeviceTokenJson(reqId, 'dt-new-1'));
        await pumpMicrotasks();

        expect(cm.state, GatewayConnectionState.connected);
        expect(
          tokenStore.savedInstances,
          ['inst-1'],
          reason:
              'ConnectionManager must persist auth.deviceToken to the store '
              'on successful hello-ok (spec §2.2 务必持久化)',
        );
        expect(
          await tokenStore.load('inst-1'),
          'dt-new-1',
          reason: 'the stored value must equal the issued deviceToken',
        );

        await cm.dispose();
      });

      test(
        'does NOT call store.save when hello-ok has no auth.deviceToken',
        () async {
          final ws = ControllableWebSocket.create();
          final tokenStore = _FakeDeviceTokenStore();

          final cm = ConnectionManager(
            instanceId: 'inst-1',
            gatewayUrl: 'ws://localhost:9999/ws',
            token: 'pairing-code-xyz',
            deviceId: 'test-device',
            config: ConnectionConfig(),
            webSocketFactory: (_) => ws.channel,
            deviceTokenStore: tokenStore,
          );

          cm.connect();
          await pumpMicrotasks();
          ws.completeHandshake();
          await pumpMicrotasks();

          ws.simulateServerFrame(challengeJson());
          await pumpMicrotasks();
          final reqId = extractReqId(ws.sentFrames.first);

          // hello-ok without auth.deviceToken (the current real behavior
          // of the spec'd payload, when no fresh token needs issuing).
          ws.simulateServerFrame(helloOkJson(reqId));
          await pumpMicrotasks();

          expect(cm.state, GatewayConnectionState.connected);
          expect(
            tokenStore.savedInstances,
            isEmpty,
            reason:
                'No save when the Gateway did not issue a new deviceToken '
                '(reconnect-with-existing-token case)',
          );

          await cm.dispose();
        },
      );
    });

    // ========================================================================
    // LOAD on connect
    // ========================================================================
    group('connect() prefers cached deviceToken over instance.tokenRef', () {
      test(
        'sends cached deviceToken in connect.auth.token when store has one',
        () async {
          final ws = ControllableWebSocket.create();
          final tokenStore = _FakeDeviceTokenStore();
          tokenStore.seed('inst-1', 'dt-cached-9');

          final cm = ConnectionManager(
            instanceId: 'inst-1',
            gatewayUrl: 'ws://localhost:9999/ws',
            // instance.tokenRef is the FIRST-TIME pairing code; the cached
            // deviceToken must take precedence on subsequent reconnects.
            token: 'pairing-code-xyz',
            deviceId: 'test-device',
            config: ConnectionConfig(),
            webSocketFactory: (_) => ws.channel,
            deviceTokenStore: tokenStore,
          );

          cm.connect();
          await pumpMicrotasks();
          ws.completeHandshake();
          await pumpMicrotasks();

          ws.simulateServerFrame(challengeJson());
          await pumpMicrotasks();

          // The connect frame's auth.token must be the cached deviceToken,
          // not the original pairing code.
          final sentToken = extractAuthToken(ws.sentFrames.first);
          expect(
            sentToken,
            'dt-cached-9',
            reason:
                'Subsequent connects must use the cached deviceToken '
                '(spec §2.2 后续重连复用该令牌)',
          );
          expect(
            sentToken,
            isNot('pairing-code-xyz'),
            reason: 'must NOT fall back to the first-time pairing code',
          );

          await cm.dispose();
        },
      );

      test(
        'falls back to instance.tokenRef when store has no cached token',
        () async {
          final ws = ControllableWebSocket.create();
          final tokenStore = _FakeDeviceTokenStore();
          // No seed() — first-time pairing scenario.

          final cm = ConnectionManager(
            instanceId: 'inst-new',
            gatewayUrl: 'ws://localhost:9999/ws',
            token: 'pairing-code-abc',
            deviceId: 'test-device',
            config: ConnectionConfig(),
            webSocketFactory: (_) => ws.channel,
            deviceTokenStore: tokenStore,
          );

          cm.connect();
          await pumpMicrotasks();
          ws.completeHandshake();
          await pumpMicrotasks();

          ws.simulateServerFrame(challengeJson());
          await pumpMicrotasks();

          final sentToken = extractAuthToken(ws.sentFrames.first);
          expect(
            sentToken,
            'pairing-code-abc',
            reason:
                'First-time pairing (no cached deviceToken) must use '
                'instance.tokenRef as the bearer',
          );

          await cm.dispose();
        },
      );

      test(
        'falls back to instance.tokenRef when store is null (test convenience)',
        () async {
          // Backward-compat: existing tests construct ConnectionManager
          // without passing a deviceTokenStore.  Behavior must not regress.
          final ws = ControllableWebSocket.create();

          final cm = ConnectionManager(
            instanceId: 'inst-no-store',
            gatewayUrl: 'ws://localhost:9999/ws',
            token: 'pairing-code-xyz',
            deviceId: 'test-device',
            config: ConnectionConfig(),
            webSocketFactory: (_) => ws.channel,
            // deviceTokenStore intentionally omitted
          );

          cm.connect();
          await pumpMicrotasks();
          ws.completeHandshake();
          await pumpMicrotasks();

          ws.simulateServerFrame(challengeJson());
          await pumpMicrotasks();

          final sentToken = extractAuthToken(ws.sentFrames.first);
          expect(
            sentToken,
            'pairing-code-xyz',
            reason:
                'When no deviceTokenStore is injected, ConnectionManager '
                'must continue using instance.tokenRef (no regression)',
          );

          await cm.dispose();
        },
      );
    });
  });
}
