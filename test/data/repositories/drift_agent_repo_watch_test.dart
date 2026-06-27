import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

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
  group('DriftAgentRepo.watchById', () {
    late db.AppDatabase database;
    late DriftAgentRepo agentRepo;
    late DriftInstanceRepo instanceRepo;

    setUp(() async {
      database = await _createTestDb();
      agentRepo = DriftAgentRepo(database);
      instanceRepo = DriftInstanceRepo(database);

      // Need an instance first for FK
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

    test('subscribe emits current agent as seed event', () async {
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      final stream = agentRepo.watchById('local-1');
      final emitted = await stream.first;

      expect(emitted, isNotNull);
      expect(emitted!.localId, 'local-1');
    });

    test('subscribe to nonexistent localId emits null', () async {
      final stream = agentRepo.watchById('nonexistent');
      final emitted = await stream.first;

      expect(emitted, isNull);
    });

    test('updateFullProfile emits agent with new quickCommands', () async {
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      // Skip seed (first emit is current state)
      final emitted = <Agent?>[];
      final sub = agentRepo.watchById('local-1').skip(1).listen(emitted.add);

      await agentRepo.updateFullProfile(
        'local-1',
        quickCommands: [
          QuickCommand(
            id: 'c1',
            agentId: 'local-1',
            label: '状态',
            payload: '/status',
            sortOrder: 0,
          ),
        ],
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last, isNotNull);
      expect(emitted.last!.quickCommands.length, 1);
      expect(emitted.last!.quickCommands.first.payload, '/status');
    });

    test('clearAvatar emits agent with avatarUrl=null', () async {
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
          avatarUrl: '/path/to/avatar.png',
        ),
      ]);

      final emitted = <Agent?>[];
      final sub = agentRepo.watchById('local-1').skip(1).listen(emitted.add);

      await agentRepo.clearAvatar('local-1');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last, isNotNull);
      expect(emitted.last!.avatarUrl, isNull);
    });
  });
}
