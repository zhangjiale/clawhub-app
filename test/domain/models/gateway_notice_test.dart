import 'package:claw_hub/domain/models/gateway_notice.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gap #6 收尾 (Step 1, Law 17 RED): 把诊断事件收敛成 sealed union。
///
/// 当前只有 `LargePayloadNotice` 一个子类型。本测试先于源码存在——
/// 跑它应编译失败（`gateway_notice.dart` 尚不存在）= 可接受的红。
/// GREEN 阶段创建源码后转绿。
void main() {
  group('LargePayloadNotice', () {
    test('stores sessionKey / size / limit fields', () {
      final n = LargePayloadNotice(
        sessionKey: 'agent:r-1:main',
        size: 30_000_000,
        limit: 26_214_400,
      );
      expect(n.sessionKey, 'agent:r-1:main');
      expect(n.size, 30_000_000);
      expect(n.limit, 26_214_400);
    });

    test('equality is value-based', () {
      final a = LargePayloadNotice(sessionKey: 'k', size: 100, limit: 50);
      final b = LargePayloadNotice(sessionKey: 'k', size: 100, limit: 50);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when any field differs', () {
      final base = LargePayloadNotice(sessionKey: 'k', size: 100, limit: 50);
      expect(
        base == LargePayloadNotice(sessionKey: 'other', size: 100, limit: 50),
        isFalse,
      );
      expect(
        base == LargePayloadNotice(sessionKey: 'k', size: 999, limit: 50),
        isFalse,
      );
      expect(
        base == LargePayloadNotice(sessionKey: 'k', size: 100, limit: 999),
        isFalse,
      );
    });

    test('toString includes the three field values for diagnostics', () {
      final n = LargePayloadNotice(sessionKey: 'k', size: 30, limit: 20);
      expect(n.toString(), contains('30'));
      expect(n.toString(), contains('20'));
    });
  });

  // F-4 (Law 17 RED): 客户端在途缓冲满（maxBufferedBytes）时 ConnectionManager
  // 抛 BufferOverflowException。ACL 把它翻译成本子类型推上 gatewayNoticeStream，
  // 复用 LargePayloadNotice 的 toast 基建 —— 用户看到「网关繁忙，将自动重试」
  // 而不是无说明的 FAILED。本子类型是无字段标记：缓冲满是瞬态、不可由用户
  // 缓解（不同于 payload.large 可缩短内容），文案只定性不定量。
  group('BufferOverflowNotice', () {
    test('is constructible with no fields (marker subtype)', () {
      const notice = BufferOverflowNotice();
      expect(notice, isA<GatewayNotice>());
    });

    test('all instances are equal (value-less marker)', () {
      // 无字段 -> 所有实例值相等。toast 触发靠 gatewayNoticeProvider
      // (StreamProvider) 每次流 emit 调一次 ref.listen callback
      // （见 lib/app/di/providers.dart gatewayNoticeProvider），
      // 不靠 == 区分，故标量相等不会抑制连续 toast。
      const a = BufferOverflowNotice();
      const b = BufferOverflowNotice();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString is stable and mentions the subtype name', () {
      const notice = BufferOverflowNotice();
      expect(notice.toString(), contains('BufferOverflowNotice'));
    });
  });

  group('GatewayNotice sealed union', () {
    // 穷尽性契约: sealed 保证 switch 覆盖所有子类型后无需 default。
    // 未来新增子类型(rate.limit / quota.exceeded)时若漏处理 → 编译错,
    // 强制 page 侧的 _fmt(GatewayNotice) 同步补分支。这是 Step 4 收敛点
    // 把"加事件不再碰 state/page"承诺的编译期护栏。
    test('switch over GatewayNotice is exhaustive without default', () {
      String describe(GatewayNotice n) => switch (n) {
        LargePayloadNotice(:final size, :final limit) => 'large:$size/$limit',
        BufferOverflowNotice() => 'buffer',
      };

      expect(
        describe(LargePayloadNotice(sessionKey: 'k', size: 30, limit: 20)),
        'large:30/20',
      );
      expect(describe(const BufferOverflowNotice()), 'buffer');
    });

    test('LargePayloadNotice is a GatewayNotice (subtype)', () {
      GatewayNotice asBase = LargePayloadNotice(
        sessionKey: 'k',
        size: 1,
        limit: 2,
      );
      expect(asBase, isA<LargePayloadNotice>());
    });

    test('BufferOverflowNotice is a GatewayNotice (subtype)', () {
      const GatewayNotice asBase = BufferOverflowNotice();
      expect(asBase, isA<BufferOverflowNotice>());
    });
  });
}
