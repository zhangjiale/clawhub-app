import 'dart:io';

import 'package:claw_hub/data/services/attachment_picker_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttachmentPickerService', () {
    test('implements IAttachmentPickerService interface', () {
      expect(const AttachmentPickerService(), isA<AttachmentPickerService>());
    });
  });

  group('pickFile', () {
    // pickFile reads `FilePicker.platform` (a settable static) — each test
    // installs a fake before invoking pickFile. The fake extends FilePicker
    // so it passes PlatformInterface.verifyToken in the platform setter.
    test('returns null when picker returns null (cancellation)', () async {
      FilePicker.platform = _FakeFilePicker(null);
      addTearDown(_resetFilePicker);

      final result = await const AttachmentPickerService().pickFile();
      expect(result, isNull);
    });

    test(
      'returns null when files list is empty (Android SAF edge, #4)',
      () async {
        // Regression: the old `result?.files.single.path` threw StateError (an
        // Error, not Exception) on an empty files list, escaping the caller's
        // `on Exception catch` to the zone guard. The first-or-null guard must
        // return gracefully.
        FilePicker.platform = _FakeFilePicker(FilePickerResult([]));
        addTearDown(_resetFilePicker);

        final result = await const AttachmentPickerService().pickFile();
        expect(result, isNull);
      },
    );

    test('returns null when the picked file has no path', () async {
      FilePicker.platform = _FakeFilePicker(
        FilePickerResult([PlatformFile(path: null, name: 'doc.pdf', size: 0)]),
      );
      addTearDown(_resetFilePicker);

      final result = await const AttachmentPickerService().pickFile();
      expect(result, isNull);
    });

    test('returns AttachmentPickResult for a single file with path', () async {
      final tempDir = await Directory.systemTemp.createTemp('picker_test_');
      final tempFile = File('${tempDir.path}/doc.pdf');
      await tempFile.writeAsBytes([1, 2, 3, 4, 5]); // 5 bytes
      addTearDown(() async => tempDir.delete(recursive: true));

      FilePicker.platform = _FakeFilePicker(
        FilePickerResult([
          PlatformFile(path: tempFile.path, name: 'doc.pdf', size: 5),
        ]),
      );
      addTearDown(_resetFilePicker);

      final result = await const AttachmentPickerService().pickFile();

      expect(result, isNotNull);
      expect(result!.path, tempFile.path);
      expect(result.fileName, 'doc.pdf');
      expect(result.mimeType, 'application/pdf');
      expect(result.size, 5);
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

/// Stub [FilePicker] that returns a canned [FilePickerResult] from pickFiles,
/// for unit-testing [AttachmentPickerService.pickFile] without the platform.
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.result);
  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => result;
}

/// Restore a benign stub after each pickFile test so the static
/// `FilePicker.platform` is not left holding a test-specific canned result.
void _resetFilePicker() {
  FilePicker.platform = _FakeFilePicker(null);
}
