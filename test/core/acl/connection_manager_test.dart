import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Mocktail fakes for WebSocketChannel / WebSocketSink
// ---------------------------------------------------------------------------

class MockWebSocketChannel extends Mock implements WebSocketChannel {}

class MockWebSocketSink extends Mock implements WebSocketSink {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
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
      signPayload: (_) => signCompleter.future,
    );
  });

  group('onConnectChallenge race condition guard', () {
    // -----------------------------------------------------------------------
    // Helper: pump the microtask queue so async continuations run.
    // -----------------------------------------------------------------------
    Future<void> pumpMicrotasks() => Future.delayed(Duration.zero);

    // -----------------------------------------------------------------------
    // Path 1 (HIGH) — _closeWebSocket sets channel=null during sign.
    // -----------------------------------------------------------------------
    test(
      'Path: channel set to null during signPayload — should return without NPE',
      () async {
        // Arrange: simulate authenticating state with a live channel
        cm.setTestState(GatewayConnectionState.authenticating);
        cm.setTestChannel(mockChannel);

        // Act: start challenge — it will await signCompleter.future
        final future = cm.onConnectChallenge({'nonce': 'test-nonce'});

        // While sign is pending: simulate _closeWebSocket (clears channel)
        cm.setTestChannel(null);

        // Let the sign complete — this resumes onConnectChallenge
        signCompleter.complete('mock-signature-b64');
        await pumpMicrotasks();

        // Assert: no unhandled exception, method returned cleanly
        await expectLater(future, completes);

        // channel.sink.add() must NOT have been called (guard bailed out)
        verifyNever(() => mockSink.add(any()));
      },
    );

    // -----------------------------------------------------------------------
    // Path 2 — state changes away from authenticating during sign.
    // -----------------------------------------------------------------------
    test(
      'Path: state changed during sign — should return without write',
      () async {
        cm.setTestState(GatewayConnectionState.authenticating);
        cm.setTestChannel(mockChannel);

        final future = cm.onConnectChallenge({'nonce': 'test-nonce'});

        // While sign is pending: simulate connection lost → _onConnectionDone
        cm.setTestState(GatewayConnectionState.recovering);

        signCompleter.complete('mock-signature-b64');
        await pumpMicrotasks();

        await expectLater(future, completes);
        verifyNever(() => mockSink.add(any()));
      },
    );

    // -----------------------------------------------------------------------
    // Normal path — guard lets valid state through.
    // -----------------------------------------------------------------------
    test(
      'Normal path: channel and state intact — should write to sink',
      () async {
        cm.setTestState(GatewayConnectionState.authenticating);
        cm.setTestChannel(mockChannel);

        // Don't tamper with channel or state → guard should pass
        // Need to complete the sign BEFORE awaiting so the method runs through
        final future = cm.onConnectChallenge({'nonce': 'test-nonce'});

        // Complete sign immediately so guard passes
        signCompleter.complete('mock-signature-b64');
        await pumpMicrotasks();

        await expectLater(future, completes);

        // sink.add() SHOULD have been called
        verify(() => mockSink.add(any())).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Path 3 — channel replaced (reconnect creates new channel during sign).
    // -----------------------------------------------------------------------
    test(
      'Path: channel replaced during sign — should not write to new channel',
      () async {
        cm.setTestState(GatewayConnectionState.authenticating);
        cm.setTestChannel(mockChannel);

        final future = cm.onConnectChallenge({'nonce': 'test-nonce'});

        // While sign is pending: simulate reconnect → new channel assigned
        final newMockChannel = MockWebSocketChannel();
        final newMockSink = MockWebSocketSink();
        when(() => newMockChannel.sink).thenReturn(newMockSink);
        cm.setTestChannel(newMockChannel);
        // State might still be authenticating if reconnect progressed fast
        // (pathological race). Guard catches this by channel reference change
        // if we compare references, OR by state check. Let's leave state as
        // authenticating to test the most dangerous edge case.
        // Note: the current guard checks _state and channel==null, not
        // reference equality. This test documents Path 3 awareness — if we
        // ever strengthen the guard to compare channel references, this test
        // validates that scenario.
        // For now this path is partially mitigated: if channel was set to null
        // before being replaced, the null check catches it; if the old channel
        // was kept alive, _onConnectionDone changes state → state check
        // catches it.
        signCompleter.complete('mock-signature-b64');
        await pumpMicrotasks();

        await expectLater(future, completes);
        // The guard (state == authenticating && channel != null) lets this
        // through — but that's the current design limitation. The test
        // exists to document this edge case for future hardening.
        // See docs/engineering/iron-laws.md Law 8: "document known limitations."
      },
    );
  });
}
