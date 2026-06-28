import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart'
    show StreamingDelta, StreamingDone, StreamingEvent;
import 'package:claw_hub/core/acl/i_gateway_client.dart'
    show GatewayConnectionState;
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// A gateway client with exposed stream controllers for testing
/// (mirrors the helper in chat_view_model_send_test.dart).
class _ControllableStreamsGateway extends MockGatewayClient {
  final Map<String, StreamController<Message>> messageCtrls = {};
  final Map<String, StreamController<GatewayConnectionState>> stateCtrls = {};
  final Map<String, StreamController<ToolCall>> toolCallCtrls = {};
  final Map<String, StreamController<StreamingEvent>> streamingCtrls = {};
  // 当非空时,fetchMessageHistory 返回该列表。默认空(保持原有行为)。
  List<Message> fetchHistoryMessages = const [];
  // 为 true 时,connectionStateStream 模拟 [ReplayableConnectionState] 对
  // 已连接实例的行为:先向新订阅者下沉一个 connected seed,再透传广播。
  final bool seedConnectedOnSubscribe;

  _ControllableStreamsGateway({this.seedConnectedOnSubscribe = false});

  @override
  Stream<Message> messageStream(String instanceId) {
    return messageCtrls
        .putIfAbsent(instanceId, () => StreamController<Message>.broadcast())
        .stream;
  }

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) {
    final live = stateCtrls
        .putIfAbsent(
          instanceId,
          () => StreamController<GatewayConnectionState>.broadcast(),
        )
        .stream;
    if (!seedConnectedOnSubscribe) return live;
    return _seededConnected(live);
  }

  static Stream<GatewayConnectionState> _seededConnected(
    Stream<GatewayConnectionState> live,
  ) async* {
    yield GatewayConnectionState.connected;
    yield* live;
  }

  @override
  Stream<ToolCall> toolCallStream(String instanceId) {
    return toolCallCtrls
        .putIfAbsent(instanceId, () => StreamController<ToolCall>.broadcast())
        .stream;
  }

  @override
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) {
    return streamingCtrls
        .putIfAbsent(
          instanceId,
          () => StreamController<StreamingEvent>.broadcast(),
        )
        .stream;
  }

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) async {
    return (messages: fetchHistoryMessages, nextCursor: null);
  }

  void emitMessage(String instanceId, Message msg) {
    messageCtrls[instanceId]?.add(msg);
  }

  void emitStreamingEvent(String instanceId, StreamingEvent event) {
    streamingCtrls[instanceId]?.add(event);
  }

  void emitConnectionState(String instanceId, GatewayConnectionState state) {
    stateCtrls[instanceId]?.add(state);
  }
}

/// [InMemoryMessageRepo] 子类:让 [getByConversation] 抛异常,
/// 用于验证 reloadMessages 在流式期间被跳过(不调用 _loadMessages)。
class _ThrowOnGetByConversationRepo extends InMemoryMessageRepo {
  @override
  Future<List<Message>> getByConversation(
    String conversationId, {
    String? before,
    int limit = 50,
  }) {
    throw StateError('getByConversation should not be called during streaming');
  }
}

/// [InMemoryMessageRepo] 子类:让 [insert] 抛异常,
/// 用于验证 messageStream 监听器对 FK/约束冲突的兜底(不向上抛、不中断)。
class _ThrowOnInsertRepo extends InMemoryMessageRepo {
  @override
  Future<Message> insert(Message message) {
    throw StateError('insert failed (FK constraint)');
  }
}

/// [InMemoryMessageRepo] 子类:计数 [getByConversation] 调用次数,
/// 用于验证 connected seed 不触发冗余 reloadMessages。
class _CountingGetByConversationRepo extends InMemoryMessageRepo {
  int getByConversationCallCount = 0;

  @override
  Future<List<Message>> getByConversation(
    String conversationId, {
    String? before,
    int limit = 50,
  }) {
    getByConversationCallCount++;
    return super.getByConversation(
      conversationId,
      before: before,
      limit: limit,
    );
  }
}

class _CountingConversationRepo extends InMemoryConversationRepo {
  int updateLastMessageCallCount = 0;

