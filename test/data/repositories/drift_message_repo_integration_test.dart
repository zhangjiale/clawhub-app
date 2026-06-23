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
