import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';

void main() {
  group('QrScanResult.fromMap', () {
    test('parses valid JSON with all fields', () {
      final result = QrScanResult.fromMap({
        'name': 'My MacBook',
        'gatewayUrl': 'wss://192.168.1.100:18789',
        'token': 'abc123',
      });

      expect(result.name, 'My MacBook');
      expect(result.gatewayUrl, 'wss://192.168.1.100:18789');
      expect(result.token, 'abc123');
    });

    test('parses valid JSON with only gatewayUrl', () {
      final result = QrScanResult.fromMap({
        'gatewayUrl': 'ws://10.0.0.1:8080',
      });

      expect(result.name, isNull);
      expect(result.gatewayUrl, 'ws://10.0.0.1:8080');
      expect(result.token, isNull);
    });

    test('throws FormatException when gatewayUrl is missing', () {
      expect(
        () => QrScanResult.fromMap({'name': 'Test'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when gatewayUrl is empty', () {
      expect(
        () => QrScanResult.fromMap({'gatewayUrl': '  '}),
        throwsA(isA<FormatException>()),
      );
    });

    test('trims whitespace from gatewayUrl', () {
      final result = QrScanResult.fromMap({
        'gatewayUrl': '  wss://host:18789  ',
      });

      expect(result.gatewayUrl, 'wss://host:18789');
    });
  });
}
