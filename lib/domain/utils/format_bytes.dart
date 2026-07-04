/// Formats a byte count as a human-readable `B` / `KB` / `MB` label.
///
/// Shared SSOT for byte formatting — used by [StorageInfo.sizeLabel] (storage
/// settings) and [MessageFileContent] (chat file-attachment bubble) so the
/// convention lives in one place.
///
/// Pure Dart (no Flutter dependency): both the domain model and the widget
/// can import it without crossing layer boundaries.
///
/// Outputs are pinned by `test/domain/utils/format_bytes_test.dart` and match
/// the pre-existing `StorageInfo.sizeLabel` expectations exactly.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
