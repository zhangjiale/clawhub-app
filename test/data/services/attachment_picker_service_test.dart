import 'package:claw_hub/data/services/attachment_picker_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttachmentPickerService', () {
    test('implements IAttachmentPickerService interface', () {
      expect(const AttachmentPickerService(), isA<AttachmentPickerService>());
    });
  });

  group('inferMimeType', () {
    test('returns common mime types by extension', () {
      expect(AttachmentPickerService.inferMimeType('pdf'), 'application/pdf');
      expect(AttachmentPickerService.inferMimeType('txt'), 'text/plain');
      expect(AttachmentPickerService.inferMimeType('json'), 'application/json');
      expect(AttachmentPickerService.inferMimeType('png'), 'image/png');
      expect(AttachmentPickerService.inferMimeType('jpg'), 'image/jpeg');
      expect(AttachmentPickerService.inferMimeType('jpeg'), 'image/jpeg');
      expect(AttachmentPickerService.inferMimeType('mp3'), 'audio/mpeg');
      expect(AttachmentPickerService.inferMimeType('mp4'), 'video/mp4');
    });

    test('is case-insensitive', () {
      expect(AttachmentPickerService.inferMimeType('PDF'), 'application/pdf');
      expect(AttachmentPickerService.inferMimeType('JPG'), 'image/jpeg');
    });

    test('falls back to octet-stream for unknown or null extension', () {
      expect(
        AttachmentPickerService.inferMimeType(null),
        'application/octet-stream',
      );
      expect(
        AttachmentPickerService.inferMimeType('unknown'),
        'application/octet-stream',
      );
      expect(
        AttachmentPickerService.inferMimeType(''),
        'application/octet-stream',
      );
    });
  });
}
