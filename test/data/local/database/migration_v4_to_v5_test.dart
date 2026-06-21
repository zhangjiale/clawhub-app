// V4 → V5 theme_color migration test (issue #1).
//
// Background: schema.drift changed agents.theme_color DEFAULT from
// '#007AFF' (V1) to '#4F83FF' (V2 sapphire). Pre-V2 installs still
// have rows carrying the V1 default; the onUpgrade block in
// `database.dart` rewrites those to V2 on app upgrade.
//
// This test exercises the migration SQL against a V5 in-memory DB
// pre-seeded with V1-shaped data. The full V4 → V5 upgrade wiring
// (user_version PRAGMA + Drift's onUpgrade dispatch) is a framework
// concern covered by Drift itself; we focus on the SQL semantics here.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;

const _v1DefaultColor = '#007AFF';
const _v2DefaultColor = '#4F83FF';

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

/// Insert an agent row directly via SQL so we can plant V1-shaped
/// data (theme_color = '#007AFF') that the migration is meant to
/// rewrite. Using a customStatement also sidesteps the FK chain
/// (agents → instances) that `insertAgent` would otherwise require
/// (and lets us skip a real `instances` row).
///
/// FK checks are toggled off for the duration of the insert — same
/// pattern as drift_settings_repo_test.dart.
Future<void> _insertAgent(
  db.AppDatabase database, {
  required String localId,
  required String remoteId,
  required String instanceId,
  required String themeColor,
}) async {
  await database.customStatement('PRAGMA foreign_keys = OFF');
  try {
    await database.customStatement(
      'INSERT INTO agents '
      '(local_id, remote_id, instance_id, name, theme_color, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        localId,
        remoteId,
        instanceId,
        'Test Agent $localId',
        themeColor,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  } finally {
    await database.customStatement('PRAGMA foreign_keys = ON');
  }
}

/// Same SQL the onUpgrade block in `database.dart` runs. Kept as a
/// top-level constant so the test and production code can't drift.
Future<void> _runV4ToV5Migration(db.AppDatabase database) async {
  await database.customStatement(
    "UPDATE agents SET theme_color = '$_v2DefaultColor' "
    "WHERE theme_color = '$_v1DefaultColor'",
  );
}

void main() {
  group('V4 → V5 theme_color migration', () {
    test('rewrites V1 default #007AFF to V2 #4F83FF', () async {
      final database = await _createTestDb();

      await _insertAgent(
        database,
        localId: 'agent-1',
        remoteId: 'remote-1',
        instanceId: 'inst-1',
        themeColor: _v1DefaultColor,
      );

      await _runV4ToV5Migration(database);

      final row = await database.getAgentByLocalId('agent-1').getSingle();
      expect(row.themeColor, _v2DefaultColor);
    });

    test('preserves user-chosen colors (not the V1 default)', () async {
      final database = await _createTestDb();

      const userColor = '#9B7AFF'; // V2 violet from agentThemeColors
      await _insertAgent(
        database,
        localId: 'agent-1',
        remoteId: 'remote-1',
        instanceId: 'inst-1',
        themeColor: userColor,
      );

      await _runV4ToV5Migration(database);

      final row = await database.getAgentByLocalId('agent-1').getSingle();
      expect(row.themeColor, userColor);
    });

    test('migrates a mix of V1-default and user-chosen rows', () async {
      final database = await _createTestDb();

      // Three agents: two with V1 default, one with a custom color.
      await _insertAgent(
        database,
        localId: 'a-v1',
        remoteId: 'r-v1',
        instanceId: 'inst-1',
        themeColor: _v1DefaultColor,
      );
      await _insertAgent(
        database,
        localId: 'a-cyan',
        remoteId: 'r-cyan',
        instanceId: 'inst-1',
        themeColor: '#22D3EE', // V2 cyan — user-chosen
      );
      await _insertAgent(
        database,
        localId: 'a-v1b',
        remoteId: 'r-v1b',
        instanceId: 'inst-1',
        themeColor: _v1DefaultColor,
      );

      await _runV4ToV5Migration(database);

      final rows = await database.getAllAgents().get();
      final byId = {for (final r in rows) r.localId: r.themeColor};
      expect(byId['a-v1'], _v2DefaultColor);
      expect(byId['a-cyan'], '#22D3EE'); // unchanged
      expect(byId['a-v1b'], _v2DefaultColor);
    });

    test(
      'is idempotent — running twice does not corrupt custom colors',
      () async {
        final database = await _createTestDb();

        // First migration: V1 → V2.
        await _insertAgent(
          database,
          localId: 'a-v1',
          remoteId: 'r-v1',
          instanceId: 'inst-1',
          themeColor: _v1DefaultColor,
        );
        await _runV4ToV5Migration(database);

        // Second migration on the same DB: must be a no-op (no rows match
        // the WHERE clause anymore, but a re-run still shouldn't touch
        // any custom colors).
        await _runV4ToV5Migration(database);

        final row = await database.getAgentByLocalId('a-v1').getSingle();
        expect(row.themeColor, _v2DefaultColor);
      },
    );
  });
}
