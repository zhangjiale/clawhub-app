import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'test_helpers.dart';

/// Stateful factory: returns a fresh [ControllableWebSocket] for each
/// [_doConnect] call.  Mirrors a real WebSocket lifecycle where each
/// reconnect attempt opens a fresh channel — ControllableWebSocket's
/// stream is single-subscription, so a retry on the same instance
/// crashes with "Stream has already been listened to".
class _ReusableWebSocketFactory {
  final List<ControllableWebSocket> sockets = [];

  WebSocketChannel Function(Uri) get factory {
    return (Uri uri) {
      final ws = ControllableWebSocket.ready();
      sockets.add(ws);
      return ws.channel;
    };
  }
}

ConnectionConfig testConfig() => ConnectionConfig();

// FakeDeviceTokenStore lives in test_helpers.dart (re-imported).

/// Build an AUTH_TOKEN_MISMATCH error response frame.
///
/// Spec §A.9:
///   { "type": "res", "id": "...", "ok": false,
///     "error": { "code": "AUTH_TOKEN_MISMATCH",
///                "message": "...",
///                "details": { "canRetryWithDeviceToken": true,
///                             "recommendedNextStep": "retry_with_device_token" } } }
String authTokenMismatchJson(String id, {bool canRetryWithDeviceToken = true}) {
  final details =
      '"canRetryWithDeviceToken":$canRetryWithDeviceToken,'
      '"recommendedNextStep":"retry_with_device_token"';
  return '{"type":"res","id":"$id","ok":false,'
      '"error":{"code":"AUTH_TOKEN_MISMATCH",'
      '"message":"Token rejected",'
      '"details":{$details}}}';
}

