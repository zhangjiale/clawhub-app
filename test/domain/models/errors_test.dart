// F 修复测试:errors.dart 的 ==/hashCode 契约锁定。
// equal_elements_in_set 在 Set dedup 测试中为预期行为(测试 ==/hashCode 是否生效)。
// ignore_for_file: equal_elements_in_set

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/errors.dart';

void main() {
  group('AgentNotFoundError', () {
    test('stores agentId', () {
      const error = AgentNotFoundError('test-id');
      expect(error.agentId, 'test-id');
    });

    test('toString includes agentId', () {
      const error = AgentNotFoundError('abc-123');
      expect(error.toString(), contains('abc-123'));
    });

    test('is Exception', () {
      const error = AgentNotFoundError('id');
      expect(error, isA<Exception>());
    });

    // F 修复:锁定 ==/hashCode 契约,防止 List/Set/Riverpod `select` 里
    // false-positive 去重。源已实现 (errors.dart:9-13),此处为行为契约。
    test('two errors with same agentId are == and have same hashCode', () {
      const a = AgentNotFoundError('a-1');
      const b = AgentNotFoundError('a-1');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('errors with different agentId are not ==', () {
      const a = AgentNotFoundError('a-1');
      const b = AgentNotFoundError('a-2');
      expect(a, isNot(equals(b)));
    });

    test('Set dedup treats same agentId as one element', () {
      // false-positive 去重风险的核心场景:如果 ==/hashCode 缺失,
      // Set 会把两个相同 agentId 的 error 当作不同元素。
      final set = <AgentNotFoundError>{
        const AgentNotFoundError('a-1'),
        const AgentNotFoundError('a-1'),
        const AgentNotFoundError('a-2'),
      };
      expect(set, hasLength(2));
    });
  });

  group('AgentRemovedError', () {
    test('stores agentId', () {
      const error = AgentRemovedError('test-id');
      expect(error.agentId, 'test-id');
    });

    test('toString includes agentId', () {
      const error = AgentRemovedError('abc-123');
      expect(error.toString(), contains('abc-123'));
    });

    test('is Exception', () {
      const error = AgentRemovedError('id');
      expect(error, isA<Exception>());
    });

    test('two errors with same agentId are == and have same hashCode', () {
      const a = AgentRemovedError('r-1');
      const b = AgentRemovedError('r-1');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('errors with different agentId are not ==', () {
      const a = AgentRemovedError('r-1');
      const b = AgentRemovedError('r-2');
      expect(a, isNot(equals(b)));
    });

    test('Set dedup treats same agentId as one element', () {
      final set = <AgentRemovedError>{
        const AgentRemovedError('r-1'),
        const AgentRemovedError('r-1'),
        const AgentRemovedError('r-2'),
      };
      expect(set, hasLength(2));
    });

    test(
      'AgentNotFoundError and AgentRemovedError with same agentId are not ==',
      () {
        // 不同异常类型即使 agentId 相同也不应相等 —— 类型本身是判别字段。
        // 当前实现都按 (type + agentId) 判等,所以自然不相等。锁定此行为
        // 防止未来重构时引入"跨类型 =="的隐式 bug。
        const a = AgentNotFoundError('x-1');
        const b = AgentRemovedError('x-1');
        expect(a, isNot(equals(b)));
      },
    );
  });
}
