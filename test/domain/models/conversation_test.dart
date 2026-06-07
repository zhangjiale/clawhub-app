import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/conversation.dart';

void main() {
  group('Conversation', () {
    test('通过 instanceId + agentId 生成复合键 ID', () {
      final id = Conversation.generateId('inst-001', 'agent-local-1');
      final id2 = Conversation.generateId('inst-001', 'agent-local-1');
      final id3 = Conversation.generateId('inst-001', 'agent-local-2');

      expect(id, id2); // 相同输入生成相同 ID
      expect(id, isNot(id3)); // 不同 agent 生成不同 ID
    });

    test('创建有效 Conversation', () {
      final conv = Conversation(
        agentId: 'agent-local-1',
        instanceId: 'inst-001',
      );

      expect(conv.id, Conversation.generateId('inst-001', 'agent-local-1'));
      expect(conv.agentId, 'agent-local-1');
      expect(conv.instanceId, 'inst-001');
      expect(conv.lastMessagePreview, isNull);
      expect(conv.lastMessageTime, 0);
      expect(conv.unreadCount, 0);
      expect(conv.isMuted, isFalse);
    });

    test('增量未读数', () {
      final conv = Conversation(
        agentId: 'agent-local-1',
        instanceId: 'inst-001',
        unreadCount: 3,
      );

      final updated = conv.incrementUnread();
      expect(updated.unreadCount, 4);
    });

    test('清零未读数', () {
      final conv = Conversation(
        agentId: 'agent-local-1',
        instanceId: 'inst-001',
        unreadCount: 5,
      );

      final cleared = conv.clearUnread();
      expect(cleared.unreadCount, 0);
    });

    test('更新最后消息预览', () {
      final conv = Conversation(
        agentId: 'agent-local-1',
        instanceId: 'inst-001',
      );

      final updated = conv.updateLastMessage(
        messageId: 'msg-001',
        preview: '你好，这是一条测试消息...',
        timestamp: 1717766400000,
      );

      expect(updated.lastMessageId, 'msg-001');
      expect(updated.lastMessagePreview, '你好，这是一条测试消息...');
      expect(updated.lastMessageTime, 1717766400000);
    });
  });
}
