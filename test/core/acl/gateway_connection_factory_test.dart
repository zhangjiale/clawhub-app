import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_connection_factory.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GatewayConnectionFactory', () {
    test('creates ConnectionManager with provided parameters', () {
      const factory = GatewayConnectionFactory();
      final manager = factory.create(
        instanceId: 'inst-1',
        gatewayUrl: 'wss://example.com',
        token: 'token-1',
        deviceId: 'device-1',
        config: ConnectionConfig(),
      );
      expect(manager, isA<ConnectionManager>());
    });
  });
}
