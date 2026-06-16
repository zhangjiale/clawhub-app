import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
}
