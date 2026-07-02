import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

ConnectionConfig testConfig({Future<String> Function(String)? signPayload}) =>
    ConnectionConfig(signPayload: signPayload);

/// Locally re-declare the policy builder so this test stays independent of
/// `connection_manager_policy_test.dart`'s private helper. (Avoids importing
/// a top-level symbol from another test file — that's brittle.)
String helloOkWithBufferedLimit(
  String id, {
  required int maxBufferedBytes,
  int? maxPayload,
}) {
  final fields = <String, dynamic>{
    'tickIntervalMs': 15000,
    'maxBufferedBytes': maxBufferedBytes,
  };
  if (maxPayload != null) fields['maxPayload'] = maxPayload;
  final policyJson = fields.entries
      .map((e) => '"${e.key}":${e.value}')
      .join(',');
  return '{"type":"res","id":"$id","ok":true,'
      '"payload":{"type":"hello-ok","protocol":4,'
      '"policy":{$policyJson}}}';
}

/// JSON of a successful response frame for a given request id.
String okResponse(String id) =>
    '{"type":"res","id":"$id","ok":true,"payload":{"ok":true}}';

void main() {
  // ===========================================================================
  // Gap #2 (buffer half): client-side guard against in-flight send buffer
  // exceeding server-declared maxBufferedBytes.
  //
  // Spec §2.2 says hello-ok.policy carries maxBufferedBytes (~50MB default)
  // as a back-pressure hint. The previous implementation only parsed and
  // stored the field — it never counted bytes pending on the wire. Result:
  // a burst of large sends could queue hundreds of MB on the socket before
  // the server's first `payload.large` response — too late, we already
  // OOM'd or stalled the drain loop.
  //
  // These tests pin the contract: register each request's UTF-8 byte size
  // in a monotonic counter, reject NEW requests that would push it past
  // the cap (reject-new strategy — matches the existing PayloadTooLarge
  // fail-fast and gives call sites a typed BufferOverflowException to catch).
  // ===========================================================================
  group(
    'ConnectionManager buffered-bytes enforcement (Gap #2 buffer half)',
    () {
      test('cumulative in-flight requests exceeding maxBufferedBytes throw '
          'BufferOverflowException on the next sendRequest', () async {
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

        // Tight cap: 400 bytes. Each chat.send with message='x'*200 is
        // ~270 UTF-8 bytes total (200 + ~70 JSON wrapper). Two requests
        // fit (~540 > 400) — so the *second* sendRequest that arrives while
        // the first is in-flight must throw.
        ws.simulateServerFrame(
          helloOkWithBufferedLimit(
            reqId,
            maxBufferedBytes: 400,
            maxPayload: 10_000_000,
          ),
        );
        await pumpMicrotasks();

        expect(cm.state, GatewayConnectionState.connected);

        // Fire-and-forget first request — deliberately do NOT await, so its
        // completer stays pending and its bytes stay counted.
        final firstFuture = cm.sendRequest('chat.send', <String, dynamic>{
          'message': 'x' * 200,
        });

        await pumpMicrotasks();

        // Sanity: first request was registered, counter is positive but
        // under the cap.
        expect(
          cm.bufferedBytesForTesting,
          greaterThan(0),
          reason: 'first in-flight request must increment the counter',
        );
        expect(
          cm.bufferedBytesForTesting,
          lessThanOrEqualTo(400),
          reason: 'first request alone must fit under the cap',
        );

        // Second same-shape request would push counter past 400 → throw.
        await expectLater(
          cm.sendRequest('chat.send', <String, dynamic>{'message': 'x' * 200}),
          throwsA(isA<BufferOverflowException>()),
          reason:
              'second in-flight request that would push the counter past '
              'maxBufferedBytes must reject-new',
        );

        // No additional frame was written — the rejected request never
        // touched the socket. (connect frame + first chat.send = 2 total.)
        expect(ws.sentFrames.length, 2);
        expect(ws.sentFrames.last, contains('"method":"chat.send"'));

        // Clean up by completing the first request so its finally releases
        // the counter and the completer can resolve.
        final firstFrameId = extractReqId(ws.sentFrames[1]);
        ws.simulateServerFrame(okResponse(firstFrameId));
        await expectLater(firstFuture, completes);

        await cm.dispose();
      });

      test('single request larger than maxBufferedBytes throws', () async {
        // If maxBufferedBytes is set tighter than the request, we still
        // reject-new rather than split the request — easier to reason about
        // and matches how PayloadTooLargeException already behaves.
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

        // maxBufferedBytes = 100, but payload alone is ~270 bytes — MUST throw.
        ws.simulateServerFrame(
          helloOkWithBufferedLimit(
            reqId,
            maxBufferedBytes: 100,
            maxPayload: 10_000_000,
          ),
        );
        await pumpMicrotasks();

        await expectLater(
          cm.sendRequest('chat.send', <String, dynamic>{'message': 'x' * 200}),
          throwsA(
            isA<BufferOverflowException>()
                .having(
                  (e) => e.attemptedSize,
                  'attemptedSize',
                  greaterThan(100),
                )
                .having((e) => e.maxSize, 'maxSize', 100),
          ),
        );

        // Counter is still zero — the rejected request was never registered.
        expect(
          cm.bufferedBytesForTesting,
          0,
          reason:
              'a rejected sendRequest must not have incremented the counter',
        );

        await cm.dispose();
      });

      test('completing an in-flight request decrements the counter so the '
          'next sendRequest can proceed', () async {
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

        // Cap chosen so a single 200-byte-message request fits, and exactly
        // one of them does (200 + 70 < 300) — second same-shape would push
        // past 300 IF the first hadn't completed.
        ws.simulateServerFrame(
          helloOkWithBufferedLimit(
            reqId,
            maxBufferedBytes: 1000,
            maxPayload: 10_000_000,
          ),
        );
        await pumpMicrotasks();

        // Fire first request without awaiting; capture its id for the
        // simulated response. Use a small message so a single request
        // ~200 bytes fits comfortably under the cap — this test only
        // covers the increment/decrement lifecycle, the reject-new path
        // is pinned by the first test in this group.
        final firstFuture = cm.sendRequest('chat.send', <String, dynamic>{
          'message': 'x' * 100,
        });
        await pumpMicrotasks();
        final firstFrameId = extractReqId(ws.sentFrames[1]);
        expect(
          cm.bufferedBytesForTesting,
          greaterThan(0),
          reason: 'first request must count toward the cap',
        );

        // Simulate the server completing the request — this resolves the
        // completer, the finally block in sendRequest runs, counter drops.
        ws.simulateServerFrame(okResponse(firstFrameId));
        await expectLater(firstFuture, completes);
        await pumpMicrotasks();

        expect(
          cm.bufferedBytesForTesting,
          0,
          reason:
              'completing an in-flight request must decrement the counter '
              '(its finally subtracts the payload size)',
        );

        // Now a second same-shape request must be accepted — the counter
        // went back to 0, so the buffer can absorb it.
        final secondFuture = cm.sendRequest('chat.send', <String, dynamic>{
          'message': 'x' * 100,
        });
        await pumpMicrotasks();
        expect(
          cm.bufferedBytesForTesting,
          greaterThan(0),
          reason:
              'second request after freeing the slot must re-arm the '
              'counter',
        );

        // Cleanup: complete and dispose.
        final secondFrameId = extractReqId(ws.sentFrames[2]);
        ws.simulateServerFrame(okResponse(secondFrameId));
        await expectLater(secondFuture, completes);
        await cm.dispose();
      });

      test('dispose() runs each pending request\'s finally, ending with '
          'bufferedBytesForTesting == 0 (no double-subtract)', () async {
        // _failAllPending (called by dispose) completes all pending
        // completers with a CONNECTION_LOST error. Each sendRequest's
        // finally must run exactly once, decrementing _bufferedBytes once.
        // If the manager ALSO touches _bufferedBytes inside _failAllPending,
        // we'd subtract twice — once in clear()'s sweep and once in each
        // caller finally — going negative or wrapping. This test guards
        // against that regression.
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
          helloOkWithBufferedLimit(
            reqId,
            maxBufferedBytes: 10_000_000,
            maxPayload: 10_000_000,
          ),
        );
        await pumpMicrotasks();

        // Three concurrent in-flight requests, none will be responded to.
        final f1 = cm.sendRequest('chat.send', <String, dynamic>{
          'message': 'x' * 100,
        });
        final f2 = cm.sendRequest('chat.send', <String, dynamic>{
          'message': 'x' * 100,
        });
        final f3 = cm.sendRequest('chat.send', <String, dynamic>{
          'message': 'x' * 100,
        });
        await pumpMicrotasks();

        final beforeDispose = cm.bufferedBytesForTesting;
        expect(
          beforeDispose,
          greaterThan(0),
          reason: 'three in-flight requests must increase the counter',
        );

        // _failAllPending (called by dispose) completes each pending
        // completer with an ok:false ResponseFrame (code: CONNECTION_LOST)
        // — a *normal* completion (complete), not completeError. sendRequest
        // therefore returns the frame normally and its `finally` block runs,
        // decrementing _bufferedBytes once per request. We don't await
        // f1/f2/f3: the assertion only cares that the counter drains to
        // zero, not the resolved values (all ok:false CONNECTION_LOST
        // frames). The previous `catchError` wrappers were dead code —
        // they only fire on a rejected future, which never happens here.
        unawaited(f1);
        unawaited(f2);
        unawaited(f3);

        await cm.dispose();
        await pumpMicrotasks();

        expect(
          cm.bufferedBytesForTesting,
          0,
          reason:
              'after dispose() / _failAllPending, every pending request '
              'must have run its finally exactly once; the counter must be '
              'zero, not negative (no double-subtract) and not stuck on the '
              'pre-dispose value',
        );
      });

      // Finding #2: the onError (no follow-up done) and tick-timeout
      // connection-drop paths did NOT call _failAllPending — only
      // _onConnectionDone / dispose / disconnect did. So an in-flight
      // request's completer stayed pending until its ≤30s requestTimeoutMs
      // fired, leaving _bufferedBytes inflated. A fresh sendRequest after a
      // ~1s reconnect would then false-trip the reject-new guard
      // (stale 40MB + new 15MB > 50MB → spurious BufferOverflowException →
      // FAILED + "网关繁忙" toast) until the old timeout finally drained it.
      // The dispose test above only covers the dispose path, so this was
      // uncaught. Fix: _onConnectionError / _onWebSocketClosed call
      // _failAllPending, mirroring _onConnectionDone.
      test('connection drop via onError drains _bufferedBytes (no stale '
          'bytes to false-trip BufferOverflow on reconnect)', () async {
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
        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);
        ws.simulateServerFrame(
          helloOkWithBufferedLimit(
            reqId,
            maxBufferedBytes: 10_000_000,
            maxPayload: 10_000_000,
          ),
        );
        await pumpMicrotasks();
        expect(cm.state, GatewayConnectionState.connected);

        // In-flight request whose completer stays pending until
        // _failAllPending completes it. Fire unawaited so its bytes stay
        // counted.
        unawaited(
          cm.sendRequest('chat.send', <String, dynamic>{'message': 'x' * 500}),
        );
        await pumpMicrotasks();
        expect(
          cm.bufferedBytesForTesting,
          greaterThan(0),
          reason: 'in-flight request must increment the counter',
        );

        // Transport error with NO follow-up done (some platforms emit onError
        // without onDone) → _onConnectionError. Before the fix this did NOT
        // fail pending, leaving _bufferedBytes inflated.
        ws.simulateError(Exception('transport reset'));
        await pumpMicrotasks();

        expect(
          cm.bufferedBytesForTesting,
          0,
          reason:
              '_onConnectionError must _failAllPending so each pending '
              'sendRequest\'s finally decrements _bufferedBytes. A non-zero '
              'value means stale bytes persist and a post-reconnect '
              'sendRequest would false-trip BufferOverflowException.',
        );

        await cm.dispose();
      });

      test('tick-timeout connection drop drains _bufferedBytes (same fix for '
          'the _onWebSocketClosed path)', () async {
        // The tick-timeout path goes through _closeWebSocket().then(
        // _onWebSocketClosed) — cancelling the incoming subscription, so
        // _onConnectionDone does NOT fire (cancelOnError:false + explicit
        // cancel). Only _onWebSocketClosed runs, so the same _failAllPending
        // gap applies. Drive it via a fake timer factory so we don't wait
        // the real 2×tickInterval.
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

        unawaited(cm.connect());
        await pumpMicrotasks();
        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);
        ws.simulateServerFrame(
          helloOkWithBufferedLimit(
            reqId,
            maxBufferedBytes: 10_000_000,
            maxPayload: 10_000_000,
          ),
        );
        await pumpMicrotasks();
        expect(cm.state, GatewayConnectionState.connected);

        unawaited(
          cm.sendRequest('chat.send', <String, dynamic>{'message': 'x' * 500}),
        );
        await pumpMicrotasks();
        expect(cm.bufferedBytesForTesting, greaterThan(0));

        // The tick-timeout timer is the one created in _resetTickTimeout
        // (called on hello-ok). Fire it → _closeWebSocket().then(
        // _onWebSocketClosed). _closeWebSocket is async, so pump microtasks
        // to let the .then chain run.
        timers.activeTimers
            .lastWhere((t) => t.duration.inMilliseconds == 30000)
            .fire();
        await pumpMicrotasks();
        await pumpMicrotasks();

        expect(
          cm.bufferedBytesForTesting,
          0,
          reason:
              'tick-timeout → _onWebSocketClosed must _failAllPending so '
              'pending completers resolve and their finallys drain the '
              'counter. Non-zero = stale bytes persist across reconnect.',
        );

        await cm.dispose();
      });
    },
  );

  group('BufferOverflowException', () {
    test('reports buffered, attempted, and max sizes for diagnostics', () {
      final ex = BufferOverflowException(
        message: 'in-flight buffer full',
        bufferedBytes: 49_000_000,
        attemptedSize: 6_000_000,
        maxSize: 52_428_800,
      );
      expect(ex.bufferedBytes, 49_000_000);
      expect(ex.attemptedSize, 6_000_000);
      expect(ex.maxSize, 52_428_800);
      expect(ex.message, 'in-flight buffer full');
      expect(ex.toString(), contains('49000000'));
      expect(ex.toString(), contains('6000000'));
      expect(ex.toString(), contains('52428800'));
    });
  });
}
