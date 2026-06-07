import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/message_status.dart';

void main() {
  group('MessageStatus', () {
    group('枚举值映射', () {
      test('fromInt 应正确映射所有7种状态', () {
        expect(MessageStatus.fromInt(0), MessageStatus.draft);
        expect(MessageStatus.fromInt(1), MessageStatus.pending);
        expect(MessageStatus.fromInt(2), MessageStatus.sending);
        expect(MessageStatus.fromInt(3), MessageStatus.sent);
        expect(MessageStatus.fromInt(4), MessageStatus.delivered);
        expect(MessageStatus.fromInt(5), MessageStatus.failed);
        expect(MessageStatus.fromInt(6), MessageStatus.expired);
      });

      test('toInt 应正确序列化所有状态', () {
        expect(MessageStatus.draft.toInt(), 0);
        expect(MessageStatus.pending.toInt(), 1);
        expect(MessageStatus.sending.toInt(), 2);
        expect(MessageStatus.sent.toInt(), 3);
        expect(MessageStatus.delivered.toInt(), 4);
        expect(MessageStatus.failed.toInt(), 5);
        expect(MessageStatus.expired.toInt(), 6);
      });

      test('无效值应抛出异常', () {
        expect(() => MessageStatus.fromInt(-1), throwsA(isA<ArgumentError>()));
        expect(() => MessageStatus.fromInt(7), throwsA(isA<ArgumentError>()));
      });
    });

    group('状态流转规则', () {
      test('DRAFT 只能流转到 PENDING 或自身(编辑中)', () {
        expect(MessageStatus.draft.canTransitionTo(MessageStatus.pending), isTrue);
        expect(MessageStatus.draft.canTransitionTo(MessageStatus.sending), isFalse);
        expect(MessageStatus.draft.canTransitionTo(MessageStatus.sent), isFalse);
      });

      test('PENDING 可以流转到 SENDING 或 FAILED', () {
        expect(MessageStatus.pending.canTransitionTo(MessageStatus.sending), isTrue);
        expect(MessageStatus.pending.canTransitionTo(MessageStatus.failed), isTrue);
        expect(MessageStatus.pending.canTransitionTo(MessageStatus.sent), isFalse);
      });

      test('SENDING 可以流转到 SENT、FAILED 或 EXPIRED', () {
        expect(MessageStatus.sending.canTransitionTo(MessageStatus.sent), isTrue);
        expect(MessageStatus.sending.canTransitionTo(MessageStatus.failed), isTrue);
        expect(MessageStatus.sending.canTransitionTo(MessageStatus.expired), isTrue);
        expect(MessageStatus.sending.canTransitionTo(MessageStatus.draft), isFalse);
      });

      test('SENT 只能流转到 DELIVERED', () {
        expect(MessageStatus.sent.canTransitionTo(MessageStatus.delivered), isTrue);
        expect(MessageStatus.sent.canTransitionTo(MessageStatus.failed), isFalse);
      });

      test('DELIVERED 是终态之一，不可再流转', () {
        expect(MessageStatus.delivered.canTransitionTo(MessageStatus.sent), isFalse);
        expect(MessageStatus.delivered.canTransitionTo(MessageStatus.failed), isFalse);
        expect(MessageStatus.delivered.canTransitionTo(MessageStatus.expired), isFalse);
      });

      test('EXPIRED 是终态，不可再流转', () {
        expect(MessageStatus.expired.canTransitionTo(MessageStatus.pending), isFalse);
        expect(MessageStatus.expired.canTransitionTo(MessageStatus.sending), isFalse);
      });

      test('FAILED 可以重试流转到 SENDING', () {
        expect(MessageStatus.failed.canTransitionTo(MessageStatus.sending), isTrue);
        expect(MessageStatus.failed.canTransitionTo(MessageStatus.expired), isTrue);
      });
    });

    group('终态判断', () {
      test('DELIVERED 和 EXPIRED 是终态', () {
        expect(MessageStatus.delivered.isTerminal, isTrue);
        expect(MessageStatus.expired.isTerminal, isTrue);
      });

      test('非终态状态', () {
        expect(MessageStatus.draft.isTerminal, isFalse);
        expect(MessageStatus.pending.isTerminal, isFalse);
        expect(MessageStatus.sending.isTerminal, isFalse);
        expect(MessageStatus.sent.isTerminal, isFalse);
        expect(MessageStatus.failed.isTerminal, isFalse);
      });
    });

    group('可重试判断', () {
      test('FAILED 状态可重试', () {
        expect(MessageStatus.failed.isRetryable, isTrue);
      });

      test('其他状态不可重试', () {
        expect(MessageStatus.draft.isRetryable, isFalse);
        expect(MessageStatus.pending.isRetryable, isFalse);
        expect(MessageStatus.sending.isRetryable, isFalse);
        expect(MessageStatus.sent.isRetryable, isFalse);
        expect(MessageStatus.delivered.isRetryable, isFalse);
        expect(MessageStatus.expired.isRetryable, isFalse);
      });
    });
  });
}
