/// 附件选择结果。
///
/// 由 [IAttachmentPickerService] 返回，封装文件/图片选择后的元数据：
/// 本地路径、文件名、MIME 类型、大小。UI 层拿到后直接交给 ViewModel
/// 发送，字节读取与 base64 编码仍由 ACL 在发送时完成。
class AttachmentPickResult {
  /// 本地绝对路径。
  final String path;

  /// 文件名（含扩展名）。
  final String fileName;

  /// MIME 类型，已由 picker service 根据平台返回或扩展名推断。
  final String mimeType;

  /// 文件大小（字节）。
  final int size;

  const AttachmentPickResult({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.size,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachmentPickResult &&
          other.path == path &&
          other.fileName == fileName &&
          other.mimeType == mimeType &&
          other.size == size;

  @override
  int get hashCode => Object.hash(path, fileName, mimeType, size);

  @override
  String toString() =>
      'AttachmentPickResult(fileName: $fileName, mimeType: $mimeType, size: $size)';
}
