import 'package:claw_hub/domain/models/pending_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingNotification', () {
    test('stores fields with defaults', () {
      final n = PendingNotification(
        id: 1,
        agentId: 'agent-1',
        instanceId: 'inst-1',
        agentName: '小明虾',
        summary: '回复内容',
        createdAt: 1700000000,
        messageServerId: 'srv-1',
      );

      expect(n.id, 1);
      expect(n.agentId, 'agent-1');
      expect(n.instanceId, 'inst-1');
      expect(n.agentName, '小明虾');
      expect(n.summary, '回复内容');
      expect(n.createdAt, 1700000000);
      expect(n.messageServerId, 'srv-1');
      expect(n.delivered, isFalse);
    });

    test('copyWith marks delivered without touching other fields', () {
      final n = PendingNotification(
        id: 1,
        agentId: 'a',
        instanceId: 'i',
        agentName: 'n',
        summary: 's',
        createdAt: 1,
        messageServerId: null,
      );
      final delivered = n.copyWith(delivered: true);

      expect(delivered.delivered, isTrue);
      expect(delivered.agentId, 'a');
      expect(delivered.summary, 's');
      expect(delivered.messageServerId, isNull);
      // original unchanged
      expect(n.delivered, isFalse);
    });

    test('equality is value-based including id', () {
      final a = PendingNotification(
        id: 1,
        agentId: 'a',
        instanceId: 'i',
        agentName: 'n',
        summary: 's',
        createdAt: 1,
        messageServerId: 'x',
      );
      final b = PendingNotification(
        id: 1,
        agentId: 'a',
        instanceId: 'i',
        agentName: 'n',
        summary: 's',
        createdAt: 1,
        messageServerId: 'x',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('dedupKey uses instanceId + serverId when serverId present', () {
      final withServer = PendingNotification(
        id: 1,
        agentId: 'a',
        instanceId: 'i',
        agentName: 'n',
        summary: 's',
        createdAt: 1,
        messageServerId: 'srv-1',
      );
      final noServer = PendingNotification(
        id: 2,
        agentId: 'a',
        instanceId: 'i',
        agentName: 'n',
        summary: 's',
        createdAt: 1,
        messageServerId: null,
      );
      expect(withServer.dedupKey, 'i:srv-1');
      // no serverId → null key (caller must fall back to clientId-based dedup)
      expect(noServer.dedupKey, isNull);
    });
  });
}
