import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/usecases/outbox_processor.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';

class _MockMessageRepo extends Mock implements IMessageRepo {}

class _MockConversationRepo extends Mock implements IConversationRepo {}

class _MockInstanceRepo extends Mock implements IInstanceRepo {}

class _MockAgentRepo extends Mock implements IAgentRepo {}

class _MockGatewayClient extends Mock implements IGatewayClient {}

class _FakeLogger implements ILogger {
  final List<String> infos = [];
  final List<String> errors = [];
  @override
  void info(String message) => infos.add(message);
  @override
  void error(String message, [StackTrace? stackTrace]) => errors.add(message);
}

const _testInstanceId = 'inst-test';
const _testAgentLocalId = 'agent-local';
const _testAgentRemoteId = 'agent-remote';
const _testConversationId = 'conv-test';

Message _msg({
  required String clientId,
  required int logicalClock,
  MessageStatus status = MessageStatus.pending,
  int? timestamp,
}) {
  return Message(
    clientId: clientId,
    conversationId: _testConversationId,
    agentId: _testAgentLocalId,
    role: MessageRole.user,
    content: 'hello $clientId',
    type: MessageType.text,
    status: status,
    logicalClock: logicalClock,
    timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
  );
}

Instance _onlineInstance() => Instance(
  id: _testInstanceId,
  name: '测试实例',
  gatewayUrl: 'wss://test.example.com:18789',
  tokenRef: 'ref-1',
  healthStatus: HealthStatus.online,
);

Instance _offlineInstance() =>
    _onlineInstance().copyWith(healthStatus: HealthStatus.offline);

Agent _testAgent() => Agent(
  localId: _testAgentLocalId,
  remoteId: _testAgentRemoteId,
  instanceId: _testInstanceId,
  name: '产品虾',
);

