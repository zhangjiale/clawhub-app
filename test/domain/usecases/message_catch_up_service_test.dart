import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/usecases/message_catch_up_service.dart';

class _MockAgentRepo extends Mock implements IAgentRepo {}

class _MockMessageRepo extends Mock implements IMessageRepo {}

class _MockConversationRepo extends Mock implements IConversationRepo {}

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

Agent _testAgent() => Agent(
  localId: _testAgentLocalId,
  remoteId: _testAgentRemoteId,
  instanceId: _testInstanceId,
  name: '产品虾',
);

Message _newMsg({required String serverId, required String clientId}) =>
    Message(
      clientId: clientId,
      serverId: serverId,
      conversationId: '', // Will be normalized by MessageCatchUpService
      agentId: _testAgentRemoteId,
      role: MessageRole.agent,
      content: 'Hello from $serverId',
      type: MessageType.text,
      status: MessageStatus.delivered,
      logicalClock: 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

void main() {
  late MessageCatchUpService service;
  late _MockAgentRepo agentRepo;
  late _MockMessageRepo messageRepo;
  late _MockConversationRepo conversationRepo;
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
  });

  setUp(() {
    agentRepo = _MockAgentRepo();
    messageRepo = _MockMessageRepo();
    conversationRepo = _MockConversationRepo();
    gatewayClient = _MockGatewayClient();
    logger = _FakeLogger();

    service = MessageCatchUpService(
      agentRepo: agentRepo,
      messageRepo: messageRepo,
      conversationRepo: conversationRepo,
      gatewayClient: gatewayClient,
      logger: logger,
    );

    // Default: instance has one agent
    when(
      () => agentRepo.getByInstanceId(_testInstanceId),
    ).thenAnswer((_) async => [_testAgent()]);

    // Default: getOrCreate returns a valid conversation
    when(() => conversationRepo.getOrCreate(any(), any())).thenAnswer(
      (_) async => Conversation(
        id: Conversation.generateId(_testInstanceId, _testAgentLocalId),
        agentId: _testAgentLocalId,
        instanceId: _testInstanceId,
      ),
    );
  });

  group('catchUp - basic scenarios', () {
    test('returns 0 when instance has no agents', () async {
      when(
        () => agentRepo.getByInstanceId(_testInstanceId),
      ).thenAnswer((_) async => []);

      final result = await service.catchUp(_testInstanceId);

      expect(result.inserted, 0);
      expect(result.truncated, isFalse);
      verifyNever(
        () => gatewayClient.fetchMessageHistory(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
        ),
      );
    });

    test('inserts new messages from a single page', () async {
      final msg1 = _newMsg(serverId: 's1', clientId: 'c1');
      final msg2 = _newMsg(serverId: 's2', clientId: 'c2');

      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: null,
          limit: 50,
        ),
      ).thenAnswer((_) async => (messages: [msg1, msg2], nextCursor: null));
      when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
        inv,
      ) async {
        final msgs = inv.positionalArguments[0] as List<Message>;
        return msgs; // All are new
      });

      final result = await service.catchUp(_testInstanceId);

      expect(result.inserted, 2);
      expect(result.truncated, isFalse);
      // Verify conversation was pre-created before insert
      verify(
        () => conversationRepo.getOrCreate(_testInstanceId, _testAgentLocalId),
      ).called(1);
      verify(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: null,
          limit: 50,
        ),
      ).called(1);
    });

    test('returns 0 when Gateway returns empty message list', () async {
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => (messages: <Message>[], nextCursor: null));

      final result = await service.catchUp(_testInstanceId);
      expect(result.inserted, 0);
      expect(result.truncated, isFalse);
    });
  });

  group('catchUp - stop condition', () {
    test('stops pagination when a page contains known messages', () async {
      final msg1 = _newMsg(serverId: 'new-1', clientId: 'nc1');
      final msg2 = _newMsg(serverId: 'known-1', clientId: 'kc1');

      // Page 1: msg1 is new, msg2 is known → should stop after this page
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: null,
          limit: 50,
        ),
      ).thenAnswer(
        (_) async => (messages: [msg1, msg2], nextCursor: 'cursor-page2'),
      );
      when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
        inv,
      ) async {
        final msgs = inv.positionalArguments[0] as List<Message>;
        // Only msg1 was actually new; msg2 was already known
        return [msgs.first];
      });

      final result = await service.catchUp(_testInstanceId);

      expect(result.inserted, 1); // Only msg1 was inserted
      expect(result.truncated, isFalse); // Stopped via dedup, not page cap
    });

    test('continues pagination when all messages on a page are new', () async {
      final msg1 = _newMsg(serverId: 'new-1', clientId: 'nc1');
      final msg2 = _newMsg(serverId: 'new-2', clientId: 'nc2');
      final msg3 = _newMsg(serverId: 'new-3', clientId: 'nc3');

      // Page 1: all new → continue
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: null,
          limit: 50,
        ),
      ).thenAnswer(
        (_) async => (messages: [msg1, msg2], nextCursor: 'cursor-p2'),
      );
      // Page 2: msg3 is new, but no more cursor → stop
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: 'cursor-p2',
          limit: 50,
        ),
      ).thenAnswer((_) async => (messages: [msg3], nextCursor: null));
      when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
        inv,
      ) async {
        final msgs = inv.positionalArguments[0] as List<Message>;
        return msgs; // All are new
      });

      final result = await service.catchUp(_testInstanceId);

      expect(result.inserted, 3);
      expect(result.truncated, isFalse); // Stopped via null cursor, not cap
    });

    test('stops when cursor is null (no more pages)', () async {
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          cursor: null,
          limit: 50,
        ),
      ).thenAnswer(
        (_) async => (
          messages: [_newMsg(serverId: 's1', clientId: 'c1')],
          nextCursor: null,
        ),
      );
      when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
        inv,
      ) async {
        final msgs = inv.positionalArguments[0] as List<Message>;
        return msgs;
      });

      final result = await service.catchUp(_testInstanceId);

      expect(result.inserted, 1);
      expect(result.truncated, isFalse);
      // Only the initial (cursor=null) call was made
      verify(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: null,
          limit: 50,
        ),
      ).called(1);
    });
  });

  group('catchUp - truncation', () {
    test(
      'reports truncated=true when page cap is hit with more pages left',
      () async {
        // Service capped at 2 pages — Gateway always has another page.
        final cappedService = MessageCatchUpService(
          agentRepo: agentRepo,
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          gatewayClient: gatewayClient,
          logger: logger,
          maxPagesPerConversation: 2,
        );

        // Every page returns new messages + a next cursor (never ends).
        when(
          () => gatewayClient.fetchMessageHistory(
            instanceId: _testInstanceId,
            agentId: _testAgentRemoteId,
            cursor: any(named: 'cursor'),
            limit: 50,
          ),
        ).thenAnswer(
          (_) async => (
            messages: [
              _newMsg(
                serverId: 's-${DateTime.now().microsecondsSinceEpoch}',
                clientId: 'c-${DateTime.now().microsecondsSinceEpoch}',
              ),
            ],
            nextCursor: 'more',
          ),
        );
        when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
          inv,
        ) async {
          final msgs = inv.positionalArguments[0] as List<Message>;
          return msgs; // All new — never trips the dedup stop condition
        });

        final result = await cappedService.catchUp(_testInstanceId);

        expect(result.inserted, 2); // 2 pages × 1 message
        expect(result.truncated, isTrue);
        // Exactly 2 fetch calls (the cap), not 3.
        verify(
          () => gatewayClient.fetchMessageHistory(
            instanceId: _testInstanceId,
            agentId: _testAgentRemoteId,
            cursor: any(named: 'cursor'),
            limit: 50,
          ),
        ).called(2);
      },
    );

    test(
      'reports truncated=false when history fully caught up before cap',
      () async {
        final cappedService = MessageCatchUpService(
          agentRepo: agentRepo,
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          gatewayClient: gatewayClient,
          logger: logger,
          maxPagesPerConversation: 2,
        );

        // Page 1: new messages, page 2: cursor runs out.
        when(
          () => gatewayClient.fetchMessageHistory(
            instanceId: _testInstanceId,
            agentId: _testAgentRemoteId,
            cursor: null,
            limit: 50,
          ),
        ).thenAnswer(
          (_) async => (
            messages: [_newMsg(serverId: 's1', clientId: 'c1')],
            nextCursor: 'p2',
          ),
        );
        when(
          () => gatewayClient.fetchMessageHistory(
            instanceId: _testInstanceId,
            agentId: _testAgentRemoteId,
            cursor: 'p2',
            limit: 50,
          ),
        ).thenAnswer(
          (_) async => (
            messages: [_newMsg(serverId: 's2', clientId: 'c2')],
            nextCursor: null, // no more pages
          ),
        );
        when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
          inv,
        ) async {
          final msgs = inv.positionalArguments[0] as List<Message>;
          return msgs;
        });

        final result = await cappedService.catchUp(_testInstanceId);

        expect(result.inserted, 2);
        expect(result.truncated, isFalse); // Reached end of history, not cap
      },
    );
  });

  group('catchUp - error isolation', () {
    test('continues to next agent when one agent fails', () async {
      final agent2 = Agent(
        localId: 'agent-local-2',
        remoteId: 'agent-remote-2',
        instanceId: _testInstanceId,
        name: '代码虾',
      );
      when(
        () => agentRepo.getByInstanceId(_testInstanceId),
      ).thenAnswer((_) async => [_testAgent(), agent2]);

      // Agent 1: Gateway fails
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: null,
          limit: 50,
        ),
      ).thenThrow(Exception('network error'));
      // Agent 2: succeeds
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: 'agent-remote-2',
          cursor: null,
          limit: 50,
        ),
      ).thenAnswer(
        (_) async => (
          messages: [_newMsg(serverId: 's-agent2', clientId: 'c-agent2')],
          nextCursor: null,
        ),
      );
      when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
        inv,
      ) async {
        final msgs = inv.positionalArguments[0] as List<Message>;
        return msgs;
      });

      final result = await service.catchUp(_testInstanceId);

      // Only agent 2's message was inserted (agent 1 failed but was caught)
      expect(result.inserted, 1);
      expect(result.truncated, isFalse);
      expect(logger.errors.any((e) => e.contains('network error')), isTrue);
      // Agent 2's getOrCreate was still called
      verify(
        () => conversationRepo.getOrCreate(_testInstanceId, 'agent-local-2'),
      ).called(1);
    });

    test(
      'Gateway fetch failure does not throw — logs and returns partial',
      () async {
        when(
          () => gatewayClient.fetchMessageHistory(
            instanceId: any(named: 'instanceId'),
            agentId: any(named: 'agentId'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          ),
        ).thenThrow(Exception('gateway down'));

        // Should not throw
        final result = await service.catchUp(_testInstanceId);
        expect(result.inserted, 0);
        expect(result.truncated, isFalse);
        expect(logger.errors, isNotEmpty);
      },
    );
  });

  group('catchUp - conversation pre-creation', () {
    test('calls getOrCreate before inserting messages', () async {
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => (
          messages: [_newMsg(serverId: 's1', clientId: 'c1')],
          nextCursor: null,
        ),
      );
      when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
        inv,
      ) async {
        final msgs = inv.positionalArguments[0] as List<Message>;
        return msgs;
      });

      await service.catchUp(_testInstanceId);

      // getOrCreate BEFORE batchInsertByIndexedIds
      verify(
        () => conversationRepo.getOrCreate(_testInstanceId, _testAgentLocalId),
      ).called(1);
    });
  });

  group('catchUp - re-entrancy', () {
    test('rejects concurrent catch-up for the same instance', () async {
      // Make the first fetch hang
      final completer =
          Completer<({List<Message> messages, String? nextCursor})>();
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          cursor: any(named: 'cursor'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) => completer.future);

      final first = service.catchUp(_testInstanceId);
      final second = service.catchUp(_testInstanceId);

      completer.complete((messages: <Message>[], nextCursor: null));

      final results = await Future.wait([first, second]);
      expect(results.map((r) => r.inserted), [0, 0]);
      expect(results.every((r) => !r.truncated), isTrue);
      // Second call was rejected — agentRepo queried only once (by first call)
      verify(() => agentRepo.getByInstanceId(_testInstanceId)).called(1);
    });
  });

  group('catchUp - conversationId normalization', () {
    test(
      'normalizes empty conversationId to canonical hash before insert',
      () async {
        final msgFromGateway = Message(
          clientId: 'c-gw',
          serverId: 's-gw',
          conversationId: '', // Gateway may return empty conversationId
          agentId: _testAgentRemoteId,
          role: MessageRole.agent,
          content: 'Hello',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 0,
        );

        when(
          () => gatewayClient.fetchMessageHistory(
            instanceId: any(named: 'instanceId'),
            agentId: any(named: 'agentId'),
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => (messages: [msgFromGateway], nextCursor: null),
        );

        // Capture what was passed to batchInsertByIndexedIds
        List<Message>? captured;
        when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
          inv,
        ) async {
          captured = inv.positionalArguments[0] as List<Message>;
          return captured!;
        });

        await service.catchUp(_testInstanceId);

        // The inserted message should have a non-empty conversationId
        expect(captured, isNotNull);
        expect(captured!.single.conversationId, isNotEmpty);
        expect(captured!.single.conversationId, isNot(''));
      },
    );
  });
}
