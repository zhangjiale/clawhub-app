import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_conversation_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';

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

/// Law 17: Drift repo getByIds batch 查询测试。
void main() {
  // ---------------------------------------------------------------------------
  // DriftAgentRepo.getByIds
  // ---------------------------------------------------------------------------
  group('DriftAgentRepo.getByIds', () {
    late db.AppDatabase database;
    late DriftAgentRepo agentRepo;

    setUp(() async {
      database = await _createTestDb();
      agentRepo = DriftAgentRepo(database);

      // Seed instance for FK
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

    test('returns empty map for empty list', () async {
      final result = await agentRepo.getByIds([]);
      expect(result, isEmpty);
    });

    test('returns empty map when no IDs match', () async {
      final result = await agentRepo.getByIds(['non-existent-1', 'nope-2']);
      expect(result, isEmpty);
    });

    test('returns single agent by ID', () async {
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'remote-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6C8AAF',
        ),
      ]);

      final result = await agentRepo.getByIds(['local-1']);
      expect(result.length, 1);
      expect(result['local-1']!.name, '产品虾');
      expect(result['local-1']!.themeColor, '#6C8AAF');
    });

    test('returns multiple agents by IDs', () async {
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-a',
          remoteId: 'remote-a',
          instanceId: 'inst-1',
          name: 'Agent A',
          themeColor: '#FF0000',
        ),
        Agent(
          localId: 'local-b',
          remoteId: 'remote-b',
          instanceId: 'inst-1',
          name: 'Agent B',
          themeColor: '#00FF00',
        ),
        Agent(
          localId: 'local-c',
          remoteId: 'remote-c',
          instanceId: 'inst-1',
          name: 'Agent C',
          themeColor: '#0000FF',
        ),
      ]);

      final result = await agentRepo.getByIds(['local-a', 'local-c']);
      expect(result.length, 2);
      expect(result['local-a']!.name, 'Agent A');
      expect(result['local-c']!.name, 'Agent C');
      expect(result.containsKey('local-b'), isFalse);
    });

    test('returns only matching IDs (partial match)', () async {
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'exists-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: 'Exists',
          themeColor: '#111111',
        ),
      ]);

      final result = await agentRepo.getByIds(['exists-1', 'missing-1']);
      expect(result.length, 1);
      expect(result['exists-1']!.name, 'Exists');
    });
  });

  // ---------------------------------------------------------------------------
  // DriftConversationRepo.getByIds
  // ---------------------------------------------------------------------------
  group('DriftConversationRepo.getByIds', () {
    late db.AppDatabase database;
    late DriftConversationRepo conversationRepo;
    late DriftAgentRepo agentRepo;

    setUp(() async {
      database = await _createTestDb();
      conversationRepo = DriftConversationRepo(database);
      agentRepo = DriftAgentRepo(database);

      // Seed instance for FK
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
      // Seed agents so conversation FK (agent_id) is satisfied
      for (final id in ['agent-1', 'agent-a', 'agent-b', 'agent-x']) {
        await agentRepo.syncFromGateway('inst-1', [
          Agent(
            localId: id,
            remoteId: 'remote-$id',
            instanceId: 'inst-1',
            name: 'Agent $id',
            themeColor: '#111111',
          ),
        ]);
      }
    });

    test('returns empty map for empty list', () async {
      final result = await conversationRepo.getByIds([]);
      expect(result, isEmpty);
    });

    test('returns empty map when no IDs match', () async {
      final result = await conversationRepo.getByIds(['no-such-id']);
      expect(result, isEmpty);
    });

    test('returns conversation by ID', () async {
      final conv = await conversationRepo.getOrCreate('inst-1', 'agent-1');
      final result = await conversationRepo.getByIds([conv.id]);
      expect(result.length, 1);
      expect(result[conv.id]!.instanceId, 'inst-1');
      expect(result[conv.id]!.agentId, 'agent-1');
    });

    test('returns multiple conversations by IDs', () async {
      final conv1 = await conversationRepo.getOrCreate('inst-1', 'agent-a');
      final conv2 = await conversationRepo.getOrCreate('inst-1', 'agent-b');

      final result = await conversationRepo.getByIds([conv1.id, conv2.id]);
      expect(result.length, 2);
      expect(result[conv1.id]!.agentId, 'agent-a');
      expect(result[conv2.id]!.agentId, 'agent-b');
    });

    test('returns only matching IDs (partial match)', () async {
      final conv = await conversationRepo.getOrCreate('inst-1', 'agent-x');
      final result = await conversationRepo.getByIds([conv.id, 'fake-id']);
      expect(result.length, 1);
      expect(result[conv.id]!.agentId, 'agent-x');
    });
  });

  // ---------------------------------------------------------------------------
  // DriftInstanceRepo.getByIds (US-021 N+1 修复)
  // ---------------------------------------------------------------------------
  group('DriftInstanceRepo.getByIds', () {
    late db.AppDatabase database;
    late DriftInstanceRepo instanceRepo;

    Future<void> seedInstance(String id, String name) async {
      await instanceRepo.save(
        Instance(
          id: id,
          name: name,
          gatewayUrl: 'wss://$id.test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
        ),
      );
    }

    setUp(() async {
      database = await _createTestDb();
      instanceRepo = DriftInstanceRepo(database);
    });

    test('returns empty map for empty list', () async {
      final result = await instanceRepo.getByIds([]);
      expect(result, isEmpty);
    });

    test('returns empty map when no IDs match', () async {
      final result = await instanceRepo.getByIds(['ghost-1', 'ghost-2']);
      expect(result, isEmpty);
    });

    test('returns single instance by ID', () async {
      await seedInstance('inst-1', 'A');
      final result = await instanceRepo.getByIds(['inst-1']);
      expect(result.length, 1);
      expect(result['inst-1']!.name, 'A');
    });

    test('returns multiple instances by IDs', () async {
      await seedInstance('inst-a', 'A');
      await seedInstance('inst-b', 'B');
      await seedInstance('inst-c', 'C');

      final result = await instanceRepo.getByIds(['inst-a', 'inst-c']);
      expect(result.length, 2);
      expect(result['inst-a']!.name, 'A');
      expect(result['inst-c']!.name, 'C');
      expect(result.containsKey('inst-b'), isFalse);
    });

    test('returns only matching IDs (partial match)', () async {
      await seedInstance('exists-1', 'Exists');
      final result = await instanceRepo.getByIds(['exists-1', 'missing-1']);
      expect(result.length, 1);
      expect(result['exists-1']!.name, 'Exists');
    });
  });
}
