// US-021 E2E: Agent tombstone 完整生命周期（真实 DriftAgentRepo + in-memory SQLite）。
// 覆盖 spec §5.7 的 5 步：sync 建立 → tombstone → (outbox skip 见 outbox_processor_test)
// → 复活 → 清空。outbox skip 行为已在 outbox_processor_test 单测覆盖，此处聚焦
// sync diff + 默认过滤 + 复活 + 空列表的端到端正确性。
//
// 第二组 ChatRoom tombstone placeholder flow 是 Task 5 新增的端到端集成测试，
// 跨 sync → outbox flush（EXPIRED）→ search filter → ChatViewModel
// 四个子系统。UI 层的占位页渲染（ChatRoomPage / AgentProfilePage）有独立的
// widget test 覆盖，本测试只验证 ViewModel/Provider 层数据契约：tombstone
// 之后 state.isAgentRemoved=true 且对应搜索/发送路径都被正确过滤/转换。
// 整个 test/integration/ 目录用 `flutter test test/integration/` 单独运行。
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_conversation_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/data/repositories/drift_message_repo.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/usecases/outbox_processor.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/features/search/viewmodels/search_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';

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
    // MockGatewayClient.loadMockData 在 init 时尝试 load 资产 → 需要
    // TestWidgetsFlutterBinding。ChatViewModel._init 调
    // fetchMessageHistory 触发此路径。
    TestWidgetsFlutterBinding.ensureInitialized();
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

  // ===========================================================================
  // Task 5 (US-021 v1.1): 端到端 tombstone 流程跨 sync → outbox EXPIRED → search filter
  // → ChatViewModel.isAgentRemoved 三个子系统一起验证。占位页 widget 渲染由
  // chat_room_page_test / agent_profile_page_test / agent_config_page_test 各自的
  // widget test 覆盖，本测试只验证 ViewModel/Provider 层数据契约。
  //
  // 注：package:test_api 的 @Tags 仅 @Target library level，不能贴在单个 test。
  // 整个 integration/ 目录默认只在此套件下执行，可通过
  // `flutter test test/integration/` 选择性跑，或在 CI 中按目录过滤。
  // ===========================================================================
  group('ChatRoom tombstone placeholder flow', () {
    test(
      'end-to-end: sync [A,B] → PENDING message → tombstone A → outbox EXPIRED → '
      'search filters tombstoned → ChatViewModel.isAgentRemoved flips to true',
      () async {
        // ---- 1. Initial sync with [A, B] creates active agents ----
        gateway.agents = [_remote('local-a', 'r-a'), _remote('local-b', 'r-b')];
        await agentRepo.syncFromGateway('inst-1', gateway.agents);
        expect(
          (await agentRepo.getAll()).length,
          2,
          reason: 'sync [A,B] 应建立 2 个 active agent',
        );
        final aBefore = await agentRepo.getById('local-a');
        expect(aBefore!.isRemoved, isFalse);

        // 用真实 Drift repo 插入 PENDING 消息（A 还在）
        final messageRepo = DriftMessageRepo(database);
        final conversationRepo = DriftConversationRepo(database);
        // 先把 A 和 B 的 conversation 行建好（FK 约束要求消息必须挂在
        // 已存在的 conversation 下；getOrCreate 不依赖 agent 是否被 tombstone）
        await conversationRepo.getOrCreate('inst-1', 'local-a');
        await conversationRepo.getOrCreate('inst-1', 'local-b');
        final pendingMsg = Message(
          clientId: 'msg-pending-a',
          conversationId: Conversation.generateId('inst-1', 'local-a'),
          agentId: 'local-a',
          role: MessageRole.user,
          content: 'hello A before tombstone',
          type: MessageType.text,
          status: MessageStatus.pending,
          logicalClock: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        await messageRepo.insert(pendingMsg);
        // 验证消息确实是 PENDING（sync tombstone 后才能被 EXPIRED）
        final fetched = await messageRepo.getByClientId('msg-pending-a');
        expect(fetched, isNotNull);
        expect(fetched!.status, MessageStatus.pending);

        // ---- 2 & 3. Sync with [B] only → A tombstoned ----
        gateway.agents = [_remote('local-b', 'r-b')];
        await agentRepo.syncFromGateway('inst-1', gateway.agents);
        final aAfter = await agentRepo.getById('local-a');
        expect(
          aAfter,
          isNotNull,
          reason: 'tombstoned agent 行仍在 DB（getById 不过滤 US-021 契约）',
        );
        expect(aAfter!.isRemoved, isTrue);
        expect(
          (await agentRepo.getAll()).length,
          1,
          reason: 'getAll 默认过滤 tombstoned → 只剩 B',
        );

        // ---- 4. OutboxProcessor flush → PENDING → EXPIRED ----
        // 用真实 Drift repos + Mock Gateway（OutboxProcessor flush 实际跑
        // tombstoned-skip → updateStatus(EXPIRED) 分支）
        final sendUseCase = SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: DriftInstanceRepo(database),
          gatewayClient: MockGatewayClient(),
        );
        final outbox = OutboxProcessor(
          messageRepo: messageRepo,
          instanceRepo: DriftInstanceRepo(database),
          agentRepo: agentRepo,
          sendMessageUseCase: sendUseCase,
          logger: _SilentLogger(),
        );
        final sent = await outbox.flushOutbox('inst-1');
        expect(sent, 0, reason: 'tombstoned agent 不应发送任何消息');

        // 关键断言：tombstoned-agent 的 PENDING 消息已被 OutboxProcessor 转为 EXPIRED
        final expired = await messageRepo.getByClientId('msg-pending-a');
        expect(expired, isNotNull);
        expect(
          expired!.status,
          MessageStatus.expired,
          reason:
              'tombstoned agent 的 PENDING 消息必须被 OutboxProcessor 转为 '
              'EXPIRED（避免 24h PENDING 卡死计数）',
        );

        // ---- 5. Search filters tombstoned agents ----
        // 用真实的 DriftAgentRepo（getByIds 不过滤 tombstoned，SearchViewModel
        // 在 _executeSearch 里做 isRemoved 过滤 —— 等价于 production 路径）
        final searchVm = SearchViewModel(
          messageRepo: messageRepo,
          agentRepo: agentRepo,
          conversationRepo: conversationRepo,
        );
        // 重建一条属于 A 的消息（A 已 tombstone）以制造可搜索文本
        final msgA = Message(
          clientId: 'msg-search-a',
          conversationId: Conversation.generateId('inst-1', 'local-a'),
          agentId: 'local-a',
          role: MessageRole.user,
          content: 'findme tombstoned',
          type: MessageType.text,
          status: MessageStatus.sent,
          logicalClock: 2,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        await messageRepo.insert(msgA);
        final msgB = Message(
          clientId: 'msg-search-b',
          conversationId: Conversation.generateId('inst-1', 'local-b'),
          agentId: 'local-b',
          role: MessageRole.user,
          content: 'findme alive',
          type: MessageType.text,
          status: MessageStatus.sent,
          logicalClock: 3,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        await messageRepo.insert(msgB);

        searchVm.onQueryChanged('findme');
        // 等 debounce (300ms) + execute
        await Future<void>.delayed(const Duration(milliseconds: 400));

        final results = switch (searchVm.state.results) {
          LoadData(:final value) => value,
          _ => <Object>[],
        };
        expect(
          results.length,
          1,
          reason:
              '搜索 "findme" 应只返回 alive agent (B) 的结果，'
              'tombstoned agent (A) 的消息被过滤',
        );
        expect(
          (results.first as dynamic).agentId,
          'local-b',
          reason: 'tombstoned agent (A) 必须从搜索结果过滤',
        );
        expect(
          results.any((r) => (r as dynamic).agentId == 'local-a'),
          isFalse,
          reason: 'A 已 tombstone，搜索结果不应包含 A 的消息',
        );
        searchVm.dispose();

        // ---- 6. ChatViewModel.isAgentRemoved flips to true after tombstone ----
        // 用真实 DriftAgentRepo + InMemoryConversationRepo（VM.init 不需要
        // 真实 conversation 表） + MockGatewayClient（避免开真实 WebSocket）。
        // 关键路径：refreshAgent() 重查 DriftAgentRepo.getById → 拿到
        // isRemoved=true → _syncAgentRemoved() → state.isAgentRemoved=true。
        final chatVm = ChatViewModel(
          agentRepo: agentRepo,
          conversationRepo: InMemoryConversationRepo(),
          messageRepo: InMemoryMessageRepo(),
          instanceRepo: DriftInstanceRepo(database),
          gatewayClient: MockGatewayClient(),
          sendMessageUseCase: SendMessageUseCase(
            messageRepo: InMemoryMessageRepo(),
            conversationRepo: InMemoryConversationRepo(),
            instanceRepo: DriftInstanceRepo(database),
            gatewayClient: MockGatewayClient(),
          ),
          achievementChecker: _NoopAchievementChecker(),
          instanceId: 'inst-1',
          agentId: 'local-a',
        );
        await chatVm.init();
        // init() 走 _agentRepo.getById → 拿到已 tombstone 的 agent
        // → _syncAgentRemoved() → state.isAgentRemoved = true
        expect(
          chatVm.state.isAgentRemoved,
          isTrue,
          reason:
              'ChatViewModel.init() 后 state.isAgentRemoved 必须同步 '
              'DriftAgentRepo 中 A 的 tombstone 状态（AC8 占位页契约）',
        );
        chatVm.dispose();
      },
    );
  });
}

/// 不输出日志的 ILogger — 避免 OutboxProcessor 在测试中产生噪音。
class _SilentLogger implements ILogger {
  @override
  void info(String message) {}
  @override
  void error(String message, [StackTrace? stackTrace]) {}
}

/// ChatViewModel 的 IAchievementChecker 是 fire-and-forget 空实现，
/// 直接吞掉调用即可。
class _NoopAchievementChecker implements IAchievementChecker {
  @override
  void check(String agentId) {}
}
