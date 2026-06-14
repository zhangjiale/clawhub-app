import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart'
    show GatewayConnectionState, StreamingDelta, StreamingDone, StreamingEvent;
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/ui_kit/async_state.dart';

void main() {
  group('ChatViewModel.send', () {
    late InMemoryAgentRepo agentRepo;
    late InMemoryMessageRepo messageRepo;
    late InMemoryConversationRepo conversationRepo;
    late InMemoryInstanceRepo instanceRepo;
    late MockGatewayClient gateway;

    setUp(() {
      agentRepo = InMemoryAgentRepo();
      messageRepo = InMemoryMessageRepo();
      conversationRepo = InMemoryConversationRepo();
      instanceRepo = InMemoryInstanceRepo();
      gateway = MockGatewayClient();
    });

    ChatViewModel createViewModel({
      required String instanceId,
      required String agentId,
    }) {
      return ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: instanceId,
        agentId: agentId,
      );
    }

    test('WHEN agent is loaded AND init completed THEN send inserts message '
        'and updates state', () async {
      // Setup: add agent to repo
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);

      // Create instance so isConnectable check passes
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test Instance',
          gatewayUrl: 'wss://test.example.com:443',
          tokenRef: 'test-token-ref',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );

      final vm = createViewModel(instanceId: 'inst-1', agentId: 'local-1');
      await vm.init();

      expect(vm.agent, isNotNull, reason: 'Agent should be loaded after init');
      expect(
        vm.state.messages,
        isA<LoadData<List<Message>>>(),
        reason: 'Messages should be loaded after init',
      );

      await vm.send('Hello!');

      final state = vm.state;
      expect(
        state.messages,
        isA<LoadData<List<Message>>>(),
        reason: 'Messages should be LoadData after send',
      );
      final messages = (state.messages as LoadData<List<Message>>).value;
      expect(
        messages.any(
          (m) => m.content == 'Hello!' && m.role == MessageRole.user,
        ),
        isTrue,
        reason: 'Sent message should be present with correct content and role',
      );
      expect(
        state.thinkingState,
        ThinkingState.thinking,
        reason: 'Thinking state should be active after send',
      );
    });

    test('WHEN agent does NOT exist in DB THEN send shows LoadError instead '
        'of silently doing nothing', () async {
      final vm = createViewModel(
        instanceId: 'inst-1',
        agentId: 'local-nonexistent',
      );
      // NOTE: intentionally NOT calling vm.init() — send() will call it internally

      expect(
        vm.agent,
        isNull,
        reason: 'Agent should be null when init not called',
      );

      await vm.send('Hello!');

      // FIX: send() now awaits init() internally, discovers agent is
      // missing, and surfaces LoadError to the UI.
      final state = vm.state;
      expect(
        state.messages,
        isA<LoadError>(),
        reason: 'Should show LoadError when agent not found',
      );
      expect(
        (state.messages as LoadError).error.toString(),
        contains('Agent not found'),
        reason: 'Error message should indicate agent not found',
      );
      expect(
        state.thinkingState,
        ThinkingState.idle,
        reason: 'Thinking state should remain idle on error',
      );
    });

    test('WHEN agent exists but init NOT awaited (race condition) '
        'THEN send awaits init automatically and succeeds', () async {
      // Setup: add agent to repo
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);

      // Create instance
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://t.example.com:443',
          tokenRef: 'test-token-ref',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );

      final vm = createViewModel(instanceId: 'inst-1', agentId: 'local-1');

      // Simulate the provider pattern: call init() but do NOT await it
      // (same as the production code in chat_providers.dart)
      vm.init(); // NOT awaited — just like the provider

      // User sends message before init completes
      // FIX: send() now awaits _initFuture internally, so this succeeds
      await vm.send('Hello!');

      final state = vm.state;
      expect(
        state.messages,
        isA<LoadData<List<Message>>>(),
        reason: 'Messages should be LoadData after send (race handled)',
      );
      final messages = (state.messages as LoadData<List<Message>>).value;
      expect(
        messages.any(
          (m) => m.content == 'Hello!' && m.role == MessageRole.user,
        ),
        isTrue,
        reason: 'Message should be sent even when init raced with send',
      );
      expect(
        state.thinkingState,
        ThinkingState.thinking,
        reason: 'Thinking state should be active after send',
      );
    });

    test('WHEN send fails (gateway throws) THEN thinking stays idle '
        'and message shows FAILED status', () async {
      // Setup: add agent and instance to repos
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
          gatewayUrl: 'wss://t.example.com:443',
          tokenRef: 'test-token-ref',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );

      // Use a gateway that throws on sendMessage
      final failingGateway = _FailingGatewayClient();
      final failingUseCase = SendMessageUseCase(
        messageRepo: messageRepo,
        conversationRepo: conversationRepo,
        instanceRepo: instanceRepo,
        gatewayClient: failingGateway,
      );

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        gatewayClient: failingGateway,
        sendMessageUseCase: failingUseCase,
        instanceId: 'inst-1',
        agentId: 'local-1',
      );
      await vm.init();

      await vm.send('Hello!');

      final state = vm.state;
      // Message should be present with FAILED status
      final messages = (state.messages as LoadData<List<Message>>).value;
      final sentMsg = messages.firstWhere((m) => m.content == 'Hello!');
      expect(
        sentMsg.status,
        MessageStatus.failed,
        reason: 'Message should be FAILED when gateway throws',
      );
      expect(
        state.thinkingState,
        ThinkingState.idle,
        reason: 'Thinking state should stay idle when send fails',
      );
    });

    test('WHEN instance is offline THEN thinking stays idle '
        'and message stays PENDING', () async {
      // Setup: add agent and OFFLINE instance to repos
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
          gatewayUrl: 'wss://t.example.com:443',
          tokenRef: 'test-token-ref',
          healthStatus: HealthStatus.offline,
          isLocalNetwork: false,
        ),
      );

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
      );
      await vm.init();

      await vm.send('Hello!');

      final state = vm.state;
      final messages = (state.messages as LoadData<List<Message>>).value;
      final sentMsg = messages.firstWhere((m) => m.content == 'Hello!');
      expect(
        sentMsg.status,
        MessageStatus.pending,
        reason: 'Message should stay PENDING when instance is offline',
      );
      expect(
        state.thinkingState,
        ThinkingState.idle,
        reason: 'Thinking state should stay idle when message is pending',
      );
    });
  });

  // ==========================================================================
  // Law 16: Stream-driven state mutations
  // ==========================================================================
  group('ChatViewModel stream-driven state mutations', () {
    late InMemoryAgentRepo agentRepo;
    late InMemoryMessageRepo messageRepo;
    late InMemoryConversationRepo conversationRepo;
    late InMemoryInstanceRepo instanceRepo;
    late _ControllableStreamsGateway gateway;

    setUp(() {
      agentRepo = InMemoryAgentRepo();
      messageRepo = InMemoryMessageRepo();
      conversationRepo = InMemoryConversationRepo();
      instanceRepo = InMemoryInstanceRepo();
      gateway = _ControllableStreamsGateway();
    });

    ChatViewModel createViewModel({
      required String instanceId,
      required String agentId,
    }) {
      return ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: instanceId,
        agentId: agentId,
      );
    }

    Future<ChatViewModel> setupAgentAndInit() async {
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

      final vm = createViewModel(instanceId: 'inst-1', agentId: 'local-1');
      await vm.init();
      return vm;
    }

    test('message stream: agent reply stops thinking', () async {
      final vm = await setupAgentAndInit();

      await vm.send('Hello!');
      expect(
        vm.state.thinkingState,
        ThinkingState.thinking,
        reason: 'Should be thinking after sending message',
      );

      final reply = Message(
        clientId: 'reply-1',
        serverId: 'srv-1',
        conversationId: 'conv-inst-1++local-1',
        agentId: 'r-1',
        role: MessageRole.agent,
        content: '你好！',
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: 1,
      );
      gateway.emitMessage('inst-1', reply);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        vm.state.thinkingState,
        ThinkingState.idle,
        reason: 'Agent reply via stream should stop thinking',
      );
    });

    test('message stream: agent reply is inserted into repo', () async {
      final vm = await setupAgentAndInit();

      final reply = Message(
        clientId: 'reply-2',
        serverId: 'srv-2',
        conversationId: 'conv-inst-1++local-1',
        agentId: 'r-1',
        role: MessageRole.agent,
        content: 'Agent reply!',
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: 1,
      );
      gateway.emitMessage('inst-1', reply);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final messages = await messageRepo.getByConversation(
        'conv-inst-1++local-1',
      );
      expect(
        messages.any((m) => m.clientId == 'reply-2'),
        isTrue,
        reason: 'Agent reply from stream should be persisted to repo',
      );
    });

    test('connection state stream: updates state.connectionState', () async {
      final vm = await setupAgentAndInit();

      expect(
        vm.state.connectionState,
        GatewayConnectionState.disconnected,
        reason: 'Initial state should be disconnected',
      );

      gateway.emitConnectionState('inst-1', GatewayConnectionState.connecting);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(vm.state.connectionState, GatewayConnectionState.connecting);

      gateway.emitConnectionState('inst-1', GatewayConnectionState.connected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(vm.state.connectionState, GatewayConnectionState.connected);
    });

    test('tool call stream: adds tool call to state.toolCalls', () async {
      final vm = await setupAgentAndInit();

      expect(vm.state.toolCalls, isEmpty);

      final tc = ToolCall(
        id: 'tc-1',
        messageId: 'msg-1',
        toolName: 'search',
        inputArgs: '{"query":"test"}',
        outputResult: null,
        status: ToolCallStatus.running,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        endedAt: null,
      );
      gateway.emitToolCall('inst-1', tc);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(vm.state.toolCalls, contains('msg-1'));
      expect(vm.state.toolCalls['msg-1']!.toolName, 'search');
      expect(vm.state.toolCalls['msg-1']!.status, ToolCallStatus.running);
    });

    test(
      'tool call stream: updates existing tool call on second event',
      () async {
        final vm = await setupAgentAndInit();

        gateway.emitToolCall(
          'inst-1',
          ToolCall(
            id: 'tc-2',
            messageId: 'msg-2',
            toolName: 'read_file',
            inputArgs: '{"path":"/tmp/test"}',
            outputResult: null,
            status: ToolCallStatus.running,
            startedAt: DateTime.now().millisecondsSinceEpoch,
            endedAt: null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.state.toolCalls['msg-2']!.status, ToolCallStatus.running);

        gateway.emitToolCall(
          'inst-1',
          ToolCall(
            id: 'tc-2',
            messageId: 'msg-2',
            toolName: 'read_file',
            inputArgs: '{"path":"/tmp/test"}',
            outputResult: 'File contents',
            status: ToolCallStatus.success,
            startedAt: DateTime.now().millisecondsSinceEpoch,
            endedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(vm.state.toolCalls['msg-2']!.status, ToolCallStatus.success);
        expect(vm.state.toolCalls['msg-2']!.outputResult, 'File contents');
      },
    );

    // ========================================================================
    // Streaming delta tests (Issue #4: previously uncovered)
    // ========================================================================
    group('streaming delta stream', () {
      test(
        'StreamingDelta with matching agentId accumulates in streamingText',
        () async {
          final vm = await setupAgentAndInit();

          expect(
            vm.state.streamingText,
            isEmpty,
            reason: 'streamingText should start empty',
          );

          gateway.emitStreamingEvent(
            'inst-1',
            StreamingDelta(agentId: 'r-1', text: '你好'),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            vm.state.streamingText,
            '你好',
            reason: 'Delta with matching agentId should be accumulated',
          );

          gateway.emitStreamingEvent(
            'inst-1',
            StreamingDelta(agentId: 'r-1', text: '世界'),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            vm.state.streamingText,
            '你好世界',
            reason: 'Second delta should be appended',
          );
        },
      );

      test(
        'StreamingDone with matching agentId clears streamingText',
        () async {
          final vm = await setupAgentAndInit();

          // First, accumulate some text
          gateway.emitStreamingEvent(
            'inst-1',
            StreamingDelta(agentId: 'r-1', text: '流式内容'),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(vm.state.streamingText, '流式内容');

          // StreamingDone should clear the buffer
          gateway.emitStreamingEvent('inst-1', StreamingDone(agentId: 'r-1'));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            vm.state.streamingText,
            isEmpty,
            reason: 'StreamingDone should clear the streaming buffer',
          );
        },
      );

      test('StreamingDelta with different agentId is ignored', () async {
        final vm = await setupAgentAndInit();

        // Delta for a different agent (r-2, not r-1)
        gateway.emitStreamingEvent(
          'inst-1',
          StreamingDelta(agentId: 'r-2', text: '其他 Agent 的回复'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          vm.state.streamingText,
          isEmpty,
          reason: 'Delta for a different agent should be ignored',
        );

        // Verify our agent's deltas still work
        gateway.emitStreamingEvent(
          'inst-1',
          StreamingDelta(agentId: 'r-1', text: '正确内容'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          vm.state.streamingText,
          '正确内容',
          reason: 'Correct agent delta should accumulate after filtering',
        );
      });

      test(
        'StreamingDone for different agentId does NOT clear our buffer',
        () async {
          final vm = await setupAgentAndInit();

          // Accumulate text for our agent
          gateway.emitStreamingEvent(
            'inst-1',
            StreamingDelta(agentId: 'r-1', text: '我们的内容'),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(vm.state.streamingText, '我们的内容');

          // Done event for a different agent
          gateway.emitStreamingEvent('inst-1', StreamingDone(agentId: 'r-2'));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            vm.state.streamingText,
            '我们的内容',
            reason:
                'StreamingDone for a different agent should NOT clear our buffer',
          );

          // Done event for our agent should still clear
          gateway.emitStreamingEvent('inst-1', StreamingDone(agentId: 'r-1'));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(vm.state.streamingText, isEmpty);
        },
      );
    });
  });
}

/// A gateway client that throws on [sendMessage] to simulate connection failure.
class _FailingGatewayClient extends MockGatewayClient {
  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async {
    throw Exception('Simulated connection failure');
  }
}

/// A gateway client with exposed stream controllers for testing
/// stream-driven state mutations (Law 16).
class _ControllableStreamsGateway extends MockGatewayClient {
  final Map<String, StreamController<Message>> messageCtrls = {};
  final Map<String, StreamController<GatewayConnectionState>> stateCtrls = {};
  final Map<String, StreamController<ToolCall>> toolCallCtrls = {};
  final Map<String, StreamController<StreamingEvent>> streamingCtrls = {};

  @override
  Stream<Message> messageStream(String instanceId) {
    return messageCtrls
        .putIfAbsent(instanceId, () => StreamController<Message>.broadcast())
        .stream;
  }

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) {
    return stateCtrls
        .putIfAbsent(
          instanceId,
          () => StreamController<GatewayConnectionState>.broadcast(),
        )
        .stream;
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

  void emitMessage(String instanceId, Message msg) {
    messageCtrls[instanceId]?.add(msg);
  }

  void emitConnectionState(String instanceId, GatewayConnectionState state) {
    stateCtrls[instanceId]?.add(state);
  }

  void emitToolCall(String instanceId, ToolCall tc) {
    toolCallCtrls[instanceId]?.add(tc);
  }

  void emitStreamingEvent(String instanceId, StreamingEvent event) {
    streamingCtrls[instanceId]?.add(event);
  }

  @override
  Future<void> dispose() async {
    for (final c in messageCtrls.values) {
      await c.close();
    }
    for (final c in stateCtrls.values) {
      await c.close();
    }
    for (final c in toolCallCtrls.values) {
      await c.close();
    }
    for (final c in streamingCtrls.values) {
      await c.close();
    }
    await super.dispose();
  }
}
