// US-021 E2E: Agent tombstone 完整生命周期（真实 DriftAgentRepo + in-memory SQLite）。
// 覆盖 spec §5.7 的 5 步：sync 建立 → tombstone → (outbox skip 见 outbox_processor_test)
// → 复活 → 清空。outbox skip 行为已在 outbox_processor_test 单测覆盖，此处聚焦
// sync diff + 默认过滤 + 复活 + 空列表的端到端正确性。
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/tool_call.dart';

/// 可变 fetchAgents 返回值的 IGatewayClient stub（其他方法 throw，本测试不用）。
class _MutableFetchGatewayClient implements IGatewayClient {
  List<Agent> agents = const [];
  @override
  Future<List<Agent>> fetchAgents(String instanceId) async => agents;

  @override
  Future<void> connect(Instance instance) => throw UnimplementedError();
  @override
  Future<void> disconnect(String instanceId) => throw UnimplementedError();
  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) => throw UnimplementedError();
  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) => throw UnimplementedError();
  @override
  Future<bool> testConnection(Instance instance) => throw UnimplementedError();
  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) =>
      throw UnimplementedError();
  @override
  void resetConnectionState(String instanceId) => throw UnimplementedError();
  @override
  Stream<Message> messageStream(String instanceId) =>
      throw UnimplementedError();
  @override
  Stream<ToolCall> toolCallStream(String instanceId) =>
      throw UnimplementedError();
  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId) =>
      throw UnimplementedError();
  @override
  Future<void> dispose() async {}
  @override
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) =>
      throw UnimplementedError();
}

Future<db.AppDatabase> _createDb() async {
  final database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (sqlDb) => sqlDb.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  addTearDown(() => database.close());
  return database;
}

Agent _remote(String localId, String remoteId) => Agent(
  localId: localId,
  remoteId: remoteId,
  instanceId: 'inst-1',
  name: '虾-$remoteId',
);

void main() {
  late db.AppDatabase database;
  late DriftAgentRepo agentRepo;
  late _MutableFetchGatewayClient gateway;

  setUp(() async {
    database = await _createDb();
    agentRepo = DriftAgentRepo(database);
    gateway = _MutableFetchGatewayClient();
    await DriftInstanceRepo(database).save(
      Instance(
        id: 'inst-1',
        name: 'Test',
        gatewayUrl: 'ws://test:18789',
        tokenRef: 'tok',
        healthStatus: HealthStatus.online,
      ),
    );
  });

  test(
    'US-021 tombstone lifecycle: sync → tombstone → revive → empty',
    () async {
      // 1. sync [A, B, C] → 3 active
      gateway.agents = [
        _remote('local-a', 'r-a'),
        _remote('local-b', 'r-b'),
        _remote('local-c', 'r-c'),
      ];
      await agentRepo.syncFromGateway('inst-1', gateway.agents);
      expect((await agentRepo.getAll()).length, 3);

      // 2. sync [A, B] → C tombstoned, getAll 返回 2
      gateway.agents = [_remote('local-a', 'r-a'), _remote('local-b', 'r-b')];
      await agentRepo.syncFromGateway('inst-1', gateway.agents);
      expect((await agentRepo.getAll()).length, 2);
      final c = await agentRepo.getById('local-c');
      expect(c!.isRemoved, isTrue);
      // C 的历史 conversation 仍可查（FK 未级联）—— getById 不过滤
      expect(c, isNotNull);

      // 4. sync [A, B, C] → C 复活，getAll 返回 3
      gateway.agents = [
        _remote('local-a', 'r-a'),
        _remote('local-b', 'r-b'),
        _remote('local-c', 'r-c'),
      ];
      await agentRepo.syncFromGateway('inst-1', gateway.agents);
      expect((await agentRepo.getAll()).length, 3);
      expect((await agentRepo.getById('local-c'))!.isRemoved, isFalse);

      // 5. sync [] → 全部 tombstone，getAll 返回 0，agent 行仍在 DB（getById 可查）
      gateway.agents = [];
      await agentRepo.syncFromGateway('inst-1', gateway.agents);
      expect((await agentRepo.getAll()).length, 0);
      expect((await agentRepo.getById('local-a'))!.isRemoved, isTrue);
      expect((await agentRepo.getById('local-b'))!.isRemoved, isTrue);
      expect((await agentRepo.getById('local-c'))!.isRemoved, isTrue);
    },
  );

  test(
    'US-021 tombstone preserves conversations across tombstone→revive cycle',
    () async {
      // 建立 A，插入一条 conversation 引用 A
      gateway.agents = [_remote('local-a', 'r-a')];
      await agentRepo.syncFromGateway('inst-1', gateway.agents);
      await database.customStatement(
        'INSERT INTO conversations (id, agent_id, instance_id) VALUES (?, ?, ?)',
        ['conv-a', 'local-a', 'inst-1'],
      );

      // tombstone A
      gateway.agents = [];
      await agentRepo.syncFromGateway('inst-1', gateway.agents);
      // conversation 仍在
      var conv = await database
          .customSelect(
            'SELECT id FROM conversations WHERE id = ?',
            variables: [Variable.withString('conv-a')],
          )
          .get();
      expect(conv, isNotEmpty);

      // 复活 A
      gateway.agents = [_remote('local-a', 'r-a')];
      await agentRepo.syncFromGateway('inst-1', gateway.agents);
      // conversation 仍在（tombstone/复活都不碰 conversations 表）
      conv = await database
          .customSelect(
            'SELECT id FROM conversations WHERE id = ?',
            variables: [Variable.withString('conv-a')],
          )
          .get();
      expect(conv, isNotEmpty);
      expect((await agentRepo.getById('local-a'))!.isRemoved, isFalse);
    },
  );
}
