import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' as image_picker;

import '../../core/i_attachment_picker_service.dart';
import '../../domain/models/attachment_pick_result.dart';

/// [IAttachmentPickerService] 的默认实现。
///
/// 直接调用 `image_picker` 与 `file_picker`，并把平台返回的结果归一化为
/// [AttachmentPickResult]。所有 MIME 推断、异步 IO 都放在这里，
/// 不让 UI 层沾染平台细节。
class AttachmentPickerService implements IAttachmentPickerService {
  const AttachmentPickerService();

  @override
  Future<AttachmentPickResult?> pickImage({
    required ImageSource source,
    int imageQuality = 85,
  }) async {
    final picked = await image_picker.ImagePicker().pickImage(
      source: _mapSource(source),
      imageQuality: imageQuality,
    );
    if (picked == null) return null;

    final file = File(picked.path);
    final size = await file.length();
    return AttachmentPickResult(
      path: picked.path,
      fileName: picked.name,
      mimeType: picked.mimeType ?? 'image/jpeg',
      size: size,
    );
  }

  @override
  Future<AttachmentPickResult?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    // Defensive: `files` may be empty on some Android SAF paths, and
    // `single` throws StateError (an Error, not Exception) which would
    // escape the caller's `on Exception catch`. Use first-or-null and a
    // null path guard so cancellation/empty results return gracefully.
    final platformFile = result != null && result.files.isNotEmpty
        ? result.files.first
        : null;
    final path = platformFile?.path;
    if (path == null) return null;

    final file = File(path);
    final size = await file.length();
    // `path` non-null implies `platformFile` is non-null because it was
    // derived from `platformFile?.path`.
    return AttachmentPickResult(
      path: path,
      fileName: platformFile!.name,
      mimeType: inferMimeType(platformFile.extension),
      size: size,
    );
  }

  image_picker.ImageSource _mapSource(ImageSource source) {
    switch (source) {
      case ImageSource.camera:
        return image_picker.ImageSource.camera;
      case ImageSource.gallery:
        return image_picker.ImageSource.gallery;
    }
  }

  /// 由扩展名粗推 MIME；`file_picker` 不返回 mimeType 时给一个合理兜底。
  static String inferMimeType(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'zip':
        return 'application/zip';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'mp3':
        return 'audio/mpeg';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }
}
