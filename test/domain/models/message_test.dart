import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('Message', () {
    test('创建有效文本消息', () {
      final msg = Message(
        clientId: 'client-001',
        conversationId: 'conv-001',
        agentId: 'agent-local-1',
        role: MessageRole.user,
        content: '你好，虾！',
        type: MessageType.text,
        logicalClock: 1,
      );

      expect(msg.clientId, 'client-001');
      expect(msg.serverId, isNull);
      expect(msg.conversationId, 'conv-001');
      expect(msg.agentId, 'agent-local-1');
      expect(msg.role, MessageRole.user);
      expect(msg.content, '你好，虾！');
      expect(msg.type, MessageType.text);
      expect(msg.status, MessageStatus.pending); // 默认 PENDING
      expect(msg.logicalClock, 1);
      expect(msg.timestamp, isNotNull);
      expect(msg.metadata, isNull);
    });

    test('创建 Agent 回复消息', () {
      final msg = Message(
        clientId: 'client-002',
        serverId: 'server-xyz', // Gateway 分配的 serverId
        conversationId: 'conv-001',
        agentId: 'agent-local-1',
        role: MessageRole.agent,
        content: '你好！有什么可以帮你的？',
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: 2,
      );

      expect(msg.role, MessageRole.agent);
      expect(msg.serverId, 'server-xyz');
      expect(msg.status, MessageStatus.delivered);
    });

    test('创建工具调用类型消息', () {
      final msg = Message(
        clientId: 'client-003',
        conversationId: 'conv-001',
        agentId: 'agent-local-1',
        role: MessageRole.agent,
        content: '正在执行数据分析...',
        type: MessageType.toolCall,
        logicalClock: 3,
        metadata: {'toolCallId': 'tc-001'},
      );

      expect(msg.type, MessageType.toolCall);
      expect(msg.metadata, {'toolCallId': 'tc-001'});
    });

    group('状态绑定 serverId', () {
      test('收到 ACK 后绑定 serverId 并标记 SENT', () {
        var msg = Message(
          clientId: 'client-004',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '测试消息',
          type: MessageType.text,
          status: MessageStatus.sending,
          logicalClock: 1,
        );

        final bound = msg.bindServerId('server-ack-001');

        expect(bound.serverId, 'server-ack-001');
        expect(bound.status, MessageStatus.sent);
        expect(bound.clientId, msg.clientId); // clientId 不变
      });

      test('非 SENDING 状态绑定 serverId 应抛异常', () {
        final msg = Message(
          clientId: 'client-005',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '测试消息',
          type: MessageType.text,
          status: MessageStatus.pending,
          logicalClock: 1,
        );

        expect(
          () => msg.bindServerId('server-ack-002'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('状态转换', () {
      test('DRAFT -> PENDING (发送)', () {
        final msg = Message(
          clientId: 'client-006',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '草稿消息',
          type: MessageType.text,
          status: MessageStatus.draft,
          logicalClock: 1,
        );

        final sent = msg.transitionTo(MessageStatus.pending);
        expect(sent.status, MessageStatus.pending);
      });

      test('FAILED -> SENDING (重试)', () {
        final msg = Message(
          clientId: 'client-007',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '重试消息',
          type: MessageType.text,
          status: MessageStatus.failed,
          logicalClock: 1,
        );

        final retried = msg.transitionTo(MessageStatus.sending);
        expect(retried.status, MessageStatus.sending);
      });

      test('非法状态转换应抛异常', () {
        final msg = Message(
          clientId: 'client-008',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '已送达',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
        );

        expect(
          () => msg.transitionTo(MessageStatus.failed),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('消息去重', () {
      test('同 clientId 视为相同消息', () {
        final msg1 = Message(
          clientId: 'client-dup',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: 'A',
          type: MessageType.text,
          logicalClock: 1,
        );
        final msg2 = Message(
          clientId: 'client-dup',
          serverId: 'server-later',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: 'A (updated)',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
        );

        expect(msg1.clientId, msg2.clientId);
        expect(msg1 == msg2, isFalse); // 不同对象（serverId 不同）
        expect(msg1.hasSameIdentity(msg2), isTrue); // 但身份相同
      });

      test('同 serverId 视为相同消息', () {
        final msg1 = Message(
          clientId: 'client-a',
          serverId: 'server-same',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: 'A',
          type: MessageType.text,
          logicalClock: 1,
        );
        final msg2 = Message(
          clientId: 'client-b',
          serverId: 'server-same',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: 'B',
          type: MessageType.text,
          logicalClock: 2,
        );

        expect(msg1.hasSameIdentity(msg2), isTrue);
      });
    });
  });
}
