import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

class MockAvatarStorageService extends Mock implements IAvatarStorageService {}

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

void main() {
  group('DriftAgentRepo.updateFullProfile quickCommands', () {
    late db.AppDatabase database;
    late DriftAgentRepo agentRepo;

    setUp(() async {
      database = await _createTestDb();
      agentRepo = DriftAgentRepo(database);
    });

    test('writes and reads quick commands with normalized sortOrder', () async {
      // Need an instance first for FK
      final instanceRepo = DriftInstanceRepo(database);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'ws://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
        ),
      );

      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'remote-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
      ]);

      await agentRepo.updateFullProfile(
        'local-1',
        quickCommands: [
          QuickCommand(
            id: '2',
            agentId: 'local-1',
            label: '记忆',
            payload: '/memory',
            sortOrder: 1,
          ),
          QuickCommand(
            id: '1',
            agentId: 'local-1',
            label: '状态',
            payload: '/status',
            sortOrder: 0,
          ),
        ],
      );

      final updated = await agentRepo.getById('local-1');
      expect(updated!.quickCommands.map((c) => c.id), ['1', '2']);
      expect(updated.quickCommands.map((c) => c.sortOrder), [0, 1]);
    });

    test('empty list clears quick commands', () async {
      final instanceRepo = DriftInstanceRepo(database);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'ws://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
        ),
      );
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'remote-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
      ]);

      await agentRepo.updateFullProfile(
        'local-1',
        quickCommands: [
          QuickCommand(id: '1', agentId: 'local-1', label: '状态', payload: '/s'),
        ],
      );
      await agentRepo.updateFullProfile('local-1', quickCommands: []);

      final updated = await agentRepo.getById('local-1');
      expect(updated!.quickCommands, isEmpty);
    });
  });

  group('DriftAgentRepo.deleteByInstanceId avatar cleanup', () {
    late db.AppDatabase database;
    late DriftAgentRepo agentRepo;
    late MockAvatarStorageService mockAvatarStorage;

    setUp(() async {
      database = await _createTestDb();
      mockAvatarStorage = MockAvatarStorageService();
      agentRepo = DriftAgentRepo(database, avatarStorage: mockAvatarStorage);
      when(
        () => mockAvatarStorage.deleteAvatar(any()),
      ).thenAnswer((_) async {});
    });

    test('calls deleteAvatar for each agent in deleted instance', () async {
      final instanceRepo = DriftInstanceRepo(database);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'ws://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
        ),
      );

      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'remote-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
        Agent(
          localId: 'local-2',
          remoteId: 'remote-2',
          instanceId: 'inst-1',
          name: '代码虾',
        ),
      ]);

      await agentRepo.deleteByInstanceId('inst-1');

      verify(() => mockAvatarStorage.deleteAvatar('local-1')).called(1);
      verify(() => mockAvatarStorage.deleteAvatar('local-2')).called(1);
    });

    test('deleteAvatar failure does not throw', () async {
      when(
        () => mockAvatarStorage.deleteAvatar(any()),
      ).thenThrow(Exception('disk error'));

      final instanceRepo = DriftInstanceRepo(database);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'ws://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
        ),
      );

      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'remote-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
      ]);

      await agentRepo.deleteByInstanceId('inst-1');

      final agent = await agentRepo.getById('local-1');
      expect(agent, isNull);
    });
  });

  // US-021: syncFromGateway 差集 → tombstone / 复活。
  group('DriftAgentRepo.syncFromGateway tombstone diff (US-021)', () {
    late db.AppDatabase database;
    late DriftAgentRepo agentRepo;

    setUp(() async {
      database = await _createTestDb();
      agentRepo = DriftAgentRepo(database);
      final instanceRepo = DriftInstanceRepo(database);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'ws://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
        ),
      );
    });

    Agent remote(String localId, String remoteId, {String name = '虾'}) => Agent(
      localId: localId,
      remoteId: remoteId,
      instanceId: 'inst-1',
      name: name,
    );

    test('tombstones agent that disappears from remote list', () async {
      await agentRepo.syncFromGateway('inst-1', [
        remote('local-a', 'r-a'),
        remote('local-b', 'r-b'),
        remote('local-c', 'r-c'),
      ]);

      // C 从远端消失
      await agentRepo.syncFromGateway('inst-1', [
        remote('local-a', 'r-a'),
        remote('local-b', 'r-b'),
      ]);

      final c = await agentRepo.getById('local-c');
      expect(c, isNotNull);
      expect(c!.isRemoved, isTrue);
      expect(c.removedAt, isNotNull);

      // A、B 仍 active
      final a = await agentRepo.getById('local-a');
      expect(a!.isRemoved, isFalse);
      final b = await agentRepo.getById('local-b');
      expect(b!.isRemoved, isFalse);
    });

    test('revives agent that reappears on remote list', () async {
      await agentRepo.syncFromGateway('inst-1', [remote('local-c', 'r-c')]);
      await agentRepo.syncFromGateway('inst-1', []); // C 被 tombstone
      expect((await agentRepo.getById('local-c'))!.isRemoved, isTrue);

      // C 在远端重新出现 → 复活
      await agentRepo.syncFromGateway('inst-1', [remote('local-c', 'r-c')]);

      final c = await agentRepo.getById('local-c');
      expect(c!.isRemoved, isFalse);
      expect(c.removedAt, isNull);
    });

    test('does not touch hidden_at column during sync diff', () async {
      await agentRepo.syncFromGateway('inst-1', [remote('local-c', 'r-c')]);

      // 手动给 hidden_at 写个值（模拟 v2 用户隐藏；v1 无写入路径，测试直接 SQL）
      await database.customStatement(
        'UPDATE agents SET hidden_at = 1719300000000 WHERE local_id = ?',
        ['local-c'],
      );

      // 触发 sync（C 仍在远端，不会被 tombstone 也不会复活）
      await agentRepo.syncFromGateway('inst-1', [remote('local-c', 'r-c')]);

      final c = await agentRepo.getById('local-c');
      expect(c!.hiddenAt, 1719300000000); // hidden_at 不被 sync 触碰
      expect(c.isRemoved, isFalse);
    });

    test('tombstones ALL agents when remote list is empty (协议契约)', () async {
      await agentRepo.syncFromGateway('inst-1', [
        remote('local-a', 'r-a'),
        remote('local-b', 'r-b'),
      ]);

      // 远端一个都没有 → 协议下唯一含义是"Gateway 真无 agent"，全部 tombstone
      await agentRepo.syncFromGateway('inst-1', []);

      final a = await agentRepo.getById('local-a');
      final b = await agentRepo.getById('local-b');
      expect(a!.isRemoved, isTrue);
      expect(b!.isRemoved, isTrue);
    });

    test(
      'preserves conversations for tombstoned agents (FK not cascaded)',
      () async {
        await agentRepo.syncFromGateway('inst-1', [remote('local-c', 'r-c')]);

        // 直接 SQL 插入一条 conversation 引用该 agent（绕开 conversation repo）
        await database.customStatement(
          'INSERT INTO conversations (id, agent_id, instance_id) VALUES (?, ?, ?)',
          ['conv-c', 'local-c', 'inst-1'],
        );

        // tombstone C
        await agentRepo.syncFromGateway('inst-1', []);

        // conversation 行仍存在（tombstone 是 UPDATE，不触发 FK CASCADE）
        final conv = await database
            .customSelect(
              'SELECT id FROM conversations WHERE id = ?',
              variables: [Variable.withString('conv-c')],
            )
            .get();
        expect(conv, isNotEmpty);
        expect(conv, isNotEmpty);
        // agent 行也仍在（只是 removed_at 非空）
        expect((await agentRepo.getById('local-c'))!.isRemoved, isTrue);
      },
    );

    test('is idempotent across repeated sync (do-while 重入不重复打标)', () async {
      await agentRepo.syncFromGateway('inst-1', [
        remote('local-a', 'r-a'),
        remote('local-c', 'r-c'),
      ]);

      // 第一次：C 消失 → tombstone
      await agentRepo.syncFromGateway('inst-1', [remote('local-a', 'r-a')]);
      final removedAt1 = (await agentRepo.getById('local-c'))!.removedAt;

      // 第二次：C 仍缺失 → 不应改写 removed_at（幂等）
      await agentRepo.syncFromGateway('inst-1', [remote('local-a', 'r-a')]);
      final removedAt2 = (await agentRepo.getById('local-c'))!.removedAt;

      expect(removedAt2, removedAt1);
    });
  });

  // US-021: 默认过滤语义。getAll / getByInstanceId 默认排除 tombstoned +
  // hidden agent；getById / findByCompositeKey 必须不过滤（OutboxProcessor
  // 与 sync 复活逻辑依赖此契约）。
  group('DriftAgentRepo default filtering (US-021)', () {
    late db.AppDatabase database;
    late DriftAgentRepo agentRepo;

    setUp(() async {
      database = await _createTestDb();
      agentRepo = DriftAgentRepo(database);
      final instanceRepo = DriftInstanceRepo(database);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'ws://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
        ),
      );
      // 插入 3 个 agent：A active, B tombstoned, C hidden(via SQL)
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-a',
          remoteId: 'r-a',
          instanceId: 'inst-1',
          name: 'A',
        ),
        Agent(
          localId: 'local-b',
          remoteId: 'r-b',
          instanceId: 'inst-1',
          name: 'B',
        ),
        Agent(
          localId: 'local-c',
          remoteId: 'r-c',
          instanceId: 'inst-1',
          name: 'C',
        ),
      ]);
      // tombstone B（远端删除）
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-a',
          remoteId: 'r-a',
          instanceId: 'inst-1',
          name: 'A',
        ),
        Agent(
          localId: 'local-c',
          remoteId: 'r-c',
          instanceId: 'inst-1',
          name: 'C',
        ),
      ]);
      // 手动隐藏 C（v1 无写入路径，测试直接 SQL）
      await database.customStatement(
        'UPDATE agents SET hidden_at = 1719300000000 WHERE local_id = ?',
        ['local-c'],
      );
    });

    test('getAll excludes tombstoned and hidden agents by default', () async {
      final all = await agentRepo.getAll();
      final ids = all.map((a) => a.localId).toSet();
      expect(ids, {'local-a'}); // 只有 A active
      expect(all.every((a) => !a.isRemoved && !a.isHidden), isTrue);
    });

    test(
      'getByInstanceId excludes tombstoned and hidden agents by default',
      () async {
        final byInst = await agentRepo.getByInstanceId('inst-1');
        final ids = byInst.map((a) => a.localId).toSet();
        expect(ids, {'local-a'});
      },
    );

    test(
      'getById returns tombstoned agent (unfiltered) — OutboxProcessor 契约',
      () async {
        final b = await agentRepo.getById('local-b');
        expect(b, isNotNull);
        expect(b!.isRemoved, isTrue);
      },
    );

    test('getById returns hidden agent (unfiltered)', () async {
      final c = await agentRepo.getById('local-c');
      expect(c, isNotNull);
      expect(c!.isHidden, isTrue);
    });

    test(
      'findByCompositeKey returns tombstoned agent (unfiltered) — sync 复活契约',
      () async {
        final b = await agentRepo.findByCompositeKey('inst-1', 'r-b');
        expect(b, isNotNull);
        expect(b!.isRemoved, isTrue);
      },
    );
  });
}
