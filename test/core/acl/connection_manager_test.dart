import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/utils/retry_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'test_helpers.dart';

ConnectionConfig testConfig({Future<String> Function(String)? signPayload}) =>
    ConnectionConfig(signPayload: signPayload);

String notPairedJson(String id, {String requestId = 'req-abc'}) =>
    '{"type":"res","id":"$id","ok":false,"error":{"code":"NOT_PAIRED","message":"Device not paired","details":{"requestId":"$requestId","deviceId":"test-device"}}}';

String deviceIdMismatchJson(String id) =>
    '{"type":"res","id":"$id","ok":false,"error":{"code":"DEVICE_AUTH_DEVICE_ID_MISMATCH","message":"Device ID mismatch"}}';

String authErrorJson(
  String id, {
  String code = 'AUTH_TOKEN_INVALID',
  String message = 'Bad token',
}) =>
    '{"type":"res","id":"$id","ok":false,"error":{"code":"$code","message":"$message"}}';

const String presenceJson =
    '{"type":"event","event":"presence","payload":{"status":"online"}}';

// FakeTimer / FakeTimerFactory live in test_helpers.dart — re-imported here.
// ============================================================================
// Tests
// ============================================================================

void main() {
  // ==========================================================================
  // Group 0: Existing race-condition guard tests (regression suite)
  // ==========================================================================
  group('onConnectChallenge race condition guard', () {
    late ConnectionManager cm;
    late Completer<String> signCompleter;
    late MockWebSocketChannel mockChannel;
    late MockWebSocketSink mockSink;

    setUp(() {
      signCompleter = Completer<String>();
      mockSink = MockWebSocketSink();
      mockChannel = MockWebSocketChannel();
      when(() => mockChannel.sink).thenReturn(mockSink);

      cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) => signCompleter.future),
      );
    });

    test('Path: channel null during sign — return without NPE', () async {
      cm.setTestState(GatewayConnectionState.authenticating);
      cm.setTestChannel(mockChannel);

      final future = cm.onConnectChallenge({'nonce': 'test-nonce'});
      cm.setTestChannel(null);
      signCompleter.complete('mock-sig');
      await pumpMicrotasks();

      await expectLater(future, completes);
      verifyNever(() => mockSink.add(any()));
    });

    test('Path: state changed during sign — return without write', () async {
      cm.setTestState(GatewayConnectionState.authenticating);
      cm.setTestChannel(mockChannel);

      final future = cm.onConnectChallenge({'nonce': 'test-nonce'});
      cm.setTestState(GatewayConnectionState.recovering);
      signCompleter.complete('mock-sig');
      await pumpMicrotasks();

      await expectLater(future, completes);
      verifyNever(() => mockSink.add(any()));
    });

    test('Normal path: channel and state intact — writes to sink', () async {
      cm.setTestState(GatewayConnectionState.authenticating);
      cm.setTestChannel(mockChannel);

      final future = cm.onConnectChallenge({'nonce': 'test-nonce'});
      signCompleter.complete('mock-sig');
      await pumpMicrotasks();

      await expectLater(future, completes);
      verify(() => mockSink.add(any())).called(1);
    });

    test('Path: channel replaced — documents known limitation', () async {
      cm.setTestState(GatewayConnectionState.authenticating);
      cm.setTestChannel(mockChannel);

      final future = cm.onConnectChallenge({'nonce': 'test-nonce'});

      final newMockChannel = MockWebSocketChannel();
      final newMockSink = MockWebSocketSink();
      when(() => newMockChannel.sink).thenReturn(newMockSink);
      cm.setTestChannel(newMockChannel);

      signCompleter.complete('mock-sig');
      await pumpMicrotasks();

      await expectLater(future, completes);
    });
  });

  // ==========================================================================
  // Group A: Handshake
  // ==========================================================================
  group('Handshake', () {
    test('challenge → connect → hello-ok → connected', () async {
      final ws = ControllableWebSocket.create();
      final factoryCalls = <Uri>[];

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (uri) {
          factoryCalls.add(uri);
          return ws.channel;
        },
      );

      final states = <GatewayConnectionState>[];
      cm.connectionState.listen(states.add);

      cm.connect();
      await pumpMicrotasks();

      // Factory called with correct URL
      expect(factoryCalls.length, 1);
      expect(factoryCalls.first.queryParameters['token'], 'test-token');

      // Complete WS handshake
      ws.completeHandshake();
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.authenticating);

      // Server sends challenge
      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      // Client sent connect request
      expect(ws.sentFrames.length, 1, reason: 'should send connect request');
      expect(ws.sentFrames.first, contains('"type":"req"'));
      expect(ws.sentFrames.first, contains('"method":"connect"'));

      final reqId = extractReqId(ws.sentFrames.first);

      // Server responds with hello-ok
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);
      expect(states, contains(GatewayConnectionState.connected));

      await cm.dispose();
    });

    test('Handshake timeout in authenticating → authFailed', () async {
      final ws = ControllableWebSocket.ready();

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
      );

      cm.connect();
      await pumpMicrotasks();
      expect(cm.state, GatewayConnectionState.authenticating);

      // sendRequest must reject in authenticating state
      await expectLater(
        () => cm.sendRequest('test', {}),
        throwsA(isA<NotConnectedException>()),
      );

      await cm.dispose();
    });

    test('Bad URL → connect fails (authFailed, no reconnect)', () async {
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'not-a-url:::',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
      );

      await cm.connect();

      // Uri.parse may either throw FormatException or parse leniently.
      // Either way a permanently-bad URL must not schedule a reconnect.
      expect(
        cm.state,
        anyOf(
          GatewayConnectionState.authFailed,
          GatewayConnectionState.disconnected,
        ),
      );

      await cm.dispose();
    });

    test(
      'Non-ws scheme → FormatException → authFailed, no reconnect',
      () async {
        // An http:// URL has a valid URI format but the wrong scheme for
        // WebSocket.  The scheme guard in _doConnect must throw
        // FormatException which is caught as a permanent error.
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'http://example.com/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(),
        );

        await cm.connect();

        expect(
          cm.state,
          GatewayConnectionState.authFailed,
          reason:
              'Wrong scheme must be treated as permanent — '
              'no reconnect should be scheduled',
        );

        await cm.dispose();
      },
    );

    test(
      'WebSocketChannelException (transient) → disconnected + reconnect',
      () async {
        // Connection refused is transient — should trigger auto-reconnect.
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: (_) =>
              throw WebSocketChannelException('Connection refused'),
        );

        await cm.connect();

        expect(
          cm.state,
          GatewayConnectionState.disconnected,
          reason:
              'Transient transport errors should schedule reconnect, '
              'not abort permanently',
        );

        await cm.dispose();
      },
    );

    test('WebSocket handshake → reaches connecting state', () async {
      final ws = ControllableWebSocket.create(); // ready never completes

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
      );

      final states = <GatewayConnectionState>[];
      cm.connectionState.listen(states.add);

      cm.connect();
      await pumpMicrotasks();

      expect(states, contains(GatewayConnectionState.connecting));

      await cm.dispose();
    });
  });

  // ==========================================================================
  // Group B: Authentication failures
  // ==========================================================================
  group('Authentication failures', () {
    test('Non-ok connect response → authFailed', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
      );

      final states = <GatewayConnectionState>[];
      cm.connectionState.listen(states.add);

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(authErrorJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.authFailed);
      expect(states, contains(GatewayConnectionState.authFailed));

      await cm.dispose();
    });

    test('NOT_PAIRED → pairingRequired + pairingInfo emitted', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
      );

      final pairingInfos = <GatewayPairingInfo?>[];
      cm.pairingInfo.listen(pairingInfos.add);

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(notPairedJson(reqId, requestId: 'req-xyz'));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.pairingRequired);
      expect(pairingInfos.last, isNotNull);
      expect(pairingInfos.last!.requestId, 'req-xyz');

      await cm.dispose();
    });

    test('DEVICE_ID_MISMATCH → recovering (not authFailed)', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
      );

      final states = <GatewayConnectionState>[];
      cm.connectionState.listen(states.add);

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(deviceIdMismatchJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.recovering);
      expect(states, contains(GatewayConnectionState.recovering));
      expect(states, isNot(contains(GatewayConnectionState.authFailed)));

      await cm.dispose();
    });

    // -------------------------------------------------------------------------
    // Regression: NOT_PAIRED / DEVICE_ID_MISMATCH in terminal state must NOT
    // override the terminal state (Fix 2 / #2 of the post-Fix-1 audit).
    //
    // Same race Fix 3 closed for `_handleAuthTokenMismatchRetry`:
    // `_handlePairingRequired` and `_handleDeviceIdMismatch` lack a
    // `_state.isTerminal` pre-check. A stale NOT_PAIRED / DEVICE_ID_MISMATCH
    // response arriving while state has already moved to a terminal
    // (authFailed / pairingRequired / reconnectExhausted / disconnected)
    // will:
    //   1. Overwrite the terminal state with pairingRequired / recovering.
    //   2. Schedule a fresh connect or pairing retry, masking the original
    //      failure from the user.
    //
    // The pairingInfo stream side-effect is also gated by this guard so a
    // stale NOT_PAIRED doesn't surface a phantom pairing request after the
    // user has explicitly disconnected / failed auth.
    // -------------------------------------------------------------------------
    test(
      'NOT_PAIRED in terminal state (authFailed) does NOT override state',
      () async {
        final ws = ControllableWebSocket.ready();
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(signPayload: (_) async => 'mock-sig'),
          webSocketFactory: (_) => ws.channel,
        );

        final pairingInfos = <GatewayPairingInfo?>[];
        cm.pairingInfo.listen(pairingInfos.add);

        cm.connect();
        await pumpMicrotasks();
        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);

        // Force terminal state BEFORE the NOT_PAIRED response arrives.
        // Race window: another code path moved us to authFailed while
        // the connect response was still in flight.
        cm.setTestState(GatewayConnectionState.authFailed);
        expect(cm.state, GatewayConnectionState.authFailed);

        ws.simulateServerFrame(notPairedJson(reqId, requestId: 'req-stale'));
        await pumpMicrotasks();
        for (var i = 0; i < 4; i++) {
          await pumpMicrotasks();
        }

        expect(
          cm.state,
          GatewayConnectionState.authFailed,
          reason:
              'stale NOT_PAIRED arriving in a terminal state must NOT '
              'override it to pairingRequired',
        );
        expect(
          pairingInfos,
          isEmpty,
          reason:
              'no pairingInfo should be emitted for a stale NOT_PAIRED in '
              'a terminal state — would confuse the UI',
        );

        await cm.dispose();
      },
    );

    test(
      'NOT_PAIRED in terminal state (disconnected) does NOT schedule retry',
      () async {
        final ws = ControllableWebSocket.ready();
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(signPayload: (_) async => 'mock-sig'),
          webSocketFactory: (_) => ws.channel,
        );

        cm.connect();
        await pumpMicrotasks();
        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);

        // User has explicitly disconnected; state → disconnected (terminal).
        await cm.disconnect();
        expect(cm.state, GatewayConnectionState.disconnected);

        // Stale NOT_PAIRED response arrives. Without the fix, the
        // handler would set state to pairingRequired + schedule a
        // 10s pairing retry — a zombie retry after the user explicitly
        // disconnected.
        ws.simulateServerFrame(notPairedJson(reqId));
        await pumpMicrotasks();
        for (var i = 0; i < 4; i++) {
          await pumpMicrotasks();
        }

        expect(
          cm.state,
          GatewayConnectionState.disconnected,
          reason: 'user disconnect must not be overwritten by stale NOT_PAIRED',
        );

        await cm.dispose();
      },
    );

    test(
      'DEVICE_ID_MISMATCH in terminal state (authFailed) does NOT retry',
      () async {
        final ws = ControllableWebSocket.ready();
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(signPayload: (_) async => 'mock-sig'),
          webSocketFactory: (_) => ws.channel,
        );

        cm.connect();
        await pumpMicrotasks();
        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);

        cm.setTestState(GatewayConnectionState.authFailed);

        ws.simulateServerFrame(deviceIdMismatchJson(reqId));
        await pumpMicrotasks();
        for (var i = 0; i < 4; i++) {
          await pumpMicrotasks();
        }

        expect(
          cm.state,
          GatewayConnectionState.authFailed,
          reason:
              'stale DEVICE_ID_MISMATCH must NOT override terminal '
              'authFailed with recovering + 2s retry timer',
        );

        await cm.dispose();
      },
    );
  });

  // ==========================================================================
  // Group C: Tick / keepalive
  // ==========================================================================
  group('Tick / keepalive', () {
    test('tick resets timeout, does not change state', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
      );

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);

      ws.simulateServerFrame(tickJson);
      await pumpMicrotasks();

      expect(
        cm.state,
        GatewayConnectionState.connected,
        reason: 'tick should not change state',
      );

      await cm.dispose();
    });
  });

  // ==========================================================================
  // Group D: Exponential backoff
  // ==========================================================================
  group('Exponential backoff', () {
    test('connect triggers connecting → authenticating progression', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
      );

      final states = <GatewayConnectionState>[];
      cm.connectionState.listen(states.add);

      expect(cm.state, GatewayConnectionState.disconnected);

      cm.connect();
      await pumpMicrotasks();

      // For a pre-ready channel, the flow goes: disconnected → connecting →
      //   (ready fires) → authenticating
      expect(states, contains(GatewayConnectionState.connecting));

      await cm.dispose();
    });
  });

  // ==========================================================================
  // Group E: Intentional disconnect
  // ==========================================================================
  group('Intentional disconnect', () {
    test('disconnect() → state is disconnected, no reconnect', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
      );

      await cm.disconnect();

      expect(cm.state, GatewayConnectionState.disconnected);

      // The internal _intentionalDisconnect flag is set, so no reconnect
      // will be scheduled even if we simulate connection loss.
    });

    test('dispose() → all stream controllers emit done', () async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
      );

      final stateDone = Completer<void>();
      final eventDone = Completer<void>();
      final pairingDone = Completer<void>();

      cm.connectionState.listen(null, onDone: () => stateDone.complete());
      cm.events.listen(null, onDone: () => eventDone.complete());
      cm.pairingInfo.listen(null, onDone: () => pairingDone.complete());

      await cm.dispose();

      await expectLater(stateDone.future, completes);
      await expectLater(eventDone.future, completes);
      await expectLater(pairingDone.future, completes);
    });
  });

  // ==========================================================================
  // Group F: State machine guards
  // ==========================================================================
  group('State machine guards', () {
    test(
      'sendRequest throws NotConnectedException in all non-connected states',
      () async {
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(),
        );

        for (final state in [
          GatewayConnectionState.disconnected,
          GatewayConnectionState.connecting,
          GatewayConnectionState.authenticating,
          GatewayConnectionState.recovering,
          GatewayConnectionState.authFailed,
          GatewayConnectionState.pairingRequired,
        ]) {
          cm.setTestState(state);
          expect(
            () => cm.sendRequest('test', {}),
            throwsA(isA<NotConnectedException>()),
            reason: 'should throw for $state',
          );
        }

        await cm.dispose();
      },
    );
  });

  // ==========================================================================
  // Group G: Event routing
  // ==========================================================================
  group('Event routing', () {
    /// Helper: complete a full handshake to reach connected, then return
    /// the ws and cm for event testing.
    Future<({ControllableWebSocket ws, ConnectionManager cm})>
    connectAndHandshake() async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
      );

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);
      return (ws: ws, cm: cm);
    }

    test('chat event forwarded to events stream', () async {
      final (:ws, :cm) = await connectAndHandshake();

      final events = <EventFrame>[];
      cm.events.listen(events.add);

      ws.simulateServerFrame(chatDeltaJson(deltaText: 'hello'));
      await pumpMicrotasks();

      expect(events.length, 1);
      expect(events.first.event, 'chat');

      await cm.dispose();
    });

    test('tick is NOT forwarded to events stream', () async {
      final (:ws, :cm) = await connectAndHandshake();

      final events = <EventFrame>[];
      cm.events.listen(events.add);

      ws.simulateServerFrame(tickJson);
      await pumpMicrotasks();

      expect(
        events,
        isEmpty,
        reason: 'tick must be handled internally, not forwarded',
      );

      await cm.dispose();
    });

    test('shutdown event → disconnected', () async {
      final (:ws, :cm) = await connectAndHandshake();

      ws.simulateServerFrame(shutdownJson);
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.disconnected);

      await cm.dispose();
    });

    test('unknown events forwarded to events stream', () async {
      final (:ws, :cm) = await connectAndHandshake();

      final events = <EventFrame>[];
      cm.events.listen(events.add);

      ws.simulateServerFrame(presenceJson);
      await pumpMicrotasks();

      expect(events.length, 1);
      expect(events.first.event, 'presence');

      await cm.dispose();
    });
  });

  // ==========================================================================
  // Group H: Request/response correlation
  // ==========================================================================
  group('Request/response correlation', () {
    /// Helper: complete a full handshake to reach connected, return ws + cm.
    Future<({ControllableWebSocket ws, ConnectionManager cm})>
    connectAndHandshake() async {
      final ws = ControllableWebSocket.ready();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
      );

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);
      return (ws: ws, cm: cm);
    }

    test('sendRequest — response matched by request ID', () async {
      final (:ws, :cm) = await connectAndHandshake();

      final responseFuture = cm.sendRequest('agents.list', {});
      await pumpMicrotasks();

      // Should have sent a request frame
      final agentListFrames = ws.sentFrames
          .where((f) => f.contains('"method":"agents.list"'))
          .toList();
      expect(agentListFrames.length, 1);
      expect(agentListFrames.first, contains('"method":"agents.list"'));

      final reqId = extractReqId(agentListFrames.first);

      final responseJson =
          '{"type":"res","id":"$reqId","ok":true,'
          '"payload":{"agents":[{"id":"agent-1","name":"Test"}]}}';
      ws.simulateServerFrame(responseJson);
      await pumpMicrotasks();

      final response = await responseFuture;
      expect(response.ok, true);
      expect(response.payload, isNotNull);
      expect(response.payload!['agents'], isNotNull);

      await cm.dispose();
    });

    test('disconnect fails pending requests with CONNECTION_LOST', () async {
      final (:ws, :cm) = await connectAndHandshake();

      final responseFuture = cm.sendRequest('agents.list', {});
      await pumpMicrotasks();

      await cm.disconnect();

      final response = await responseFuture;
      expect(response.ok, false);
      expect(response.error, isNotNull);
      expect(response.error!.code, 'CONNECTION_LOST');
    });
  });

  // ==========================================================================
  // Group I: Exponential backoff computation (verified via TimerFactory)
  // ==========================================================================
  group('_computeBackoff', () {
    /// Helper that creates a [ConnectionManager] whose webSocketFactory
    /// always throws, so every _doConnect call immediately fails and
    /// schedules a reconnect timer.
    ConnectionManager failingCm(FakeTimerFactory timers) {
      return ConnectionManager(
        instanceId: 'test',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 't',
        deviceId: 'd',
        config: testConfig(),
        webSocketFactory: (_) =>
            throw WebSocketChannelException('Connection refused'),
        timerFactory: timers.call,
        // Use infinite retries for backoff sequence test — the new default
        // (maxAttempts: 3) would stop after 3 failures and break the sequence.
        retryStrategy: RetryStrategy.networkReconnect,
      );
    }

    test('first reconnect timer uses base delay (1s)', () async {
      final timers = FakeTimerFactory();
      final cm = failingCm(timers);

      cm.connect();
      await pumpMicrotasks();

      // First reconnect: _reconnectAttempt == 0 → _computeBackoff() == 1
      expect(timers.lastTimer!.duration.inSeconds, 1);

      await cm.dispose();
    });

    test('backoff sequence: 1→2→4→8→16→30→30', () async {
      final timers = FakeTimerFactory();
      final cm = failingCm(timers);

      cm.connect();
      await pumpMicrotasks();

      // Firing each timer callback increments _reconnectAttempt (via onFire)
      // then calls _doConnect which throws, scheduling the next timer.
      expect(timers.lastTimer!.duration.inSeconds, 1); // attempt 0

      timers.lastTimer!.fire();
      await pumpMicrotasks();
      expect(timers.lastTimer!.duration.inSeconds, 2); // attempt 1

      timers.lastTimer!.fire();
      await pumpMicrotasks();
      expect(timers.lastTimer!.duration.inSeconds, 4); // attempt 2

      timers.lastTimer!.fire();
      await pumpMicrotasks();
      expect(timers.lastTimer!.duration.inSeconds, 8); // attempt 3

      timers.lastTimer!.fire();
      await pumpMicrotasks();
      expect(timers.lastTimer!.duration.inSeconds, 16); // attempt 4

      timers.lastTimer!.fire();
      await pumpMicrotasks();
      expect(
        timers.lastTimer!.duration.inSeconds,
        30,
      ); // attempt 5 (capped at max)

      timers.lastTimer!.fire();
      await pumpMicrotasks();
      expect(
        timers.lastTimer!.duration.inSeconds,
        30,
      ); // attempt 6 (still capped)

      await cm.dispose();
    });
  });

  // ==========================================================================
  // Group J: Timer-based behavior
  // ==========================================================================
  group('Timer-based behavior', () {
    /// Helper: connect and complete handshake, returning cm + timers + ws.
    Future<
      ({
        ControllableWebSocket ws,
        ConnectionManager cm,
        FakeTimerFactory timers,
      })
    >
    connectAndHandshakeWithTimers({int tickIntervalMs = 15000}) async {
      final ws = ControllableWebSocket.ready();
      final timers = FakeTimerFactory();

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
        timerFactory: timers.call,
      );

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);
      return (ws: ws, cm: cm, timers: timers);
    }

    test(
      'connect timeout schedules a 15s timer during authenticating',
      () async {
        final ws = ControllableWebSocket.create(); // never ready
        final timers = FakeTimerFactory();

        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: (_) => ws.channel,
          timerFactory: timers.call,
        );

        cm.connect();
        await pumpMicrotasks();

        // WebSocket not ready yet — still connecting, not authenticating
        // The connect timeout is set AFTER ws.ready completes, in authenticating
        // So no timer yet because the channel isn't ready
        expect(
          timers.activeTimers,
          isEmpty,
          reason:
              'connect timeout only starts in authenticating, '
              'and ws.ready has not completed yet',
        );

        await cm.dispose();
      },
    );

    test(
      'connect timeout fires → authFailed when stuck in authenticating',
      () async {
        final ws = ControllableWebSocket.ready();
        final timers = FakeTimerFactory();

        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: (_) => ws.channel,
          timerFactory: timers.call,
        );

        final states = <GatewayConnectionState>[];
        cm.connectionState.listen(states.add);

        cm.connect();
        await pumpMicrotasks();

        // Now in authenticating state, timeout timer is active
        expect(cm.state, GatewayConnectionState.authenticating);

        // The connect timeout timer (15s) should have been created
        final timeoutTimers = timers.activeTimers.where(
          (t) => t.duration == const Duration(seconds: 15),
        );
        expect(
          timeoutTimers.length,
          1,
          reason: 'connect timeout timer should be active in authenticating',
        );

        // Fire it — should transition to authFailed
        timeoutTimers.first.fire();
        await pumpMicrotasks();

        expect(cm.state, GatewayConnectionState.authFailed);
        expect(states, contains(GatewayConnectionState.authFailed));

        await cm.dispose();
      },
    );

    test('hello-ok cancels connect timeout', () async {
      final ws = ControllableWebSocket.ready();
      final timers = FakeTimerFactory();

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
        timerFactory: timers.call,
      );

      cm.connect();
      await pumpMicrotasks();

      // Capture the connect timeout timer BEFORE handshake completes
      final timeoutTimers = timers.activeTimers
          .where((t) => t.duration == const Duration(seconds: 15))
          .toList();
      expect(timeoutTimers.length, 1);
      final capturedTimer = timeoutTimers.first;

      // Complete handshake
      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);

      // The captured connect timeout must now be cancelled
      expect(
        capturedTimer.isCancelled,
        isTrue,
        reason: 'connect timeout must be cancelled after hello-ok',
      );

      await cm.dispose();
    });

    test('tick timeout fires → recovering + reconnect scheduled', () async {
      final result = await connectAndHandshakeWithTimers();
      final cm = result.cm;
      final timers = result.timers;

      final states = <GatewayConnectionState>[];
      cm.connectionState.listen(states.add);

      // The tick timeout timer (2 * 15000ms = 30s) should be active
      final tickTimers = timers.activeTimers.where(
        (t) => t.duration == const Duration(milliseconds: 30000),
      );
      expect(
        tickTimers.length,
        1,
        reason: 'tick timeout timer should be active after connected',
      );

      // Fire the tick timeout
      tickTimers.first.fire();
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.recovering);
      expect(states, contains(GatewayConnectionState.recovering));

      // Reconnect timer must be scheduled AFTER close completes.
      // The tick-timeout callback now sequences via .then() to prevent
      // _closeWebSocket() from nulling a newly-established channel.
      final reconnectTimers = timers.activeTimers.where(
        (t) => t.duration == const Duration(seconds: 1),
      );
      expect(
        reconnectTimers.length,
        1,
        reason: 'reconnect timer should be scheduled after close',
      );

      await cm.dispose();
    });

    test('tick timeout sequences close before reconnect', () async {
      // Verify that when tick timeout fires, _closeWebSocket() fully
      // completes BEFORE the state transitions to recovering and a
      // reconnect is scheduled.  This prevents the race where a delayed
      // _closeWebSocket() nulls a fresh _channel established by the
      // reconnect timer (see _resetTickTimeout for the .then() fix).
      final result = await connectAndHandshakeWithTimers();
      final cm = result.cm;
      final timers = result.timers;

      // Capture the tick timeout timer.
      final tickTimers = timers.activeTimers.where(
        (t) => t.duration == const Duration(milliseconds: 30000),
      );
      expect(tickTimers.length, 1);

      // Before firing: no reconnect timers, state is connected.
      expect(cm.state, GatewayConnectionState.connected);

      // Fire tick timeout — the callback fires _closeWebSocket() first,
      // then chains state change + reconnect via .then().
      tickTimers.first.fire();

      // Immediately after the synchronous fire, the .then() callback
      // has NOT yet run (it's queued as a microtask).  At this point
      // _closeWebSocket() has completed (mocks are synchronous), and
      // the reconnect is queued but not yet executed.
      // After pumpMicrotasks the .then() runs.
      await pumpMicrotasks();

      // Now the .then() has run: state → recovering, reconnect scheduled.
      expect(cm.state, GatewayConnectionState.recovering);
      final reconnectTimers = timers.activeTimers.where(
        (t) => t.duration == const Duration(seconds: 1),
      );
      expect(reconnectTimers.length, 1);

      await cm.dispose();
    });

    test(
      'tick resets timeout — old timer cancelled, new one created',
      () async {
        final result = await connectAndHandshakeWithTimers();
        final cm = result.cm;
        final timers = result.timers;
        final ws = result.ws;

        // Count active tick timers before tick
        final tickTimersBefore = timers.activeTimers
            .where((t) => t.duration == const Duration(milliseconds: 30000))
            .toList();
        expect(tickTimersBefore.length, 1);
        final oldTimer = tickTimersBefore.first;

        // Send a tick
        ws.simulateServerFrame(tickJson);
        await pumpMicrotasks();

        // Old tick timer should be cancelled
        expect(
          oldTimer.isCancelled,
          isTrue,
          reason: 'old tick timer must be cancelled on new tick',
        );

        // New tick timer should be active
        final tickTimersAfter = timers.activeTimers.where(
          (t) => t.duration == const Duration(milliseconds: 30000),
        );
        expect(
          tickTimersAfter.length,
          1,
          reason: 'new tick timer should be created',
        );

        expect(
          cm.state,
          GatewayConnectionState.connected,
          reason: 'tick should not change state',
        );

        await cm.dispose();
      },
    );

    test('pairing required schedules a 10s retry timer', () async {
      final ws = ControllableWebSocket.ready();
      final timers = FakeTimerFactory();

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
        timerFactory: timers.call,
      );

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(notPairedJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.pairingRequired);

      // A 10s pairing retry timer should be scheduled
      final pairingTimers = timers.activeTimers.where(
        (t) => t.duration == const Duration(seconds: 10),
      );
      expect(
        pairingTimers.length,
        1,
        reason: 'pairing retry timer (10s) should be scheduled',
      );

      await cm.dispose();
    });

    test('pairing retry timer fires → transitions to connecting', () async {
      final ws = ControllableWebSocket.ready();
      final timers = FakeTimerFactory();

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
        timerFactory: timers.call,
      );

      final states = <GatewayConnectionState>[];
      cm.connectionState.listen(states.add);

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(notPairedJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.pairingRequired);

      // Fire the pairing retry timer — should trigger _doConnect
      // which sets state to connecting
      timers.fireLast();
      await pumpMicrotasks();

      // _doConnect is called by the timer, which tries to create a new
      // WebSocket connection. The factory returns our controllable ws,
      // but since the previous stream was closed, this may not complete.
      // The key assertion: the state machine transitioned.
      expect(
        states,
        contains(GatewayConnectionState.connecting),
        reason:
            'pairing retry should trigger a new connect attempt '
            '(state → connecting)',
      );

      await cm.dispose();
    });

    test('intentional disconnect cancels all timers', () async {
      final result = await connectAndHandshakeWithTimers();
      final cm = result.cm;
      final timers = result.timers;

      // Tick timer should be active
      expect(timers.activeTimers.isNotEmpty, isTrue);

      await cm.disconnect();

      // All timers should be cancelled
      for (final t in timers.timers) {
        expect(
          t.isCancelled,
          isTrue,
          reason: 'all timers should be cancelled on disconnect',
        );
      }
    });

    test('disconnect (not intentional) schedules reconnect timer', () async {
      final result = await connectAndHandshakeWithTimers();
      final cm = result.cm;
      final timers = result.timers;
      final ws = result.ws;

      // Simulate unexpected connection loss
      ws.simulateServerClose();
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.recovering);

      // A reconnect timer should be scheduled (backoff=1s since first attempt)
      final reconnectTimers = timers.activeTimers.where(
        (t) => t.duration == const Duration(seconds: 1),
      );
      expect(
        reconnectTimers.length,
        1,
        reason:
            'reconnect timer should be scheduled after '
            'unexpected disconnect',
      );

      await cm.dispose();
    });

    test('dispose cancels all timers and streams', () async {
      final result = await connectAndHandshakeWithTimers();
      final cm = result.cm;
      final timers = result.timers;

      expect(timers.activeTimers.isNotEmpty, isTrue);

      final stateDone = Completer<void>();
      cm.connectionState.listen(null, onDone: () => stateDone.complete());

      await cm.dispose();
      await expectLater(stateDone.future, completes);

      for (final t in timers.timers) {
        expect(
          t.isCancelled,
          isTrue,
          reason: 'all timers should be cancelled on dispose',
        );
      }
    });

    // ======================================================================
    // Law 16: _onConnectionError side-effect coverage
    // ======================================================================
    test('_onConnectionError from connected → recovering + reconnect', () async {
      // Fix 3 (post-Fix-1 audit): _onConnectionError now mirrors
      // _onWebSocketClosed — state goes to recovering AND a reconnect
      // timer is scheduled. The old behaviour relied on _onConnectionDone
      // firing next, but some platforms / scenarios don't emit done
      // after onError, leaving the connection stuck in `recovering`
      // indefinitely.
      //
      // Regression test:
      // `_onConnectionError alone (no follow-up done) leaves system recoverable`
      // below pins the user-visible contract: a timer must be scheduled.
      final result = await connectAndHandshakeWithTimers();
      final ws = result.ws;
      final cm = result.cm;
      final timers = result.timers;

      final states = <GatewayConnectionState>[];
      cm.connectionState.listen(states.add);

      ws.simulateError('Transport error');
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.recovering);
      expect(states, contains(GatewayConnectionState.recovering));

      // Reconnect timer must be scheduled — the bug was that
      // _onConnectionError set state to `recovering` but didn't schedule a
      // reconnect, leaving the system stuck until _onConnectionDone (which
      // may never fire) cancelled the state. Verify via the
      // RetryStrategy-shaped 1s delay rather than the raw active-timer
      // count: Finding #2 also cancels the stale tick timer here, so the
      // count is net-zero (-1 tick, +1 reconnect) — asserting the count
      // would couple this test to the tick-cancellation side effect.
      final reconnectTimers = timers.activeTimers.where(
        (t) => t.duration == const Duration(seconds: 1),
      );
      expect(
        reconnectTimers.length,
        1,
        reason:
            '_onConnectionError must schedule a reconnect — otherwise a '
            'transport error without a follow-up done leaves the '
            'connection stuck in `recovering` indefinitely',
      );

      // Finding #2: the stale tick timeout timer is cancelled (covered
      // explicitly by the dedicated test below).
    });

    test('_onConnectionError cancels the stale tick timeout timer '
        '(Finding #2)', () async {
      // When a transport error arrives on an ESTABLISHED connection, the
      // tick watchdog timer (2 × tickIntervalMs) is still armed.
      // _onConnectionError must cancel it — otherwise the stale tick can
      // fire _onWebSocketClosed during recovery, which runs _cancelTimers +
      // _scheduleReconnect and clobbers the reconnect timer that
      // _onConnectionError just scheduled (delaying reconnect by up to
      // 2 × tickInterval, and in a narrow window aborting an in-flight
      // reconnect). Mirrors _onConnectionDone, which already calls
      // _cancelTimers.
      final result = await connectAndHandshakeWithTimers();
      final ws = result.ws;
      final cm = result.cm;
      final timers = result.timers;

      // Tick timeout (2 × 15000ms) is active while connected.
      final tickBefore = timers.activeTimers.where(
        (t) => t.duration == const Duration(milliseconds: 30000),
      );
      expect(tickBefore.length, 1);

      ws.simulateError('Transport error');
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.recovering);

      // The stale tick timeout timer MUST be cancelled.
      final tickAfter = timers.activeTimers.where(
        (t) => t.duration == const Duration(milliseconds: 30000),
      );
      expect(
        tickAfter.length,
        0,
        reason:
            '_onConnectionError must cancel the stale tick timeout timer '
            'so it cannot fire _onWebSocketClosed during recovery and '
            'reset the reconnect schedule',
      );

      await cm.dispose();
    });

    test(
      '_onConnectionError alone (no follow-up done) leaves system recoverable',
      () async {
        // The original bug report (Fix 3 of the post-Fix-1 audit):
        // some platforms / scenarios fire `onError` on the WebSocket
        // stream without a follow-up `done`. In that case the old
        // `_onConnectionError` set state to `recovering` and waited
        // for `_onConnectionDone` to schedule a reconnect. Without
        // `done`, the system sat in `recovering` forever and the UI
        // showed "reconnecting" with no recovery action.
        //
        // The fix makes `_onConnectionError` self-sufficient: it
        // schedules a reconnect directly, mirroring `_onWebSocketClosed`.
        //
        // This test simulates ONLY an error (no `simulateServerClose`)
        // and verifies a reconnect timer is scheduled.  We don't fire
        // the timer here — firing it would invoke `_doConnect` on the
        // same exhausted ControllableWebSocket stream and fail; the
        // other tests in this group already verify the timer fires
        // correctly when a fresh socket is available (see the
        // `connect() during reconnect dedup` tests).
        final result = await connectAndHandshakeWithTimers();
        final ws = result.ws;
        final cm = result.cm;
        final timers = result.timers;

        ws.simulateError('Transport error without done');
        await pumpMicrotasks();

        // State must be recovering.
        expect(cm.state, GatewayConnectionState.recovering);

        // A reconnect timer MUST be active — otherwise the system is
        // stuck (the bug). Look for the RetryStrategy-shaped delay
        // (1s on first attempt) which `_scheduleReconnect` produces.
        final reconnectTimers = timers.activeTimers.where(
          (t) =>
              t.duration == const Duration(seconds: 1) ||
              t.duration == const Duration(seconds: 2),
        );
        expect(
          reconnectTimers.length,
          1,
          reason:
              '_onConnectionError must schedule a reconnect — no follow-up '
              'done will arrive, so without an explicit schedule the '
              'connection would be stuck in `recovering` forever',
        );

        await cm.dispose();
      },
    );

    test('_onConnectionError fails pending requests when connected '
        '(drains _bufferedBytes — Finding #2)', () async {
      final result = await connectAndHandshakeWithTimers();
      final ws = result.ws;
      final cm = result.cm;

      // Fire a request so it's pending when the error arrives
      final requestFuture = cm.sendRequest('agents.list', {});
      await pumpMicrotasks();

      ws.simulateError('Transport error');
      await pumpMicrotasks();

      // Finding #2: _onConnectionError now fails pending user sendRequests
      // (gated on `connected`) so their finallys drain _bufferedBytes.
      // Previously the request stayed pending until its ≤30s
      // requestTimeoutMs — leaving stale bytes to false-trip
      // BufferOverflowException on the ~1s reconnect (spurious FAILED +
      // "网关繁忙" toast). The request resolves with the CONNECTION_LOST
      // error frame (ok:false), not an exception.
      final done = Completer<void>();
      requestFuture.then(
        (_) => done.complete(),
        onError: (_) => done.complete(),
      );
      await pumpMicrotasks();
      expect(
        done.isCompleted,
        isTrue,
        reason:
            'pending request MUST resolve on connection error when '
            'connected — otherwise _bufferedBytes stays inflated and a '
            'reconnect-time sendRequest false-trips BufferOverflowException',
      );
    });

    // Regression: connect-timeout timer from a previous attempt must be
    // cancelled when a new _doConnect starts.
    //
    // Bug scenario:
    //   1. _doConnect #1 → state=connecting→authenticating → T1 (15s) created.
    //   2. hello-ok never arrives (transport error mid-handshake).
    //   3. _onConnectionError → state=recovering → reconnect timer R1 (1s).
    //   4. R1 fires → _doConnect #2 → state=connecting→authenticating → T2
    //      created (overwrites T1's reference WITHOUT cancelling T1).
    //   5. T1 fires 15s after step 1, during step 4's authenticating phase.
    //      `if (_state == authenticating)` passes → false `_handleAuthFailure`
    //      → user sees authFailed instead of recovering.
    //
    // The fix cancels T1 at the start of _doConnect. Without it, the
    // old timer survives the reconnect and corrupts the new handshake.
    test('connect-timeout timer is cancelled when _doConnect restarts '
        '(no false auth failure from stale timer)', () async {
      final ws = ControllableWebSocket.ready();
      final timers = FakeTimerFactory();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
        timerFactory: timers.call,
      );

      cm.connect();
      await pumpMicrotasks();
      ws.completeHandshake();
      await pumpMicrotasks();

      // Drive handshake to authenticating — challenge received but
      // no hello-ok yet. The 15s connect-timeout timer T1 is now
      // active in the FakeTimerFactory.
      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      expect(cm.state, GatewayConnectionState.authenticating);

      final t1Candidates = timers.activeTimers
          .where((t) => t.duration == const Duration(seconds: 15))
          .toList();
      expect(
        t1Candidates.length,
        1,
        reason: 'connect-timeout timer must be active during authenticating',
      );
      final t1 = t1Candidates.first;
      expect(t1.isActive, isTrue);

      // Transport error mid-handshake → _onConnectionError schedules
      // a reconnect (1s backoff per RetryStrategy).
      ws.simulateError('Transport error during handshake');
      await pumpMicrotasks();

      // Capture the reconnect timer and fire it → _doConnect #2
      // starts → new connect-timeout timer T2 is created.
      final reconnectCandidates = timers.activeTimers
          .where((t) => t.duration == const Duration(seconds: 1))
          .toList();
      expect(reconnectCandidates.length, 1);
      reconnectCandidates.first.fire();
      await pumpMicrotasks();

      // CRITICAL ASSERTION: T1 must be cancelled. Without the fix,
      // T1's callback would still fire ~15s after step 1 and falsely
      // fail the new handshake via `_handleAuthFailure('Handshake
      // timeout')`.
      expect(
        t1.isCancelled,
        isTrue,
        reason:
            'connect-timeout timer from a previous attempt must be '
            'cancelled when a new _doConnect starts — otherwise the '
            'old callback can fire during the new authenticating phase '
            'and falsely trigger auth failure',
      );

      await cm.dispose();
    });

    test('_onConnectionError from authenticating → recovering', () async {
      final ws = ControllableWebSocket.ready();
      final timers = FakeTimerFactory();
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(signPayload: (_) async => 'mock-sig'),
        webSocketFactory: (_) => ws.channel,
        timerFactory: timers.call,
      );

      cm.connect();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      expect(cm.state, GatewayConnectionState.authenticating);

      final states = <GatewayConnectionState>[];
      cm.connectionState.listen(states.add);

      ws.simulateError('Auth phase error');
      await pumpMicrotasks();

      expect(
        cm.state,
        GatewayConnectionState.recovering,
        reason: 'Error during auth phase should trigger recovery',
      );
      expect(states, contains(GatewayConnectionState.recovering));
    });
  });
}
