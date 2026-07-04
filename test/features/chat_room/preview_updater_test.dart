import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/features/chat_room/viewmodels/preview_updater.dart';

/// 构造可控 timestamp 的 Message(模拟 messageStream 到达的 agent 回复)。
Message _msg({
  required String id,
  required int timestamp,
  MessageType type = MessageType.text,
}) {
  return Message(
    clientId: id,
    conversationId: 'c-1',
    agentId: 'r-1',
    role: MessageRole.agent,
    content: 'content-$id',
    type: type,
    status: MessageStatus.delivered,
    logicalClock: timestamp,
    timestamp: timestamp,
  );
}

void main() {
  late List<Message> flushed;
  late PreviewUpdater updater;

  // 每次重建 updater 同时重置 flushed,便于断言「onFlush 被调了几次、带谁」。
  PreviewUpdater makeUpdater({required bool mounted}) {
    flushed = [];
    return PreviewUpdater(
      onFlush: (m) async {
        flushed.add(m);
      },
      isMounted: () => mounted,
    );
  }

  setUp(() {
    updater = makeUpdater(mounted: true);
  });

  // Timer(Duration.zero) 在事件队列上调度,pump 让队列排空一次。
  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 10));

  group('PreviewUpdater', () {
    test('schedule(toolCall) is a no-op — guard 1', () async {
      updater.schedule(
        _msg(id: 'tc', timestamp: 1, type: MessageType.toolCall),
      );
      await pump();

      expect(flushed, isEmpty, reason: 'toolCall 消息不应触发 preview flush');
    });

    test(
      'three messages in the same event loop coalesce to one flush of the newest',
      () async {
        updater.schedule(_msg(id: 'm1', timestamp: 1));
        updater.schedule(_msg(id: 'm2', timestamp: 2));
        updater.schedule(_msg(id: 'm3', timestamp: 3));
        await pump();

        expect(flushed.length, 1, reason: '同一事件循环内的多条消息应合并为一次 flush');
        expect(flushed.single.clientId, 'm3', reason: 'timestamp 最大的那条胜出');
      },
    );

    test(
      'older message scheduled after a newer one does not overwrite it',
      () async {
        updater.schedule(_msg(id: 'new', timestamp: 5));
        updater.schedule(_msg(id: 'old', timestamp: 2));
        await pump();

        expect(flushed.length, 1);
        expect(
          flushed.single.clientId,
          'new',
          reason: '旧消息不得覆盖已 pending 的更新消息',
        );
      },
    );

    test(
      'dispose cancels the pending timer and clears state — no flush',
      () async {
        updater.schedule(_msg(id: 'm1', timestamp: 1));
        updater.dispose();
        await pump();

        expect(flushed, isEmpty, reason: 'dispose 必须取消未触发的 flush');
      },
    );

    test('isMounted()==false suppresses the flush', () async {
      final unmounted = makeUpdater(mounted: false);
      unmounted.schedule(_msg(id: 'm1', timestamp: 1));
      await pump();

      expect(flushed, isEmpty, reason: 'VM 不再 mounted 时不得调用 onFlush');
      unmounted.dispose();
    });
  });
}
