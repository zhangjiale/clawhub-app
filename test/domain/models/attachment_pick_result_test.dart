import 'package:claw_hub/domain/models/attachment_pick_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttachmentPickResult', () {
    const result = AttachmentPickResult(
      path: '/tmp/photo.jpg',
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      size: 1234,
    );

    test('holds pick metadata', () {
      expect(result.path, '/tmp/photo.jpg');
      expect(result.fileName, 'photo.jpg');
      expect(result.mimeType, 'image/jpeg');
      expect(result.size, 1234);
    });

    test('equality uses all fields', () {
      expect(
        const AttachmentPickResult(
          path: '/tmp/photo.jpg',
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
          size: 1234,
        ),
        result,
      );
    });

    test('different fields are not equal', () {
      expect(
        const AttachmentPickResult(
          path: '/tmp/photo.jpg',
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
          size: 9999,
        ),
        isNot(result),
      );
    });
  });
}
