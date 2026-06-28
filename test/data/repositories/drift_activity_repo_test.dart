import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_activity_repo.dart';

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

/// Seed instance + agent so test messages can satisfy FK constraints
/// (we then disable FK to skip the conversation row).
Future<void> _seedTestAgent(db.AppDatabase database, String agentId) async {
  await database.customStatement('PRAGMA foreign_keys = OFF');
  try {
    await database.customStatement(
      'INSERT OR IGNORE INTO instances '
      '(id, name, gateway_url, token_ref, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['inst-1', 'test-instance', 'ws://localhost:18789', 'test-token', 0],
    );
    await database.customStatement(
      'INSERT OR IGNORE INTO agents '
      '(local_id, remote_id, instance_id, name, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [agentId, 'remote-$agentId', 'inst-1', 'Test Agent', 0],
    );
  } finally {
    await database.customStatement('PRAGMA foreign_keys = ON');
  }
}

/// Insert a minimal message row. Uses a fake conversation id; the activity
/// repo only filters by `agent_id` and `timestamp`, so the FK to
/// `conversations.id` does not need to resolve for this query to work.
Future<void> _insertMessage(
  db.AppDatabase database, {
  required String clientId,
  required String agentId,
  required int timestampMs,
  int role = 0,
  int type = 0,
  int status = 4,
}) async {
  await database.customStatement('PRAGMA foreign_keys = OFF');
  try {
    await database.customStatement(
      'INSERT INTO messages '
      '(client_id, conversation_id, agent_id, role, content, type, '
      'status, logical_clock, timestamp) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        clientId,
        'fake-conv-1',
        agentId,
        role,
        'hello',
        type,
        status,
        timestampMs,
        timestampMs,
      ],
    );
  } finally {
    await database.customStatement('PRAGMA foreign_keys = ON');
  }
}

void main() {
  late db.AppDatabase database;
  late DriftActivityRepo repo;

  setUp(() async {
    database = await _createTestDb();
    await _seedTestAgent(database, 'agent-1');
    repo = DriftActivityRepo(database);
  });

  // Anchor "today" to a fixed UTC midnight so tests are deterministic.
  // All timestamps are in milliseconds since epoch.
  final todayUtc = DateTime.utc(2024, 6, 15);
  final todayBucket = todayUtc.millisecondsSinceEpoch ~/ 86400000;

  group('getDailyActivity', () {
    test('returns 30 zero-count entries when agent has no messages', () async {
      final result = await repo.getDailyActivity('agent-1', now: todayUtc);
      expect(result.length, 30);
      expect(result.every((d) => d.messageCount == 0), isTrue);
      expect(result.first.dayBucket, todayBucket - 29);
      expect(result.last.dayBucket, todayBucket);
    });

    test(
      'three same-day messages aggregate to one bucket with count=3',
      () async {
        // 3 messages all on today, slightly different times
        final baseMs = todayBucket * 86400000;
        for (var i = 0; i < 3; i++) {
          await _insertMessage(
            database,
            clientId: 'c-$i',
            agentId: 'agent-1',
            timestampMs: baseMs + i * 3600000, // 0h, 1h, 2h
          );
        }

        final result = await repo.getDailyActivity('agent-1', now: todayUtc);
        expect(result.length, 30);
        expect(result.last.dayBucket, todayBucket);
        expect(result.last.messageCount, 3);
        // All other 29 days empty
        expect(result.take(29).every((d) => d.messageCount == 0), isTrue);
      },
    );

    test('multi-day messages are sorted by dayBucket ascending', () async {
      // Insert one message on day-29, one on day-15, one on day-0 (today)
      for (final offset in const [-29, -15, 0]) {
        final dayMs = (todayBucket + offset) * 86400000;
        await _insertMessage(
          database,
          clientId: 'c-$offset',
          agentId: 'agent-1',
          timestampMs: dayMs,
        );
      }

      final result = await repo.getDailyActivity('agent-1', now: todayUtc);
      // 30 entries, count==1 at offsets -29, -15, 0; rest 0
      expect(result[0].dayBucket, todayBucket - 29);
      expect(result[0].messageCount, 1);
      expect(result[14].dayBucket, todayBucket - 15);
      expect(result[14].messageCount, 1);
      expect(result[29].dayBucket, todayBucket);
      expect(result[29].messageCount, 1);
      // Sorted asc
      for (var i = 1; i < result.length; i++) {
        expect(result[i].dayBucket, greaterThan(result[i - 1].dayBucket));
      }
    });

    test('messages older than window are excluded', () async {
      // Insert one at day-30 (just outside 30-day window) and one at day-29
      for (final offset in const [-30, -29]) {
        final dayMs = (todayBucket + offset) * 86400000;
        await _insertMessage(
          database,
          clientId: 'c-$offset',
          agentId: 'agent-1',
          timestampMs: dayMs,
        );
      }

      final result = await repo.getDailyActivity('agent-1', now: todayUtc);
      // day-30 excluded, only day-29 counts
      expect(result.first.dayBucket, todayBucket - 29);
      expect(result.first.messageCount, 1);
      expect(result.last.dayBucket, todayBucket);
      expect(result.last.messageCount, 0);
    });

    test('different agent is filtered out', () async {
      await _seedTestAgent(database, 'agent-2');
      final baseMs = todayBucket * 86400000;
      await _insertMessage(
        database,
        clientId: 'other',
        agentId: 'agent-2',
        timestampMs: baseMs,
      );

      final result = await repo.getDailyActivity('agent-1', now: todayUtc);
      expect(result.every((d) => d.messageCount == 0), isTrue);
    });

    test('custom days parameter respected', () async {
      final result = await repo.getDailyActivity(
        'agent-1',
        days: 7,
        now: todayUtc,
      );
      expect(result.length, 7);
      expect(result.first.dayBucket, todayBucket - 6);
      expect(result.last.dayBucket, todayBucket);
    });
  });
}