  @override
  Future<Conversation> updateLastMessage({
    required String conversationId,
    required String messageId,
    required String preview,
    required int timestamp,
    required MessageRole role,
  }) {
    updateLastMessageCallCount++;
    return super.updateLastMessage(
      conversationId: conversationId,
      messageId: messageId,
      preview: preview,
      timestamp: timestamp,
      role: role,
    );
  }
}

void main() {
  group('ChatViewModel streaming guard (clear-cache tick safety)', () {
    late InMemoryAgentRepo agentRepo;
    late InMemoryMessageRepo messageRepo;
    late InMemoryConversationRepo conversationRepo;
    late InMemoryInstanceRepo instanceRepo;
    late _ControllableStreamsGateway gateway;
    late IAchievementChecker achievementChecker;

    ChatViewModel createViewModel(
      InMemoryMessageRepo repo, {
      InMemoryConversationRepo? conversationOverride,
    }) {
      final conversations = conversationOverride ?? conversationRepo;
      return ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversations,
        messageRepo: repo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: repo,
          conversationRepo: conversations,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: achievementChecker,
        flushDelay: Duration.zero,
      );
    }

    Future<ChatViewModel> setupAndInit(
      InMemoryMessageRepo repo, {
      InMemoryConversationRepo? conversationOverride,
    }) async {
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.example.com:443',
          tokenRef: 'test-token-ref',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );
      final vm = createViewModel(
        repo,
        conversationOverride: conversationOverride,
      );
      await vm.init();
      return vm;
    }

    setUp(() {
      agentRepo = InMemoryAgentRepo();
      messageRepo = InMemoryMessageRepo();
      conversationRepo = InMemoryConversationRepo();
      instanceRepo = InMemoryInstanceRepo();
      gateway = _ControllableStreamsGateway();
      achievementChecker = _MockAchievementChecker();
    });

    test('isStreaming is false initially', () async {
      final vm = await setupAndInit(messageRepo);
      expect(vm.isStreaming, isFalse);
      vm.dispose();
    });

    test(
      'isStreaming flips true on StreamingDelta, false on StreamingDone',
      () async {
        final vm = await setupAndInit(messageRepo);

        gateway.emitStreamingEvent(
          'inst-1',
          StreamingDelta(agentId: 'r-1', text: '你好'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.isStreaming, isTrue, reason: 'delta should mark streaming');

        gateway.emitStreamingEvent('inst-1', StreamingDone(agentId: 'r-1'));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.isStreaming, isFalse, reason: 'done should clear streaming');

        vm.dispose();
      },
    );

    test(
      'reloadMessages during streaming is a no-op (skips getByConversation)',
      () async {
        // getByConversation throws — if reloadMessages is NOT skipped,
        // _loadMessages catches it and sets state.messages = LoadError.
        // Skip => state.messages unchanged.
        final throwingRepo = _ThrowOnGetByConversationRepo();
        final vm = await setupAndInit(throwingRepo);
        final messagesBefore = vm.state.messages;

        gateway.emitStreamingEvent(
          'inst-1',
          StreamingDelta(agentId: 'r-1', text: '流式中'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.isStreaming, isTrue);

        await vm.reloadMessages(); // must be skipped

        expect(
          vm.state.messages,
          same(messagesBefore),
          reason: 'reloadMessages during streaming must be a no-op',
        );
        vm.dispose();
      },
    );

    test(
      'messageStream insert failure is tolerated (does not throw upward)',
      () async {
        // insert throws (simulating FK constraint failure). The messageStream
        // listener must catch it and not propagate — otherwise subsequent
        // messages are lost and the VM state is corrupted.
        final throwingRepo = _ThrowOnInsertRepo();
        final vm = await setupAndInit(throwingRepo);

        final reply = Message(
          clientId: 'reply-1',
          serverId: null,
          conversationId: '',
          agentId: 'r-1',
          role: MessageRole.agent,
          content: '回复',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
        );

        // Should not throw.
        gateway.emitMessage('inst-1', reply);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // VM still usable: state.messages is not stuck in LoadError from a
        // propagated exception.
        expect(vm.state.messages, isA<LoadData<List<Message>>>());
        vm.dispose();
      },
    );

    // ---------------------------------------------------------------
    // Regression: 网关断开导致 _isStreaming 卡死 (US-030 clear-cache tick)
    //
    // 旧行为:StreamingDelta 到达后 _isStreaming=true,但只有 StreamingDone /
    // agent Message / send() / onError / dispose 五个路径会重置它。网关断开
    // 不重置 → 用户随后点击「清除全部缓存」时 cacheClearedTickProvider++
    // → reloadMessages() 在 `if (_isStreaming) return;` 处早退 → state.messages
    // 保留旧快照。修复: connection-state listener 在 disconnected / reconnecting
    // 时主动重置 _isStreaming=false,让 reload 正常进行。
    // ---------------------------------------------------------------
    test(
      'isStreaming resets to false when connection drops mid-stream',
      () async {
        final vm = await setupAndInit(messageRepo);

        gateway.emitStreamingEvent(
          'inst-1',
          StreamingDelta(agentId: 'r-1', text: 'd'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.isStreaming, isTrue, reason: 'delta should mark streaming');

        // Simulate Gateway disconnect mid-stream WITHOUT a StreamingDone.
        gateway.emitConnectionState(
          'inst-1',
          GatewayConnectionState.disconnected,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          vm.isStreaming,
          isFalse,
          reason:
              'disconnect must reset streaming flag so reloadMessages '
              'can proceed on subsequent cacheClearedTickProvider tick',
        );
        vm.dispose();
      },
    );

    test('reloadMessages after disconnect-mid-stream proceeds '
        '(cache-cleared tick no longer skipped)', () async {
      // Throw-on-getByConversation repo: if reloadMessages proceeds, the
      // throw is caught and state.messages becomes LoadError. If skipped,
      // state.messages stays LoadData(empty).
      final throwingRepo = _ThrowOnGetByConversationRepo();
      final vm = await setupAndInit(throwingRepo);
      final messagesBefore = vm.state.messages;

      gateway.emitStreamingEvent(
        'inst-1',
        StreamingDelta(agentId: 'r-1', text: 'd'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(vm.isStreaming, isTrue);

      // Connection drops — _isStreaming must reset.
      gateway.emitConnectionState(
        'inst-1',
        GatewayConnectionState.disconnected,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(vm.isStreaming, isFalse);

      // Simulate the cacheClearedTickProvider++ → reloadMessages() chain.
      // Post-fix: reloadMessages proceeds; the throw makes state.messages
      // become LoadError (NOT same(messagesBefore)).
      await vm.reloadMessages();

      expect(
        vm.state.messages,
        isNot(same(messagesBefore)),
        reason:
            'reloadMessages must proceed after disconnect-mid-stream '
            '— pre-fix it would skip on stale _isStreaming=true',
      );
      expect(vm.state.messages, isA<LoadError<List<Message>>>());
      vm.dispose();
    });

    test('isStreaming resets to false on reconnecting state too', () async {
      final vm = await setupAndInit(messageRepo);

      gateway.emitStreamingEvent(
        'inst-1',
        StreamingDelta(agentId: 'r-1', text: 'd'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // recovering (the more common mid-stream Gateway state before
      // falling back to disconnected) must also reset the flag.
      gateway.emitConnectionState('inst-1', GatewayConnectionState.recovering);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(vm.isStreaming, isFalse);
      vm.dispose();
    });

    // ---------------------------------------------------------------
    // Regression: fetchMessageHistory 的 insert 循环必须有 per-iteration
    // try/catch (与 messageStream 路径对称)。
    //
    // 旧行为:循环内的 _messageRepo.insert 抛 FK 异常时,整个循环中止,
    // _loadMessages() 永不调用,后续消息静默丢失。
    // 修复:每条 insert 包 try/catch (debugPrint + continue),与流式路径
    // 行 368-379 完全对称。
    // ---------------------------------------------------------------
    test('fetchMessageHistory per-insert failure does NOT abort the whole loop '
        '(continues + still calls _loadMessages)', () async {
      // Gateway 返回 3 条历史;配合 _ThrowOnInsertRepo 模拟所有 insert 都
      // 抛 FK 异常。修复前:整批 import 中止,_loadMessages 不调用,
      // state.messages 卡在 LoadError 或预存快照。修复后:逐条 catch,
      // _loadMessages 仍执行,state.messages = LoadData(空)。
      gateway.fetchHistoryMessages = [
        Message(
          clientId: 'hist-1',
          serverId: null,
          conversationId: '',
          agentId: 'r-1',
          role: MessageRole.agent,
          content: '历史 1',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
          timestamp: 1,
        ),
        Message(
          clientId: 'hist-2',
          serverId: null,
          conversationId: '',
          agentId: 'r-1',
          role: MessageRole.agent,
          content: '历史 2',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 2,
          timestamp: 2,
        ),
        Message(
          clientId: 'hist-3',
          serverId: null,
          conversationId: '',
          agentId: 'r-1',
          role: MessageRole.agent,
          content: '历史 3',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 3,
          timestamp: 3,
        ),
      ];
      final throwingRepo = _ThrowOnInsertRepo();
      final vm = await setupAndInit(throwingRepo);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      // _loadMessages 仍被调用 → LoadData(空),不是 LoadError
      expect(
        vm.state.messages,
        isA<LoadData<List<Message>>>(),
        reason:
            'per-insert guard must let _loadMessages run '
            'even when every insert throws',
      );
      vm.dispose();
    });

    test(
      'rapid incoming messages coalesce preview update and message reload',
      () async {
        final countingMessages = _CountingGetByConversationRepo();
        final countingConversations = _CountingConversationRepo();
        final vm = await setupAndInit(
          countingMessages,
          conversationOverride: countingConversations,
        );
        final baselineLoads = countingMessages.getByConversationCallCount;

        for (var i = 0; i < 3; i++) {
          gateway.emitMessage(
            'inst-1',
            Message(
              clientId: 'reply-$i',
              serverId: null,
              conversationId: '',
              agentId: 'r-1',
              role: MessageRole.agent,
              content: '回复 $i',
              type: MessageType.text,
              status: MessageStatus.delivered,
              logicalClock: i + 1,
              timestamp: i + 1,
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final data = vm.state.messages as LoadData<List<Message>>;
        expect(
          data.value.map((m) => m.clientId),
          containsAll(['reply-0', 'reply-1', 'reply-2']),
        );
        expect(
          countingMessages.getByConversationCallCount - baselineLoads,
          1,
          reason: '同一事件循环内的多条入站消息应合并为一次全量 reload',
        );
        expect(
          countingConversations.updateLastMessageCallCount,
          1,
          reason: 'conversation preview 只需要写最终最新一条消息',
        );
        final conversation = await countingConversations.getById(
          Conversation.generateId('inst-1', 'local-1'),
        );
        expect(conversation!.lastMessageId, 'reply-2');
        vm.dispose();
      },
    );

    test(
      'connected seed does NOT trigger redundant reloadMessages on cold start',
      () async {
        // 模拟「实例已 connected」：connectionStateStream 下沉 connected seed。
        gateway = _ControllableStreamsGateway(seedConnectedOnSubscribe: true);
        final countingRepo = _CountingGetByConversationRepo();

        final vm = await setupAndInit(countingRepo);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // _init() 自身调用 _loadMessages() 两次（初始快照 + 历史拉取后）,
        // 加 N+1 修复后的历史预取（line 635），故基线为 3。connected seed
        // 必须被抑制 —— 否则会在此多出第 4 次 getByConversation
        // （即本次回归要锁住的冗余查询）。
        expect(
          countingRepo.getByConversationCallCount,
          3,
          reason:
              'connected seed must not trigger a redundant reloadMessages — '
              '_init() already loaded the latest snapshot twice (initial + '
              'post-history) plus one history prefetch (N+1 fix). A 4th call '
              'means the synthetic seed slipped through and fired '
              'reloadMessages() on cold start.',
        );

        // 真实 connecting→connected 转换仍照常重载（拾取 outbox 冲刷）。
        gateway.emitConnectionState(
          'inst-1',
          GatewayConnectionState.connecting,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        gateway.emitConnectionState('inst-1', GatewayConnectionState.connected);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          countingRepo.getByConversationCallCount,
          4,
          reason:
              'real connecting→connected transition must still reload to pick '
              'up OutboxProcessor PENDING→SENT flushes.',
        );
        vm.dispose();
      },
    );
  });
}
