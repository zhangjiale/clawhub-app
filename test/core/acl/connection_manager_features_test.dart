import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

ConnectionConfig testConfig() => ConnectionConfig();

/// Build a hello-ok response with a custom `features.events` array.
/// Centralised so every test ships identical JSON shape (a hand-built
/// string with a typo would mask a real parser bug).
String helloOkWithEventsJson(String id, List<String> events) {
  final eventsJson = events.map((e) => '"$e"').join(',');
  return '{"type":"res","id":"$id","ok":true,'
      '"payload":{"type":"hello-ok","protocol":4,'
      '"policy":{"tickIntervalMs":15000},'
      '"features":{"events":[$eventsJson]}}}';
}

void main() {
  // ============================================================================
  // Gap #3: parse hello-ok.features.events into a Set for UI fallback decisions.
  //
  // Spec §2.2 says hello-ok carries `features.events: ["chat", "tick", ...]`
  // listing the event types the Gateway will actually push.  Previously
  // the field was dropped on the floor — the client had no way to tell
  // "Gateway pushes chat" from "Gateway never pushes chat" (silently).
  //
  // These tests pin the contract:
  //   1. Parse events into a Set
  //   2. Expose via `supportedEvents` getter
  //   3. Missing features block → empty Set (backward compat with old
  //      Gateway builds that don't send `features`)
  //   4. Defensive against non-string elements (schema drift protection,
  //      same spirit as F-1 `details` type guard)
  // ============================================================================
  group('ConnectionManager features.events parsing (Gap #3)', () {
    test('parses features.events into supportedEvents set', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
      );

      unawaited(cm.connect());
      await pumpMicrotasks();
      ws.completeHandshake();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.first);

      ws.simulateServerFrame(
        helloOkWithEventsJson(reqId, [
          'chat',
          'tick',
          'health',
          'agent',
          'presence',
        ]),
      );
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);
      expect(
        cm.supportedEvents,
        equals({'chat', 'tick', 'health', 'agent', 'presence'}),
        reason: 'hello-ok.features.events must populate supportedEvents set',
      );

      await cm.dispose();
    });

    test('empty events array yields empty set (not null)', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
      );

      unawaited(cm.connect());
      await pumpMicrotasks();
      ws.completeHandshake();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkWithEventsJson(reqId, []));
      await pumpMicrotasks();

      expect(
        cm.supportedEvents,
        isEmpty,
        reason: 'empty events array must yield empty set, not null',
      );
      // Set, not null — UI must be able to call `.contains()` without
      // null-checks.
      expect(cm.supportedEvents, isA<Set<String>>());

      await cm.dispose();
    });

    test(
      'missing features field falls back to empty set (backward compat)',
      () async {
        final ws = ControllableWebSocket.ready();
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: (_) => ws.channel,
        );

        unawaited(cm.connect());
        await pumpMicrotasks();
        ws.completeHandshake();
        await pumpMicrotasks();

        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);
        // helloOkJson has no `features` block at all (test_helpers.dart).
        ws.simulateServerFrame(helloOkJson(reqId));
        await pumpMicrotasks();

        expect(cm.state, GatewayConnectionState.connected);
        expect(
          cm.supportedEvents,
          isEmpty,
          reason:
              'old Gateway builds that don\'t send `features` must not '
              'crash the client',
        );

        await cm.dispose();
      },
    );

    test(
      'features.events with non-string entries is defensively filtered',
      () async {
        final ws = ControllableWebSocket.ready();
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: (_) => ws.channel,
        );

        unawaited(cm.connect());
        await pumpMicrotasks();
        ws.completeHandshake();
        await pumpMicrotasks();

        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);

        // Hand-built JSON with a non-string element (123) mixed with
        // strings.  This mirrors F-1's `details` type guard — we must
        // not crash on a schema-drift where a future Gateway sends
        // e.g. { "chat": { ... } } for rich event descriptors.
        final raw =
            '{"type":"res","id":"$reqId","ok":true,'
            '"payload":{"type":"hello-ok","protocol":4,'
            '"policy":{"tickIntervalMs":15000},'
            '"features":{"events":["chat",123,"tick",null,"health"]}}}';
        ws.simulateServerFrame(raw);
        await pumpMicrotasks();

        expect(cm.state, GatewayConnectionState.connected);
        expect(
          cm.supportedEvents,
          equals({'chat', 'tick', 'health'}),
          reason:
              'non-string entries (int, null) must be silently '
              'dropped, not crash the parse',
        );

        await cm.dispose();
      },
    );

    test(
      'missing events sub-field (features: {}) falls back to empty set',
      () async {
        final ws = ControllableWebSocket.ready();
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: (_) => ws.channel,
        );

        unawaited(cm.connect());
        await pumpMicrotasks();
        ws.completeHandshake();
        await pumpMicrotasks();

        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);
        // features block exists but no `events` sub-field.
        final raw =
            '{"type":"res","id":"$reqId","ok":true,'
            '"payload":{"type":"hello-ok","protocol":4,'
            '"policy":{"tickIntervalMs":15000},'
            '"features":{"methods":["health","status"]}}}';
        ws.simulateServerFrame(raw);
        await pumpMicrotasks();

        expect(cm.state, GatewayConnectionState.connected);
        expect(
          cm.supportedEvents,
          isEmpty,
          reason:
              'features present but events absent must fall back to empty '
              'set (forward-compat: future Gateway may add features.methods '
              'without features.events)',
        );

        await cm.dispose();
      },
    );

    test('supportedEvents is unmodifiable — caller mutation throws', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
      );

      unawaited(cm.connect());
      await pumpMicrotasks();
      ws.completeHandshake();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkWithEventsJson(reqId, ['chat', 'tick']));
      await pumpMicrotasks();

      // Read-only contract: caller must NOT be able to mutate internal
      // state via the getter. UnmodifiableSetView throws on .add().
      final exposed = cm.supportedEvents;
      expect(
        () => exposed.add('evil-injected'),
        throwsUnsupportedError,
        reason:
            'supportedEvents must expose a read-only view — .add() '
            'must throw, not silently no-op or mutate internal state',
      );

      // After attempted mutation, internal state is unchanged.
      expect(cm.supportedEvents, equals({'chat', 'tick'}));

      await cm.dispose();
    });
  });
}
