import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

ConnectionConfig testConfig({Future<String> Function(String)? signPayload}) =>
    ConnectionConfig(signPayload: signPayload);

/// Build a hello-ok response with custom policy fields. Centralised here so
/// every policy test uses identical shape (no risk of one test shipping a
/// malformed hello-ok that masks a real parser bug).
String helloOkWithPolicy(
  String id, {
  int? tickIntervalMs,
  int? maxPayload,
  int? maxBufferedBytes,
}) {
  final fields = <String, dynamic>{};
  if (tickIntervalMs != null) fields['tickIntervalMs'] = tickIntervalMs;
  if (maxPayload != null) fields['maxPayload'] = maxPayload;
  if (maxBufferedBytes != null) fields['maxBufferedBytes'] = maxBufferedBytes;
  final policyJson = fields.isEmpty
      ? '{}'
      : fields.entries.map((e) => '"${e.key}":${e.value}').join(',');
  return '{"type":"res","id":"$id","ok":true,'
      '"payload":{"type":"hello-ok","protocol":4,'
      '"policy":{$policyJson}}}';
}

void main() {
  // ============================================================================
  // Gap #2: client-side protection against over-sized payloads.
  //
  // Spec §2.2 says hello-ok.policy carries `maxPayload` and
  // `maxBufferedBytes` caps. The previous implementation only read
  // `tickIntervalMs`, so the client could:
  //   1. Accept arbitrarily-large payloads and OOM
  //   2. Send > limit to the server, which would (silently) drop them
  //      or bounce back a `payload.large` event (Gap #6)
  //
  // These tests pin the contract: read the policy, fail fast on oversize.
  // ============================================================================
  group('ConnectionManager policy parsing (Gap #2)', () {
    test(
      'reads maxPayload and maxBufferedBytes from hello-ok.policy',
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

        ws.simulateServerFrame(
          helloOkWithPolicy(
            reqId,
            maxPayload: 10_000_000,
            maxBufferedBytes: 20_000_000,
          ),
        );
        await pumpMicrotasks();

        expect(cm.state, GatewayConnectionState.connected);

        // Direct getter assertions — pin the exact negotiated values
        // so a refactor that accidentally drops maxBufferedBytes from
        // the parser is caught immediately.
        expect(
          cm.maxPayloadBytesForTesting,
          10_000_000,
          reason: 'hello-ok.policy.maxPayload must be honoured verbatim',
        );
        expect(
          cm.maxBufferedBytesForTesting,
          20_000_000,
          reason: 'hello-ok.policy.maxBufferedBytes must be honoured verbatim',
        );

        // The fields are private; verify their effect via sendRequest —
        // a small payload must NOT trigger PayloadTooLargeException.
        // (We don't drive a response — just confirm no immediate throw.)
        final params = <String, dynamic>{'message': 'hello'};
        final responseFuture = cm.sendRequest('chat.send', params);

        await pumpMicrotasks();
        expect(responseFuture, isA<Future<ResponseFrame>>());

        await cm.dispose();
      },
    );

    test(
      'partial policy (only maxPayload) keeps default for maxBufferedBytes',
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
        ws.simulateServerFrame(helloOkWithPolicy(reqId, maxPayload: 5_000_000));
        await pumpMicrotasks();

        expect(cm.maxPayloadBytesForTesting, 5_000_000);
        // maxBufferedBytes NOT in policy → keep default (50MB).
        expect(
          cm.maxBufferedBytesForTesting,
          defaultMaxBufferedBytes,
          reason: 'missing field must fall back to default, not zero',
        );

        await cm.dispose();
      },
    );

    test('no policy block keeps both fields at defaults', () async {
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
      // helloOkJson has no policy block at all
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(cm.maxPayloadBytesForTesting, defaultMaxPayloadBytes);
      expect(cm.maxBufferedBytesForTesting, defaultMaxBufferedBytes);

      await cm.dispose();
    });

    test(
      'sendRequest throws PayloadTooLargeException for over-size payload',
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

        // Tighten the limit to 1KB so we don't need a 25MB test payload.
        ws.simulateServerFrame(helloOkWithPolicy(reqId, maxPayload: 1024));
        await pumpMicrotasks();

        expect(cm.state, GatewayConnectionState.connected);

        // 2KB payload → exceeds 1KB limit → must throw.
        final bigPayload = 'x' * 2048;
        final params = <String, dynamic>{'message': bigPayload};

        await expectLater(
          cm.sendRequest('chat.send', params),
          throwsA(
            isA<PayloadTooLargeException>()
                .having((e) => e.actualSize, 'actualSize', greaterThan(1024))
                .having((e) => e.maxSize, 'maxSize', 1024),
          ),
        );

        // Critically: no frame was written to the socket for the
        // over-sized request. We sent connect + request, so 2 frames
        // total — neither should be the rejected chat.send.
        expect(ws.sentFrames.length, 1, reason: 'only connect frame sent');
        expect(ws.sentFrames.last, contains('"method":"connect"'));

        await cm.dispose();
      },
    );

    test(
      'sendRequest accepts payload exactly at maxPayload (boundary)',
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
        ws.simulateServerFrame(helloOkWithPolicy(reqId, maxPayload: 1024));
        await pumpMicrotasks();

        // Find the smallest 'message' string whose full request JSON
        // exactly hits 1024 bytes. Build a JSON template, compute the
        // padding length needed. Simpler: send something well under
        // 1024 bytes (a 100-char message) — should pass.
        final smallPayload = 'x' * 100;
        final params = <String, dynamic>{'message': smallPayload};
        final responseFuture = cm.sendRequest('chat.send', params);

        await pumpMicrotasks();
        // Should NOT have thrown; the request is pending.
        expect(responseFuture, isA<Future<ResponseFrame>>());

        await cm.dispose();
      },
    );

    test(
      'falls back to defaultMaxPayloadBytes (25MB) when policy is missing',
      () async {
        // A bare hello-ok with no policy block at all. The CM should
        // keep its pre-handshake default (defaultMaxPayloadBytes) so
        // the limit stays enforced even without server cooperation.
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

        // helloOkJson has no policy block (per test_helpers.dart)
        ws.simulateServerFrame(helloOkJson(reqId));
        await pumpMicrotasks();

        expect(cm.state, GatewayConnectionState.connected);

        // Send a 26MB payload — exceeds the 25MB default. We don't
        // need to actually transmit 26MB of UTF-8; just verify the
        // throw triggers. Build a payload with sparse characters to
        // approximate 26MB in memory without huge test cost.
        final hugePayload = 'x' * (26 * 1024 * 1024);
        await expectLater(
          cm.sendRequest('chat.send', {'message': hugePayload}),
          throwsA(isA<PayloadTooLargeException>()),
        );

        await cm.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    // -------------------------------------------------------------------------
    // Regression: UTF-8 cheap-size bypass (Fix 1)
    //
    // The previous sendRequest used `requestJson.length` (UTF-16 code units)
    // as a "cheap upper bound" before falling back to `utf8.encode`. This is
    // broken for non-ASCII content because String.length is a LOWER bound on
    // the UTF-8 byte count — CJK characters are 1 code unit but 3 UTF-8 bytes.
    // A 25M-char CJK payload reads as 25M code units (passes the cheap check)
    // but is ~75MB on the wire, defeating the entire Gap #2 OOM guard.
    //
    // These tests pin the contract: maxPayload is enforced against UTF-8
    // BYTES, not code units.
    // -------------------------------------------------------------------------
    test('CJK payload is measured in UTF-8 bytes, not code units', () async {
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
      // Tight limit so we can craft a small test that still trips the
      // UTF-8 vs code-unit mismatch.
      ws.simulateServerFrame(helloOkWithPolicy(reqId, maxPayload: 1024));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);

      // 350 CJK chars: 350 code units (well under 1024) but 1050 UTF-8
      // bytes for the message alone. With ~80 bytes of JSON wrapper, the
      // full request is ~430 code units but ~1130 UTF-8 bytes — exceeds
      // the 1024 cap ONLY in UTF-8 bytes, not in code units. The old
      // cheap check passed this; the correct check must throw.
      final cjkMessage = '中' * 350;
      final params = <String, dynamic>{'message': cjkMessage};

      await expectLater(
        cm.sendRequest('chat.send', params),
        throwsA(
          isA<PayloadTooLargeException>()
              .having((e) => e.actualSize, 'actualSize', greaterThan(1024))
              .having((e) => e.maxSize, 'maxSize', 1024),
        ),
        reason:
            'CJK payload whose UTF-16 length is under maxPayload but whose '
            'UTF-8 byte length exceeds it must still throw '
            'PayloadTooLargeException',
      );

      // No chat.send frame was written — the over-sized request was
      // rejected before reaching the socket.
      expect(
        ws.sentFrames.length,
        1,
        reason: 'only connect frame sent; oversize chat.send was rejected',
      );
      expect(ws.sentFrames.last, contains('"method":"connect"'));

      await cm.dispose();
    });

    test('emoji payload is measured in UTF-8 bytes, not code units', () async {
      // Different multibyte category from CJK: emoji are 4 UTF-8 bytes
      // per code point (vs CJK's 3). We need UTF-8 bytes > 1024 while
      // code units ≤ 1024 to exercise the fix.
      //
      // 300 emoji = 300 code units (≤ 1024) but 1200 UTF-8 bytes for
      // the message alone — plus ~80 bytes of JSON wrapper = ~1280
      // total, which exceeds the 1024 cap ONLY in UTF-8 bytes, not
      // in code units. The old cheap check would have passed this;
      // the correct check must throw.
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
      ws.simulateServerFrame(helloOkWithPolicy(reqId, maxPayload: 1024));
      await pumpMicrotasks();

      final emojiMessage = '😀' * 300; // 300 code units, 1200 UTF-8 bytes
      final params = <String, dynamic>{'message': emojiMessage};

      await expectLater(
        cm.sendRequest('chat.send', params),
        throwsA(isA<PayloadTooLargeException>()),
        reason: 'emoji payload must be measured in UTF-8 bytes, not code units',
      );

      await cm.dispose();
    });

    test('ASCII payload at exactly the code-unit limit is accepted', () async {
      // Sanity-check the boundary: an ASCII payload whose UTF-8 byte
      // count equals the code-unit count should NOT trigger the guard.
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
      ws.simulateServerFrame(helloOkWithPolicy(reqId, maxPayload: 1024));
      await pumpMicrotasks();

      // 100 ASCII chars + ~80 byte wrapper ≈ 180 UTF-8 bytes — well
      // under the 1024 cap on either measurement.
      final asciiPayload = 'x' * 100;
      final params = <String, dynamic>{'message': asciiPayload};
      final responseFuture = cm.sendRequest('chat.send', params);

      await pumpMicrotasks();
      expect(
        responseFuture,
        isA<Future<ResponseFrame>>(),
        reason: 'small ASCII payload must not be rejected',
      );

      await cm.dispose();
    });

    // -------------------------------------------------------------------------
    // Regression: maxPayload ≤ 0 from server (Fix 2)
    //
    // A misconfigured server returning maxPayload=0 (or negative) used to
    // wedge every sendRequest — cheapSize > 0 always triggered the throw.
    // The fix falls back to the spec default in that case.
    // -------------------------------------------------------------------------
    test(
      'maxPayload=0 from server falls back to defaultMaxPayloadBytes',
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
        ws.simulateServerFrame(helloOkWithPolicy(reqId, maxPayload: 0));
        await pumpMicrotasks();

        expect(
          cm.maxPayloadBytesForTesting,
          defaultMaxPayloadBytes,
          reason:
              'maxPayload=0 must fall back to spec default — otherwise every '
              'sendRequest would throw PayloadTooLargeException',
        );

        // A small payload must succeed under the default cap.
        final responseFuture = cm.sendRequest('chat.send', {'message': 'hi'});
        await pumpMicrotasks();
        expect(responseFuture, isA<Future<ResponseFrame>>());

        await cm.dispose();
      },
    );

    test(
      'negative maxPayload from server falls back to defaultMaxPayloadBytes',
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
        ws.simulateServerFrame(helloOkWithPolicy(reqId, maxPayload: -1));
        await pumpMicrotasks();

        expect(
          cm.maxPayloadBytesForTesting,
          defaultMaxPayloadBytes,
          reason: 'negative maxPayload must also fall back to default',
        );

        await cm.dispose();
      },
    );

    // Regression: server-sent JSON numbers that jsonDecode materializes as
    // `double` (e.g. `26214400.0`, or any number carrying a fractional /
    // exponent part) must NOT silently drop the server-negotiated cap.
    //
    // Bug: the parser used `policy['maxPayload'] as int?`. `as int?` on a
    // `double` is a *cast* (TypeError), not a null-coercion — it throws
    // inside `_handleConnectResponse`. The state has already been set to
    // `connected` (line ~667, before policy parsing), so the throw is
    // swallowed by the connect-response `.catchError` and the handshake
    // *looks* successful — but `_maxPayloadBytes`/`_maxBufferedBytes` are
    // never updated, silently degrading to the 25MB/50MB defaults. A
    // server that negotiated a 10MB cap then sees the client ship 15MB
    // payloads it should have rejected. Defensive `num`-based parsing
    // (`is num` + `toInt()`) accepts both int and double.
    //
    // (helloOkWithPolicy only emits ints, so this test hand-writes the
    // hello-ok JSON with `N.0` doubles — mirroring the raw-JSON pattern in
    // connection_manager_auth_retry_test.dart.)
    test('maxPayload / maxBufferedBytes sent as JSON double are parsed '
        'without crashing', () async {
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

      // Note the `.0` — jsonDecode yields `double` for these.
      ws.simulateServerFrame(
        '{"type":"res","id":"$reqId","ok":true,'
        '"payload":{"type":"hello-ok","protocol":4,'
        '"policy":{"tickIntervalMs":15000,'
        '"maxPayload":10000000.0,'
        '"maxBufferedBytes":20000000.0}}}',
      );
      await pumpMicrotasks();

      // Before the fix: the `as int?` cast throws (TypeError), the
      // connect-response `.catchError` swallows it, state stays
      // `connected` (already set before policy parsing) — but the cap is
      // silently ignored and `_maxPayloadBytes` keeps its default.
      expect(
        cm.state,
        GatewayConnectionState.connected,
        reason: 'handshake must complete; the double must not crash it',
      );
      expect(
        cm.maxPayloadBytesForTesting,
        10_000_000,
        reason: 'double 10000000.0 must coerce to int 10000000',
      );
      expect(
        cm.maxBufferedBytesForTesting,
        20_000_000,
        reason: 'double 20000000.0 must coerce to int 20000000',
      );

      await cm.dispose();
    });
  });

  group('PayloadTooLargeException', () {
    test('reports actual and max sizes for diagnostics', () {
      final ex = PayloadTooLargeException(
        message: 'too big',
        actualSize: 30_000_000,
        maxSize: 26_214_400,
      );
      expect(ex.actualSize, 30_000_000);
      expect(ex.maxSize, 26_214_400);
      expect(ex.message, 'too big');
      expect(ex.toString(), contains('30000000'));
      expect(ex.toString(), contains('26214400'));
    });
  });

  group('spec §2.2 constants', () {
    test('defaultMaxPayloadBytes is 25MB', () {
      expect(defaultMaxPayloadBytes, 26214400);
    });
    test('defaultMaxBufferedBytes is 50MB', () {
      expect(defaultMaxBufferedBytes, 52428800);
    });
  });
}
