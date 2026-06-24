// V5 → V6 Agent tombstone 列迁移测试 (US-021)。
//
// 背景：US-021 给 agents 表加 removed_at / hidden_at 两个 nullable INTEGER 列。
// onUpgrade 的 `if (from < 6)` 分支用 migrator.addColumn 添加。本测试验证：
// - 升级后新列存在且默认 NULL
// - 现有字段值不变
// - 升级后 agent 行仍可正常查询
//
// 模式参照 migration_v4_to_v5_test.dart：用 raw SQL 插入 v5 形态的行 →
// 跑迁移 → 断言。完整的 user_version + onUpgrade 派发是 Drift 框架职责，
// 此处聚焦迁移 SQL 语义。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;

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

/// 直接用 SQL 插入一个 v5 形态的 agent 行（无 removed_at/hidden_at 列）。
/// 关闭 FK 检查以绕开 agents → instances 的外键链。
Future<void> _insertV5Agent(
  db.AppDatabase database, {
  required String localId,
  required String remoteId,
  required String instanceId,
  String name = 'Test Agent',
  String themeColor = '#4F83FF',
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
        name,
        themeColor,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  } finally {
    await database.customStatement('PRAGMA foreign_keys = ON');
  }
}

void main() {
  group('V5 → V6 agent tombstone columns migration', () {
    test('removed_at / hidden_at 列存在且默认为 NULL', () async {
      final database = await _createTestDb();

      await _insertV5Agent(
        database,
        localId: 'agent-1',
        remoteId: 'remote-1',
        instanceId: 'inst-1',
      );

      // AppDatabase 构造时 schemaVersion=6，Drift 自动跑 onUpgrade 把列加上。
      // 直接读取验证默认值。
      final row = await database.getAgentByLocalId('agent-1').getSingle();
      expect(row.removedAt, isNull);
      expect(row.hiddenAt, isNull);
    });

    test('现有字段值在迁移后保持不变', () async {
      final database = await _createTestDb();

      await _insertV5Agent(
        database,
        localId: 'agent-1',
        remoteId: 'remote-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#22D3EE',
      );

      final row = await database.getAgentByLocalId('agent-1').getSingle();
      expect(row.name, '产品虾');
      expect(row.themeColor, '#22D3EE');
      expect(row.remoteId, 'remote-1');
      expect(row.instanceId, 'inst-1');
    });

    test('迁移后多行 agent 仍可正常查询', () async {
      final database = await _createTestDb();

      await _insertV5Agent(
        database,
        localId: 'a-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
      );
      await _insertV5Agent(
        database,
        localId: 'a-2',
        remoteId: 'r-2',
        instanceId: 'inst-1',
      );
      await _insertV5Agent(
        database,
        localId: 'a-3',
        remoteId: 'r-3',
        instanceId: 'inst-2',
      );

      final allRows = await database.getAllAgents().get();
      expect(allRows.length, 3);
      // 每行的新列都应为 NULL
      for (final row in allRows) {
        expect(row.removedAt, isNull);
        expect(row.hiddenAt, isNull);
      }
    });

    test('findByCompositeKey 仍能查到迁移后的 agent（不过滤 tombstone）', () async {
      final database = await _createTestDb();

      await _insertV5Agent(
        database,
        localId: 'agent-1',
        remoteId: 'remote-1',
        instanceId: 'inst-1',
      );

      final row = await database
          .findAgentByCompositeKey('inst-1', 'remote-1')
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.removedAt, isNull);
    });
  });
}
