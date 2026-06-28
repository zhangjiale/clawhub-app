import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_settings_repo.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';

Future<db.AppDatabase> _createTestDb() async {
  final database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (sqlDb) {
        sqlDb.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
  addTearDown(() => database.close());
  return database;
}

/// Insert a test message into the database.
///
/// The generated [db.AppDatabase.insertMessage] has 11 required positional
/// parameters — this helper wraps the call for readability.
///
/// Because [insertMessage] enforces foreign keys (→ conversations, agents),
/// we temporarily disable FK checks for test-only data. The FK validation
/// lives in the real repo layers, not the database engine.
Future<int> _insertTestMessage({
  required db.AppDatabase db,
  required String clientId,
  String? serverId,
  required String conversationId,
  required String agentId,
  int role = 0,
  String? content,
  int type = 0,
  int status = 4,
  int logicalClock = 0,
  int? timestamp,
  String? metadata,
}) async {
  await db.customStatement('PRAGMA foreign_keys = OFF');
  try {
    return await db.insertMessage(
      clientId,
      serverId,
      conversationId,
      agentId,
      role,
      content,
      type,
      status,
      logicalClock,
      timestamp ?? DateTime.now().millisecondsSinceEpoch,
      metadata,
    );
  } finally {
    await db.customStatement('PRAGMA foreign_keys = ON');
  }
}

void main() {
  group('DriftSettingsRepo.getPreferences', () {
    late db.AppDatabase database;
    late DriftSettingsRepo repo;

    setUp(() async {
      database = await _createTestDb();
      repo = DriftSettingsRepo(database, logger: const DebugPrintLogger());
    });

    test('returns defaults when no row exists in database', () async {
      final prefs = await repo.getPreferences();
      expect(prefs, equals(UserPreferences.defaults()));
    });

    test('returns persisted preferences after update', () async {
      final updated = UserPreferences.defaults().copyWith(
        notificationsEnabled: false,
        dndEnabled: true,
      );
      await repo.updatePreferences(updated);

      final prefs = await repo.getPreferences();
      expect(prefs.notificationsEnabled, isFalse);
      expect(prefs.dndEnabled, isTrue);
      // Other fields should still be at defaults
      expect(prefs.notifyOnReply, isTrue);
      expect(prefs.biometricEnabled, isFalse);
    });
  });

  group('DriftSettingsRepo.updatePreferences', () {
    late db.AppDatabase database;
    late DriftSettingsRepo repo;

    setUp(() async {
      database = await _createTestDb();
      repo = DriftSettingsRepo(database, logger: const DebugPrintLogger());
    });

    test('persists all boolean fields correctly', () async {
      await repo.updatePreferences(
        UserPreferences.defaults().copyWith(
          notificationsEnabled: false,
          notifyOnReply: false,
          notifyOnError: false,
          notifyOnConnectionChange: false,
          dndEnabled: true,
          biometricEnabled: true,
        ),
      );

      final prefs = await repo.getPreferences();
      expect(prefs.notificationsEnabled, isFalse);
      expect(prefs.notifyOnReply, isFalse);
      expect(prefs.notifyOnError, isFalse);
      expect(prefs.notifyOnConnectionChange, isFalse);
      expect(prefs.dndEnabled, isTrue);
      expect(prefs.biometricEnabled, isTrue);
    });

    test('persists DND time range correctly', () async {
      await repo.updatePreferences(
        UserPreferences.defaults().copyWith(
          dndEnabled: true,
          dndStartHour: 23,
          dndStartMinute: 30,
          dndEndHour: 7,
          dndEndMinute: 15,
        ),
      );

      final prefs = await repo.getPreferences();
      expect(prefs.dndStartHour, 23);
      expect(prefs.dndStartMinute, 30);
      expect(prefs.dndEndHour, 7);
      expect(prefs.dndEndMinute, 15);
    });

    test('overwrites previous values on subsequent update', () async {
      await repo.updatePreferences(
        UserPreferences.defaults().copyWith(dndEnabled: true),
      );
      var prefs = await repo.getPreferences();
      expect(prefs.dndEnabled, isTrue);

      await repo.updatePreferences(
        UserPreferences.defaults().copyWith(dndEnabled: false),
      );
      prefs = await repo.getPreferences();
      expect(prefs.dndEnabled, isFalse);
    });

    test('multiple updates in sequence all persist', () async {
      await repo.updatePreferences(
        UserPreferences.defaults().copyWith(notificationsEnabled: false),
      );
      await repo.updatePreferences(
        UserPreferences.defaults().copyWith(dndEnabled: true, dndStartHour: 21),
      );

      final prefs = await repo.getPreferences();
      // Second update overwrote the first (full-row UPSERT).
      // Since the second didn't touch notificationsEnabled, it should be
      // back to default (true) — full row overwrite semantics.
      expect(prefs.notificationsEnabled, isTrue);
      expect(prefs.dndEnabled, isTrue);
      expect(prefs.dndStartHour, 21);
    });
  });

  group('DriftSettingsRepo.watchPreferences', () {
    late db.AppDatabase database;
    late DriftSettingsRepo repo;

    setUp(() async {
      database = await _createTestDb();
      repo = DriftSettingsRepo(database, logger: const DebugPrintLogger());
    });

    test('emits defaults when no row exists', () async {
      final stream = repo.watchPreferences();
      final prefs = await stream.first;
      expect(prefs, equals(UserPreferences.defaults()));
    });

    test('emits updated value after persist', () async {
      final stream = repo.watchPreferences();

      // First emission is defaults
      final first = await stream.first;
      expect(first.dndEnabled, isFalse);

      // Persist a change
      await repo.updatePreferences(
        UserPreferences.defaults().copyWith(dndEnabled: true),
      );

      // Second emission should reflect the update
      final second = await stream.first;
      expect(second.dndEnabled, isTrue);
    });
  });

  group('DriftSettingsRepo.getStorageInfo', () {
    late db.AppDatabase database;
    late DriftSettingsRepo repo;

    setUp(() async {
      database = await _createTestDb();
      repo = DriftSettingsRepo(database, logger: const DebugPrintLogger());
    });

    test(
      'returns storage info with zero messages for empty database',
      () async {
        final info = await repo.getStorageInfo();
        expect(info.messageCount, 0);
        expect(info.databaseSizeBytes, greaterThan(0)); // SQLite overhead
      },
    );

    test('messageCount reflects inserted messages', () async {
      // Insert a few messages to verify COUNT(*)
      for (var i = 0; i < 5; i++) {
        await _insertTestMessage(
          db: database,
          clientId: 'client-$i',
          conversationId: 'conv-1',
          agentId: 'agent-1',
          content: 'Test message $i',
          logicalClock: i,
        );
      }

      final info = await repo.getStorageInfo();
      expect(info.messageCount, 5);
    });

    test('returns cached result within TTL', () async {
      // First call — hits DB
      final info1 = await repo.getStorageInfo();

      // Insert a message — but cache should still return old value
      await _insertTestMessage(
        db: database,
        clientId: 'client-ttl',
        conversationId: 'conv-1',
        agentId: 'agent-1',
        content: 'TTL test',
      );

      // Second call within TTL — should return cached (stale) result
      final info2 = await repo.getStorageInfo();
      expect(info2.messageCount, info1.messageCount);

      // After invalidation, should get fresh count
      repo.invalidateStorageCache();
      final info3 = await repo.getStorageInfo();
      expect(info3.messageCount, 1);
    });

    test('sizeLabel returns human-readable format', () async {
      final info = await repo.getStorageInfo();
      final label = info.sizeLabel;
      // Should be non-empty and end with B, KB, or MB
      expect(label, isNotEmpty);
      expect(
        label.endsWith(' B') || label.endsWith('KB') || label.endsWith('MB'),
        isTrue,
      );
    });
  });

  group('DriftSettingsRepo.clearAll (US-030)', () {
    late db.AppDatabase database;
    late DriftSettingsRepo repo;

    setUp(() async {
      database = await _createTestDb();
      repo = DriftSettingsRepo(database, logger: const DebugPrintLogger());
    });

    /// Seed minimal data across all related tables so CASCADE has
    /// something to clean. Uses FK=OFF because the helper inserts in
    /// an order that may not satisfy the engine's constraints; the
    /// real FK validation lives in repository layers, not the DB.
    Future<void> seedAllTables() async {
      await database.customStatement('PRAGMA foreign_keys = OFF');
      try {
        await database.customStatement(
          'INSERT INTO instances '
          '(id, name, gateway_url, token_ref, created_at) '
          'VALUES (?, ?, ?, ?, ?)',
          ['inst-1', 'Test', 'ws://localhost:18789', 'token', 0],
        );
        await database.customStatement(
          'INSERT INTO agents '
          '(local_id, remote_id, instance_id, name, created_at) '
          'VALUES (?, ?, ?, ?, ?)',
          ['agent-1', 'r1', 'inst-1', 'Test Agent', 0],
        );
        await database.customStatement(
          'INSERT INTO conversations '
          '(id, agent_id, instance_id) '
          'VALUES (?, ?, ?)',
          ['conv-1', 'agent-1', 'inst-1'],
        );
        for (var i = 0; i < 3; i++) {
          await database.customStatement(
            'INSERT INTO messages '
            '(client_id, conversation_id, agent_id, role, content, '
            'type, status, logical_clock, timestamp) '
            'VALUES (?, ?, ?, 0, ?, 0, 4, ?, ?)',
            ['c-$i', 'conv-1', 'agent-1', 'hello $i', i, i * 1000],
          );
        }
        await database.customStatement(
          'INSERT INTO achievement_unlocks '
          '(achievement_id, agent_id, unlocked_at) '
          'VALUES (?, ?, ?)',
          ['first-chat', 'agent-1', 1000],
        );
        await database.customStatement(
          'INSERT INTO tool_calls '
          '(id, message_id, tool_name, status) '
          'VALUES (?, ?, ?, ?)',
          ['tc-1', 'c-0', 'search', 0],
        );
        // pending_notifications: DND 静默队列条目,持有 message_server_id
        // 用于跨重启去重。clearAll 删消息后,残留条目会让 dispatcher 误判
        // 已通知(serverId 去重误杀新通知),故应一并清理。
        await database.customStatement(
          'INSERT INTO pending_notifications '
          '(agent_id, instance_id, agent_name, summary, created_at, '
          'message_server_id, delivered) '
          'VALUES (?, ?, ?, ?, ?, ?, 0)',
          ['agent-1', 'inst-1', 'Test Agent', '回复摘要', 1000, 'srv-old'],
        );
      } finally {
        await database.customStatement('PRAGMA foreign_keys = ON');
      }
    }

    test('clears messages, tool_calls, achievement_unlocks, FTS', () async {
      await seedAllTables();
      // Pre-condition: data is present
      expect(
        (await database
                .customSelect('SELECT COUNT(*) AS n FROM messages')
                .getSingle())
            .read<int>('n'),
        3,
      );
      expect(
        (await database
                .customSelect('SELECT COUNT(*) AS n FROM agents')
                .getSingle())
            .read<int>('n'),
        1,
      );

      await repo.clearAll();

      // Post-condition: content tables empty, skeleton preserved
      for (final table in [
        'messages',
        'tool_calls',
        'achievement_unlocks',
        'pending_notifications',
        'messages_fts',
      ]) {
        final n =
            (await database
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n');
        expect(n, 0, reason: 'table $table should be empty after clearAll');
      }
    });

    /// Regression: 流式中 clearAll 后,Agent 的最终回复仍能落库。
    ///
    /// 旧实现 `DELETE FROM agents` 触发 CASCADE 删掉 conversations,
    /// 导致进行中流的 `StreamingDone` 消息 INSERT 因 `conversation_id`
    /// 外键不存在而抛 `FOREIGN KEY constraint failed`,回复永久丢失。
    /// 保留骨架(agents/conversations)后,INSERT 不再失败。
    test(
      'preserves agents and conversations skeleton (FK-safe clear)',
      () async {
        await seedAllTables();

        await repo.clearAll();

        // Skeleton survives — agents & conversations NOT deleted
        final agentCount =
            (await database
                    .customSelect('SELECT COUNT(*) AS n FROM agents')
                    .getSingle())
                .read<int>('n');
        expect(agentCount, 1, reason: 'agents skeleton must survive clearAll');

        final convCount =
            (await database
                    .customSelect('SELECT COUNT(*) AS n FROM conversations')
                    .getSingle())
                .read<int>('n');
        expect(
          convCount,
          1,
          reason: 'conversations skeleton must survive clearAll',
        );

        // The bug fix: a message referencing the surviving conversation_id
        // must insert WITHOUT raising FK constraint failure.
        await database.customStatement(
          'INSERT INTO messages '
          '(client_id, conversation_id, agent_id, role, content, '
          'type, status, logical_clock, timestamp) '
          'VALUES (?, ?, ?, 1, ?, 0, 4, 0, 5000)',
          ['streaming-final', 'conv-1', 'agent-1', 'final reply'],
        );

        final msgCount =
            (await database
                    .customSelect('SELECT COUNT(*) AS n FROM messages')
                    .getSingle())
                .read<int>('n');
        expect(
          msgCount,
          1,
          reason: 'post-clear streaming message must persist',
        );
      },
    );

    test('preserves instances and user_preferences', () async {
      await seedAllTables();
      // Add a user_preferences row to verify it survives
      await database.customStatement(
        'INSERT OR REPLACE INTO user_preferences '
        '(id, notifications_enabled, notify_on_reply, notify_on_error, '
        'notify_on_connection_change, dnd_enabled, dnd_start_hour, '
        'dnd_start_minute, dnd_end_hour, dnd_end_minute, '
        'biometric_enabled) '
        'VALUES (1, 0, 1, 1, 1, 1, 22, 0, 8, 0, 0)',
      );

      await repo.clearAll();

      // instances: 1 row preserved
      final instCount =
          (await database
                  .customSelect('SELECT COUNT(*) AS n FROM instances')
                  .getSingle())
              .read<int>('n');
      expect(instCount, 1, reason: 'instances must survive clearAll');

      // user_preferences: 1 row preserved
      final prefsCount =
          (await database
                  .customSelect('SELECT COUNT(*) AS n FROM user_preferences')
                  .getSingle())
              .read<int>('n');
      expect(prefsCount, 1, reason: 'user_preferences must survive clearAll');
    });

    test(
      'invalidateStorageCache is called (getStorageInfo returns 0 after clear)',
      () async {
        await seedAllTables();
        // Warm cache
        final before = await repo.getStorageInfo();
        expect(before.messageCount, 3);

        await repo.clearAll();

        // getStorageInfo after clear should NOT be cached — should return 0
        final after = await repo.getStorageInfo();
        expect(after.messageCount, 0);
      },
    );

    test('clearAll on empty database is a no-op (does not throw)', () async {
      // No data, just call
      await repo.clearAll();
      // Still no exception
      final info = await repo.getStorageInfo();
      expect(info.messageCount, 0);
    });
  });

  // ---------------------------------------------------------------
  // Regression: clearAll 必须向 UI 报告"部分失败" (US-030 partial failure)
  //
  // 旧实现 clearAll() 返回 void 且 catch 中静默吞掉头像清理异常,UI 永远
  // 显示"已清除全部缓存",用户不知道头像文件残留在磁盘（macOS 沙箱/权限
  // 拒绝等场景）。修复:返回 ClearAllResult { dbCleared, avatarsCleared },
  // 让 storage_management_page 能区分完整成功/部分失败。
  // ---------------------------------------------------------------
  group('DriftSettingsRepo.clearAll partial-failure reporting', () {
    late db.AppDatabase database;
    late _StubAvatarStorageService avatarService;

    setUp(() async {
      database = await _createTestDb();
      avatarService = _StubAvatarStorageService();
    });

    test(
      'returns allSucceeded=true when avatar service is null (no-op path)',
      () async {
        final repo = DriftSettingsRepo(
          database,
          logger: const DebugPrintLogger(),
        );
        final result = await repo.clearAll();
        expect(result.dbCleared, isTrue);
        expect(result.avatarsCleared, isTrue);
        expect(result.allSucceeded, isTrue);
      },
    );

    test('returns allSucceeded=true when avatar service succeeds', () async {
      avatarService.shouldThrowOnClearAll = false;
      final repo = DriftSettingsRepo(
        database,
        avatarStorageService: avatarService,
        logger: const DebugPrintLogger(),
      );
      final result = await repo.clearAll();
      expect(result.dbCleared, isTrue);
      expect(result.avatarsCleared, isTrue);
      expect(result.allSucceeded, isTrue);
      expect(avatarService.clearAllCallCount, 1);
    });

    test('returns partialFailure=true when avatar service throws '
        '(DB cleared, avatar files orphaned on disk)', () async {
      avatarService.shouldThrowOnClearAll = true;
      final repo = DriftSettingsRepo(
        database,
        avatarStorageService: avatarService,
        logger: const DebugPrintLogger(),
      );
      final result = await repo.clearAll();
      // DB 清理仍然成功 —— partialFailure
      expect(result.dbCleared, isTrue);
      expect(result.avatarsCleared, isFalse);
      expect(result.partialFailure, isTrue);
      expect(result.allSucceeded, isFalse);
    });

    test('partial-failure result does NOT roll back DB cleanup', () async {
      avatarService.shouldThrowOnClearAll = true;
      // Seed DB so we can prove rollback didn't happen
      await database.customStatement('PRAGMA foreign_keys = OFF');
      try {
        await database.customStatement(
          'INSERT INTO messages (client_id, conversation_id, agent_id, '
          'role, content, type, status, logical_clock, timestamp) '
          'VALUES (?, ?, ?, 0, ?, 0, 4, 0, ?)',
          ['c-partial', 'conv-x', 'agent-x', 'partial', 0],
        );
      } finally {
        await database.customStatement('PRAGMA foreign_keys = ON');
      }

      final repo = DriftSettingsRepo(
        database,
        avatarStorageService: avatarService,
        logger: const DebugPrintLogger(),
      );
      await repo.clearAll();

      // DB 仍然被清空 —— 头像失败不回滚 DB
      final n =
          (await database
                  .customSelect('SELECT COUNT(*) AS n FROM messages')
                  .getSingle())
              .read<int>('n');
      expect(n, 0, reason: 'DB must be cleared even if avatar cleanup fails');
    });
  });
}

/// Test stub: minimal IAvatarStorageService that records clearAll calls
/// and can be configured to throw on demand.
class _StubAvatarStorageService implements IAvatarStorageService {
  bool shouldThrowOnClearAll = false;
  int clearAllCallCount = 0;

  @override
  Future<void> clearAll() async {
    clearAllCallCount++;
    if (shouldThrowOnClearAll) {
      throw StateError('simulated filesystem permission denied');
    }
  }

  // 以下成员在 clearAll 测试路径上不会被调用,留 stub 占位。
  @override
  Future<String> saveAvatar(String localId, Uint8List bytes) async => '';

  @override
  Future<void> deleteAvatar(String localId) async {}

  @override
  bool avatarExists(String localId) => false;

  @override
  String getAvatarPath(String localId) => '';
}
