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
  // 而不是无说明的 FAILED。本子类型带 [emittedAt] 时间戳：缓冲满是瞬态、
  // 不可由用户缓解（不同于 payload.large 可缩短内容），文案只定性不定量；
  // 时间戳只用于去重层区分连续事件，不向用户展示。
  group('BufferOverflowNotice', () {
    test('is constructible and defaults emittedAt to now', () {
      final before = DateTime.now();
      final notice = BufferOverflowNotice();
      final after = DateTime.now();
      expect(notice, isA<GatewayNotice>());
      expect(
        notice.emittedAt.isAfter(before) || notice.emittedAt == before,
        isTrue,
      );
      expect(
        notice.emittedAt.isBefore(after) || notice.emittedAt == after,
        isTrue,
      );
    });

    test('emittedAt can be injected for tests', () {
      final t = DateTime.utc(2026, 7, 5, 12, 0);
      final notice = BufferOverflowNotice(emittedAt: t);
      expect(notice.emittedAt, t);
    });

    test('instances are identity-equal only — no value dedup (#9)', () {
      // Review #9: BufferOverflowNotice is a transient event, not a value
      // object. Consecutive notices must NOT be ==, or Riverpod's
      // StreamProvider dedups consecutive AsyncData and the second
      // ref.listen (toast) is suppressed. Pre-fix == compared emittedAt,
      // which collapsed same-millisecond (web) / same-microsecond (native)
      // bursts into one toast. Identity equality guarantees every notice is
      // distinct regardless of timestamp precision.
      final t = DateTime.utc(2026, 7, 5, 12, 0);
      final a = BufferOverflowNotice(emittedAt: t);
      final b = BufferOverflowNotice(emittedAt: t);
      expect(a == b, isFalse, reason: 'distinct instances must not be ==');
      expect(a == a, isTrue, reason: 'identity self-equality');
      final other = BufferOverflowNotice(
        emittedAt: DateTime.utc(2026, 7, 5, 12, 1),
      );
      expect(a == other, isFalse);
    });

    test('toString includes emittedAt for diagnostics', () {
      final t = DateTime.utc(2026, 7, 5, 12, 0);
      final notice = BufferOverflowNotice(emittedAt: t);
      expect(notice.toString(), contains('BufferOverflowNotice'));
      expect(notice.toString(), contains(t.toIso8601String()));
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
      expect(describe(BufferOverflowNotice()), 'buffer');
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
      final GatewayNotice asBase = BufferOverflowNotice();
      expect(asBase, isA<BufferOverflowNotice>());
    });
  });
}
