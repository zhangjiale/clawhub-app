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

  group('AttachmentReadException.tooLarge formatting (#14)', () {
    // Review #14: the inline `${size ~/ 1024 ~/ 1024}MB` floored both size and
    // limit to integer MB, so a 5.5 MB file over a 5.0 MB limit rendered as
    // "5MB > 5MB limit" (contradictory). formatBytes preserves one decimal
    // and handles KB, so the message now reads "5.5 MB > 5.0 MB limit".
    test('MB-range sizes format with one decimal (no integer-MB collapse)', () {
      final exc = AttachmentReadException.tooLarge(
        size: 5767168, // 5.5 MB
        limit: 5242880, // 5.0 MB
        type: MessageType.file,
      );
      final msg = exc.toString();
      expect(msg, contains('5.5 MB'));
      expect(msg, contains('5.0 MB'));
      expect(
        msg,
        isNot(contains('5MB > 5MB')),
        reason:
            'double ~/ must not collapse size and limit to the same '
            'integer MB — that reads as "5MB > 5MB" (contradictory)',
      );
    });

    test('sub-MB sizes format as KB (previously 999KB → "0MB")', () {
      final exc = AttachmentReadException.tooLarge(
        size: 999 * 1024, // 999.0 KB
        limit: 500 * 1024, // 500.0 KB
        type: MessageType.image,
      );
      final msg = exc.toString();
      expect(msg, contains('999.0 KB'));
      expect(msg, contains('500.0 KB'));
      expect(
        msg,
        isNot(contains('0MB')),
        reason: 'sub-MB sizes must show KB, not floor to "0MB"',
      );
    });
  });
}
