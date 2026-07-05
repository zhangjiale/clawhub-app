import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:claw_hub/core/acl/attachment_encoder.dart';
import 'package:claw_hub/core/acl/outbound_request_builder.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = OutboundRequestBuilder();

  Message textMsg(String content) {
    return Message(
      clientId: 'client-1',
      conversationId: 'conv-1',
      agentId: 'agent-1',
      role: MessageRole.user,
      content: content,
      type: MessageType.text,
      logicalClock: 1,
    );
  }

  Message imageMsg(String path, {String? fileName, String? mimeType}) {
    return Message(
      clientId: 'client-2',
      conversationId: 'conv-1',
      agentId: 'agent-1',
      role: MessageRole.user,
      content: path,
      type: MessageType.image,
      logicalClock: 2,
      metadata: {'fileName': fileName, 'mimeType': mimeType},
    );
  }

  group('OutboundRequestBuilder', () {
    test('text message builds valid chat.send JSON in worker', () async {
      final result = await builder.buildChatSendRequest(
        message: textMsg('hello'),
        sessionKey: 'agent:a1:main',
        idempotencyKey: 'client-1',
        requestId: 'req-1',
      );

      final json = jsonDecode(result.requestJson) as Map<String, dynamic>;
      expect(json['type'], 'req');
      expect(json['id'], 'req-1');
      expect(json['method'], 'chat.send');
      expect(json['params']['sessionKey'], 'agent:a1:main');
      expect(json['params']['message'], 'hello');
      expect(json['params']['idempotencyKey'], 'client-1');
      expect(result.payloadSize, greaterThan(0));
    });

    test(
      'image message reads file and embeds base64 attachment in worker',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('orb_test_');
        final file = File('${tempDir.path}/test.png');
        await file.writeAsBytes(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]));
        addTearDown(() async => tempDir.delete(recursive: true));

        final result = await builder.buildChatSendRequest(
          message: imageMsg(
            file.path,
            fileName: 'test.png',
            mimeType: 'image/png',
          ),
          sessionKey: 'agent:a1:main',
          idempotencyKey: 'client-2',
          requestId: 'req-2',
        );

        final json = jsonDecode(result.requestJson) as Map<String, dynamic>;
        expect(json['method'], 'chat.send');
        final attachments = json['params']['attachments'] as List<dynamic>;
        expect(attachments, hasLength(1));
        expect(attachments.first['mimeType'], 'image/png');
        expect(attachments.first['content'], isA<String>());
        expect(attachments.first['content'], isNotEmpty);
        expect(attachments.first['filename'], 'test.png');
      },
    );

    test(
      'image attachment exceeding 10MB throws AttachmentReadException.tooLarge',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('orb_test_');
        final file = File('${tempDir.path}/big.png');
        // 11MB of zeros
        await file.writeAsBytes(Uint8List(11 * 1024 * 1024));
        addTearDown(() async => tempDir.delete(recursive: true));

        expect(
          () => builder.buildChatSendRequest(
            message: imageMsg(file.path),
            sessionKey: 'agent:a1:main',
            idempotencyKey: 'client-2',
            requestId: 'req-3',
          ),
          throwsA(isA<AttachmentReadException>()),
        );
      },
    );

    test('payloadSize matches UTF-8 byte count of returned JSON', () async {
      final result = await builder.buildChatSendRequest(
        message: textMsg('中文测试'),
        sessionKey: 'agent:a1:main',
        idempotencyKey: 'client-1',
        requestId: 'req-4',
      );

      expect(result.payloadSize, utf8.encode(result.requestJson).length);
    });
  });
}
