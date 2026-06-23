import 'dart:async';

import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/models/clear_all_result.dart';
import 'package:claw_hub/domain/models/storage_info.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_settings_repo.dart';

import '../local/database/database.dart' as db;

/// Drift/SQLite implementation of [ISettingsRepo].
///
/// Manages a singleton row (id = 1) in the [user_preferences] table.
/// On first access, if the row doesn't exist, defaults are returned
/// (and persisted on first write via INSERT OR REPLACE).
class DriftSettingsRepo implements ISettingsRepo {
  final db.AppDatabase _database;
  final IAvatarStorageService? _avatarStorageService;
  final ILogger _logger;

  DriftSettingsRepo(
    this._database, {
    IAvatarStorageService? avatarStorageService,
    required ILogger logger,
  }) : _avatarStorageService = avatarStorageService,
       _logger = logger;

  // ---------------------------------------------------------------------------
  // Storage info cache — avoids full COUNT(*) scan on every settings open
  // ---------------------------------------------------------------------------

  StorageInfo? _cachedStorageInfo;
  DateTime? _cacheTimestamp;
  static const _cacheTtl = Duration(seconds: 30);

  @override
  Future<UserPreferences> getPreferences() async {
    final row = await _database.getUserPreferences().getSingleOrNull();
    if (row == null) return UserPreferences.defaults();
    return _rowToDomain(row);
  }

  @override
  Future<void> updatePreferences(UserPreferences preferences) async {
    await _database.upsertUserPreferences(
      _boolToInt(preferences.notificationsEnabled),
      _boolToInt(preferences.notifyOnReply),
      _boolToInt(preferences.notifyOnError),
      _boolToInt(preferences.notifyOnConnectionChange),
      _boolToInt(preferences.dndEnabled),
      preferences.dndStartHour,
      preferences.dndStartMinute,
      preferences.dndEndHour,
      preferences.dndEndMinute,
      _boolToInt(preferences.biometricEnabled),
    );
  }

  @override
  Stream<UserPreferences> watchPreferences() {
    return _database.select(_database.userPreferences).watch().map((rows) {
      if (rows.isEmpty) return UserPreferences.defaults();
      return _rowToDomain(rows.first);
    });
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    // Return cached result if still fresh, to avoid full COUNT(*) scan
    // on every settings page open.
    if (_cachedStorageInfo != null && _cacheTimestamp != null) {
      final age = DateTime.now().difference(_cacheTimestamp!);
      if (age < _cacheTtl) return _cachedStorageInfo!;
    }

    // Single query: merge both PRAGMAs and COUNT(*) into one round-trip.
    final row = await _database
        .customSelect(
          'SELECT '
          '(SELECT page_count FROM pragma_page_count()) * '
          '(SELECT page_size FROM pragma_page_size()) AS db_size_bytes, '
          '(SELECT COUNT(*) FROM messages) AS msg_count',
          readsFrom: {_database.messages},
        )
        .getSingle();

    final info = StorageInfo(
      databaseSizeBytes: row.read<int>('db_size_bytes'),
      messageCount: row.read<int>('msg_count'),
    );
    _cachedStorageInfo = info;
    _cacheTimestamp = DateTime.now();
    return info;
  }

  /// Invalidate the storage info cache so the next [getStorageInfo] call
  /// will re-read from the database.  Call this after bulk message
  /// inserts or deletes that materially change the count.
  @override
  void invalidateStorageCache() {
    _cachedStorageInfo = null;
    _cacheTimestamp = null;
  }

  @override
  Future<ClearAllResult> clearAll() async {
    // 1) 事务内:清 FTS5 + 清空聊天内容(保留 agents/conversations 骨架)。
    //
    // 顺序不能调换:`purgeAllMessagesFts` 必须先于 `clearAllContent` 的
    // `DELETE FROM messages`,否则 contentless FTS5 表在 content 表为空后
    // 执行 'delete-all' 会报 integrity error。
    //
    // 保留骨架的原因:进行中的流式会话在 clearAll 后仍会收到 `StreamingDone`,
    // 最终消息 INSERT 依赖 conversation_id 外键存在;删 agents 会 CASCADE 删
    // conversations,导致 INSERT 抛 FK 异常、回复丢失。
    await _database.transaction(() async {
      await _database.purgeAllMessagesFts();
      await _database.clearAllContent();
    });

    // 2) 事务外:清头像文件(best-effort,跨存储介质,失败不抛)
    //    DB 已经清空,但 UI 层必须知道头像清理失败,否则会误以为磁盘上
    //    没有残留头像文件。返回的 ClearAllResult.avatarsCleared 反映这一点。
    var avatarsCleared = true;
    if (_avatarStorageService != null) {
      try {
        await _avatarStorageService.clearAll();
      } catch (error, stackTrace) {
        // iron-law-allow: Law8 — best-effort filesystem cleanup
        _logger.error(
          '[DriftSettingsRepo] Avatar clear failed: $error',
          stackTrace,
        );
        avatarsCleared = false;
      }
    }

    // 3) 失效存储信息缓存,下次 getStorageInfo() 会重新计算
    invalidateStorageCache();

    return ClearAllResult(dbCleared: true, avatarsCleared: avatarsCleared);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Convert Drift row directly to domain entity (no intermediate DTO).
  UserPreferences _rowToDomain(db.UserPreference row) {
    return UserPreferences(
      notificationsEnabled: _intToBool(row.notificationsEnabled),
      notifyOnReply: _intToBool(row.notifyOnReply),
      notifyOnError: _intToBool(row.notifyOnError),
      notifyOnConnectionChange: _intToBool(row.notifyOnConnectionChange),
      dndEnabled: _intToBool(row.dndEnabled),
      dndStartHour: row.dndStartHour,
      dndStartMinute: row.dndStartMinute,
      dndEndHour: row.dndEndHour,
      dndEndMinute: row.dndEndMinute,
      biometricEnabled: _intToBool(row.biometricEnabled),
    );
  }

  static int _boolToInt(bool value) => value ? 1 : 0;
  static bool _intToBool(int value) => value != 0;
}
