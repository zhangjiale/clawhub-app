import 'dart:io';
import 'dart:typed_data';

import 'package:claw_hub/core/acl/attachment_encoder.dart';
import 'package:claw_hub/domain/models/enums.dart' show MessageType;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const encoder = AttachmentEncoder();

  group('AttachmentEncoder.encode', () {
    test('returns null for text messages', () async {
      final result = await encoder.encode(
        type: MessageType.text,
        path: '/any/path.txt',
      );
      expect(result, isNull);
    });

    test('returns null for toolCall messages', () async {
      final result = await encoder.encode(
        type: MessageType.toolCall,
        path: '/any/path.txt',
      );
      expect(result, isNull);
    });

    test('throws AttachmentReadException when path is missing', () async {
      await expectLater(
        encoder.encode(type: MessageType.image, path: null),
        throwsA(isA<AttachmentReadException>()),
      );
      await expectLater(
        encoder.encode(type: MessageType.image, path: ''),
        throwsA(isA<AttachmentReadException>()),
      );
    });

    test('encodes a readable image file to base64', () async {
      final tempFile = await File(
        '${Directory.systemTemp.path}/att_encoder_img_${DateTime.now().millisecondsSinceEpoch}.bin',
      ).writeAsBytes(Uint8List.fromList([0, 1, 2, 3]));
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });

      final result = await encoder.encode(
        type: MessageType.image,
        path: tempFile.path,
      );
      expect(result, isNotNull);
      expect(result, isNotEmpty);
    });

    test(
      'throws AttachmentReadException when image file exceeds limit',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('att_oversize_');
        final tempFile = File('${tempDir.path}/oversize.bin');
        // Image limit is 10 MB; write 11 MB.
        await tempFile.writeAsBytes(Uint8List(11 * 1024 * 1024));
        addTearDown(() async {
          if (await tempFile.exists()) await tempFile.delete();
          await tempDir.delete();
        });

        await expectLater(
          encoder.encode(type: MessageType.image, path: tempFile.path),
          throwsA(isA<AttachmentReadException>()),
        );
      },
    );

    test('throws AttachmentReadException when file does not exist', () async {
      await expectLater(
        encoder.encode(
          type: MessageType.file,
          path: '/nonexistent/path/doc.pdf',
        ),
        throwsA(isA<AttachmentReadException>()),
      );
    });
  });
}
