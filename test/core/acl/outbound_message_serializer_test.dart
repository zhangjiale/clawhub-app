import 'package:claw_hub/core/acl/outbound_message_serializer.dart';
import 'package:claw_hub/domain/models/enums.dart'
    show MessageRole, MessageType;
import 'package:claw_hub/domain/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const serializer = OutboundMessageSerializer();

  // ==========================================================================
  // serialize (PROTOCOL-VERIFY: appendix F, 2026-07-03)
  //
  // chat.send 的 message 必须是字符串,多模态走顶层 attachments 数组
  // (元素弱约束,推荐 {mimeType, content: base64, filename?})。
  // ⚠️ attachment 字段名 mimeType vs mime 有歧义(F.2),需 capture 确认 ——
  // 只改 seam + 本组。详见 docs/technical/acl-protocol-gaps.md Gap #8。
  // ==========================================================================
  group('serialize (PROTOCOL-VERIFY appendix F)', () {
    test('text message → message=content, attachments=null', () {
      final msg = Message(
        clientId: 'c1',
        conversationId: 'conv',
        agentId: 'a',
        role: MessageRole.user,
        content: '你好',
        type: MessageType.text,
        logicalClock: 1,
      );
      final r = serializer.serialize(msg);
      expect(r.message, '你好');
      expect(r.attachments, isNull);
    });

    test('text message with null content → message="", attachments=null', () {
      final msg = Message(
        clientId: 'c1',
        conversationId: 'conv',
        agentId: 'a',
        role: MessageRole.user,
        content: null,
        type: MessageType.text,
        logicalClock: 1,
      );
      final r = serializer.serialize(msg);
      expect(r.message, '');
      expect(r.attachments, isNull);
    });

    test(
      'image with base64 → message=caption, attachments=[{mimeType,content,filename}]',
      () {
        final msg = Message(
          clientId: 'c1',
          conversationId: 'conv',
          agentId: 'a',
          role: MessageRole.user,
          content: '/tmp/img.jpg',
          type: MessageType.image,
          logicalClock: 1,
          metadata: const {
            'fileName': 'img.jpg',
            'mimeType': 'image/jpeg',
            'caption': '看这张',
          },
        );
        final r = serializer.serialize(msg, base64Data: 'B64');
        expect(r.message, '看这张');
        expect(r.attachments, hasLength(1));
        expect(r.attachments!.first['mimeType'], 'image/jpeg');
        expect(r.attachments!.first['content'], 'B64');
        expect(r.attachments!.first['filename'], 'img.jpg');
      },
    );

    test(
      'image without caption + base64 → message="", attachments present',
      () {
        final msg = Message(
          clientId: 'c1',
          conversationId: 'conv',
          agentId: 'a',
          role: MessageRole.user,
          content: '/tmp/img.jpg',
          type: MessageType.image,
          logicalClock: 1,
          metadata: const {'fileName': 'img.jpg', 'mimeType': 'image/png'},
        );
        final r = serializer.serialize(msg, base64Data: 'B64');
        expect(r.message, '');
        expect(r.attachments, hasLength(1));
        expect(r.attachments!.first['mimeType'], 'image/png');
      },
    );

    test(
      'image without base64 (read failed) → degraded message=[图片], attachments=null',
      () {
        final msg = Message(
          clientId: 'c1',
          conversationId: 'conv',
          agentId: 'a',
          role: MessageRole.user,
          content: '/tmp/img.jpg',
          type: MessageType.image,
          logicalClock: 1,
        );
        final r = serializer.serialize(msg);
        expect(r.message, '[图片]');
        expect(r.attachments, isNull);
      },
    );

    test(
      'file with base64 → message="", attachments=[{mimeType,content,filename}]',
      () {
        final msg = Message(
          clientId: 'c1',
          conversationId: 'conv',
          agentId: 'a',
          role: MessageRole.user,
          content: '/tmp/doc.pdf',
          type: MessageType.file,
          logicalClock: 1,
          metadata: const {
            'fileName': 'doc.pdf',
            'mimeType': 'application/pdf',
          },
        );
        final r = serializer.serialize(msg, base64Data: 'FB64');
        expect(r.message, '');
        expect(r.attachments, hasLength(1));
        expect(r.attachments!.first['mimeType'], 'application/pdf');
        expect(r.attachments!.first['content'], 'FB64');
        expect(r.attachments!.first['filename'], 'doc.pdf');
      },
    );

    test(
      'file without base64 → degraded message=[文件] name, attachments=null',
      () {
        final msg = Message(
          clientId: 'c1',
          conversationId: 'conv',
          agentId: 'a',
          role: MessageRole.user,
          content: '/tmp/doc.pdf',
          type: MessageType.file,
          logicalClock: 1,
        );
        final r = serializer.serialize(msg);
        expect(r.message, '[文件] 文件');
        expect(r.attachments, isNull);
      },
    );
  });
}
