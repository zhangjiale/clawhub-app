import 'dart:async';

import 'package:claw_hub/core/acl/gateway_instance_connection.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GatewayInstanceConnection', () {
    GatewayInstanceConnection createConnection() {
      return GatewayInstanceConnection(
        messageCtrl: StreamController<Message>.broadcast(),
        toolCallCtrl: StreamController<ToolCall>.broadcast(),
        pairingInfoCtrl: StreamController<GatewayPairingInfo?>.broadcast(),
        streamingCtrl: StreamController<StreamingEvent>.broadcast(),
      );
    }

    test('controllers are open after creation', () {
      final conn = createConnection();
      expect(conn.messageCtrl.isClosed, isFalse);
      expect(conn.toolCallCtrl.isClosed, isFalse);
      expect(conn.pairingInfoCtrl.isClosed, isFalse);
      expect(conn.streamingCtrl.isClosed, isFalse);
      expect(conn.gatewayNoticeCtrl.isClosed, isFalse);
    });

    test('dispose closes all controllers', () async {
      final conn = createConnection();
      await conn.dispose();
      expect(conn.messageCtrl.isClosed, isTrue);
      expect(conn.toolCallCtrl.isClosed, isTrue);
      expect(conn.pairingInfoCtrl.isClosed, isTrue);
      expect(conn.streamingCtrl.isClosed, isTrue);
      expect(conn.gatewayNoticeCtrl.isClosed, isTrue);
    });

    test('cleanupManager without manager is a no-op', () async {
      final conn = createConnection();
      await conn.cleanupManager();
      expect(conn.manager, isNull);
      expect(conn.messageCtrl.isClosed, isFalse);
    });

    test('cleanupManager is re-entrant safe', () async {
      final conn = createConnection();
      await conn.cleanupManager();
      await conn.cleanupManager();
      expect(conn.manager, isNull);
      expect(conn.messageCtrl.isClosed, isFalse);
    });

    test('dispose is idempotent', () async {
      final conn = createConnection();
      await conn.dispose();
      await conn.dispose();
      expect(conn.messageCtrl.isClosed, isTrue);
    });
  });
}
