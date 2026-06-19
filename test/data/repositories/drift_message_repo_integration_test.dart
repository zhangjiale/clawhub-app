import 'package:flutter_test/flutter_test.dart';
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
}
