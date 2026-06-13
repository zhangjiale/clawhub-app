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
}
