import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/usecases/gateway_change_exceptions.dart';

void main() {
  group('GatewayChangeRequiredException', () {
    test('携带 localAgentCount', () {
      const e = GatewayChangeRequiredException(localAgentCount: 7);
      expect(e.localAgentCount, 7);
    });

    test('toString 含数量', () {
      const e = GatewayChangeRequiredException(localAgentCount: 3);
      expect(e.toString(), contains('3'));
    });
  });

  group('PurgeFailedException', () {
    test('携带 message 与 cause, toString 含 message', () {
      final inner = StateError('db locked');
      final e = PurgeFailedException(message: '清除本地数据失败', cause: inner);
      expect(e.message, '清除本地数据失败');
      expect(e.cause, same(inner));
      expect(e.toString(), contains('清除本地数据失败'));
    });
  });

  group('GatewayUnreachableException', () {
    test('携带默认中文 message, toString 含 message', () {
      const e = GatewayUnreachableException();
      expect(e.message, isNotEmpty);
      expect(e.message, contains('Gateway'));
      expect(e.toString(), contains(e.message));
    });

    test('可自定义 message', () {
      const e = GatewayUnreachableException(message: '自定义错误');
      expect(e.message, '自定义错误');
      expect(e.toString(), contains('自定义错误'));
    });
  });
}
