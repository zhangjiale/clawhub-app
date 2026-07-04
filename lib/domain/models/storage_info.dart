import '../utils/format_bytes.dart';

/// Snapshot of on-device storage usage.
///
/// Returned by [ISettingsRepo.getStorageInfo] for display on the
/// storage management settings page.
class StorageInfo {
  /// Approximate size of the SQLite database file in bytes.
  final int databaseSizeBytes;

  /// Total number of persisted messages across all conversations.
  final int messageCount;

  const StorageInfo({required this.databaseSizeBytes, this.messageCount = 0});

  /// Human-readable database size label.
  String get sizeLabel => formatBytes(databaseSizeBytes);
}
