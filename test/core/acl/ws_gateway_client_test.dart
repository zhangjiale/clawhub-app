import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/ws_gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // isTestTerminalState — predicate function
  // ---------------------------------------------------------------------------

  group('WsGatewayClient.isTestTerminalState', () {
    test('connected should be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(GatewayConnectionState.connected),
        isTrue,
      );
    });

    test('authFailed should be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(GatewayConnectionState.authFailed),
        isTrue,
      );
    });

    test('disconnected should be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(
          GatewayConnectionState.disconnected,
        ),
        isTrue,
      );
    });

    test('pairingRequired should be terminal (prevents 30s timeout)', () {
      // Regression: before the fix, testConnection's firstWhere ignored
      // pairingRequired, causing new devices to wait 30 s for approval.
      expect(
        WsGatewayClient.isTestTerminalState(
          GatewayConnectionState.pairingRequired,
        ),
        isTrue,
      );
    });

    test('connecting should NOT be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(GatewayConnectionState.connecting),
        isFalse,
      );
    });

    test('authenticating should NOT be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(
          GatewayConnectionState.authenticating,
        ),
        isFalse,
      );
    });

    test('recovering should NOT be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(GatewayConnectionState.recovering),
        isFalse,
      );
    });
  });
}
