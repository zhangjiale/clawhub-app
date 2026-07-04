import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart'
    show StreamingDelta, StreamingDone, StreamingEvent;
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/features/chat_room/viewmodels/streaming_lifecycle.dart';

/// 记录 error 调用,用于验证 onError 路径的日志副作用。
class _RecordingLogger implements ILogger {
  final List<String> errors = [];

  @override
  void info(String message) {}

  @override
  void error(String message, [StackTrace? stackTrace]) => errors.add(message);
}

void main() {
  late StreamController<StreamingEvent> controller;
  late List<String> changes;
  late int onDeltaActivityCount;
  late int onStreamErrorCount;
  late _RecordingLogger logger;
  // tearDown 用:每个 test 的 makeSL() 把实例挂这儿,统一 dispose 防止
  // 30s stall timer 跨 test 残留触发 pending-timer 警告。
  StreamingLifecycle? slForTeardown;

  setUp(() {
    logger = _RecordingLogger();
    controller = StreamController<StreamingEvent>.broadcast();
  });

  tearDown(() {
    slForTeardown?.dispose();
    slForTeardown = null;
    controller.close();
  });

  StreamingLifecycle makeSL({
    Duration flushDelay = Duration.zero,
    Duration stallDelay = const Duration(seconds: 30),
  }) {
    changes = [];
    onDeltaActivityCount = 0;
    onStreamErrorCount = 0;
    final sl = StreamingLifecycle(
      flushDelay: flushDelay,
      stallDelay: stallDelay,
      onStreamingTextChanged: (t) => changes.add(t),
      onDeltaActivity: () => onDeltaActivityCount++,
      onStreamError: () => onStreamErrorCount++,
      logger: logger,
    );
    slForTeardown = sl;
    return sl;
  }

  // Timer(Duration.zero) 在事件队列上调度,pump 让队列排空一次。
  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 10));

  group('StreamingLifecycle', () {
    test('isStreaming is false initially', () {
      final sl = makeSL();
      expect(sl.isStreaming, isFalse);
    });

    test(
      'StreamingDelta flips isStreaming true and pushes accumulated text',
      () async {
        final sl = makeSL();
        sl.start(controller.stream, 'r-1');

        controller.add(StreamingDelta(agentId: 'r-1', text: '你好'));
        await pump();

        expect(sl.isStreaming, isTrue);
        expect(changes, ['你好']);
      },
    );

    test(
      'multiple deltas in the same event loop coalesce to one flush',
      () async {
        final sl = makeSL();
        sl.start(controller.stream, 'r-1');

        controller.add(StreamingDelta(agentId: 'r-1', text: 'a'));
        controller.add(StreamingDelta(agentId: 'r-1', text: 'b'));
        controller.add(StreamingDelta(agentId: 'r-1', text: 'c'));
        await pump();

        expect(changes, ['abc'], reason: '三次 delta 应合并为一次 flush,推累积全文');
        expect(
          onDeltaActivityCount,
          3,
          reason: 'onDeltaActivity 每次 delta 都触发(在 50KB cap 之外)',
        );
      },
    );

    test(
      'buffer ≥ 50KB stops appending but isStreaming/onDeltaActivity still fire',
      () async {
        final sl = makeSL();
        sl.start(controller.stream, 'r-1');

        final big = 'x' * (60 * 1024);
        controller.add(StreamingDelta(agentId: 'r-1', text: big));
        controller.add(StreamingDelta(agentId: 'r-1', text: 'NOT-APPENDED'));
        await pump();

        expect(
          sl.isStreaming,
          isTrue,
          reason: 'cap 只挡 buffer.write,不挡 isStreaming',
        );
        expect(onDeltaActivityCount, 2, reason: 'onDeltaActivity 在 if 之外,始终触发');
        expect(changes.last, big);
        expect(
          changes.last.contains('NOT-APPENDED'),
          isFalse,
          reason: '50KB 后第二条 delta 不应被 append',
        );
      },
    );

    test(
      'StreamingDone clears isStreaming, flushes immediately, pushes empty',
      () async {
        final sl = makeSL();
        sl.start(controller.stream, 'r-1');

        controller.add(StreamingDelta(agentId: 'r-1', text: 'hi'));
        controller.add(StreamingDone(agentId: 'r-1'));
        await pump();

        expect(sl.isStreaming, isFalse);
        expect(changes, ['hi', ''], reason: 'done 先立即 flush 累积文本,再推空');
      },
    );

    test('onError clears isStreaming, flushes, cancels stall, logs', () async {
      final sl = makeSL();
      sl.start(controller.stream, 'r-1');

      controller.add(StreamingDelta(agentId: 'r-1', text: 'hi'));
      controller.addError(StateError('boom'));
      await pump();

      expect(sl.isStreaming, isFalse);
      expect(changes, ['hi', ''], reason: 'error 路径先 flush 累积文本,再推空');
      expect(onStreamErrorCount, 1, reason: 'onError 应通知 VM 取消 _timeoutTimer');
      expect(logger.errors, hasLength(1));
      expect(logger.errors.single, contains('boom'));
    });

    test(
      'resetForSend cancels sub, clears buffer/lastPublished, pushes empty',
      () async {
        final sl = makeSL();
        sl.start(controller.stream, 'r-1');
        controller.add(StreamingDelta(agentId: 'r-1', text: 'hi'));
        await pump(); // flush 'hi' → lastPublished=2, buffer='hi'

        sl.resetForSend();
        expect(sl.isStreaming, isFalse);
        expect(changes.last, '', reason: 'resetForSend 推空');

        // sub 已取消 + buffer 已清:重新订阅后下一条 delta 只 flush 新文本(不残留 hi)。
        sl.start(controller.stream, 'r-1');
        controller.add(StreamingDelta(agentId: 'r-1', text: 'new'));
        await pump();
        expect(changes.last, 'new', reason: 'buffer 已清,不会残留 hi');
      },
    );

    test(
      'onConnectionLost clears buffer/stall, pushes empty, keeps subscription',
      () async {
        final sl = makeSL();
        sl.start(controller.stream, 'r-1');
        controller.add(StreamingDelta(agentId: 'r-1', text: 'hi'));
        await pump(); // flush 'hi'

        sl.onConnectionLost();
        expect(sl.isStreaming, isFalse);
        expect(changes.last, '');

        // sub 未取消:下一条 delta 仍到达;buffer 已清 → 不残留 hi。
        controller.add(StreamingDelta(agentId: 'r-1', text: 'new'));
        await pump();
        expect(changes.last, 'new');
      },
    );

    test(
      'onReplyArrived clears isStreaming + pushes empty, keeps buffer',
      () async {
        final sl = makeSL();
        sl.start(controller.stream, 'r-1');
        controller.add(StreamingDelta(agentId: 'r-1', text: 'hi'));
        await pump(); // flush 'hi', buffer='hi', lastPublished=2

        sl.onReplyArrived();
        expect(sl.isStreaming, isFalse);
        expect(changes.last, '');

        // buffer 未清:新 delta 追加到旧 buffer 之上 → flush 'hiX'(不是 'X')。
        controller.add(StreamingDelta(agentId: 'r-1', text: 'X'));
        await pump();
        expect(changes.last, 'hiX', reason: 'buffer 未清,新 delta 累加到旧 buffer');
      },
    );

    test('cancel cancels sub+timers, clears buffer, pushes no state', () async {
      final sl = makeSL();
      sl.start(controller.stream, 'r-1');
      controller.add(StreamingDelta(agentId: 'r-1', text: 'hi'));
      await pump(); // flush 'hi'
      final changesBefore = changes.length;

      sl.cancel();
      expect(sl.isStreaming, isFalse);
      expect(changes.length, changesBefore, reason: 'cancel 不推 state');

      // sub 已取消:后续 delta 不再到达。
      controller.add(StreamingDelta(agentId: 'r-1', text: 'ignored'));
      await pump();
      expect(changes.length, changesBefore, reason: 'sub 取消后 delta 不再触发 flush');
    });

    test('stall timer fires → pushes empty, buffer untouched', () async {
      // 注入小 stallDelay,免 FakeAsync,用真实事件循环 + 足够等待窗口。
      final sl = makeSL(stallDelay: const Duration(milliseconds: 30));
      sl.start(controller.stream, 'r-1');
      controller.add(StreamingDelta(agentId: 'r-1', text: 'acc'));
      await pump(); // flush 'acc';stall(30ms) 仍 pending
      expect(changes.last, 'acc');

      // 等过 stall 窗口 → stall 触发推空。
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(changes.last, '', reason: 'stall 应推空');

      // buffer 未动:新 delta 累加到 'acc' 之上 → flush 'acc!'(不是 '!')。
      controller.add(StreamingDelta(agentId: 'r-1', text: '!'));
      await pump();
      expect(
        changes.last,
        'acc!',
        reason: 'stall 不清 buffer,新 delta 累加到旧 buffer',
      );
    });

    test('dispose is idempotent (cancel twice, no throw)', () {
      final sl = makeSL();
      sl.start(controller.stream, 'r-1');
      controller.add(StreamingDelta(agentId: 'r-1', text: 'hi'));

      sl.dispose();
      sl.dispose(); // idempotent
      sl.cancel(); // also idempotent
      expect(sl.isStreaming, isFalse);
    });
  });
}
