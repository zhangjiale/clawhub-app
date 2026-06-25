import 'package:claw_hub/domain/models/notification_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReplyEvent', () {
    test('stores identity + preview fields', () {
      final e = ReplyEvent(
        agentId: 'agent-1',
        instanceId: 'inst-1',
        agentName: '小明虾',
        contentPreview: '你好，我是小明虾',
        messageServerId: 'srv-1',
        messageClientId: 'cli-1',
      );

      expect(e.agentId, 'agent-1');
      expect(e.instanceId, 'inst-1');
      expect(e.agentName, '小明虾');
      expect(e.contentPreview, '你好，我是小明虾');
      expect(e.messageServerId, 'srv-1');
      expect(e.messageClientId, 'cli-1');
    });

    test('equality is value-based', () {
      final a = ReplyEvent(
        agentId: 'a',
        instanceId: 'i',
        agentName: 'n',
        contentPreview: 'p',
        messageServerId: 's',
        messageClientId: 'c',
      );
      final b = ReplyEvent(
        agentId: 'a',
        instanceId: 'i',
        agentName: 'n',
        contentPreview: 'p',
        messageServerId: 's',
        messageClientId: 'c',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ErrorEvent', () {
    test('stores error reason', () {
      final e = ErrorEvent(
        agentId: 'agent-1',
        instanceId: 'inst-1',
        agentName: '小明虾',
        errorSummary: '工具调用失败',
      );
      expect(e.errorSummary, '工具调用失败');
    });
  });

  group('ConnectionChangeEvent', () {
    test('stores from/to connection state', () {
      final e = ConnectionChangeEvent(
        instanceId: 'inst-1',
        instanceName: '家里',
        fromState: NotificationConnectionState.online,
        toState: NotificationConnectionState.reconnecting,
      );
      expect(e.fromState, NotificationConnectionState.online);
      expect(e.toState, NotificationConnectionState.reconnecting);
    });

    test('isOnlineDrop is true only when online -> offline', () {
      expect(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: 'n',
          fromState: NotificationConnectionState.online,
          toState: NotificationConnectionState.offline,
        ).isOnlineDrop,
        isTrue,
      );
      expect(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: 'n',
          fromState: NotificationConnectionState.reconnecting,
          toState: NotificationConnectionState.online,
        ).isOnlineDrop,
        isFalse,
      );
      // reconnecting 是自动重连的中间状态，不应视为掉线。
      expect(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: 'n',
          fromState: NotificationConnectionState.online,
          toState: NotificationConnectionState.reconnecting,
        ).isOnlineDrop,
        isFalse,
      );
    });
  });

  group('NotificationConnectionState', () {
    test('maps from acl states via fromOnline flag helper', () {
      expect(NotificationConnectionState.online.isOnline, isTrue);
      expect(NotificationConnectionState.reconnecting.isOnline, isFalse);
      expect(NotificationConnectionState.offline.isOnline, isFalse);
    });
  });
}