void main() {
  late OutboxProcessor processor;
  late SendMessageUseCase sendUseCase;
  late _MockMessageRepo messageRepo;
  late _MockConversationRepo conversationRepo;
  late _MockInstanceRepo instanceRepo;
  late _MockAgentRepo agentRepo;
  late _MockGatewayClient gatewayClient;
  late _FakeLogger logger;

  setUpAll(() {
    registerFallbackValue(
      Message(
        clientId: 'fallback',
        conversationId: 'conv',
        agentId: 'agent',
        role: MessageRole.user,
        type: MessageType.text,
        logicalClock: 0,
      ),
    );
    registerFallbackValue(MessageStatus.pending);
  });

  setUp(() {
    messageRepo = _MockMessageRepo();
    conversationRepo = _MockConversationRepo();
    instanceRepo = _MockInstanceRepo();
    agentRepo = _MockAgentRepo();
    gatewayClient = _MockGatewayClient();
    logger = _FakeLogger();

    sendUseCase = SendMessageUseCase(
      messageRepo: messageRepo,
      conversationRepo: conversationRepo,
      instanceRepo: instanceRepo,
      gatewayClient: gatewayClient,
    );
    processor = OutboxProcessor(
      messageRepo: messageRepo,
      instanceRepo: instanceRepo,
      agentRepo: agentRepo,
      sendMessageUseCase: sendUseCase,
      logger: logger,
    );

    // Default stubs
    when(() => messageRepo.resetStaleSending(any())).thenAnswer((_) async => 0);
    when(
      () => agentRepo.getById(_testAgentLocalId),
    ).thenAnswer((_) async => _testAgent());
  });

  group('flushOutbox - empty / offline cases', () {
    test('returns 0 when outbox is empty', () async {
      when(
        () => instanceRepo.getById(_testInstanceId),
      ).thenAnswer((_) async => _onlineInstance());
      when(
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ).thenAnswer((_) async => []);

      final sent = await processor.flushOutbox(_testInstanceId);

      expect(sent, 0);
      verify(() => messageRepo.resetStaleSending(any())).called(1);
      // Connectivity check happens before outbox fetch, so getById is called
      verify(() => instanceRepo.getById(_testInstanceId)).called(1);
      verify(() => messageRepo.getOutboxByInstance(_testInstanceId)).called(1);
    });

    test(
      'returns 0 when instance is offline (skips getOutboxByInstance)',
      () async {
        when(
          () => instanceRepo.getById(_testInstanceId),
        ).thenAnswer((_) async => _offlineInstance());

        final sent = await processor.flushOutbox(_testInstanceId);

        expect(sent, 0);
        // Connectivity check happens BEFORE outbox fetch — verify the query was never wasted
        verifyNever(() => messageRepo.getOutboxByInstance(any()));
        verifyNever(() => messageRepo.tryTransitionToSending(any(), any()));
      },
    );

    test(
      'returns 0 when instance is null (deleted, skips getOutboxByInstance)',
      () async {
        when(
          () => instanceRepo.getById(_testInstanceId),
        ).thenAnswer((_) async => null);

        final sent = await processor.flushOutbox(_testInstanceId);

        expect(sent, 0);
        // Connectivity check happens BEFORE outbox fetch — verify the query was never wasted
        verifyNever(() => messageRepo.getOutboxByInstance(any()));
      },
    );
  });

  group('flushOutbox - sequential send', () {
    test('sends PENDING messages in logicalClock order', () async {
      final m1 = _msg(clientId: 'm1', logicalClock: 1);
      final m2 = _msg(clientId: 'm2', logicalClock: 2);
      final m3 = _msg(clientId: 'm3', logicalClock: 3);
      // Repository is contracted to sort by logicalClock ASC
      when(
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ).thenAnswer((_) async => [m1, m2, m3]);
      when(
        () => instanceRepo.getById(_testInstanceId),
      ).thenAnswer((_) async => _onlineInstance());
      when(
        () => messageRepo.tryTransitionToSending(any(), any()),
      ).thenAnswer((_) async => true);
      when(() => messageRepo.getByClientId(any())).thenAnswer(
        (inv) async => _msg(
          clientId: inv.positionalArguments[0] as String,
          logicalClock: 0,
          status: MessageStatus.sending,
        ),
      );
      when(
        () => gatewayClient.sendMessage(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          message: any(named: 'message'),
        ),
      ).thenAnswer(
        (_) async => (
          serverId: 's-${DateTime.now().microsecondsSinceEpoch}',
          timestamp: 1,
        ),
      );
      when(() => messageRepo.bindServerId(any(), any())).thenAnswer((
        inv,
      ) async {
        final clientId = inv.positionalArguments[0] as String;
        return _msg(
          clientId: clientId,
          logicalClock: 0,
          status: MessageStatus.sent,
        );
      });

      final sent = await processor.flushOutbox(_testInstanceId);

      expect(sent, 3);
      // Verify CAS was called for each message with PENDING expected status
      verify(
        () => messageRepo.tryTransitionToSending('m1', MessageStatus.pending),
      ).called(1);
      verify(
        () => messageRepo.tryTransitionToSending('m2', MessageStatus.pending),
      ).called(1);
      verify(
        () => messageRepo.tryTransitionToSending('m3', MessageStatus.pending),
      ).called(1);
    });

    test('FAILED messages use FAILED as expectedStatus for CAS', () async {
      final m1 = _msg(
        clientId: 'm1',
        logicalClock: 1,
        status: MessageStatus.failed,
      );
      when(
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ).thenAnswer((_) async => [m1]);
      when(
        () => instanceRepo.getById(_testInstanceId),
      ).thenAnswer((_) async => _onlineInstance());
      when(
        () => messageRepo.tryTransitionToSending(any(), any()),
      ).thenAnswer((_) async => true);
      when(() => messageRepo.getByClientId(any())).thenAnswer(
        (inv) async => _msg(
          clientId: inv.positionalArguments[0] as String,
          logicalClock: 0,
          status: MessageStatus.sending,
        ),
      );
      when(
        () => gatewayClient.sendMessage(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          message: any(named: 'message'),
        ),
      ).thenAnswer((_) async => (serverId: 's1', timestamp: 1));
      when(() => messageRepo.bindServerId(any(), any())).thenAnswer(
        (inv) async => _msg(
          clientId: inv.positionalArguments[0] as String,
          logicalClock: 0,
          status: MessageStatus.sent,
        ),
      );

      final sent = await processor.flushOutbox(_testInstanceId);

      expect(sent, 1);
      verify(
        () => messageRepo.tryTransitionToSending('m1', MessageStatus.failed),
      ).called(1);
    });

    test(
      'skips message when CAS fails (already processed by another path)',
      () async {
        final m1 = _msg(clientId: 'm1', logicalClock: 1);
        final m2 = _msg(clientId: 'm2', logicalClock: 2);
        when(
          () => messageRepo.getOutboxByInstance(_testInstanceId),
        ).thenAnswer((_) async => [m1, m2]);
        when(
          () => instanceRepo.getById(_testInstanceId),
        ).thenAnswer((_) async => _onlineInstance());
        // m1: CAS fails (already SENT by SendMessageUseCase concurrently)
        when(
          () => messageRepo.tryTransitionToSending('m1', MessageStatus.pending),
        ).thenAnswer((_) async => false);
        // m2: CAS succeeds
        when(
          () => messageRepo.tryTransitionToSending('m2', MessageStatus.pending),
        ).thenAnswer((_) async => true);
        when(() => messageRepo.getByClientId('m1')).thenAnswer(
          (_) async =>
              _msg(clientId: 'm1', logicalClock: 1, status: MessageStatus.sent),
        );
        when(() => messageRepo.getByClientId('m2')).thenAnswer(
          (_) async => _msg(
            clientId: 'm2',
            logicalClock: 2,
            status: MessageStatus.sending,
          ),
        );
        when(
          () => gatewayClient.sendMessage(
            instanceId: any(named: 'instanceId'),
            agentId: any(named: 'agentId'),
            message: any(named: 'message'),
          ),
        ).thenAnswer((_) async => (serverId: 's2', timestamp: 1));
        when(() => messageRepo.bindServerId('m2', any())).thenAnswer(
          (_) async =>
              _msg(clientId: 'm2', logicalClock: 2, status: MessageStatus.sent),
        );

        final sent = await processor.flushOutbox(_testInstanceId);

        expect(sent, 1);
        // m1 was skipped — gateway should only be called for m2
        verify(
          () => gatewayClient.sendMessage(
            instanceId: _testInstanceId,
            agentId: _testAgentRemoteId,
            message: any(named: 'message'),
          ),
        ).called(1);
      },
    );
  });

  group('flushOutbox - failure handling', () {
    test(
      'marks message FAILED on send error and continues with next',
      () async {
        final m1 = _msg(clientId: 'm1', logicalClock: 1);
        final m2 = _msg(clientId: 'm2', logicalClock: 2);
        when(
          () => messageRepo.getOutboxByInstance(_testInstanceId),
        ).thenAnswer((_) async => [m1, m2]);
        when(
          () => instanceRepo.getById(_testInstanceId),
        ).thenAnswer((_) async => _onlineInstance());
        when(
          () => messageRepo.tryTransitionToSending(any(), any()),
        ).thenAnswer((_) async => true);
        when(() => messageRepo.getByClientId(any())).thenAnswer(
          (inv) async => _msg(
            clientId: inv.positionalArguments[0] as String,
            logicalClock: 0,
            status: MessageStatus.sending,
          ),
        );
        // m1 fails, m2 succeeds
        var callCount = 0;
        when(
          () => gatewayClient.sendMessage(
            instanceId: any(named: 'instanceId'),
            agentId: any(named: 'agentId'),
            message: any(named: 'message'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) throw Exception('network error');
          return (serverId: 's2', timestamp: 1);
        });
        when(
          () => messageRepo.updateStatus(any(), MessageStatus.failed),
        ).thenAnswer(
          (inv) async => _msg(
            clientId: inv.positionalArguments[0] as String,
            logicalClock: 0,
            status: MessageStatus.failed,
          ),
        );
        when(() => messageRepo.bindServerId(any(), any())).thenAnswer(
          (inv) async => _msg(
            clientId: inv.positionalArguments[0] as String,
            logicalClock: 0,
            status: MessageStatus.sent,
          ),
        );

        final sent = await processor.flushOutbox(_testInstanceId);

        expect(sent, 1); // only m2 succeeded
        // m1 标记为 FAILED —— 由 retry 的 catch 块写入，恰好一次。
        // OutboxProcessor 不再二次兜底写 FAILED（retry 是唯一权威）。
        verify(
          () => messageRepo.updateStatus('m1', MessageStatus.failed),
        ).called(1);
      },
    );

    test('skips message when agent is missing (deleted)', () async {
      final m1 = _msg(clientId: 'm1', logicalClock: 1);
      when(
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ).thenAnswer((_) async => [m1]);
      when(
        () => instanceRepo.getById(_testInstanceId),
      ).thenAnswer((_) async => _onlineInstance());
      when(
        () => agentRepo.getById(_testAgentLocalId),
      ).thenAnswer((_) async => null);

      final sent = await processor.flushOutbox(_testInstanceId);

      expect(sent, 0);
      verifyNever(() => messageRepo.tryTransitionToSending(any(), any()));
      verifyNever(
        () => gatewayClient.sendMessage(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          message: any(named: 'message'),
        ),
      );
    });

    test('skips PENDING message when agent is tombstoned (US-021)', () async {
      final m1 = _msg(clientId: 'm1', logicalClock: 1);
      when(
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ).thenAnswer((_) async => [m1]);
      when(
        () => instanceRepo.getById(_testInstanceId),
      ).thenAnswer((_) async => _onlineInstance());
      // Agent 存在但被 tombstone（Gateway 端已删除）。直接构造（copyWith
      // 故意不暴露 removedAt，见 spec §3.3）。
      when(() => agentRepo.getById(_testAgentLocalId)).thenAnswer(
        (_) async => Agent(
          localId: _testAgentLocalId,
          remoteId: _testAgentRemoteId,
          instanceId: _testInstanceId,
          name: '产品虾',
          removedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final sent = await processor.flushOutbox(_testInstanceId);

      expect(sent, 0);
      verifyNever(() => messageRepo.tryTransitionToSending(any(), any()));
      verifyNever(
        () => gatewayClient.sendMessage(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          message: any(named: 'message'),
        ),
      );
    });

    test('skips FAILED message when agent is tombstoned (US-021)', () async {
      final m1 = _msg(clientId: 'm1', logicalClock: 1);
      // FAILED 消息也在 outbox 中
      when(
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ).thenAnswer((_) async => [m1]);
      when(
        () => instanceRepo.getById(_testInstanceId),
      ).thenAnswer((_) async => _onlineInstance());
      when(() => agentRepo.getById(_testAgentLocalId)).thenAnswer(
        (_) async => Agent(
          localId: _testAgentLocalId,
          remoteId: _testAgentRemoteId,
          instanceId: _testInstanceId,
          name: '产品虾',
          removedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final sent = await processor.flushOutbox(_testInstanceId);

      expect(sent, 0);
      verifyNever(() => messageRepo.tryTransitionToSending(any(), any()));
    });

    // 注：active agent 正常发送的路径由 "sends PENDING messages in logicalClock
    // order" 测试覆盖；此处只新增 tombstone-skip 行为（US-021 真正的增量）。
  });

  group('flushOutbox - expiry', () {
    test('marks messages older than 24h as EXPIRED', () async {
      final oldTimestamp = DateTime.now()
          .subtract(const Duration(hours: 25))
          .millisecondsSinceEpoch;
      final expired = _msg(
        clientId: 'old',
        logicalClock: 1,
        timestamp: oldTimestamp,
      );
      when(
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ).thenAnswer((_) async => [expired]);
      when(
        () => instanceRepo.getById(_testInstanceId),
      ).thenAnswer((_) async => _onlineInstance());
      when(
        () => messageRepo.updateStatus('old', MessageStatus.expired),
      ).thenAnswer(
        (_) async => _msg(
          clientId: 'old',
          logicalClock: 1,
          status: MessageStatus.expired,
          timestamp: oldTimestamp,
        ),
      );

      final sent = await processor.flushOutbox(_testInstanceId);

      expect(sent, 0);
      verify(
        () => messageRepo.updateStatus('old', MessageStatus.expired),
      ).called(1);
      verifyNever(() => messageRepo.tryTransitionToSending(any(), any()));
    });
  });

  group('flushOutbox - re-entrancy', () {
    test('rejects concurrent flush for the same instance', () async {
      when(
        () => instanceRepo.getById(_testInstanceId),
      ).thenAnswer((_) async => _onlineInstance());
      // Set up a slow getOutboxByInstance so the first flush is in flight
      // when the second call begins.
      final completer = Completer<List<Message>>();
      when(
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ).thenAnswer((_) => completer.future);

      final firstFlush = processor.flushOutbox(_testInstanceId);
      // While the first flush is awaiting getOutboxByInstance, fire a second.
      final secondFlush = processor.flushOutbox(_testInstanceId);

      // Resolve the first flush's outbox query with empty list.
      completer.complete([]);

      final results = await Future.wait([firstFlush, secondFlush]);
      // One of them returned 0 (empty queue), the other rejected and returned 0.
      // The key assertion: resetStaleSending was only called once
      // (the second flush short-circuited before the lock-protected work).
      expect(results, [0, 0]);
      verify(() => messageRepo.resetStaleSending(any())).called(1);
    });
  });

  group('flushOutbox - crash recovery', () {
    test('calls resetStaleSending before processing outbox', () async {
      when(
        () => instanceRepo.getById(_testInstanceId),
      ).thenAnswer((_) async => _onlineInstance());
      when(
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ).thenAnswer((_) async => []);

      await processor.flushOutbox(_testInstanceId);

      // resetStaleSending first, then connectivity check, then outbox fetch
      verifyInOrder([
        () => messageRepo.resetStaleSending(any()),
        () => instanceRepo.getById(any()),
        () => messageRepo.getOutboxByInstance(_testInstanceId),
      ]);
    });

    test('passes correct instanceId to resetStaleSending', () async {
      when(
        () => instanceRepo.getById('inst-a'),
      ).thenAnswer((_) async => _onlineInstance());
      when(
        () => messageRepo.getOutboxByInstance('inst-a'),
      ).thenAnswer((_) async => []);

      await processor.flushOutbox('inst-a');

      verify(() => messageRepo.resetStaleSending('inst-a')).called(1);
      verifyNever(() => messageRepo.resetStaleSending('inst-b'));
    });

    test('resetStaleSending for instance B does NOT affect instance A '
        '(cross-instance isolation)', () async {
      const instanceA = 'inst-a';
      const instanceB = 'inst-b';

      // Instance A is online and has outbox messages
      when(
        () => messageRepo.resetStaleSending(instanceA),
      ).thenAnswer((_) async => 0);
      when(
        () => messageRepo.resetStaleSending(instanceB),
      ).thenAnswer((_) async => 0);

      // Instance A: online, has messages
      when(() => messageRepo.getOutboxByInstance(instanceA)).thenAnswer(
        (_) async => [
          _msg(clientId: 'ma1', logicalClock: 1),
          _msg(clientId: 'ma2', logicalClock: 2),
        ],
      );
      when(
        () => instanceRepo.getById(instanceA),
      ).thenAnswer((_) async => _onlineInstance());
      when(
        () => messageRepo.tryTransitionToSending(any(), any()),
      ).thenAnswer((_) async => true);
      when(() => messageRepo.getByClientId(any())).thenAnswer(
        (inv) async => _msg(
          clientId: inv.positionalArguments[0] as String,
          logicalClock: 0,
          status: MessageStatus.sending,
        ),
      );
      when(
        () => gatewayClient.sendMessage(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          message: any(named: 'message'),
        ),
      ).thenAnswer((_) async => (serverId: 's1', timestamp: 1));
      when(() => messageRepo.bindServerId(any(), any())).thenAnswer(
        (inv) async => _msg(
          clientId: inv.positionalArguments[0] as String,
          logicalClock: 0,
          status: MessageStatus.sent,
        ),
      );

      // Instance B: online, empty outbox
      when(
        () => instanceRepo.getById(instanceB),
      ).thenAnswer((_) async => _onlineInstance());
      when(
        () => messageRepo.getOutboxByInstance(instanceB),
      ).thenAnswer((_) async => []);

      // Flush instance A first — this will start processing messages
      final flushA = processor.flushOutbox(instanceA);

      // While A is processing (awaiting gateway), flush instance B
      final flushB = processor.flushOutbox(instanceB);

      final results = await Future.wait([flushA, flushB]);
      expect(results, [2, 0]); // A flushed 2, B had 0

      // Each instance called resetStaleSending with ITS OWN id.
      // This is the key: instance B did NOT reset instance A's messages.
      verify(() => messageRepo.resetStaleSending(instanceA)).called(1);
      verify(() => messageRepo.resetStaleSending(instanceB)).called(1);

      // Instance A's outbox was queried and processed
      verify(() => messageRepo.getOutboxByInstance(instanceA)).called(1);

      // Instance A's messages were sent
      verify(() => messageRepo.tryTransitionToSending('ma1', any())).called(1);
      verify(() => messageRepo.tryTransitionToSending('ma2', any())).called(1);
    });
  });
}
