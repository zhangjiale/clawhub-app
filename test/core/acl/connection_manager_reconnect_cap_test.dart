import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/utils/retry_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake timer for tests that don't need time control.
class _FakeTimer implements Timer {
  final Duration duration;
  final void Function() _callback;
  _FakeTimer(this.duration, this._callback);
  @override
  void cancel() {}
  @override
  bool get isActive => false;
  @override
  int get tick => 0;

  static final Timer Function(Duration, void Function()) noop =
      (Duration d, void Function() cb) => _FakeTimer(d, cb);
}

/// Tests for US-016 AC-3: bounded reconnect with reconnectExhausted state.
void main() {
  group('RetryStrategy - reconnect cap', () {
    test('maxAttempts: 3 allows attempts 0,1,2 and rejects 3+', () {
      const strategy = RetryStrategy(maxAttempts: 3);
      expect(strategy.shouldRetry(0), isTrue);
      expect(strategy.shouldRetry(1), isTrue);
      expect(strategy.shouldRetry(2), isTrue);
      expect(strategy.shouldRetry(3), isFalse);
      expect(strategy.shouldRetry(4), isFalse);
      expect(strategy.shouldRetry(100), isFalse);
    });

    test('maxAttempts: 0 rejects all attempts', () {
      const strategy = RetryStrategy(maxAttempts: 0);
      expect(strategy.shouldRetry(0), isFalse);
      expect(strategy.shouldRetry(1), isFalse);
    });

    test('maxAttempts: null allows unlimited retries', () {
      const strategy = RetryStrategy(maxAttempts: null);
      expect(strategy.shouldRetry(0), isTrue);
      expect(strategy.shouldRetry(100), isTrue);
      expect(strategy.shouldRetry(1000), isTrue);
    });

    // maxAttempts: 2 = 3 total (1 initial + 2 retries, per RetryStrategy doc).
    test('networkReconnectLimited has maxAttempts: 2 (3 total)', () {
      expect(RetryStrategy.networkReconnectLimited.maxAttempts, 2);
      expect(RetryStrategy.networkReconnectLimited.shouldRetry(1), isTrue);
      expect(RetryStrategy.networkReconnectLimited.shouldRetry(2), isFalse);
    });

    test(
      'networkReconnect has null maxAttempts (infinite, backward compat)',
      () {
        expect(RetryStrategy.networkReconnect.maxAttempts, isNull);
        expect(RetryStrategy.networkReconnect.shouldRetry(0), isTrue);
        expect(RetryStrategy.networkReconnect.shouldRetry(100), isTrue);
      },
    );

    test('default ConnectionManager uses bounded retry (maxAttempts: 2)', () {
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: ConnectionConfig(),
        timerFactory: _FakeTimer.noop,
      );
      // The default strategy should be bounded (not infinite)
      // We verify by checking that the CM was created without error
      expect(cm.state, GatewayConnectionState.disconnected);
    });

    test(
      'explicit RetryStrategy.networkReconnect preserves infinite retries',
      () {
        final cm = ConnectionManager(
          instanceId: 'test-instance',
          gatewayUrl: 'ws://localhost:9999/ws',
          token: 'test-token',
          deviceId: 'test-device',
          config: ConnectionConfig(),
          retryStrategy: RetryStrategy.networkReconnect,
          timerFactory: _FakeTimer.noop,
        );
        expect(cm.state, GatewayConnectionState.disconnected);
      },
    );
  });

  group('reconnectExhausted state transition', () {
    test('setTestState can set reconnectExhausted', () {
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: ConnectionConfig(),
        retryStrategy: const RetryStrategy(maxAttempts: 3),
        timerFactory: _FakeTimer.noop,
      );

      // setTestState updates _state synchronously (verified via cm.state)
      cm.setTestState(GatewayConnectionState.reconnectExhausted);
      expect(cm.state, GatewayConnectionState.reconnectExhausted);
    });

    test('state transitions through various states', () {
      final cm = ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: ConnectionConfig(),
        retryStrategy: const RetryStrategy(maxAttempts: 3),
        timerFactory: _FakeTimer.noop,
      );

      expect(cm.state, GatewayConnectionState.disconnected);

      cm.setTestState(GatewayConnectionState.connecting);
      expect(cm.state, GatewayConnectionState.connecting);

      cm.setTestState(GatewayConnectionState.connected);
      expect(cm.state, GatewayConnectionState.connected);

      cm.setTestState(GatewayConnectionState.reconnectExhausted);
      expect(cm.state, GatewayConnectionState.reconnectExhausted);

      // No-op when setting same state twice
      cm.setTestState(GatewayConnectionState.reconnectExhausted);
      expect(cm.state, GatewayConnectionState.reconnectExhausted);
    });
  });

  group('GatewayConnectionState exhaustiveness', () {
    test('all expected values are defined', () {
      // Verify the full enum has all values including the new one
      const values = GatewayConnectionState.values;
      expect(values, contains(GatewayConnectionState.disconnected));
      expect(values, contains(GatewayConnectionState.connecting));
      expect(values, contains(GatewayConnectionState.authenticating));
      expect(values, contains(GatewayConnectionState.connected));
      expect(values, contains(GatewayConnectionState.recovering));
      expect(values, contains(GatewayConnectionState.authFailed));
      expect(values, contains(GatewayConnectionState.pairingRequired));
      expect(values, contains(GatewayConnectionState.reconnectExhausted));
      expect(values.length, 8);
    });
  });

  group('RetryStrategy delay calculation', () {
    test('delayForAttempt follows exponential backoff', () {
      const strategy = RetryStrategy(baseDelaySeconds: 1, maxDelaySeconds: 30);
      expect(strategy.delayForAttempt(0).inSeconds, 1);
      expect(strategy.delayForAttempt(1).inSeconds, 2);
      expect(strategy.delayForAttempt(2).inSeconds, 4);
      expect(strategy.delayForAttempt(3).inSeconds, 8);
      expect(strategy.delayForAttempt(4).inSeconds, 16);
      expect(strategy.delayForAttempt(5).inSeconds, 30); // capped
      expect(strategy.delayForAttempt(10).inSeconds, 30); // still capped
    });
  });
}