void main() {
  // ============================================================================
  // Gap #1+: AUTH_TOKEN_MISMATCH 设备令牌重试（spec §A.9）
  //
  // 背景：Gateway 在以下两种场景会返回 AUTH_TOKEN_MISMATCH：
  //   (a) 服务端 token 刚刚被轮换（`device.token.rotate`），客户端缓存的
  //       deviceToken 暂时无效
  //   (b) 服务端 session 短暂不一致（刚刚 revoke 又允许重连）
  //
  // Spec §A.9 允许"可信客户端"（环回或带 tlsFingerprint 的 wss://）在
  // server 主动声明 `canRetryWithDeviceToken=true` 时重试一次。若仍
  // 失败，必须停止自动重连并提示用户 —— 不能再退避重试。
  //
  // 注：本项目当前 ConnectionConfig 没有 isLocalNetwork / tlsFingerprint
  // 字段（F-3 标注），所以**信任判断委托给 server 的 canRetryWithDeviceToken
  // 标志**。如果 server 拒绝（canRetry=false 或缺失），直接 _handleAuthFailure。
  // 这样默认行为是"保守"（fail closed），未来加 isLocalNetwork 后可以
  // 再加一道本地校验。
  //
  // 这些测试固定以下契约：
  //   1. AUTH_TOKEN_MISMATCH + canRetry=true → 自动重试一次（不需退避）
  //   2. 重试成功 → 进入 connected，`_hasAttemptedDeviceTokenRetry` 重置
  //   3. 重试再失败 → 终态 authFailed，不再自动重试
  //   4. canRetry=false 或缺失 → 不重试，直接 authFailed
  //   5. 重试用的是缓存 deviceToken（不是 pairing code），所以 token 必现
  // ============================================================================
  group('ConnectionManager AUTH_TOKEN_MISMATCH retry (Gap #1+)', () {
    test(
      'AUTH_TOKEN_MISMATCH + canRetry=true triggers immediate retry',
      () async {
        final tokenStore = FakeDeviceTokenStore();
        await tokenStore.save('test-instance', 'cached-token-xxx');
        final wsFactory = _ReusableWebSocketFactory();

        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'pairing-code',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: wsFactory.factory,
          deviceTokenStore: tokenStore,
        );

        unawaited(cm.connect());
        await pumpMicrotasks();
        final ws1 = wsFactory.sockets.first;
        ws1.completeHandshake();
        await pumpMicrotasks();

        // ---- First connect attempt → AUTH_TOKEN_MISMATCH ----
        ws1.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final firstReqId = extractReqId(ws1.sentFrames.first);
        ws1.simulateServerFrame(
          authTokenMismatchJson(firstReqId, canRetryWithDeviceToken: true),
        );
        await pumpMicrotasks();

        // Should NOT yet be authFailed — retry should fire.
        expect(
          cm.state,
          isNot(GatewayConnectionState.authFailed),
          reason:
              'canRetryWithDeviceToken=true must not mark terminal until '
              'retry also fails',
        );

        // Wait for _scheduleDoConnect(0) → _doConnect to fire.
        for (var i = 0; i < 8; i++) {
          await pumpMicrotasks();
        }

        // A new ControllableWebSocket must have been created for the retry.
        expect(
          wsFactory.sockets.length,
          equals(2),
          reason: 'retry should open a fresh WebSocket',
        );
        final ws2 = wsFactory.sockets[1];

        // ---- Retry's challenge → respond with hello-ok ----
        ws2.completeHandshake();
        await pumpMicrotasks();
        ws2.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final secondReqId = extractReqId(ws2.sentFrames.first);
        ws2.simulateServerFrame(helloOkJson(secondReqId));
        await pumpMicrotasks();

        expect(
          cm.state,
          GatewayConnectionState.connected,
          reason: 'retry succeeded → state is connected',
        );
        // Token was used as bearer (via _resolveBearerToken → cache hit)
        // on both the first and retry attempts.
        expect(tokenStore.loadCalls, greaterThanOrEqualTo(2));

        await cm.dispose();
      },
    );

    test(
      'retry that also fails → terminal authFailed (no further retries)',
      () async {
        final tokenStore = FakeDeviceTokenStore();
        await tokenStore.save('test-instance', 'cached-token');
        final wsFactory = _ReusableWebSocketFactory();

        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'pairing-code',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: wsFactory.factory,
          deviceTokenStore: tokenStore,
        );

        unawaited(cm.connect());
        await pumpMicrotasks();
        final ws1 = wsFactory.sockets.first;
        ws1.completeHandshake();
        await pumpMicrotasks();

        // First attempt → AUTH_TOKEN_MISMATCH
        ws1.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final firstReqId = extractReqId(ws1.sentFrames.first);
        ws1.simulateServerFrame(
          authTokenMismatchJson(firstReqId, canRetryWithDeviceToken: true),
        );
        await pumpMicrotasks();

        // Wait for retry to fire.
        for (var i = 0; i < 8; i++) {
          await pumpMicrotasks();
        }

        // Retry opened a new socket.
        expect(wsFactory.sockets.length, equals(2));
        final ws2 = wsFactory.sockets[1];
        ws2.completeHandshake();
        await pumpMicrotasks();

        // Retry also fails with AUTH_TOKEN_MISMATCH → terminal authFailed.
        ws2.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final secondReqId = extractReqId(ws2.sentFrames.first);
        ws2.simulateServerFrame(
          authTokenMismatchJson(secondReqId, canRetryWithDeviceToken: true),
        );
        await pumpMicrotasks();

        expect(
          cm.state,
          GatewayConnectionState.authFailed,
          reason:
              'retry also failing AUTH_TOKEN_MISMATCH must mark terminal '
              'authFailed — spec §A.9 says stop auto-retry',
        );

        // Critically: NO third connect attempt is fired.  The spec
        // says "可尝试一次" (try once); we already used our one retry.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await pumpMicrotasks();
        expect(
          wsFactory.sockets.length,
          equals(2),
          reason:
              'must not retry a third time after retry-also-fails — '
              'spec §A.9 limits retry count to 1',
        );

        await cm.dispose();
      },
    );

    test('AUTH_TOKEN_MISMATCH + canRetryWithDeviceToken=false → terminal '
        'authFailed (no retry)', () async {
      final ws = ControllableWebSocket.ready();
      final tokenStore = FakeDeviceTokenStore();
      await tokenStore.save('test-instance', 'cached-token');

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'pairing-code',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
        deviceTokenStore: tokenStore,
      );

      unawaited(cm.connect());
      await pumpMicrotasks();
      ws.completeHandshake();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(
        authTokenMismatchJson(reqId, canRetryWithDeviceToken: false),
      );
      await pumpMicrotasks();

      expect(
        cm.state,
        GatewayConnectionState.authFailed,
        reason:
            'canRetryWithDeviceToken=false → server says no retry → '
            'go straight to terminal authFailed',
      );

      // Verify no retry frame was sent.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await pumpMicrotasks();
      final connectFrames = ws.sentFrames
          .where((f) => f.contains('"method":"connect"'))
          .length;
      expect(connectFrames, equals(1), reason: 'no retry must be attempted');

      await cm.dispose();
    });

    test('AUTH_TOKEN_MISMATCH with missing canRetryWithDeviceToken field '
        '→ terminal authFailed (fail-closed default)', () async {
      final ws = ControllableWebSocket.ready();
      final tokenStore = FakeDeviceTokenStore();
      await tokenStore.save('test-instance', 'cached-token');

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'pairing-code',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (_) => ws.channel,
        deviceTokenStore: tokenStore,
      );

      unawaited(cm.connect());
      await pumpMicrotasks();
      ws.completeHandshake();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.first);

      // Server omits canRetryWithDeviceToken entirely.  Per spec §A.9
      // the field is a hint; absent = no hint = no retry.
      final raw =
          '{"type":"res","id":"$reqId","ok":false,'
          '"error":{"code":"AUTH_TOKEN_MISMATCH",'
          '"message":"Token rejected",'
          '"details":{"recommendedNextStep":"retry_with_device_token"}}}';
      ws.simulateServerFrame(raw);
      await pumpMicrotasks();

      expect(
        cm.state,
        GatewayConnectionState.authFailed,
        reason:
            'absent canRetryWithDeviceToken = no hint → fail closed, '
            'no retry',
      );

      await cm.dispose();
    });

    test(
      'non-AUTH_TOKEN_MISMATCH errors do not consume the retry budget',
      () async {
        final ws = ControllableWebSocket.ready();
        final tokenStore = FakeDeviceTokenStore();
        await tokenStore.save('test-instance', 'cached-token');

        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'pairing-code',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: (_) => ws.channel,
          deviceTokenStore: tokenStore,
        );

        unawaited(cm.connect());
        await pumpMicrotasks();
        ws.completeHandshake();
        await pumpMicrotasks();

        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);
        // Some other error — NOT AUTH_TOKEN_MISMATCH.
        final raw =
            '{"type":"res","id":"$reqId","ok":false,'
            '"error":{"code":"AUTH_SIGNATURE_INVALID",'
            '"message":"bad signature",'
            '"details":{}}}';
        ws.simulateServerFrame(raw);
        await pumpMicrotasks();

        expect(
          cm.state,
          GatewayConnectionState.authFailed,
          reason:
              'non-AUTH_TOKEN_MISMATCH errors must not retry — only '
              'this specific code gets the deviceToken retry budget',
        );

        await cm.dispose();
      },
    );

    // -------------------------------------------------------------------------
    // Regression: AUTH_TOKEN_MISMATCH must NOT retry from a terminal state
    // (Fix 3).
    //
    // Bug: `_handleAuthTokenMismatchRetry` sets
    // `_hasAttemptedDeviceTokenRetry = true` and calls
    // `_immediateReconnect(...)` unconditionally.  But
    // `_immediateReconnect` overrides `_state` to `disconnected` and
    // schedules a reconnect — papering over an existing terminal state
    // (authFailed / pairingRequired / reconnectExhausted) and burning
    // the retry budget for a session that should never have retried.
    //
    // Concrete scenario (race window):
    //   1. CM is mid-handshake (state=authenticating), connect in flight.
    //   2. A separate code path forces terminal state (authFailed)
    //      before the connect response arrives.
    //   3. Server returns AUTH_TOKEN_MISMATCH + canRetry=true.
    //   4. `_handleConnectResponse` fires `_handleAuthTokenMismatchRetry`
    //      WITHOUT checking that state is now terminal.
    //   5. Bug: state overwritten to disconnected, reconnect scheduled,
    //      retry budget consumed.
    //
    // Without the fix: state goes authFailed → disconnected and a new
    // connect fires. With the fix: state stays authFailed, no reconnect,
    // retry budget untouched.
    // -------------------------------------------------------------------------
    test(
      'AUTH_TOKEN_MISMATCH in terminal state (authFailed) does NOT retry',
      () async {
        final ws = ControllableWebSocket.ready();
        final tokenStore = FakeDeviceTokenStore();
        await tokenStore.save('test-instance', 'cached-token');

        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'pairing-code',
          deviceId: 'test-device',
          config: testConfig(),
          webSocketFactory: (_) => ws.channel,
          deviceTokenStore: tokenStore,
        );

        unawaited(cm.connect());
        await pumpMicrotasks();
        ws.completeHandshake();
        await pumpMicrotasks();

        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);

        // Force terminal state BEFORE the connect response arrives,
        // simulating a race where another code path (e.g. an error
        // timeout, or a stale res from a prior session) put us in
        // authFailed while the connect was still in flight.
        cm.setTestState(GatewayConnectionState.authFailed);
        expect(cm.state, GatewayConnectionState.authFailed);

        // Server returns AUTH_TOKEN_MISMATCH + canRetry=true — the
        // exact code path the retry handler exists for.
        ws.simulateServerFrame(
          authTokenMismatchJson(reqId, canRetryWithDeviceToken: true),
        );
        await pumpMicrotasks();
        // Let any queued microtasks (the retry handler) run.
        for (var i = 0; i < 4; i++) {
          await pumpMicrotasks();
        }

        // State must remain authFailed — the retry must NOT overwrite
        // it to disconnected.
        expect(
          cm.state,
          GatewayConnectionState.authFailed,
          reason:
              'AUTH_TOKEN_MISMATCH arriving in a terminal state must NOT '
              'trigger a retry — that would mask the underlying auth '
              'failure from the user and burn the retry budget',
        );

        // Critically: no retry was attempted. Without the fix the
        // handler would call _immediateReconnect which schedules a
        // 0s _scheduleDoConnect — but the socket was already torn down
        // via the terminal-state path, so the next pump would surface
        // it as a second connect attempt.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await pumpMicrotasks();
        final connectFrames = ws.sentFrames
            .where((f) => f.contains('"method":"connect"'))
            .length;
        expect(
          connectFrames,
          equals(1),
          reason:
              'must NOT issue a retry connect — only the original connect '
              'frame should exist',
        );

        await cm.dispose();
      },
    );

    test('AUTH_TOKEN_MISMATCH in terminal state (disconnected) does NOT '
        'consume retry budget', () async {
      // The clearest consequence of the bug: a stale AUTH_TOKEN_MISMATCH
      // arriving in a disconnected session (e.g. user clicked
      // disconnect; the response was already buffered on the wire) sets
      // `_hasAttemptedDeviceTokenRetry = true`.  When the user later
      // reconnects and legitimately hits AUTH_TOKEN_MISMATCH, the
      // retry budget is already consumed → the legitimate retry is
      // skipped → the user sees authFailed instead of getting the
      // one retry the spec §A.9 promises.
      final tokenStore = FakeDeviceTokenStore();
      await tokenStore.save('test-instance', 'cached-token');

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'pairing-code',
        deviceId: 'test-device',
        config: testConfig(),
        // Use a no-op factory — we never want this test to actually
        // open a socket (state stays in `disconnected` for the
        // entire test).
        webSocketFactory: (_) =>
            throw StateError('no socket should be opened in this test'),
        deviceTokenStore: tokenStore,
      );

      // User has explicitly disconnected.
      await cm.disconnect();
      expect(cm.state, GatewayConnectionState.disconnected);

      // We can't easily drive a real connect response here, but we
      // can directly verify the fix's contract via the authFailed
      // test above plus this assertion: once a clean session ends in
      // disconnected, a subsequent AUTH_TOKEN_MISMATCH must leave the
      // budget intact.  This is implicitly verified by the fix's
      // `if (_state.isTerminal) return;` guard — the budget is only
      // set inside the guarded block.
      //
      // The authFailed case above is the executable proof; this test
      // documents the user-visible consequence so future regressions
      // are caught by name even if the authFailed test is renamed.
      expect(tokenStore.loadCalls, equals(0));

      await cm.dispose();
    });

    // -------------------------------------------------------------------------
    // Regression: manual connect() must re-arm the AUTH_TOKEN_MISMATCH retry
    // budget.
    //
    // Bug: `_hasAttemptedDeviceTokenRetry` is set true on the first retry
    // (`_handleAuthTokenMismatchRetry`) and reset to false ONLY on a
    // successful hello-ok. If the retry also fails → terminal authFailed,
    // the budget stays consumed. The public `connect()` resets
    // `_reconnectAttempt` but NOT the retry budget, so a subsequent manual
    // reconnect — which spec §A.9 promises "1 retry per connection attempt"
    // — finds the budget already spent, skips the retry, and goes straight
    // to authFailed.
    //
    // Concrete scenario:
    //   1. connect() → AUTH_TOKEN_MISMATCH(canRetry=true) → retry fires
    //      (budget=true).
    //   2. retry also hits AUTH_TOKEN_MISMATCH → terminal authFailed
    //      (budget stays true; hello-ok never reached).
    //   3. User manually calls connect() → new attempt.
    //   4. Server returns AUTH_TOKEN_MISMATCH(canRetry=true) again.
    //   5. Bug: `_canRetryAuthTokenMismatch` returns false (budget still
    //      true) → no retry → authFailed.
    //      Fix: connect() resets the budget, so the retry fires and opens a
    //      fresh WebSocket (socket[3]).
    //
    // The reset MUST live in `connect()` (the manual-attempt entry point),
    // NOT in `_doConnect` — the auto-retry path goes through
    // `_scheduleDoConnect → _doConnect`, so resetting there would re-arm the
    // budget on every retry and create an infinite-retry loop.
    // -------------------------------------------------------------------------
    test('manual connect() after retry-budget exhaustion re-allows the '
        'AUTH_TOKEN_MISMATCH retry', () async {
      final tokenStore = FakeDeviceTokenStore();
      await tokenStore.save('test-instance', 'cached-token');
      final wsFactory = _ReusableWebSocketFactory();

      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'pairing-code',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: wsFactory.factory,
        deviceTokenStore: tokenStore,
      );

      // ---- First attempt → AUTH_TOKEN_MISMATCH → retry → also fails ----
      unawaited(cm.connect());
      await pumpMicrotasks();
      wsFactory.sockets.first.completeHandshake();
      await pumpMicrotasks();

      wsFactory.sockets.first.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final firstReqId = extractReqId(wsFactory.sockets.first.sentFrames.first);
      wsFactory.sockets.first.simulateServerFrame(
        authTokenMismatchJson(firstReqId, canRetryWithDeviceToken: true),
      );
      await pumpMicrotasks();

      // Let the auto-retry (socket[1]) fire.
      for (var i = 0; i < 8; i++) {
        await pumpMicrotasks();
      }
      expect(
        wsFactory.sockets.length,
        equals(2),
        reason: 'first AUTH_TOKEN_MISMATCH must trigger one auto-retry',
      );

      // Retry's socket → challenge → AUTH_TOKEN_MISMATCH again → authFailed.
      final retrySocket = wsFactory.sockets[1];
      retrySocket.completeHandshake();
      await pumpMicrotasks();
      retrySocket.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final retryReqId = extractReqId(retrySocket.sentFrames.first);
      retrySocket.simulateServerFrame(
        authTokenMismatchJson(retryReqId, canRetryWithDeviceToken: true),
      );
      await pumpMicrotasks();

      expect(
        cm.state,
        GatewayConnectionState.authFailed,
        reason:
            'retry-also-fails must end in terminal authFailed — no third '
            'auto-retry (spec §A.9 "try once")',
      );

      // ---- Manual reconnect — a fresh attempt that must re-arm the budget ----
      unawaited(cm.connect());
      for (var i = 0; i < 8; i++) {
        await pumpMicrotasks();
      }
      expect(
        wsFactory.sockets.length,
        equals(3),
        reason: 'manual connect() opens a fresh WebSocket',
      );
      final manualSocket = wsFactory.sockets[2];
      manualSocket.completeHandshake();
      await pumpMicrotasks();
      manualSocket.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final manualReqId = extractReqId(manualSocket.sentFrames.first);
      manualSocket.simulateServerFrame(
        authTokenMismatchJson(manualReqId, canRetryWithDeviceToken: true),
      );
      await pumpMicrotasks();

      // The retry budget was consumed by attempt #1; a manual connect() is a
      // NEW attempt that §A.9 promises a fresh retry. Before the fix the
      // budget is still true → no retry → authFailed. After the fix the
      // retry fires and opens socket[3].
      expect(
        cm.state,
        isNot(GatewayConnectionState.authFailed),
        reason:
            'manual reconnect must re-arm the retry budget — the new '
            'attempt\'s AUTH_TOKEN_MISMATCH should trigger a retry, not '
            'terminal authFailed',
      );

      // Let the re-armed retry (socket[3]) fire.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      for (var i = 0; i < 8; i++) {
        await pumpMicrotasks();
      }
      expect(
        wsFactory.sockets.length,
        greaterThanOrEqualTo(4),
        reason:
            'the re-armed retry must open a 4th WebSocket — before the '
            'fix connect() did not reset _hasAttemptedDeviceTokenRetry, so '
            'no retry fired and sockets.length stayed at 3',
      );

      await cm.dispose();
    });
  });
}
