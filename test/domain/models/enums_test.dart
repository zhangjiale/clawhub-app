import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('HealthStatus', () {
    test('fromInt 正确映射', () {
      expect(HealthStatus.fromInt(0), HealthStatus.unknown);
      expect(HealthStatus.fromInt(1), HealthStatus.online);
      expect(HealthStatus.fromInt(2), HealthStatus.offline);
      expect(HealthStatus.fromInt(3), HealthStatus.connecting);
      expect(HealthStatus.fromInt(4), HealthStatus.expectedOffline);
      expect(HealthStatus.fromInt(5), HealthStatus.pairingRequired);
    });

    test('toInt 正确序列化', () {
      expect(HealthStatus.unknown.toInt(), 0);
      expect(HealthStatus.online.toInt(), 1);
      expect(HealthStatus.offline.toInt(), 2);
      expect(HealthStatus.connecting.toInt(), 3);
      expect(HealthStatus.expectedOffline.toInt(), 4);
      expect(HealthStatus.pairingRequired.toInt(), 5);
    });

    test('无效值抛异常', () {
      expect(() => HealthStatus.fromInt(-1), throwsA(isA<ArgumentError>()));
      expect(() => HealthStatus.fromInt(99), throwsA(isA<ArgumentError>()));
    });

    test('isConnectable - 仅在线和未知状态可连接', () {
      expect(HealthStatus.online.isConnectable, isTrue);
      expect(HealthStatus.unknown.isConnectable, isTrue);
      expect(HealthStatus.offline.isConnectable, isFalse);
      expect(HealthStatus.connecting.isConnectable, isFalse);
      expect(HealthStatus.expectedOffline.isConnectable, isFalse);
      expect(HealthStatus.pairingRequired.isConnectable, isFalse);
    });
  });

  group('MessageRole', () {
    test('fromInt 正确映射', () {
      expect(MessageRole.fromInt(0), MessageRole.user);
      expect(MessageRole.fromInt(1), MessageRole.agent);
      expect(MessageRole.fromInt(2), MessageRole.system);
    });

    test('无效值抛异常', () {
      expect(() => MessageRole.fromInt(-1), throwsA(isA<ArgumentError>()));
      expect(() => MessageRole.fromInt(3), throwsA(isA<ArgumentError>()));
    });
  });

  group('MessageType', () {
    test('fromInt 正确映射', () {
      expect(MessageType.fromInt(0), MessageType.text);
      expect(MessageType.fromInt(1), MessageType.image);
      expect(MessageType.fromInt(2), MessageType.file);
      expect(MessageType.fromInt(3), MessageType.toolCall);
    });

    test('无效值抛异常', () {
      expect(() => MessageType.fromInt(-1), throwsA(isA<ArgumentError>()));
      expect(() => MessageType.fromInt(4), throwsA(isA<ArgumentError>()));
    });
  });

  group('ToolCallStatus', () {
    test('fromInt 正确映射', () {
      expect(ToolCallStatus.fromInt(0), ToolCallStatus.pending);
      expect(ToolCallStatus.fromInt(1), ToolCallStatus.running);
      expect(ToolCallStatus.fromInt(2), ToolCallStatus.success);
      expect(ToolCallStatus.fromInt(3), ToolCallStatus.failed);
    });

    test('isCompleted 判断', () {
      expect(ToolCallStatus.success.isCompleted, isTrue);
      expect(ToolCallStatus.failed.isCompleted, isTrue);
      expect(ToolCallStatus.pending.isCompleted, isFalse);
      expect(ToolCallStatus.running.isCompleted, isFalse);
    });
  });
}
