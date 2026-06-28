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

    // Default merge-path stubs: all inbound messages are treated as NEW
    // (identity miss + no soft-match). Tests that need "known" messages
    // override getByServerId specifically (mocktail LIFO: later stub wins).
    // CatchUp now uses MergeInboundMessageUseCase (not batchInsertByIndexedIds).
    when(() => messageRepo.getByClientId(any())).thenAnswer((_) async => null);
    when(() => messageRepo.getByServerId(any())).thenAnswer((_) async => null);
    when(
      () => messageRepo.getByConversation(any(), limit: any(named: 'limit')),
    ).thenAnswer((_) async => []);
    when(
      () => messageRepo.insert(any()),
    ).thenAnswer((inv) async => inv.positionalArguments[0] as Message);
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

      // Page 1: msg1 is new, msg2 is known → should stop after this page.
      // msg2 is "known" because its serverId already exists locally.
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
      // Override: msg2's serverId already in local DB → merge returns existing.
      when(
        () => messageRepo.getByServerId('known-1'),
      ).thenAnswer((_) async => msg2);

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
        // All new (no override) — never trips the dedup stop condition.

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

      await service.catchUp(_testInstanceId);

      // getOrCreate BEFORE merge/insert
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

        // Capture what was passed to insert (merge path — msg is new here).
        Message? captured;
        when(() => messageRepo.insert(any())).thenAnswer((inv) async {
          captured = inv.positionalArguments[0] as Message;
          return captured!;
        });

        await service.catchUp(_testInstanceId);

        // The inserted message should have a non-empty (normalized) conversationId.
        expect(captured, isNotNull);
        expect(captured!.conversationId, isNotEmpty);
        expect(captured!.conversationId, isNot(''));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Bug #1 (空内容 → 误停止)：mergeWithStatus 对空内容 text 返回 wasNew=false,
  // CatchUp 把它当 pageKnown++ 计入,触发 `if (pageKnown > 0) break;` 提前停止,
  // 同页的真实新消息被丢弃。
  // 修法:MergeResult 区分 wasSkipped 与「命中已有行」,CatchUp 只把后两者计入
  // pageKnown,空内容跳过既不计 pageKnown 也不计 pageNew。
  // ---------------------------------------------------------------------------
  group('catchUp - empty-content skip must not trigger stop condition', () {
    test(
      'page with 1 empty text + 1 real new msg inserts the real msg '
      'and does NOT break early (regression: empty skipped ≠ known)',
      () async {
        final emptyMsg = Message(
          clientId: 'empty-cid',
          serverId: 'empty-srv',
          conversationId: '',
          agentId: _testAgentRemoteId,
          role: MessageRole.agent,
          content: '', // 空内容 —— merge 应跳过(wasSkipped=true)
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
          timestamp: 1718000000000,
        );
        final realMsg = Message(
          clientId: 'real-cid',
          serverId: 'real-srv',
          conversationId: '',
          agentId: _testAgentRemoteId,
          role: MessageRole.agent,
          content: 'real content',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 2,
          timestamp: 1718000000001,
        );

        when(
          () => gatewayClient.fetchMessageHistory(
            instanceId: _testInstanceId,
            agentId: _testAgentRemoteId,
            cursor: null,
            limit: 50,
          ),
        ).thenAnswer(
          (_) async => (messages: [emptyMsg, realMsg], nextCursor: null),
        );

        // 捕获 insert 调用以便断言哪条消息真正入库。
        final inserted = <Message>[];
        when(() => messageRepo.insert(any())).thenAnswer((inv) async {
          final m = inv.positionalArguments[0] as Message;
          inserted.add(m);
          return m;
        });

        final result = await service.catchUp(_testInstanceId);

        // 真实消息必须入库,不能因为前一条空内容被错误停止而丢失。
        expect(
          result.inserted,
          1,
          reason: 'realMsg 必须入库;空内容只能算 skipped,不能算 known。',
        );
        expect(
          inserted.where((m) => m.clientId == 'real-cid').length,
          1,
          reason: 'realMsg 必须被 insert 一次(携带 normalized conversationId)',
        );
        expect(
          inserted.where((m) => m.clientId == 'empty-cid').length,
          0,
          reason: 'emptyMsg 不应被 insert —— merge 在第 0 步跳过',
        );
      },
    );

    test('a page of ALL empty-content text messages does not falsely report '
        '"caught up" (truncated=false, inserted=0, but loop should not break '
        'prematurely on identity/soft-match signal)', () async {
      final empty1 = Message(
        clientId: 'e1',
        serverId: null,
        conversationId: '',
        agentId: _testAgentRemoteId,
        role: MessageRole.agent,
        content: '',
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: 1,
        timestamp: 1,
      );
      final empty2 = Message(
        clientId: 'e2',
        serverId: null,
        conversationId: '',
        agentId: _testAgentRemoteId,
        role: MessageRole.agent,
        content: null, // null content 同样应跳过
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: 2,
        timestamp: 2,
      );

      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: null,
          limit: 50,
        ),
      ).thenAnswer((_) async => (messages: [empty1, empty2], nextCursor: null));

      final result = await service.catchUp(_testInstanceId);

      expect(result.inserted, 0);
      expect(result.truncated, isFalse);
      // 关键:不能因 pageKnown>0 提前 break。空内容既非 new 也非 known——
      // nextCursor=null 时正常结束,不应触发「已追平」语义。
      expect(
        logger.infos.any((s) => s.contains('Caught up')),
        isFalse,
        reason: '空内容 skip 不能误触发「已追平」日志',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Bug #2 修复补强: catch-up 路径必须主动调用 dedupeConversation 清理历史
  // 重复行 —— 单靠 ChatViewModel 在打开聊天时调用,用户从未打开的会话里
  // 重复永远在,PR 自己的「重复根除」承诺并未在 catch-up 路径上兑现。
  // ---------------------------------------------------------------------------
  group('catchUp - calls dedupeConversation to clean legacy duplicates', () {
    test('after a single-page catch-up, dedupeConversation is called '
        'for the agent conversation', () async {
      final msg = _newMsg(serverId: 's1', clientId: 'c1');
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: null,
          limit: 50,
        ),
      ).thenAnswer((_) async => (messages: [msg], nextCursor: null));

      await service.catchUp(_testInstanceId);

      // catch-up 完成后,无论是否新插入消息,都应调用一次 dedupeConversation。
      // (cleanup 是幂等的,无重复时 no-op。)
      final expectedConvId = Conversation.generateId(
        _testInstanceId,
        _testAgentLocalId,
      );
      verify(() => messageRepo.dedupeConversation(expectedConvId)).called(1);
    });

    test('dedupeConversation is called even when catch-up inserts nothing '
        '(early stop on known message)', () async {
      final known = _newMsg(serverId: 'known-1', clientId: 'kc1');
      final unknown = _newMsg(serverId: 'new-1', clientId: 'nc1');
      when(
        () => gatewayClient.fetchMessageHistory(
          instanceId: _testInstanceId,
          agentId: _testAgentRemoteId,
          cursor: null,
          limit: 50,
        ),
      ).thenAnswer((_) async => (messages: [unknown, known], nextCursor: null));
      when(
        () => messageRepo.getByServerId('known-1'),
      ).thenAnswer((_) async => known);

      final result = await service.catchUp(_testInstanceId);

      // pageKnown>0 → break,但 dedupeConversation 仍应在最后被调用一次。
      expect(result.inserted, 1);
      final expectedConvId = Conversation.generateId(
        _testInstanceId,
        _testAgentLocalId,
      );
      verify(() => messageRepo.dedupeConversation(expectedConvId)).called(1);
    });
  });
}
