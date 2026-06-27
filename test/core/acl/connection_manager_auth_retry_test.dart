import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_device_token_store.dart';
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

/// In-memory device token store for tests — supports both `save` and
/// `load` (which `_resolveBearerToken` calls) and `delete` (which the
/// retry path could use if needed in future).
class _InMemoryDeviceTokenStore implements IDeviceTokenStore {
  final Map<String, String> _tokens = {};

  /// Number of times load() has been called — useful for asserting
  /// "retry actually re-resolved the token via the cache".
  int loadCalls = 0;

  /// Number of times delete() has been called.
  int deleteCalls = 0;

  @override
  Future<void> save(String instanceId, String deviceToken) async {
    _tokens[instanceId] = deviceToken;
  }

  @override
  Future<String?> load(String instanceId) async {
    loadCalls++;
    return _tokens[instanceId];
  }

  @override
  Future<void> delete(String instanceId) async {
    deleteCalls++;
    _tokens.remove(instanceId);
  }
}

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
        final tokenStore = _InMemoryDeviceTokenStore();
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
        final tokenStore = _InMemoryDeviceTokenStore();
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
      final tokenStore = _InMemoryDeviceTokenStore();
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
      final tokenStore = _InMemoryDeviceTokenStore();
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
        final tokenStore = _InMemoryDeviceTokenStore();
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
  });
}
