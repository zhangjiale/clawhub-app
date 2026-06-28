import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart'
    show StreamingDelta, StreamingDone, StreamingEvent;
import 'package:claw_hub/core/acl/i_gateway_client.dart'
    show GatewayConnectionState;
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

void main() {
  group('ChatViewModel.send', () {
    late InMemoryAgentRepo agentRepo;
    late InMemoryMessageRepo messageRepo;
    late InMemoryConversationRepo conversationRepo;
    late InMemoryInstanceRepo instanceRepo;
    late MockGatewayClient gateway;
    late IAchievementChecker achievementChecker;

    setUp(() {
      agentRepo = InMemoryAgentRepo();
      messageRepo = InMemoryMessageRepo();
      conversationRepo = InMemoryConversationRepo();
      instanceRepo = InMemoryInstanceRepo();
      gateway = MockGatewayClient();
      achievementChecker = _MockAchievementChecker();
    });

    ChatViewModel createViewModel({
      required String instanceId,
      required String agentId,
    }) {
      return ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: instanceId,
        agentId: agentId,
        achievementChecker: achievementChecker,
        flushDelay: Duration.zero, // synchronous flush for tests
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

    // US-021 AC9: agent 被 Gateway 端删除（tombstoned）时，send() 应拒发并
    // 提示，不把消息塞进 outbox（OutboxProcessor 虽会 skip，但用户得不到
    // 即时反馈，消息会卡 PENDING 到 24h 过期）。
    test('WHEN agent is tombstoned (removed by Gateway) THEN send refuses '
        'with LoadError and does NOT enqueue (US-021)', () async {
      final tombstoned = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
        removedAt: 1719200000000,
      );
      await agentRepo.syncFromGateway('inst-1', [tombstoned]);

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
      // 不显式调 init —— send() 内部会调

      await vm.send('Hello!');

      final state = vm.state;
      expect(
        state.messages,
        isA<LoadError>(),
        reason: 'tombstoned agent 应显示 LoadError',
      );
      expect(
        (state.messages as LoadError).error.toString(),
        contains('removed'),
        reason: '错误信息应提示 agent 已被移除',
      );
      // 关键：不应往 message repo 写入任何消息（不进 outbox）。
      // send() 成功路径会用 clientId 写入 user message，这里抽查一个
      // 可能的 clientId 不存在 —— 更稳妥的是验证 repo 里没有任何消息。
      // InMemoryMessageRepo 无 getAll，用 getByConversation 反查。
      final convId = Conversation.generateId('inst-1', 'local-1');
      final msgs = await messageRepo.getByConversation(convId);
      expect(msgs, isEmpty, reason: 'tombstoned agent 不应产生消息');
      expect(state.thinkingState, ThinkingState.idle, reason: '不应进入 thinking');
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
        instanceRepo: instanceRepo,
        gatewayClient: failingGateway,
        sendMessageUseCase: failingUseCase,
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: achievementChecker,
        flushDelay: Duration.zero, // synchronous flush for tests
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
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: achievementChecker,
        flushDelay: Duration.zero, // synchronous flush for tests
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
    late IAchievementChecker achievementChecker;

    setUp(() {
      agentRepo = InMemoryAgentRepo();
      messageRepo = InMemoryMessageRepo();
      conversationRepo = InMemoryConversationRepo();
      instanceRepo = InMemoryInstanceRepo();
      gateway = _ControllableStreamsGateway();
      achievementChecker = _MockAchievementChecker();
    });

    ChatViewModel createViewModel({
      required String instanceId,
      required String agentId,
    }) {
      return ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: instanceId,
        agentId: agentId,
        achievementChecker: achievementChecker,
        flushDelay: Duration.zero, // synchronous flush for tests
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
      await setupAgentAndInit();

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

      // After the ChatViewModel fix, the message is inserted with the
      // canonical conversation ID (SHA-256 hash) rather than the raw
      // conversationId from the Gateway event.  This prevents FK
      // constraint violations when the Gateway sends an ID that doesn't
      // match any row in the conversations table.
      final canonicalConvId = Conversation.generateId('inst-1', 'local-1');
      final messages = await messageRepo.getByConversation(canonicalConvId);
      expect(
        messages.any((m) => m.clientId == 'reply-2'),
        isTrue,
        reason:
            'Agent reply from stream should be persisted to repo '
            '(with conversationId normalised to SHA-256 hash)',
      );
    });

    test('message stream: agent reply updates conversation preview '
        '(regression: message hub must show the actual last message, '
        'not always the user\'s last message)', () async {
      final vm = await setupAgentAndInit();
      final canonicalConvId = Conversation.generateId('inst-1', 'local-1');

      // User sends a message — preview becomes "你: <text>".
      await vm.send('用户的问题');

      var conv = await conversationRepo.getById(canonicalConvId);
      expect(conv!.lastMessageRole, MessageRole.user);
      expect(conv.lastMessagePreview, '你: 用户的问题');

      // Agent replies — the conversation preview MUST be updated to the
      // agent's reply so the Message Hub shows the true last message.
      gateway.emitMessage(
        'inst-1',
        Message(
          clientId: 'reply-preview-1',
          serverId: 'srv-preview-1',
          conversationId: 'raw-conv-id',
          agentId: 'r-1',
          role: MessageRole.agent,
          content: 'Agent 的最终回答',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      conv = await conversationRepo.getById(canonicalConvId);
      expect(conv, isNotNull);
      expect(
        conv!.lastMessageRole,
        MessageRole.agent,
        reason: 'Conversation preview role should reflect the agent reply',
      );
      expect(
        conv.lastMessagePreview,
        'Agent 的最终回答',
        reason:
            'Conversation preview should show the agent reply text '
            '(no "你:" prefix since it is the agent)',
      );
      expect(
        conv.lastMessageId,
        'reply-preview-1',
        reason: 'Conversation lastMessageId should point at the agent reply',
      );
    });

    test('message stream: tool-call message does NOT pollute conversation '
        'preview (GeneratePreview would otherwise emit "[工具调用]")', () async {
      await setupAgentAndInit();
      final canonicalConvId = Conversation.generateId('inst-1', 'local-1');

      // Establish a real text preview first.
      gateway.emitMessage(
        'inst-1',
        Message(
          clientId: 'agent-text-1',
          agentId: 'r-1',
          conversationId: 'raw',
          role: MessageRole.agent,
          content: '真·最终回复',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // A tool-call message arrives afterwards — it must NOT overwrite the
      // conversation preview with "[工具调用]".
      gateway.emitMessage(
        'inst-1',
        Message(
          clientId: 'tool-call-1',
          agentId: 'r-1',
          conversationId: 'raw',
          role: MessageRole.agent,
          content: 'some tool args',
          type: MessageType.toolCall,
          status: MessageStatus.delivered,
          logicalClock: 2,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final conv = await conversationRepo.getById(canonicalConvId);
      expect(conv, isNotNull);
      expect(
        conv!.lastMessagePreview,
        '真·最终回复',
        reason: 'Tool-call messages must not overwrite the text preview',
      );
      expect(
        conv.lastMessageId,
        'agent-text-1',
        reason: 'lastMessageId must still point at the last text message',
      );
    });

    test('message stream: a late/out-of-order older message does NOT regress '
        'conversation ordering (lastMessageTime must not rewind)', () async {
      await setupAgentAndInit();
      final canonicalConvId = Conversation.generateId('inst-1', 'local-1');

      // Newer agent reply lands first.
      gateway.emitMessage(
        'inst-1',
        Message(
          clientId: 'newer-1',
          agentId: 'r-1',
          conversationId: 'raw',
          role: MessageRole.agent,
          content: 'newer reply',
          type: MessageType.text,
          status: MessageStatus.delivered,
          timestamp: 2_000_000_000,
          logicalClock: 10,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      var conv = await conversationRepo.getById(canonicalConvId);
      final newerTime = conv!.lastMessageTime;

      // An older duplicate/replayed event arrives later. It must NOT
      // rewind lastMessageTime or overwrite the preview.
      gateway.emitMessage(
        'inst-1',
        Message(
          clientId: 'older-1',
          agentId: 'r-1',
          conversationId: 'raw',
          role: MessageRole.agent,
          content: 'older stale reply',
          type: MessageType.text,
          status: MessageStatus.delivered,
          timestamp: 1_000_000_000, // earlier than the newer message
          logicalClock: 5,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      conv = await conversationRepo.getById(canonicalConvId);
      expect(conv, isNotNull);
      expect(
        conv!.lastMessageTime,
        newerTime,
        reason: 'Stale older event must not rewind lastMessageTime',
      );
      expect(
        conv.lastMessagePreview,
        'newer reply',
        reason: 'Preview must stay on the newest message, not the stale one',
      );
    });

    test('message stream: agent reply with small logicalClock '
        'sorts chronologically (not grouped by sender)', () async {
      final vm = await setupAgentAndInit();
      final canonicalConvId = Conversation.generateId('inst-1', 'local-1');

      // User sends first message
      await vm.send('my msg1');

      // Agent replies with logicalClock=1 (simulating Gateway's clock)
      gateway.emitMessage(
        'inst-1',
        Message(
          clientId: 'agent-reply-1',
          conversationId: 'raw-conv-id',
          agentId: 'r-1',
          role: MessageRole.agent,
          content: 'agent msg1',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1, // Gateway's incompatible clock
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // User sends second message
      await vm.send('my msg2');

      // Agent replies again with logicalClock=2
      gateway.emitMessage(
        'inst-1',
        Message(
          clientId: 'agent-reply-2',
          conversationId: 'raw-conv-id',
          agentId: 'r-1',
          role: MessageRole.agent,
          content: 'agent msg2',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 2, // Gateway's incompatible clock
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Verify chronological order: user1, agent1, user2, agent2
      // getByConversation returns DESC, ListView reverses → ASC visual.
      // We check DESC order: agent2, user2, agent1, user1.
      final messages = await messageRepo.getByConversation(canonicalConvId);
      expect(messages.length, 4);

      // In DESC order, the newest (highest logicalClock) is first.
      // With the fix, agent replies get client-timestamp logicalClock,
      // so they sort correctly relative to user messages.
      final contents = messages.map((m) => m.content).toList();
      expect(
        contents,
        ['agent msg2', 'my msg2', 'agent msg1', 'my msg1'],
        reason:
            'Messages should be in strict chronological DESC order. '
            'Agent replies must NOT be grouped after all user messages '
            '(which happens when logicalClock from Gateway is too small).',
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

      test(
        'StringBuffer accumulates correctly across many small deltas',
        () async {
          final vm = await setupAgentAndInit();

          // Emit 20 small deltas (simulating a long streaming response)
          for (var i = 0; i < 20; i++) {
            gateway.emitStreamingEvent(
              'inst-1',
              StreamingDelta(agentId: 'r-1', text: 'ab'),
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));

          expect(
            vm.state.streamingText.length,
            40,
            reason: '20 deltas × 2 chars = 40 chars total',
          );
          expect(
            vm.state.streamingText,
            'ab' * 20,
            reason: 'All deltas should be concatenated in order',
          );
        },
      );

      test('send after streaming clears buffer and resets state', () async {
        final vm = await setupAgentAndInit();

        // Accumulate some streaming text
        gateway.emitStreamingEvent(
          'inst-1',
          StreamingDelta(agentId: 'r-1', text: 'streaming content'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.state.streamingText, 'streaming content');

        // Send a new message — should clear streaming text
        await vm.send('new message');

        expect(
          vm.state.streamingText,
          isEmpty,
          reason: 'New send should clear streaming text buffer',
        );
      });
    });

    // ====================================================================
    // Message routing: per-instance stream → per-agent conversation
    // ====================================================================
    group('message routing (per-instance stream → per-agent conversation)', () {
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
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
          sendMessageUseCase: SendMessageUseCase(
            messageRepo: messageRepo,
            conversationRepo: conversationRepo,
            instanceRepo: instanceRepo,
            gatewayClient: gateway,
          ),
          achievementChecker: _MockAchievementChecker(),
          instanceId: instanceId,
          agentId: agentId,
          flushDelay: Duration.zero,
        );
      }

      Future<void> setupTwoAgentsSameInstance() async {
        final agentA = Agent(
          localId: 'local-a',
          remoteId: 'r-a',
          instanceId: 'inst-1',
          name: 'Agent A',
          themeColor: '#FF0000',
        );
        final agentB = Agent(
          localId: 'local-b',
          remoteId: 'r-b',
          instanceId: 'inst-1',
          name: 'Agent B',
          themeColor: '#0000FF',
        );
        await agentRepo.syncFromGateway('inst-1', [agentA, agentB]);
        await instanceRepo.save(
          Instance(
            id: 'inst-1',
            name: 'Test',
            gatewayUrl: 'wss://test.example.com:443',
            tokenRef: 'tok',
            healthStatus: HealthStatus.online,
            isLocalNetwork: false,
          ),
        );
      }

      // ------------------------------------------------------------------
      // Message routing: per-instance stream, correctly filtered by agentId
      // ------------------------------------------------------------------
      test('message for agent-B is NOT stored when only agent-A VM is active '
          '(agentId guard)', () async {
        await setupTwoAgentsSameInstance();

        // Only create VM for agent A
        final vmA = createViewModel(instanceId: 'inst-1', agentId: 'local-a');
        await vmA.init();

        // Simulate Gateway pushing a message intended for agent B via the
        // per-instance messageStream.  The agentId guard should prevent
        // agent-A's VM from claiming this message.
        final msgForB = Message(
          clientId: 'msg-for-agent-b',
          conversationId: '',
          agentId: 'r-b',
          role: MessageRole.agent,
          content: 'Hello from Agent B',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: DateTime.now().millisecondsSinceEpoch,
        );
        gateway.emitMessage('inst-1', msgForB);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final convA = Conversation.generateId('inst-1', 'local-a');

        // The message should NOT leak into agent-A's conversation
        final msgsInConvA = await messageRepo.getByConversation(convA);
        final leaked = msgsInConvA.where(
          (m) => m.clientId == 'msg-for-agent-b',
        );
        expect(
          leaked,
          isEmpty,
          reason:
              'Messages for other agents must not leak into '
              'agent-A conversation',
        );
      });

      test('message for agent-B is correctly stored in agent-B conversation '
          'when agent-B VM is active', () async {
        await setupTwoAgentsSameInstance();

        // Both VMs active (simulates tab switching with StatefulShellRoute)
        final vmA = createViewModel(instanceId: 'inst-1', agentId: 'local-a');
        await vmA.init();
        final vmB = createViewModel(instanceId: 'inst-1', agentId: 'local-b');
        await vmB.init();

        // Push a message meant for agent B
        final msgForB = Message(
          clientId: 'msg-for-b-v2',
          conversationId: '',
          agentId: 'r-b',
          role: MessageRole.agent,
          content: 'Reply for Agent B',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: DateTime.now().millisecondsSinceEpoch,
        );
        gateway.emitMessage('inst-1', msgForB);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final convA = Conversation.generateId('inst-1', 'local-a');
        final convB = Conversation.generateId('inst-1', 'local-b');

        final storedMsg = await messageRepo.getByClientId('msg-for-b-v2');
        expect(
          storedMsg,
          isNotNull,
          reason:
              'Message should be persisted when the correct agent VM '
              'is listening',
        );

        // The message must be stored in agent-B's conversation
        expect(
          storedMsg!.conversationId,
          convB,
          reason: 'Message for agent-B must be stored in agent-B conversation',
        );

        // And must NOT appear in agent-A's conversation
        final msgsInConvA = await messageRepo.getByConversation(convA);
        expect(
          msgsInConvA.where((m) => m.clientId == 'msg-for-b-v2'),
          isEmpty,
          reason: 'Message for agent-B must not leak into agent-A conversation',
        );
      });

      test('message with empty agentId is still processed '
          '(backward compat with legacy Gateways)', () async {
        await setupTwoAgentsSameInstance();

        final vmA = createViewModel(instanceId: 'inst-1', agentId: 'local-a');
        await vmA.init();

        // Legacy Gateway may omit agentId — the guard must NOT drop these
        final msgNoAgentId = Message(
          clientId: 'msg-no-agent-id',
          conversationId: '',
          agentId: '', // Gateway omitted agentId
          role: MessageRole.agent,
          content: 'Legacy message without agentId',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: DateTime.now().millisecondsSinceEpoch,
        );
        gateway.emitMessage('inst-1', msgNoAgentId);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final convA = Conversation.generateId('inst-1', 'local-a');
        final storedMsg = await messageRepo.getByClientId('msg-no-agent-id');
        expect(
          storedMsg,
          isNotNull,
          reason: 'Messages with empty agentId must still be processed',
        );
        expect(
          storedMsg!.conversationId,
          convA,
          reason: 'Legacy messages are routed to the active conversation',
        );
      });
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

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) async {
    // Return empty history in tests — avoids rootBundle dependency
    // inherited from MockGatewayClient.loadMockData().
    return (messages: <Message>[], nextCursor: null);
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
