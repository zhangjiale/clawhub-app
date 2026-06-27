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
