import 'dart:async';

import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/features/chat_room/viewmodels/preview_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Message _msg({
    required String clientId,
    required MessageRole role,
    MessageType type = MessageType.text,
    String content = 'hi',
    int timestamp = 1718000000000,
  }) => Message(
    clientId: clientId,
    conversationId: 'conv-1',
    agentId: 'agent-1',
    role: role,
    content: content,
    type: type,
    status: MessageStatus.delivered,
    logicalClock: 1,
    timestamp: timestamp,
  );

  group('PreviewUpdater.schedule', () {
    test('flushes the latest message to onFlush', () async {
      Message? flushed;
      final updater = PreviewUpdater(
        onFlush: (m) async => flushed = m,
        isMounted: () => true,
      );

      updater.schedule(_msg(clientId: 'm1', role: MessageRole.agent));
      await pumpEventQueue();

      expect(flushed, isNotNull);
      expect(flushed!.clientId, 'm1');
    });

    test('skips toolCall messages', () async {
      Message? flushed;
      final updater = PreviewUpdater(
        onFlush: (m) async => flushed = m,
        isMounted: () => true,
      );

      updater.schedule(
        _msg(
          clientId: 'm1',
          role: MessageRole.agent,
          type: MessageType.toolCall,
        ),
      );
      await pumpEventQueue();

      expect(flushed, isNull);
    });

    // 回归:toolResult / userPlaceholder / system 消息不应覆盖会话预览。
    test('skips toolResult messages', () async {
      Message? flushed;
      final updater = PreviewUpdater(
        onFlush: (m) async => flushed = m,
        isMounted: () => true,
      );

      updater.schedule(_msg(clientId: 'm1', role: MessageRole.toolResult));
      await pumpEventQueue();

      expect(flushed, isNull);
    });

    test('skips userPlaceholder messages', () async {
      Message? flushed;
      final updater = PreviewUpdater(
        onFlush: (m) async => flushed = m,
        isMounted: () => true,
      );

      updater.schedule(_msg(clientId: 'm1', role: MessageRole.userPlaceholder));
      await pumpEventQueue();

      expect(flushed, isNull);
    });

    test('skips system messages', () async {
      Message? flushed;
      final updater = PreviewUpdater(
        onFlush: (m) async => flushed = m,
        isMounted: () => true,
      );

      updater.schedule(_msg(clientId: 'm1', role: MessageRole.system));
      await pumpEventQueue();

      expect(flushed, isNull);
    });

    test(
      'keeps the highest-timestamp candidate across coalesced schedules',
      () async {
        Message? flushed;
        final updater = PreviewUpdater(
          onFlush: (m) async => flushed = m,
          isMounted: () => true,
        );

        updater.schedule(
          _msg(clientId: 'old', role: MessageRole.agent, timestamp: 1000),
        );
        updater.schedule(
          _msg(clientId: 'new', role: MessageRole.agent, timestamp: 2000),
        );
        await pumpEventQueue();

        expect(flushed!.clientId, 'new');
      },
    );
  });
}
