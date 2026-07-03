import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/src/runtime/executor/executor.dart';
import 'package:drift/src/runtime/executor/interceptor.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_conversation_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/data/repositories/drift_message_repo.dart';
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/message_status.dart';

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
  group('DriftMessageRepo.updateStatuses', () {
    late db.AppDatabase database;
    late DriftMessageRepo messageRepo;

    setUp(() async {
      database = await _createTestDb();
      messageRepo = DriftMessageRepo(database);

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

      final agentRepo = DriftAgentRepo(database);
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'agent-1',
          remoteId: 'remote-1',
          instanceId: 'inst-1',
          name: '虾',
        ),
      ]);

      final conversationRepo = DriftConversationRepo(database);
      await conversationRepo.getOrCreate('inst-1', 'agent-1');
    });

    Message pendingMessage(String clientId) => Message(
      clientId: clientId,
      conversationId: Conversation.generateId('inst-1', 'agent-1'),
      agentId: 'agent-1',
      role: MessageRole.user,
      content: 'hello $clientId',
      type: MessageType.text,
      status: MessageStatus.pending,
      logicalClock: 1,
    );

    Message sentMessage(String clientId) => Message(
      clientId: clientId,
      conversationId: Conversation.generateId('inst-1', 'agent-1'),
      agentId: 'agent-1',
      role: MessageRole.user,
      content: 'hello $clientId',
      type: MessageType.text,
      status: MessageStatus.sent,
      logicalClock: 1,
    );

    test('updates multiple PENDING messages to EXPIRED in one batch', () async {
      await messageRepo.insert(pendingMessage('m1'));
      await messageRepo.insert(pendingMessage('m2'));
      await messageRepo.insert(pendingMessage('m3'));

      final updated = await messageRepo.updateStatuses([
        'm1',
        'm2',
      ], MessageStatus.expired);

      expect(updated, hasLength(2));
      expect(updated.map((m) => m.clientId), containsAll(['m1', 'm2']));
      expect(updated.every((m) => m.status == MessageStatus.expired), isTrue);

      final stored = await messageRepo.getByClientId('m1');
      expect(stored!.status, MessageStatus.expired);
      expect(
        (await messageRepo.getByClientId('m2'))!.status,
        MessageStatus.expired,
      );
      expect(
        (await messageRepo.getByClientId('m3'))!.status,
        MessageStatus.pending,
      );
    });

    test('skips non-existent clientIds without throwing', () async {
      await messageRepo.insert(pendingMessage('m1'));

      final updated = await messageRepo.updateStatuses([
        'm1',
        'ghost',
      ], MessageStatus.expired);

      expect(updated, hasLength(1));
      expect(updated.single.clientId, 'm1');
    });

    test(
      'skips messages whose state machine disallows the transition',
      () async {
        await messageRepo.insert(pendingMessage('m1'));
        await messageRepo.insert(sentMessage('m2'));

        final updated = await messageRepo.updateStatuses([
          'm1',
          'm2',
        ], MessageStatus.expired);

        expect(updated, hasLength(1));
        expect(updated.single.clientId, 'm1');
        expect(
          (await messageRepo.getByClientId('m2'))!.status,
          MessageStatus.sent,
        );
      },
    );

    test(
      'returns empty list for empty clientIds without touching DB',
      () async {
        final result = await messageRepo.updateStatuses(
          [],
          MessageStatus.expired,
        );
        expect(result, isEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // BUG J 修复:updateStatuses 之前用 customStatement 不会触发 messages 表的
  // stream watcher（watchOutboxCount / getByConversation.watchSingle / ...），
  // OutboxWarningBanner 会显示陈旧计数。改用 customUpdate + updates:{messages}
  // 即可触发。RED 测试:updateStatuses 后 watchOutboxCount 必须发射新值。
  // ---------------------------------------------------------------------------
  group('DriftMessageRepo.updateStatuses stream invalidation (BUG J)', () {
    late db.AppDatabase database;
    late DriftMessageRepo messageRepo;

    setUp(() async {
      database = await _createTestDb();
      messageRepo = DriftMessageRepo(database);

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

      final agentRepo = DriftAgentRepo(database);
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'agent-1',
          remoteId: 'remote-1',
          instanceId: 'inst-1',
          name: '虾',
        ),
      ]);

      final conversationRepo = DriftConversationRepo(database);
      await conversationRepo.getOrCreate('inst-1', 'agent-1');
    });

    Message pendingMessage(String clientId) => Message(
      clientId: clientId,
      conversationId: Conversation.generateId('inst-1', 'agent-1'),
      agentId: 'agent-1',
      role: MessageRole.user,
      content: 'hello $clientId',
      type: MessageType.text,
      status: MessageStatus.pending,
      logicalClock: 1,
    );

    test('watchOutboxCount emits new value after updateStatuses '
        '(BUG J — customStatement → customUpdate)', () async {
      // Seed 3 PENDING messages
      await messageRepo.insert(pendingMessage('m1'));
      await messageRepo.insert(pendingMessage('m2'));
      await messageRepo.insert(pendingMessage('m3'));

      // Subscribe to watchOutboxCount, accumulate emitted values
      final counts = <int>[];
      final sub = messageRepo.watchOutboxCount('inst-1').listen(counts.add);
      // 等初始值
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(counts, [3], reason: '订阅时应立即收到初始计数 3');

      // Act: 把 m1, m2 标 EXPIRED（之前用 customStatement,watcher 不会触发）
      await messageRepo.updateStatuses(['m1', 'm2'], MessageStatus.expired);
      // 给 stream watcher 一点时间发射新值
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Assert: stream 必须再发射一次,新计数 = 1（只剩 m3 PENDING）
      expect(
        counts,
        [3, 1],
        reason:
            'updateStatuses 必须触发 watchOutboxCount 发射新值,'
            'OutboxWarningBanner 才能实时反映 PENDING 计数变化。'
            '实际收到: $counts',
      );

      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  // BUG G 修复:updateStatuses 的 UPDATE 之前不带 status guard
  // (即 `WHERE client_id IN (...) AND status IN (...)`)。Drift 事务内本身原子,
  // 但显式 status guard 是防御性编程,防止未来重构去掉 transaction 时引入 race
  // (也与其他 CAS 方法 tryTransitionToSending 的 WHERE status=? 模式一致)。
  //
  // RED 测试:用 QueryInterceptor 抓 UPDATE 语句,断言必须含 `AND status`。
  // 不验具体状态值 — 只要 SQL 形式上含 CAS guard 即视为通过。
  // ---------------------------------------------------------------------------
  group('DriftMessageRepo.updateStatuses CAS status guard (BUG G)', () {
    test('UPDATE statement includes status guard '
        '(`AND status` in WHERE clause)', () async {
      // QueryInterceptor: 抓所有 messages 表的 UPDATE 语句
      final updateStatements = <String>[];
      final interceptor = _SqlCapturingInterceptor(
        onRunUpdate: (stmt, args) {
          final upper = stmt.toUpperCase();
          if (upper.contains('UPDATE MESSAGES') &&
              upper.contains('SET STATUS')) {
            updateStatements.add(stmt);
          }
        },
      );
      final database = db.AppDatabase(
        NativeDatabase.memory(
          setup: (sqlDb) {
            sqlDb.execute('PRAGMA foreign_keys = ON');
          },
        ).interceptWith(interceptor),
      );
      addTearDown(() => database.close());

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
      final agentRepo = DriftAgentRepo(database);
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'agent-1',
          remoteId: 'remote-1',
          instanceId: 'inst-1',
          name: '虾',
        ),
      ]);
      final conversationRepo = DriftConversationRepo(database);
      await conversationRepo.getOrCreate('inst-1', 'agent-1');

      final messageRepo = DriftMessageRepo(database);
      final pendingMsg = Message(
        clientId: 'm1',
        conversationId: Conversation.generateId('inst-1', 'agent-1'),
        agentId: 'agent-1',
        role: MessageRole.user,
        content: 'hi',
        type: MessageType.text,
        status: MessageStatus.pending,
        logicalClock: 1,
      );
      await messageRepo.insert(pendingMsg);

      // Act
      await messageRepo.updateStatuses(['m1'], MessageStatus.expired);

      // Assert: 至少一个 UPDATE 必须含 `status` guard
      // (WHERE 子句含 `status` 字段引用 —— 单行 CAS `AND status = ?` 或
      //  tuple IN `(client_id, status) IN (...)` 都算合法 guard)
      expect(
        updateStatements,
        isNotEmpty,
        reason: 'updateStatuses 内部应执行 UPDATE 消息表',
      );
      final hasGuard = updateStatements.any((s) {
        final upper = s.toUpperCase();
        // 形式 1: 显式 `AND STATUS` (单行 CAS,类似 tryTransitionToSending)
        // 形式 2: tuple IN `(CLIENT_ID, STATUS) IN (...)` (本实现采用)
        return upper.contains('AND STATUS') ||
            (upper.contains('(CLIENT_ID, STATUS)') && upper.contains(' IN ('));
      });
      expect(
        hasGuard,
        isTrue,
        reason:
            'UPDATE WHERE 子句必须含 `status` 防御性 CAS guard,'
            '防止 stale-snapshot 覆盖并发写入。'
            '实际 SQL: $updateStatements',
      );
    });
  });

  group('DriftMessageRepo image/file persistence', () {
    late db.AppDatabase database;
    late DriftMessageRepo messageRepo;

    setUp(() async {
      database = await _createTestDb();
      messageRepo = DriftMessageRepo(database);

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

      final agentRepo = DriftAgentRepo(database);
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'agent-1',
          remoteId: 'remote-1',
          instanceId: 'inst-1',
          name: '虾',
        ),
      ]);

      final conversationRepo = DriftConversationRepo(database);
      await conversationRepo.getOrCreate('inst-1', 'agent-1');
    });

    test('image message round-trips content path + metadata', () async {
      final image = Message(
        clientId: 'img-1',
        conversationId: Conversation.generateId('inst-1', 'agent-1'),
        agentId: 'agent-1',
        role: MessageRole.user,
        content: '/tmp/img.jpg',
        type: MessageType.image,
        status: MessageStatus.sent,
        logicalClock: 1,
        metadata: const {
          'fileName': 'img.jpg',
          'mimeType': 'image/jpeg',
          'size': 12345,
          'caption': '看这张',
        },
      );
      await messageRepo.insert(image);

      final stored = await messageRepo.getByClientId('img-1');
      expect(stored, isNotNull);
      expect(stored!.type, MessageType.image);
      expect(stored.isImage, isTrue);
      expect(stored.imagePath, '/tmp/img.jpg');
      expect(stored.fileName, 'img.jpg');
      expect(stored.mimeType, 'image/jpeg');
      expect(stored.fileSize, 12345);
      expect(stored.caption, '看这张');
    });

    test('file message round-trips content path + metadata', () async {
      final file = Message(
        clientId: 'file-1',
        conversationId: Conversation.generateId('inst-1', 'agent-1'),
        agentId: 'agent-1',
        role: MessageRole.user,
        content: '/tmp/doc.pdf',
        type: MessageType.file,
        status: MessageStatus.sent,
        logicalClock: 1,
        metadata: const {
          'fileName': 'doc.pdf',
          'mimeType': 'application/pdf',
          'size': 67890,
        },
      );
      await messageRepo.insert(file);

      final stored = await messageRepo.getByClientId('file-1');
      expect(stored, isNotNull);
      expect(stored!.type, MessageType.file);
      expect(stored.isFile, isTrue);
      expect(stored.filePath, '/tmp/doc.pdf');
      expect(stored.fileName, 'doc.pdf');
      expect(stored.mimeType, 'application/pdf');
      expect(stored.fileSize, 67890);
    });

    test('agent image response round-trips imageUrl metadata', () async {
      final agentImage = Message(
        clientId: 'agent-img-1',
        conversationId: Conversation.generateId('inst-1', 'agent-1'),
        agentId: 'agent-1',
        role: MessageRole.agent,
        content: null,
        type: MessageType.image,
        status: MessageStatus.delivered,
        logicalClock: 1,
        metadata: const {
          'imageUrl': 'https://example.com/x.png',
          'mimeType': 'image/png',
        },
      );
      await messageRepo.insert(agentImage);

      final stored = await messageRepo.getByClientId('agent-img-1');
      expect(stored, isNotNull);
      expect(stored!.isImage, isTrue);
      expect(stored.imageUrl, 'https://example.com/x.png');
      expect(stored.mimeType, 'image/png');
      expect(stored.imagePath, isNull); // 响应侧无本地路径
    });
  });
}

/// Drift QueryInterceptor 包装:把 runUpdate 语句+参数转给回调。
/// 用于 BUG G 测试 —— 验证 updateStatuses 内部的 UPDATE 是否含 status guard。
class _SqlCapturingInterceptor extends QueryInterceptor {
  _SqlCapturingInterceptor({required this.onRunUpdate});

  final void Function(String statement, List<Object?> args) onRunUpdate;

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    onRunUpdate(statement, args);
    return executor.runUpdate(statement, args);
  }
}
