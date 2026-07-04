import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/utils/copy_with_sentinel.dart';

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

    group('图片/文件消息 getter', () {
      test('isImage / isFile 按类型判断', () {
        final image = Message(
          clientId: 'c-img',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '/tmp/img.jpg',
          type: MessageType.image,
          logicalClock: 1,
        );
        final file = Message(
          clientId: 'c-file',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '/tmp/doc.pdf',
          type: MessageType.file,
          logicalClock: 2,
        );
        final text = Message(
          clientId: 'c-text',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: 'hi',
          type: MessageType.text,
          logicalClock: 3,
        );

        expect(image.isImage, isTrue);
        expect(image.isFile, isFalse);
        expect(file.isFile, isTrue);
        expect(file.isImage, isFalse);
        expect(text.isImage, isFalse);
        expect(text.isFile, isFalse);
      });

      test('imagePath / filePath 仅在对应类型时返回 content', () {
        final image = Message(
          clientId: 'c-img',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '/tmp/img.jpg',
          type: MessageType.image,
          logicalClock: 1,
        );
        final file = Message(
          clientId: 'c-file',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '/tmp/doc.pdf',
          type: MessageType.file,
          logicalClock: 2,
        );

        expect(image.imagePath, '/tmp/img.jpg');
        expect(image.filePath, isNull); // image 消息不暴露 filePath
        expect(file.filePath, '/tmp/doc.pdf');
        expect(file.imagePath, isNull); // file 消息不暴露 imagePath
      });

      test('fileName / mimeType / caption / fileSize 从 metadata 读取', () {
        final image = Message(
          clientId: 'c-img',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '/tmp/img.jpg',
          type: MessageType.image,
          logicalClock: 1,
          metadata: const {
            'fileName': 'img.jpg',
            'mimeType': 'image/jpeg',
            'size': 12345,
            'caption': '看这张',
          },
        );

        expect(image.fileName, 'img.jpg');
        expect(image.mimeType, 'image/jpeg');
        expect(image.caption, '看这张');
        expect(image.fileSize, 12345);
      });

      test('imageUrl 用于 Agent 回图(响应侧)', () {
        final agentImage = Message(
          clientId: 'c-agent-img',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.agent,
          content: null,
          type: MessageType.image,
          logicalClock: 1,
          metadata: const {
            'imageUrl': 'https://example.com/x.png',
            'mimeType': 'image/png',
          },
        );

        expect(agentImage.imageUrl, 'https://example.com/x.png');
        expect(agentImage.mimeType, 'image/png');
        expect(agentImage.imagePath, isNull); // 响应侧无本地路径
      });

      test('metadata 缺失时所有 getter 返回 null', () {
        final image = Message(
          clientId: 'c-img',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: '/tmp/img.jpg',
          type: MessageType.image,
          logicalClock: 1,
          // metadata 故意不传
        );

        expect(image.fileName, isNull);
        expect(image.mimeType, isNull);
        expect(image.caption, isNull);
        expect(image.fileSize, isNull);
        expect(image.imageUrl, isNull);
      });

      group('displayCaption', () {
        // displayCaption 把「用户图取 metadata.caption；Agent 回图取 content
        // (图片描述)」这一存储约定集中在 domain，widget 只读取单一 getter。
        test('用户图: 取 metadata.caption', () {
          final image = Message(
            clientId: 'c-img',
            conversationId: 'conv-001',
            agentId: 'agent-local-1',
            role: MessageRole.user,
            content: '/tmp/img.jpg',
            type: MessageType.image,
            logicalClock: 1,
            metadata: const {'caption': '看这张'},
          );

          expect(image.displayCaption, '看这张');
        });

        test('Agent 回图: 无 caption 时回退到 content(图片描述)', () {
          final agentImage = Message(
            clientId: 'c-agent-img',
            conversationId: 'conv-001',
            agentId: 'agent-local-1',
            role: MessageRole.agent,
            content: '这是一只虾的插图',
            type: MessageType.image,
            logicalClock: 1,
            metadata: const {'imageUrl': 'https://example.com/x.png'},
          );

          expect(agentImage.displayCaption, '这是一只虾的插图');
        });

        test('Agent 回图: caption 优先于 content', () {
          final agentImage = Message(
            clientId: 'c-agent-img',
            conversationId: 'conv-001',
            agentId: 'agent-local-1',
            role: MessageRole.agent,
            content: 'fallback desc',
            type: MessageType.image,
            logicalClock: 1,
            metadata: const {
              'imageUrl': 'https://example.com/x.png',
              'caption': '显式 caption',
            },
          );

          expect(agentImage.displayCaption, '显式 caption');
        });

        test('Agent 回图: content 为空时返回 null', () {
          final agentImage = Message(
            clientId: 'c-agent-img',
            conversationId: 'conv-001',
            agentId: 'agent-local-1',
            role: MessageRole.agent,
            content: '',
            type: MessageType.image,
            logicalClock: 1,
            metadata: const {'imageUrl': 'https://example.com/x.png'},
          );

          expect(agentImage.displayCaption, isNull);
        });

        test('无 imageUrl 且无 caption 时返回 null', () {
          final text = Message(
            clientId: 'c-text',
            conversationId: 'conv-001',
            agentId: 'agent-local-1',
            role: MessageRole.user,
            content: 'hi',
            type: MessageType.text,
            logicalClock: 1,
          );

          expect(text.displayCaption, isNull);
        });
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

    group('copyWith sentinel semantics', () {
      test('omitted nullable fields keep current value', () {
        final msg = Message(
          clientId: 'client-009',
          serverId: 'server-009',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: 'hello',
          type: MessageType.text,
          status: MessageStatus.sending,
          logicalClock: 1,
          timestamp: 123456789,
          metadata: const {'key': 'value'},
        );

        final copied = msg.copyWith(status: MessageStatus.sent);

        expect(copied.serverId, 'server-009');
        expect(copied.content, 'hello');
        expect(copied.metadata, {'key': 'value'});
        expect(copied.timestamp, 123456789);
      });

      test('explicit null clears nullable fields', () {
        final msg = Message(
          clientId: 'client-010',
          serverId: 'server-010',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: 'hello',
          type: MessageType.text,
          status: MessageStatus.sent,
          logicalClock: 1,
          timestamp: 123456789,
          metadata: const {'key': 'value'},
        );

        final copied = msg.copyWith(
          serverId: null,
          content: null,
          metadata: null,
        );

        expect(copied.serverId, isNull);
        expect(copied.content, isNull);
        expect(copied.metadata, isNull);
      });

      test('sentinel value leaves field unchanged', () {
        final msg = Message(
          clientId: 'client-011',
          serverId: 'server-011',
          conversationId: 'conv-001',
          agentId: 'agent-local-1',
          role: MessageRole.user,
          content: 'hello',
          type: MessageType.text,
          status: MessageStatus.sent,
          logicalClock: 1,
          timestamp: 123456789,
          metadata: const {'key': 'value'},
        );

        final copied = msg.copyWith(
          serverId: CopyWithSentinel.instance,
          content: CopyWithSentinel.instance,
          metadata: CopyWithSentinel.instance,
        );

        expect(copied.serverId, 'server-011');
        expect(copied.content, 'hello');
        expect(copied.metadata, {'key': 'value'});
      });
    });
  });
}
