import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'test_helpers.dart';

ConnectionConfig testConfig({Future<String> Function(String)? signPayload}) =>
    ConnectionConfig(signPayload: signPayload);

// ---------------------------------------------------------------------------
// Reused fakes from connection_manager_test.dart — duplicated here because
// the test file is small and we don't want to expose the helpers' FakeTimer
// to other suites that don't need it.
// ---------------------------------------------------------------------------

class FakeTimer implements Timer {
  final Duration duration;
  final void Function() _callback;
  bool _cancelled = false;
  bool _fired = false;

  FakeTimer(this.duration, this._callback);

  @override
  void cancel() {
    _cancelled = true;
  }

  @override
  bool get isActive => !_cancelled && !_fired;

  @override
  int get tick => 0;

  bool get isCancelled => _cancelled;
  bool get isFired => _fired;

  void fire() {
    if (_cancelled || _fired) return;
    _fired = true;
    _callback();
  }
}

class FakeTimerFactory {
  final List<FakeTimer> timers = [];

  Timer call(Duration duration, void Function() callback) {
    final timer = FakeTimer(duration, callback);
    timers.add(timer);
    return timer;
  }

  FakeTimer? get lastTimer => timers.isEmpty ? null : timers.last;
  Iterable<FakeTimer> get activeTimers => timers.where((t) => t.isActive);

  void reset() => timers.clear();
}

void main() {
  // ============================================================================
  // Gap #4: server-initiated `shutdown` event must trigger immediate reconnect,
  // NOT the exponential backoff used for network failures.
  //
  // Spec §2.6: "服务端主动通知客户端即将关闭" — server-side shutdown is
  // expected (rolling restart, planned maintenance). Server is ready again
  // immediately after, so the client should reconnect at once.
  // ============================================================================
  group('shutdown graceful reconnect (Gap #4)', () {
    late FakeTimerFactory timerFactory;
    late ConnectionManager cm;
    late ControllableWebSocket ws;
    late List<GatewayConnectionState> stateLog;

    setUp(() {
      timerFactory = FakeTimerFactory();
      ws = ControllableWebSocket.ready();
      stateLog = <GatewayConnectionState>[];

      cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        timerFactory: timerFactory.call,
        webSocketFactory: (_) => ws.channel,
      );
      cm.connectionState.listen(stateLog.add);
    });

    /// Drive the handshake to `connected` state.
    Future<void> driveHandshake() async {
      cm.connect();
      await pumpMicrotasks();
      ws.completeHandshake();
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(cm.state, GatewayConnectionState.connected);
    }

    test('shutdown event triggers disconnected state immediately', () async {
      await driveHandshake();
      timerFactory.reset(); // ignore handshake timers

      ws.simulateServerFrame(shutdownJson);
      await pumpMicrotasks();

      expect(
        cm.state,
        GatewayConnectionState.disconnected,
        reason: 'graceful shutdown must surface disconnected to the UI',
      );
    });

    test(
      'shutdown event schedules reconnect with 0s delay (no backoff)',
      () async {
        await driveHandshake();
        timerFactory.reset(); // ignore handshake/tick timers

        ws.simulateServerFrame(shutdownJson);
        await pumpMicrotasks();

        // The reconnect timer is the most recently scheduled timer.
        final reconnectTimer = timerFactory.lastTimer;
        expect(
          reconnectTimer,
          isNotNull,
          reason: 'graceful shutdown must schedule a reconnect',
        );
        expect(
          reconnectTimer!.duration,
          Duration.zero,
          reason:
              'must use 0s delay — server is ready immediately after '
              'graceful shutdown (spec §2.6), backoff is wrong here',
        );
      },
    );

    test('shutdown event does NOT increment _reconnectAttempt '
        '(uses _scheduleDoConnect, not _scheduleReconnect)', () async {
      await driveHandshake();
      timerFactory.reset();

      ws.simulateServerFrame(shutdownJson);
      await pumpMicrotasks();

      // The only scheduled timer must be the 0s graceful-shutdown
      // reconnect. If we had gone through _scheduleReconnect, the
      // delay would be 1s+ (from RetryStrategy.delayForAttempt(0))
      // AND _reconnectAttempt would have been bumped via its onFire
      // callback.  The 0s delay proves we bypassed _scheduleReconnect
      // entirely.  The "does NOT bump _reconnectAttempt on rolling
      // restart" property is implicit in this — each rolling restart
      // schedules a 0s reconnect that doesn't increment the counter,
      // so N rolling restarts do not converge on reconnectExhausted.
      final timer = timerFactory.lastTimer;
      expect(timer, isNotNull);
      expect(
        timer!.duration,
        Duration.zero,
        reason:
            'must use _scheduleDoConnect (no backoff); '
            '_scheduleReconnect would schedule 1s+ via RetryStrategy',
      );
    });

    test(
      'shutdown during intentional disconnect does NOT schedule reconnect',
      () async {
        await driveHandshake();

        // User explicitly disconnects (e.g. instance removed in settings).
        // _intentionalDisconnect is set; any subsequent shutdown must be
        // ignored.
        await cm.disconnect();
        expect(cm.state, GatewayConnectionState.disconnected);
        timerFactory.reset();

        // Invoke _handleEvent directly via the test seam — the channel is
        // already torn down so we can't simulate a server frame.
        cm.handleEventForTesting(Events.shutdown, <String, dynamic>{});
        await pumpMicrotasks();

        expect(
          timerFactory.lastTimer,
          isNull,
          reason:
              'must NOT schedule reconnect when user has explicitly '
              'disconnected (avoids zombie reconnects after instance removal)',
        );
      },
    );

    test(
      'shutdown during authFailed terminal state does NOT schedule reconnect',
      () async {
        await driveHandshake();
        timerFactory.reset();

        // Force a terminal state (authFailed). The graceful shutdown path
        // must respect terminal states and not paper over them.
        cm.setTestState(GatewayConnectionState.authFailed);
        cm.handleEventForTesting(Events.shutdown, <String, dynamic>{});
        await pumpMicrotasks();

        expect(
          timerFactory.lastTimer,
          isNull,
          reason:
              'must NOT schedule reconnect over a terminal state '
              '(reconnect would mask the auth failure from the user)',
        );
      },
    );
  });
}
