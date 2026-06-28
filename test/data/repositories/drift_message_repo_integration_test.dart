import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_message_repo.dart';
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_conversation_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';

/// Helper to create an in-memory AppDatabase.
///
/// Mirrors the production [createAppDatabase] setup to ensure the FTS5
/// virtual table exists, so that integration tests actually exercise the
/// real FTS5 sync path (not just the try-catch fallback).
Future<db.AppDatabase> _createTestDb() async {
  final database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (sqlDb) {
        sqlDb.execute('PRAGMA foreign_keys = ON');
        sqlDb.execute('PRAGMA journal_mode = WAL');

        // Mirror production — create FTS5 virtual table so the real
        // sync path (INSERT INTO messages_fts) is exercised.
        sqlDb.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
          content,
          content='messages',
          content_rowid='rowid'
        )
      ''');
      },
    ),
  );
  addTearDown(() => database.close());
  return database;
}

void main() {
  group('DriftMessageRepo send-message integration', () {
    late db.AppDatabase database;
    late DriftMessageRepo messageRepo;
    late DriftConversationRepo conversationRepo;
    late DriftAgentRepo agentRepo;
    late DriftInstanceRepo instanceRepo;
    late MockGatewayClient gateway;
    late SendMessageUseCase sendMessageUseCase;

    setUp(() async {
      database = await _createTestDb();
      messageRepo = DriftMessageRepo(database);
      conversationRepo = DriftConversationRepo(database);
      agentRepo = DriftAgentRepo(database);
      instanceRepo = DriftInstanceRepo(database);
      gateway = MockGatewayClient();
      sendMessageUseCase = SendMessageUseCase(
        messageRepo: messageRepo,
        conversationRepo: conversationRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
      );
    });

    test(
      'inserts and retrieves a message via Drift (FTS5 path covered)',
      () async {
        // Setup: create instance and agent (prerequisites for send)
        final instance = Instance(
          id: 'inst-1',
          name: 'Test Instance',
          gatewayUrl: 'wss://test.example.com:443',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        );
        final agent = Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: 'TestAgent',
          themeColor: '#007AFF',
        );

        await instanceRepo.save(instance);
        await agentRepo.syncFromGateway('inst-1', [agent]);

        // Act: send a message through the real Drift pipeline
        final message = await sendMessageUseCase.execute(
          instanceId: 'inst-1',
          agent: agent,
          content: 'Hello Drift!',
          type: MessageType.text,
        );

        // Assert: message was persisted and is retrievable
        expect(message.clientId, isNotEmpty);
        expect(message.content, 'Hello Drift!');
        expect(message.role, MessageRole.user);

        final conversationId = Conversation.generateId('inst-1', 'local-1');
        final loaded = await messageRepo.getByConversation(conversationId);
        expect(
          loaded.any((m) => m.clientId == message.clientId),
          isTrue,
          reason: 'Message should be retrievable from Drift after insert',
        );

        // Verify the message status is set (gateway sends, so it should be SENT)
        final reloaded = await messageRepo.getByClientId(message.clientId);
        expect(reloaded, isNotNull);
        // With MockGateway + online instance, status should progress to SENT
        expect(
          reloaded!.status,
          MessageStatus.sent,
          reason: 'Status should be SENT after gateway ACK',
        );

        // Verify FTS5 index is populated (proves the real FTS5 path, not the
        // try-catch fallback, was exercised during insert)
        final ftsResults = await database.searchMessagesSanitized(
          'Hello Drift!',
        );
        expect(
          ftsResults.any((m) => m.clientId == message.clientId),
          isTrue,
          reason: 'Message must be findable via FTS5 search',
        );
      },
    );

    test('FTS sync failure does NOT prevent message persistence', () async {
      // Setup: drop the FTS table to simulate a corrupt or missing index
      // (the table now actually exists thanks to _createTestDb's setup,
      // so this exercises a real DROP + re-insert failure path)
      await database.customStatement('DROP TABLE IF EXISTS messages_fts');

      // Setup instance and agent
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://t.example.com:443',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: 'Agent',
          themeColor: '#000',
        ),
      ]);

      final agent = (await agentRepo.getById('local-1'))!;

      // Act: send a message while FTS table is missing
      final message = await sendMessageUseCase.execute(
        instanceId: 'inst-1',
        agent: agent,
        content: 'Should persist despite FTS failure',
        type: MessageType.text,
      );

      // Assert: message was persisted even though FTS sync failed
      expect(message.clientId, isNotEmpty);
      final loaded = await messageRepo.getByClientId(message.clientId);
      expect(
        loaded,
        isNotNull,
        reason: 'Message MUST persist even when FTS sync fails',
      );
      expect(loaded!.content, 'Should persist despite FTS failure');
    });

    test('message inserted with correct fields via Drift pipeline', () async {
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://t.example.com:443',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: 'Agent',
          themeColor: '#000',
        ),
      ]);
      final agent = (await agentRepo.getById('local-1'))!;

      final message = await sendMessageUseCase.execute(
        instanceId: 'inst-1',
        agent: agent,
        content: 'Field check',
        type: MessageType.text,
      );

      final reloaded = await messageRepo.getByClientId(message.clientId);
      expect(reloaded, isNotNull);

      // Spot-check all critical fields round-tripped correctly
      expect(reloaded!.clientId, message.clientId);
      expect(
        reloaded.conversationId,
        Conversation.generateId('inst-1', 'local-1'),
      );
      expect(reloaded.agentId, 'local-1');
      expect(reloaded.role, MessageRole.user);
      expect(reloaded.content, 'Field check');
      expect(reloaded.type, MessageType.text);
      // Status should be SENT (MockGateway ACK), not stuck at PENDING
      expect(reloaded.status, MessageStatus.sent);
    });
  });

  group('DriftMessageRepo batchInsertByIndexedIds', () {
    late db.AppDatabase database;
    late DriftMessageRepo messageRepo;
    late DriftConversationRepo conversationRepo;
    late DriftAgentRepo agentRepo;
    late DriftInstanceRepo instanceRepo;
    late String conversationId;

    setUp(() async {
      database = await _createTestDb();
      messageRepo = DriftMessageRepo(database);
      conversationRepo = DriftConversationRepo(database);
      agentRepo = DriftAgentRepo(database);
      instanceRepo = DriftInstanceRepo(database);

      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://t.example.com:443',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: 'Agent',
          themeColor: '#000',
        ),
      ]);
      await conversationRepo.getOrCreate('inst-1', 'local-1');
      conversationId = Conversation.generateId('inst-1', 'local-1');
    });

    Message makeMsg({
      required String clientId,
      String? serverId,
      String content = 'hello',
      int clock = 0,
    }) {
      return Message(
        clientId: clientId,
        serverId: serverId,
        conversationId: conversationId,
        agentId: 'local-1',
        role: MessageRole.agent,
        content: content,
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: clock,
      );
    }

    test('inserts all-new messages and indexes them for FTS5', () async {
      final msgs = [
        for (var i = 0; i < 50; i++)
          makeMsg(clientId: 'c$i', serverId: 's$i', content: 'content $i'),
      ];

      final inserted = await messageRepo.batchInsertByIndexedIds(msgs);

      expect(inserted.length, 50);
      // All 50 persisted.
      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 50);

      // FTS5 indexes every inserted message — batch sync path exercised.
      // searchMessagesSanitized caps at limit (default 20), so verify a
      // high-indexed message is findable rather than counting all 50.
      final lateHit = await database.searchMessagesSanitized('content 49');
      expect(
        lateHit,
        isNotEmpty,
        reason: 'last-inserted message must be FTS-indexed',
      );
      final earlyHit = await database.searchMessagesSanitized('content 0');
      expect(
        earlyHit,
        isNotEmpty,
        reason: 'first-inserted message must be FTS-indexed',
      );
    });

    test('dedup skips messages with existing clientId', () async {
      // Pre-insert one via the single-row path.
      await messageRepo.insert(makeMsg(clientId: 'c0', serverId: 's0'));

      final msgs = [
        makeMsg(clientId: 'c0', serverId: 's0'), // dup by both ids
        makeMsg(clientId: 'c1', serverId: 's1'), // new
      ];

      final inserted = await messageRepo.batchInsertByIndexedIds(msgs);

      expect(inserted.length, 1);
      expect(inserted.single.clientId, 'c1');
      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 2); // c0 (pre-inserted) + c1
    });

    test('dedup skips messages with existing serverId only', () async {
      // Pre-insert c0 with serverId s0.
      await messageRepo.insert(makeMsg(clientId: 'c0', serverId: 's0'));

      // Different clientId, SAME serverId → must dedup by serverId.
      final msgs = [makeMsg(clientId: 'c-new', serverId: 's0')];

      final inserted = await messageRepo.batchInsertByIndexedIds(msgs);

      expect(inserted, isEmpty, reason: 'serverId collision must skip insert');
      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 1);
      expect(all.single.clientId, 'c0');
    });

    test('empty input is a no-op', () async {
      final inserted = await messageRepo.batchInsertByIndexedIds([]);
      expect(inserted, isEmpty);
      final all = await messageRepo.getByConversation(conversationId);
      expect(all, isEmpty);
    });

    test('FTS failure does not block batch persistence', () async {
      // Drop the FTS table so the batch FTS sync fails.
      await database.customStatement('DROP TABLE IF EXISTS messages_fts');

      final msgs = [
        makeMsg(clientId: 'c0', serverId: 's0', content: 'survives fts fail'),
      ];

      final inserted = await messageRepo.batchInsertByIndexedIds(msgs);

      expect(inserted.length, 1);
      final loaded = await messageRepo.getByClientId('c0');
      expect(
        loaded,
        isNotNull,
        reason: 'Messages MUST persist even when batch FTS sync fails',
      );
      expect(loaded!.content, 'survives fts fail');
    });

    test('intra-batch duplicate clientIds do not crash the batch', () async {
      // Same clientId twice in one batch — must dedup internally, not hit
      // a UNIQUE constraint that aborts the whole INSERT.
      final msgs = [
        makeMsg(clientId: 'dup', serverId: 's0', content: 'first'),
        makeMsg(clientId: 'dup', serverId: 's1', content: 'second'),
      ];

      final inserted = await messageRepo.batchInsertByIndexedIds(msgs);

      expect(inserted.length, 1, reason: 'intra-batch dup collapsed to one');
      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 1);
    });
  });

  // ===========================================================================
  // Bug #2 修复补强: dedupeConversation — 清理历史遗留的重复行。
  // 旧 CatchUp 用 batchInsertByIndexedIds(仅身份去重)在每次重启都把已发
  // user 消息 / agent 回复再插一行 → DB 累积重复。merge 修复了"不再新增",
  // 本方法清理"已存在的"重复: 按 (role, content, ±60s, type=text+非空) 聚簇,
  // 每簇保留一行(优先有 serverId 的),删除其余,并同步 FTS5。
  // ===========================================================================
  group('DriftMessageRepo.dedupeConversation (Bug #2 cleanup)', () {
    late db.AppDatabase database;
    late DriftMessageRepo messageRepo;
    late String conversationId;

    setUp(() async {
      database = await _createTestDb();
      messageRepo = DriftMessageRepo(database);
      final instanceRepo = DriftInstanceRepo(database);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://t.example.com:443',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );
      final agentRepo = DriftAgentRepo(database);
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: 'Agent',
          themeColor: '#000',
        ),
      ]);
      final conversationRepo = DriftConversationRepo(database);
      await conversationRepo.getOrCreate('inst-1', 'local-1');
      conversationId = Conversation.generateId('inst-1', 'local-1');
    });

    Message makeMsg({
      required String clientId,
      String? serverId,
      required MessageRole role,
      String? content = 'hello',
      required int timestamp,
      int clock = 0,
    }) {
      return Message(
        clientId: clientId,
        serverId: serverId,
        conversationId: conversationId,
        agentId: 'local-1',
        role: role,
        content: content,
        type: MessageType.text,
        status: role == MessageRole.user
            ? MessageStatus.sent
            : MessageStatus.delivered,
        logicalClock: clock,
        timestamp: timestamp,
      );
    }

    test('removes duplicate rows with same role+content within ±60s', () async {
      await messageRepo.insert(
        makeMsg(
          clientId: 'local-uuid',
          serverId: 'runid-junk',
          role: MessageRole.user,
          content: '你好',
          timestamp: 1718000000000,
          clock: 100,
        ),
      );
      await messageRepo.insert(
        makeMsg(
          clientId: 'history-cid',
          serverId: 'gateway-msg-id',
          role: MessageRole.user,
          content: '你好',
          timestamp: 1718000002000,
          clock: 101,
        ),
      );

      final deleted = await messageRepo.dedupeConversation(conversationId);

      expect(deleted, 1, reason: '应删除 1 个重复行,保留 1 个');
      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 1);
      // 保留行的内容正确(具体保留哪一行由 keeper 规则决定,不影响正确性
      // —— 未来历史回传会经 softMatch 再次去重)。
      expect(all.single.content, '你好');
    });

    test('keeps the row with serverId when both have one', () async {
      await messageRepo.insert(
        makeMsg(
          clientId: 'c1',
          serverId: 'srv-a',
          role: MessageRole.agent,
          content: 'reply',
          timestamp: 1718000000000,
          clock: 100,
        ),
      );
      await messageRepo.insert(
        makeMsg(
          clientId: 'c2',
          serverId: null,
          role: MessageRole.agent,
          content: 'reply',
          timestamp: 1718000003000,
          clock: 101,
        ),
      );

      await messageRepo.dedupeConversation(conversationId);

      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 1);
      expect(all.single.serverId, 'srv-a', reason: '优先保留有 serverId 的行');
    });

    test('does NOT merge same-content messages >60s apart', () async {
      await messageRepo.insert(
        makeMsg(
          clientId: 'c1',
          serverId: 's1',
          role: MessageRole.user,
          content: '好的',
          timestamp: 1718000000000,
          clock: 100,
        ),
      );
      await messageRepo.insert(
        makeMsg(
          clientId: 'c2',
          serverId: 's2',
          role: MessageRole.user,
          content: '好的',
          timestamp: 1718000000000 + 120000,
          clock: 200,
        ),
      );

      final deleted = await messageRepo.dedupeConversation(conversationId);

      expect(deleted, 0, reason: '相距 >60s 的相同内容是两条不同消息,不合并');
      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 2);
    });

    test('does NOT merge same-content across different roles', () async {
      await messageRepo.insert(
        makeMsg(
          clientId: 'c1',
          serverId: 's1',
          role: MessageRole.user,
          content: '好的',
          timestamp: 1718000000000,
          clock: 100,
        ),
      );
      await messageRepo.insert(
        makeMsg(
          clientId: 'c2',
          serverId: 's2',
          role: MessageRole.agent,
          content: '好的',
          timestamp: 1718000001000,
          clock: 101,
        ),
      );

      final deleted = await messageRepo.dedupeConversation(conversationId);

      expect(deleted, 0, reason: '不同 role 的相同内容不合并');
      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 2);
    });

    test('preserves distinct messages and FTS search still works', () async {
      await messageRepo.insert(
        makeMsg(
          clientId: 'c1',
          serverId: 's1',
          role: MessageRole.user,
          content: '你好',
          timestamp: 1718000000000,
          clock: 100,
        ),
      );
      await messageRepo.insert(
        makeMsg(
          clientId: 'c2',
          serverId: 's2',
          role: MessageRole.user,
          content: '你好',
          timestamp: 1718000002000,
          clock: 101,
        ),
      );
      await messageRepo.insert(
        makeMsg(
          clientId: 'c3',
          serverId: 's3',
          role: MessageRole.agent,
          content: '天气晴朗',
          timestamp: 1718000005000,
          clock: 102,
        ),
      );

      await messageRepo.dedupeConversation(conversationId);

      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 2, reason: 'c1/c2 合并为 1, c3 保留 → 共 2');
      final hits = await database.searchMessagesSanitized('你好');
      expect(hits, isNotEmpty);
    });

    test('handles a conversation with no duplicates (no-op)', () async {
      await messageRepo.insert(
        makeMsg(
          clientId: 'c1',
          serverId: 's1',
          role: MessageRole.user,
          content: 'unique 1',
          timestamp: 1718000000000,
          clock: 100,
        ),
      );
      await messageRepo.insert(
        makeMsg(
          clientId: 'c2',
          serverId: 's2',
          role: MessageRole.agent,
          content: 'unique 2',
          timestamp: 1718000010000,
          clock: 101,
        ),
      );

      final deleted = await messageRepo.dedupeConversation(conversationId);

      expect(deleted, 0);
      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 2);
    });

    test('deletes empty-content text messages (air-bubble cleanup)', () async {
      // 三条空 text 消息(不同时间、不同上下文,网关纯 tool_call 回复副作用),
      // + 一条有内容消息。空消息无展示价值(空气泡),应全部删除。
      await messageRepo.insert(
        makeMsg(
          clientId: 'empty-1',
          serverId: 'e1',
          role: MessageRole.agent,
          content: '',
          timestamp: 1718000000000,
          clock: 100,
        ),
      );
      await messageRepo.insert(
        makeMsg(
          clientId: 'empty-2',
          serverId: null,
          role: MessageRole.agent,
          content: '',
          timestamp: 1718000010000,
          clock: 101,
        ),
      );
      await messageRepo.insert(
        makeMsg(
          clientId: 'real-1',
          serverId: 'r1',
          role: MessageRole.agent,
          content: '有内容的回复',
          timestamp: 1718000020000,
          clock: 102,
        ),
      );

      final deleted = await messageRepo.dedupeConversation(conversationId);

      expect(deleted, 2, reason: '两条空 text 消息应被删除');
      final all = await messageRepo.getByConversation(conversationId);
      expect(all.length, 1);
      expect(all.single.content, '有内容的回复');
    });

    test('deletes null-content text messages too', () async {
      // content 为 null 的 text 消息同样无展示价值。经正常 insert 路径入库
      // (带 FTS5 同步),dedupeConversation 删除时不会破坏 FTS 一致性。
      await messageRepo.insert(
        makeMsg(
          clientId: 'null-c',
          serverId: null,
          role: MessageRole.agent,
          content: null,
          timestamp: 1718000000000,
          clock: 100,
        ),
      );

      final deleted = await messageRepo.dedupeConversation(conversationId);

      expect(deleted, 1);
      final all = await messageRepo.getByConversation(conversationId);
      expect(all, isEmpty);
    });

    // -------------------------------------------------------------------
    // Bug #5: dedupeConversation SQLITE_MAX_VARIABLE_NUMBER chunking
    //
    // Modern SQLite (bundled with Flutter 3.x via sqlite3 2.9.x) defaults
    // SQLITE_MAX_VARIABLE_NUMBER to 32766 — not the historical 999.
    // dedupeConversation builds `WHERE client_id IN (?, ?, ..., ?)` with
    // one placeholder per doomed clientId. Once >32766 doomed rows exist
    // (one legacy install's accumulated CatchUp residue before Bug #2 fix
    // landed), the single-statement IN-clause exceeds the limit and Drift
    // raises "too many SQL variables".  Real-world impact: dedupe silently
    // fails → CatchUp's claim of "重复根除" is incomplete for heavy users.
    //
    // After the merge fix the inbound path stops adding new dupes, but a
    // one-time cleanup of historical residue (a) needs to work and (b) must
    // not crash when doomed count exceeds the variable limit.
    //
    // We insert 33000 messages with identical (role, content, timestamp)
    // — all in one cluster; dedupe plans 32999 deletions → 32999 IN params
    // → 233 over the 32766 limit.
    // -------------------------------------------------------------------
    test(
      'chunks IN-clause when doomed count exceeds SQLITE_MAX_VARIABLE_NUMBER '
      '(Bug #5 — no "too many SQL variables" crash)',
      () async {
        // 33000 duplicates — above SQLite's 32766 variable limit.
        const dupCount = 33000;
        for (var i = 0; i < dupCount; i++) {
          await messageRepo.insert(
            makeMsg(
              clientId: 'dup-$i',
              serverId: null,
              role: MessageRole.user,
              content: '重复内容',
              // Same timestamp for all → pairwise-vs-first keeps them in one
              // cluster (|Δt| = 0 ≤ 60s window). Differing logicalClock is
              // not required for clustering — only timestamp proximity.
              timestamp: 1718000000000,
              clock: i,
            ),
          );
        }

        // Before fix: throws "too many SQL variables".
        // After fix: succeeds, deletes 32999, leaves 1 keeper.
        final deleted = await messageRepo.dedupeConversation(conversationId);

        expect(
          deleted,
          dupCount - 1,
          reason: '应删除 $dupCount - 1 = ${dupCount - 1} 行,保留 1 行',
        );
        final all = await messageRepo.getByConversation(conversationId);
        expect(all.length, 1);
        expect(all.single.content, '重复内容');
      },
      timeout: const Timeout(Duration(seconds: 180)),
    );
  });

  group('DriftMessageRepo.clearAgentContent (US-020 AC-3)', () {
    late db.AppDatabase database;
    late DriftMessageRepo messageRepo;
    late DriftConversationRepo conversationRepo;
    late DriftAgentRepo agentRepo;
    late DriftInstanceRepo instanceRepo;

    // Two agents under one instance — used to verify isolation
    // (清 agent A 不影响 agent B 的数据)。
    const instanceId = 'inst-1';
    const agentAId = 'local-A';
    const agentBId = 'local-B';

    setUp(() async {
      database = await _createTestDb();
      messageRepo = DriftMessageRepo(database);
      conversationRepo = DriftConversationRepo(database);
      agentRepo = DriftAgentRepo(database);
      instanceRepo = DriftInstanceRepo(database);

      await instanceRepo.save(
        Instance(
          id: instanceId,
          name: 'T',
          gatewayUrl: 'wss://t.example.com:443',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );
      await agentRepo.syncFromGateway(instanceId, [
        Agent(
          localId: agentAId,
          remoteId: 'r-A',
          instanceId: instanceId,
          name: 'AgentA',
          themeColor: '#000',
        ),
        Agent(
          localId: agentBId,
          remoteId: 'r-B',
          instanceId: instanceId,
          name: 'AgentB',
          themeColor: '#000',
        ),
      ]);
      await conversationRepo.getOrCreate(instanceId, agentAId);
      await conversationRepo.getOrCreate(instanceId, agentBId);
    });

    /// Builds a message for a given agent — used to populate both agents
    /// so we can assert isolation after clearing only one.
    Message msgFor(
      String agentLocalId, {
      required String clientId,
      String content = 'hi',
    }) {
      return Message(
        clientId: clientId,
        serverId: clientId, // 1:1 for test convenience
        conversationId: Conversation.generateId(instanceId, agentLocalId),
        agentId: agentLocalId,
        role: MessageRole.user,
        content: content,
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: 0,
      );
    }

    test('clears messages, stats, achievements, DND queue for target agent '
        'and leaves other agents intact', () async {
      // Arrange: populate both agents with messages
      await messageRepo.insert(msgFor(agentAId, clientId: 'a1', content: 'A1'));
      await messageRepo.insert(msgFor(agentAId, clientId: 'a2', content: 'A2'));
      await messageRepo.insert(msgFor(agentBId, clientId: 'b1', content: 'B1'));

      // Populate agent_stats for both
      await database.upsertAgentStats(
        agentAId,
        5, // totalDialogs
        2, // totalMessages
        0, // totalToolCalls
        1, // activeDays
        1, // currentStreak
        1000, // firstDialogDate
        2000, // lastDialogDate
      );
      await database.upsertAgentStats(agentBId, 3, 1, 0, 1, 1, 1500, 2500);

      // Populate achievement_unlocks for both
      await database.insertAchievementUnlock('first-message', agentAId, 1000);
      await database.insertAchievementUnlock('streak-3', agentAId, 2000);
      await database.insertAchievementUnlock('first-message', agentBId, 1500);

      // Populate pending_notifications for both
      await database.insertPendingNotification(
        agentAId,
        instanceId,
        'AgentA',
        'A notif',
        3000,
        'srv-a1',
      );
      await database.insertPendingNotification(
        agentBId,
        instanceId,
        'AgentB',
        'B notif',
        3500,
        'srv-b1',
      );

      // Act: clear agent A only
      await messageRepo.clearAgentContent(agentAId);

      // Assert: agent A's data fully cleared
      expect(
        await messageRepo.getMessageCount(agentAId),
        0,
        reason: 'A messages gone',
      );
      expect(
        await database.getAgentStats(agentAId).getSingleOrNull(),
        isNull,
        reason: 'A stats row deleted',
      );
      expect(
        await database.getAchievementUnlocksForAgent(agentAId).get(),
        isEmpty,
        reason: 'A achievements deleted',
      );

      // pending_notifications for A — query by counting via a custom select
      final pendingA = await database
          .customSelect(
            'SELECT COUNT(*) AS c FROM pending_notifications WHERE agent_id = ?',
            variables: [Variable.withString(agentAId)],
          )
          .getSingle();
      expect(
        pendingA.read<int>('c'),
        0,
        reason: 'A pending_notifications deleted',
      );

      // Assert: agent B's data fully intact (isolation)
      expect(
        await messageRepo.getMessageCount(agentBId),
        1,
        reason: 'B messages preserved',
      );
      expect(
        await database.getAgentStats(agentBId).getSingleOrNull(),
        isNotNull,
        reason: 'B stats preserved',
      );
      final bAchievements = await database
          .getAchievementUnlocksForAgent(agentBId)
          .get();
      expect(bAchievements.length, 1, reason: 'B achievements preserved');

      final pendingB = await database
          .customSelect(
            'SELECT COUNT(*) AS c FROM pending_notifications WHERE agent_id = ?',
            variables: [Variable.withString(agentBId)],
          )
          .getSingle();
      expect(
        pendingB.read<int>('c'),
        1,
        reason: 'B pending_notifications preserved',
      );

      // Assert: agents and conversations skeletons preserved (US-020 contract)
      expect(
        await agentRepo.getById(agentAId),
        isNotNull,
        reason: 'agent row not deleted — skeleton preserved for FK safety',
      );
      expect(
        await conversationRepo.getOrCreate(instanceId, agentAId),
        isNotNull,
        reason: 'conversation row not deleted',
      );
    });

    test('purges FTS5 index for target agent only', () async {
      // Insert one searchable message per agent.
      await messageRepo.insert(
        msgFor(agentAId, clientId: 'a1', content: 'apple keyword'),
      );
      await messageRepo.insert(
        msgFor(agentBId, clientId: 'b1', content: 'banana keyword'),
      );

      // Sanity: both findable via FTS.
      final preA = await database.searchMessagesSanitized('apple');
      final preB = await database.searchMessagesSanitized('banana');
      expect(preA, isNotEmpty);
      expect(preB, isNotEmpty);

      // Act: clear A only.
      await messageRepo.clearAgentContent(agentAId);

      // Assert: A no longer in FTS, B still indexed.
      final postA = await database.searchMessagesSanitized('apple');
      final postB = await database.searchMessagesSanitized('banana');
      expect(postA, isEmpty, reason: 'A FTS entries purged');
      expect(postB, isNotEmpty, reason: 'B FTS entries preserved');
    });

    test('is idempotent — clearing twice does not throw', () async {
      await messageRepo.insert(msgFor(agentAId, clientId: 'a1'));
      await messageRepo.clearAgentContent(agentAId);
      // Second call on already-empty agent must succeed silently.
      await messageRepo.clearAgentContent(agentAId);
      expect(await messageRepo.getMessageCount(agentAId), 0);
    });

    test('no-op for agent with no data — does not throw', () async {
      // Agent B exists but has no messages/stats/achievements yet.
      await messageRepo.clearAgentContent(agentBId);
      expect(await messageRepo.getMessageCount(agentBId), 0);
    });

    test(
      'cascades tool_calls deletion via FK (target only, isolation)',
      () async {
        // Arrange: insert a message per agent, then a tool_call row per message.
        // tool_calls.message_id references messages.client_id (FK ON DELETE
        // CASCADE). clearAgentContent relies on this cascade — assert it holds.
        await messageRepo.insert(msgFor(agentAId, clientId: 'a1'));
        await messageRepo.insert(msgFor(agentBId, clientId: 'b1'));

        Future<int> countToolCallsFor(String agentLocalId) async {
          // tool_calls has no agent_id; join via messages to count per agent.
          final row = await database
              .customSelect(
                'SELECT COUNT(*) AS c FROM tool_calls tc '
                'INNER JOIN messages m ON m.client_id = tc.message_id '
                'WHERE m.agent_id = ?',
                variables: [Variable.withString(agentLocalId)],
              )
              .getSingle();
          return row.read<int>('c');
        }

        await database.customStatement(
          "INSERT INTO tool_calls "
          "(id, message_id, tool_name, status, input_args, output_result) "
          "VALUES ('tc-a1', 'a1', 'search', 2, '{}', '{}')",
        );
        await database.customStatement(
          "INSERT INTO tool_calls "
          "(id, message_id, tool_name, status, input_args, output_result) "
          "VALUES ('tc-b1', 'b1', 'search', 2, '{}', '{}')",
        );

        // Sanity: both have a tool_call.
        expect(await countToolCallsFor(agentAId), 1);
        expect(await countToolCallsFor(agentBId), 1);

        // Act: clear A only.
        await messageRepo.clearAgentContent(agentAId);

        // Assert: A's tool_call cascaded away; B's preserved.
        expect(
          await countToolCallsFor(agentAId),
          0,
          reason: 'A tool_calls cascaded on message delete',
        );
        expect(
          await countToolCallsFor(agentBId),
          1,
          reason: 'B tool_calls preserved',
        );
      },
    );
  });
}
