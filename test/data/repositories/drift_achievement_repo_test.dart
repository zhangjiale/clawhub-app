import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_achievement_repo.dart';

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

/// Insert a minimal agent row to satisfy FK constraints, and disable FK
/// checks so that test data doesn't require fully-populated cascades.
Future<void> _seedTestAgent(db.AppDatabase database, String agentId) async {
  // Temporarily disable FK checks to insert test-only agent data.
  // Real FK validation lives in the repository layers, not the DB engine.
  await database.customStatement('PRAGMA foreign_keys = OFF');
  try {
    await database.customStatement(
      'INSERT OR IGNORE INTO instances (id, name, gateway_url, token_ref, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['inst-1', 'test-instance', 'ws://localhost:18789', 'test-token', 0],
    );
    await database.customStatement(
      'INSERT OR IGNORE INTO agents (local_id, remote_id, instance_id, name, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [agentId, 'remote-$agentId', 'inst-1', 'Test Agent', 0],
    );
  } finally {
    await database.customStatement('PRAGMA foreign_keys = ON');
  }
}

void main() {
  late db.AppDatabase database;
  late DriftAchievementRepo repo;

  setUp(() async {
    database = await _createTestDb();
    repo = DriftAchievementRepo(database);
  });

  group('Achievement unlocks', () {
    setUp(() async {
      await _seedTestAgent(database, 'agent-1');
    });

    test('getUnlocks returns all 8 achievements with none unlocked', () async {
      final unlocks = await repo.getUnlocks('agent-1');

      expect(unlocks.length, 8);
      expect(unlocks.every((a) => !a.unlocked), isTrue);
    });

    test('batchUnlock unlocks specified achievements', () async {
      final result = await repo.batchUnlock('agent-1', {
        'first_dialog',
        'streak_7',
      });

      final fd = result.firstWhere((a) => a.id == 'first_dialog');
      expect(fd.unlocked, isTrue);
      expect(fd.unlockedAt, isNotNull);

      final s7 = result.firstWhere((a) => a.id == 'streak_7');
      expect(s7.unlocked, isTrue);

      final others = result.where(
        (a) => a.id != 'first_dialog' && a.id != 'streak_7',
      );
      expect(others.every((a) => !a.unlocked), isTrue);
    });

    test('batchUnlock is idempotent', () async {
      final r1 = await repo.batchUnlock('agent-1', {'first_dialog'});
      final r2 = await repo.batchUnlock('agent-1', {'first_dialog'});

      final fd1 = r1.firstWhere((a) => a.id == 'first_dialog');
      final fd2 = r2.firstWhere((a) => a.id == 'first_dialog');
      expect(fd1.unlockedAt, fd2.unlockedAt);
    });

    test('batchUnlock with empty set returns current state', () async {
      await repo.batchUnlock('agent-1', {'first_dialog'});
      final result = await repo.batchUnlock('agent-1', {});

      expect(result.length, 8);
      final fd = result.firstWhere((a) => a.id == 'first_dialog');
      expect(fd.unlocked, isTrue);
    });
  });

  group('computeStats', () {
    test('returns zero stats for agent with no messages', () async {
      final stats = await repo.computeStats('agent-no-msgs');

      expect(stats.agentId, 'agent-no-msgs');
      expect(stats.totalDialogs, 0);
      expect(stats.totalMessages, 0);
      expect(stats.totalToolCalls, 0);
      expect(stats.activeDays, 0);
      expect(stats.currentStreak, 0);
      expect(stats.firstDialogDate, isNull);
      expect(stats.lastDialogDate, isNull);
    });
  });
}
