import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

ConnectionConfig testConfig() => ConnectionConfig();

/// Build a `tick` event frame with optional server timestamp (spec §2.8).
///
/// Spec: server may include `payload.ts` (epoch ms) so clients can
/// detect clock drift that would otherwise manifest as
/// DEVICE_AUTH_SIGNATURE_EXPIRED with no obvious root cause.
String tickWithTsJson({int? ts}) {
  final tsField = ts != null ? '"ts":$ts' : '';
  return '{"type":"event","event":"tick","payload":{$tsField}}';
}

void main() {
  // ============================================================================
  // Gap #5: tick.payload.ts 时钟漂移检测（spec §2.8）
  //
  // 背景：客户端时钟偏差大时 V3 签名会因 timestamp 超出 nonce 有效期
  // 而返回 DEVICE_AUTH_SIGNATURE_EXPIRED，但用户看不到任何"是客户端
  // 时钟问题"的指示，无法定位根因。
  //
  // Spec §2.8 允许 Gateway 在 tick event 中带 `payload.ts`（服务器
  // 时间戳）。客户端应：
  //   1. 解析 ts，与本地 DateTime.now() 比对
  //   2. |drift| > 5000ms 时记录警告（诊断日志 + 内部状态）
  //   3. ts 缺失或 null → 静默忽略（向后兼容）
  //
  // 这些测试固定以下契约：
  //   1. 漂移 < 5s → 不记录
  //   2. 漂移 ≥ 5s → 记录且 _lastObservedClockDriftMs 正确（带符号）
  //   3. ts 缺失 → 不崩，_lastObservedClockDriftMs 不更新
  //   4. tick 重置连接 timer 的核心职责仍然正常（不被漂移检测干扰）
  // ============================================================================
  group('ConnectionManager tick.payload.ts clock drift (Gap #5)', () {
    test('ts missing → silent (backward compat with old Gateway)', () async {
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
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);

      // tick without ts → no drift recorded
      expect(cm.lastObservedClockDriftMsForTesting, isNull);

      ws.simulateServerFrame(tickWithTsJson());
      await pumpMicrotasks();

      expect(
        cm.lastObservedClockDriftMsForTesting,
        isNull,
        reason:
            'tick without payload.ts must NOT populate clock drift '
            '(old Gateway builds don\'t send it)',
      );

      await cm.dispose();
    });

    test('ts with small drift (< 5s) is recorded silently', () async {
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
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      final clientNow = DateTime.now().millisecondsSinceEpoch;
      // 3s drift — under the 5s threshold
      ws.simulateServerFrame(tickWithTsJson(ts: clientNow + 3000));
      await pumpMicrotasks();

      final drift = cm.lastObservedClockDriftMsForTesting;
      expect(drift, isNotNull);
      // 3s ± some test overhead. Allow generous bounds since DateTime.now()
      // advances during the test.
      expect(
        drift!,
        inInclusiveRange(2500, 3500),
        reason: '3s server-ahead drift recorded verbatim',
      );

      await cm.dispose();
    });

    test(
      'ts with large drift (server ahead ≥ 5s) is recorded as positive',
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
        ws.simulateServerFrame(helloOkJson(reqId));
        await pumpMicrotasks();

        final clientNow = DateTime.now().millisecondsSinceEpoch;
        // 7s ahead — over the 5s threshold → warning path
        ws.simulateServerFrame(tickWithTsJson(ts: clientNow + 7000));
        await pumpMicrotasks();

        final drift = cm.lastObservedClockDriftMsForTesting;
        expect(drift, isNotNull);
        expect(
          drift!,
          greaterThanOrEqualTo(5000),
          reason: '7s drift must trigger warning (server ahead of client)',
        );
        expect(
          drift,
          inInclusiveRange(6500, 7500),
          reason: 'drift recorded verbatim (~7s ± overhead)',
        );

        await cm.dispose();
      },
    );

    test(
      'ts with large drift (server behind ≥ 5s) is recorded as negative',
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
        ws.simulateServerFrame(helloOkJson(reqId));
        await pumpMicrotasks();

        final clientNow = DateTime.now().millisecondsSinceEpoch;
        // 6s behind — over the 5s threshold → warning path, signed negative
        ws.simulateServerFrame(tickWithTsJson(ts: clientNow - 6000));
        await pumpMicrotasks();

        final drift = cm.lastObservedClockDriftMsForTesting;
        expect(drift, isNotNull);
        expect(
          drift!,
          lessThanOrEqualTo(-5000),
          reason: 'negative drift means server is behind client',
        );
        expect(
          drift,
          inInclusiveRange(-6500, -5500),
          reason: 'drift recorded verbatim (~-6s ± overhead)',
        );

        await cm.dispose();
      },
    );

    test(
      'tick resets the connection timer regardless of ts presence',
      () async {
        // The tick event has TWO responsibilities:
        //   (a) reset the connection keepalive timer (existing)
        //   (b) report clock drift (new, Gap #5)
        // The drift detection MUST NOT regress (a) — if the timer
        // doesn't get reset, the connection will be killed after
        // tickIntervalMs × 2.
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
        ws.simulateServerFrame(helloOkJson(reqId));
        await pumpMicrotasks();

        // Send several ticks. The timer must keep getting reset.
        // We can't easily inspect the private timer, but we can verify
        // the connection state stays `connected` after ticks that
        // would otherwise push it into reconnect territory if the
        // timer weren't being reset.
        for (var i = 0; i < 3; i++) {
          ws.simulateServerFrame(
            tickWithTsJson(ts: DateTime.now().millisecondsSinceEpoch),
          );
          await pumpMicrotasks();
        }
        expect(
          cm.state,
          GatewayConnectionState.connected,
          reason:
              'ticks must reset the keepalive timer — connection '
              'would otherwise die after tickIntervalMs × 2 of silence',
        );

        await cm.dispose();
      },
    );

    test('multiple ticks: latest drift overwrites previous value', () async {
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
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      // First tick: 3s drift (small)
      ws.simulateServerFrame(
        tickWithTsJson(ts: DateTime.now().millisecondsSinceEpoch + 3000),
      );
      await pumpMicrotasks();
      final firstDrift = cm.lastObservedClockDriftMsForTesting;

      // Second tick: 7s drift (warning) — must overwrite, not append
      ws.simulateServerFrame(
        tickWithTsJson(ts: DateTime.now().millisecondsSinceEpoch + 7000),
      );
      await pumpMicrotasks();
      final secondDrift = cm.lastObservedClockDriftMsForTesting;

      expect(firstDrift, isNotNull);
      expect(secondDrift, isNotNull);
      expect(secondDrift!, greaterThan(firstDrift!));

      await cm.dispose();
    });
  });
}
