import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
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
      repo = DriftSettingsRepo(database);
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
      repo = DriftSettingsRepo(database);
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
      repo = DriftSettingsRepo(database);
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
      repo = DriftSettingsRepo(database);
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
}
