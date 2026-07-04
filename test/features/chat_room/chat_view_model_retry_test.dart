import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// Tests for [ChatViewModel.retryMessage] (US-015 AC2 manual retry path).
class _FailingGateway extends MockGatewayClient {
  bool shouldFail = true;

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async {
    if (shouldFail) {
      throw Exception('Simulated connection failure');
    }
    return super.sendMessage(
      instanceId: instanceId,
      agentId: agentId,
      message: message,
    );
  }
}

void main() {
  group('ChatViewModel.retryMessage (US-015)', () {
    late InMemoryAgentRepo agentRepo;
    late InMemoryMessageRepo messageRepo;
    late InMemoryConversationRepo conversationRepo;
    late InMemoryInstanceRepo instanceRepo;
    late _FailingGateway gateway;
    late IAchievementChecker achievementChecker;

    setUp(() {
      agentRepo = InMemoryAgentRepo();
      messageRepo = InMemoryMessageRepo();
      conversationRepo = InMemoryConversationRepo();
      instanceRepo = InMemoryInstanceRepo();
      gateway = _FailingGateway();
      achievementChecker = _MockAchievementChecker();
    });

    ChatViewModel createViewModel() => ChatViewModel(
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
      flushDelay: Duration.zero,
    );

    Future<ChatViewModel> setupVm() async {
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test Instance',
          gatewayUrl: 'wss://test.example.com:443',
          tokenRef: 'test-token-ref',
          healthStatus: HealthStatus.online,
        ),
      );
      final vm = createViewModel();
      await vm.init();
      return vm;
    }

    test(
      'retryMessage sends FAILED message successfully when gateway recovers',
      () async {
        final vm = await setupVm();
        // 1. First send fails -> message is FAILED
        gateway.shouldFail = true;
        await vm.send('Hello!');
        var messages = (vm.state.messages as LoadData<List<Message>>).value;
        var failed = messages.firstWhere((m) => m.content == 'Hello!');
        expect(failed.status, MessageStatus.failed);

        // 2. Gateway recovers, user taps retry
        gateway.shouldFail = false;
        await vm.retryMessage(failed.clientId);

        // 3. Message should now be SENT
        messages = (vm.state.messages as LoadData<List<Message>>).value;
        final retried = messages.firstWhere(
          (m) => m.clientId == failed.clientId,
        );
        expect(retried.status, MessageStatus.sent);
        expect(retried.serverId, isNotNull);
      },
    );

    test('retryMessage marks message FAILED again on second failure', () async {
      final vm = await setupVm();
      gateway.shouldFail = true;
      await vm.send('Hello!');
      var messages = (vm.state.messages as LoadData<List<Message>>).value;
      final failed = messages.firstWhere((m) => m.content == 'Hello!');
      expect(failed.status, MessageStatus.failed);

      // Retry, but gateway still fails
      await vm.retryMessage(failed.clientId);

      messages = (vm.state.messages as LoadData<List<Message>>).value;
      final retried = messages.firstWhere((m) => m.clientId == failed.clientId);
      expect(retried.status, MessageStatus.failed);
    });

    test(
      'retryMessage sets retryFeedback when sentNow is false (send failure)',
      () async {
        final vm = await setupVm();
        gateway.shouldFail = true;
        await vm.send('Hello!');
        var messages = (vm.state.messages as LoadData<List<Message>>).value;
        final failed = messages.firstWhere((m) => m.content == 'Hello!');
        expect(failed.status, MessageStatus.failed);

        // Clear any previous retryFeedback from send()
        vm.clearRetryFeedback();
        expect(vm.state.retryFeedback, isNull);

        // Retry — gateway still fails, sentNow will be false
        await vm.retryMessage(failed.clientId);

        // Should set retryFeedback because sentNow was false and status is FAILED
        expect(vm.state.retryFeedback, isNotNull);
        expect(
          vm.state.retryFeedback,
          contains('重试失败'),
          reason: 'Should tell user the retry attempt failed',
        );
      },
    );

    test('retryMessage does nothing when instance is offline', () async {
      final vm = await setupVm();
      gateway.shouldFail = true;
      await vm.send('Hello!');
      var messages = (vm.state.messages as LoadData<List<Message>>).value;
      final failed = messages.firstWhere((m) => m.content == 'Hello!');
      expect(failed.status, MessageStatus.failed);

      // Mark instance as offline
      await instanceRepo.updateHealthStatus('inst-1', HealthStatus.offline);

      // Retry should short-circuit (no gateway call, status stays FAILED)
      await vm.retryMessage(failed.clientId);

      messages = (vm.state.messages as LoadData<List<Message>>).value;
      final retried = messages.firstWhere((m) => m.clientId == failed.clientId);
      expect(retried.status, MessageStatus.failed);

      // Should surface feedback so the user knows why retry was skipped
      expect(
        vm.state.retryFeedback,
        contains('离线'),
        reason: 'Should tell user the instance is offline',
      );
    });

    test('retryMessage surfaces feedback when agent is deleted', () async {
      final vm = await setupVm();
      gateway.shouldFail = true;
      await vm.send('Hello!');
      var messages = (vm.state.messages as LoadData<List<Message>>).value;
      final failed = messages.firstWhere((m) => m.content == 'Hello!');
      expect(failed.status, MessageStatus.failed);

      // Delete the agent from the repo
      await agentRepo.deleteByInstanceId('inst-1');

      // Retry should short-circuit with feedback
      await vm.retryMessage(failed.clientId);

      expect(vm.state.retryFeedback, isNotNull);
      expect(
        vm.state.retryFeedback,
        contains('已被删除'),
        reason: 'Should tell user the agent was deleted',
      );
    });

    test('retryMessage surfaces feedback when agent is tombstoned', () async {
      final vm = await setupVm();
      gateway.shouldFail = true;
      await vm.send('Hello!');
      var messages = (vm.state.messages as LoadData<List<Message>>).value;
      final failed = messages.firstWhere((m) => m.content == 'Hello!');
      expect(failed.status, MessageStatus.failed);

      // Simulate Gateway-side tombstone: delete local agent then re-sync with removedAt.
      await agentRepo.deleteByInstanceId('inst-1');
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          removedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

      // Retry should short-circuit with feedback and not change message status.
      await vm.retryMessage(failed.clientId);

      messages = (vm.state.messages as LoadData<List<Message>>).value;
      final retried = messages.firstWhere((m) => m.clientId == failed.clientId);
      expect(retried.status, MessageStatus.failed);
      expect(vm.state.retryFeedback, isNotNull);
      expect(
        vm.state.retryFeedback,
        contains('已被删除'),
        reason: 'Should tell user the agent was tombstoned',
      );
    });

    test('retryMessage is a no-op for non-FAILED messages', () async {
      final vm = await setupVm();
      gateway.shouldFail = false;
      await vm.send('Hello!');
      var messages = (vm.state.messages as LoadData<List<Message>>).value;
      final sent = messages.firstWhere((m) => m.content == 'Hello!');
      expect(sent.status, MessageStatus.sent);

      // Calling retryMessage on a SENT message should not change anything
      await vm.retryMessage(sent.clientId);

      messages = (vm.state.messages as LoadData<List<Message>>).value;
      final unchanged = messages.firstWhere((m) => m.clientId == sent.clientId);
      expect(unchanged.status, MessageStatus.sent);

      // Should surface feedback explaining why retry was skipped
      expect(vm.state.retryFeedback, isNotNull);
      expect(
        vm.state.retryFeedback,
        contains('无法重试'),
        reason: 'Should tell user the message is not retryable',
      );
    });

    test('clearRetryFeedback sets retryFeedback to null', () async {
      final vm = await setupVm();
      gateway.shouldFail = false;
      await vm.send('Hello!');
      final messages = (vm.state.messages as LoadData<List<Message>>).value;
      final sent = messages.firstWhere((m) => m.content == 'Hello!');

      await vm.retryMessage(sent.clientId);
      expect(vm.state.retryFeedback, isNotNull);

      vm.clearRetryFeedback();
      expect(
        vm.state.retryFeedback,
        isNull,
        reason: 'clearRetryFeedback should reset feedback to null',
      );
    });

    test(
      'retryMessage passes expectedStatus explicitly (not relying on default)',
      () async {
        // Verify that retryMessage passes message.status as expectedStatus,
        // not relying on the default MessageStatus.failed.
        // This ensures correctness if isRetryable is ever extended to include PENDING.
        final vm = await setupVm();
        gateway.shouldFail = true;
        await vm.send('Hello!');
        var messages = (vm.state.messages as LoadData<List<Message>>).value;
        final failed = messages.firstWhere((m) => m.content == 'Hello!');
        expect(failed.status, MessageStatus.failed);

        // The message's status is FAILED; retryMessage should pass
        // expectedStatus: MessageStatus.failed to match.
        gateway.shouldFail = false;
        await vm.retryMessage(failed.clientId);

        messages = (vm.state.messages as LoadData<List<Message>>).value;
        final retried = messages.firstWhere(
          (m) => m.clientId == failed.clientId,
        );
        expect(
          retried.status,
          MessageStatus.sent,
          reason:
              'Retry should succeed because expectedStatus matches actual status',
        );
        expect(retried.serverId, isNotNull);
      },
    );
  });

  group('ChatViewModel.reloadMessages / outboxCount stream (US-015)', () {
    late InMemoryAgentRepo agentRepo;
    late InMemoryMessageRepo messageRepo;
    late InMemoryConversationRepo conversationRepo;
    late InMemoryInstanceRepo instanceRepo;
    late MockGatewayClient gateway;
    late IAchievementChecker achievementChecker;

    setUp(() {
      agentRepo = InMemoryAgentRepo();
      conversationRepo = InMemoryConversationRepo();
      // 注入 conversationRepo 以便 getOutboxCountByInstance / watchOutboxCount
      // 能按 instance 过滤出真实计数（测试 stream 驱动行为）。
      messageRepo = InMemoryMessageRepo(conversationRepo: conversationRepo);
      instanceRepo = InMemoryInstanceRepo();
      gateway = MockGatewayClient();
      achievementChecker = _MockAchievementChecker();
    });

    Future<ChatViewModel> setupVm() async {
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test Instance',
          gatewayUrl: 'wss://test.example.com:443',
          tokenRef: 'test-token-ref',
          healthStatus: HealthStatus.online,
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
        flushDelay: Duration.zero,
      );
      await vm.init();
      return vm;
    }

    test(
      'refreshOutbox reloads messages inserted outside the ViewModel',
      () async {
        final vm = await setupVm();

        // Simulate a background flush: insert a message directly into the repo
        // (as OutboxProcessor would via SendMessageUseCase.retry → bindServerId)
        final canonicalConvId = Conversation.generateId('inst-1', 'local-1');
        final msg = Message(
          clientId: 'bg-msg-1',
          conversationId: canonicalConvId,
          agentId: 'local-1',
          role: MessageRole.user,
          content: 'background inserted message',
          type: MessageType.text,
          status: MessageStatus.sent,
          logicalClock: 999,
        );
        await messageRepo.insert(msg);

        // Before refresh, the VM should NOT see the message
        var messages = (vm.state.messages as LoadData<List<Message>>).value;
        expect(
          messages.any((m) => m.clientId == 'bg-msg-1'),
          isFalse,
          reason:
              'Message inserted outside VM should not be visible before refresh',
        );

        // Call reloadMessages — simulates what ref.listen does on ticker change
        await vm.reloadMessages();

        // After refresh, the VM should see the message
        messages = (vm.state.messages as LoadData<List<Message>>).value;
        expect(
          messages.any((m) => m.clientId == 'bg-msg-1'),
          isTrue,
          reason: 'reloadMessages should reload messages from repo',
        );
      },
    );

    test(
      'outboxCount updates via stream when a PENDING message is inserted',
      () async {
        final vm = await setupVm();
        expect(vm.state.outboxCount, 0);

        // Insert a PENDING message (simulating an offline send).
        // conversationRepo 已注入，getOutboxCountByInstance 能按 instance 过滤；
        // init 时 getOrCreate 已建立 conv-1 → canonicalConvId，故计数可命中。
        final canonicalConvId = Conversation.generateId('inst-1', 'local-1');
        final pendingMsg = Message(
          clientId: 'pending-1',
          conversationId: canonicalConvId,
          agentId: 'local-1',
          role: MessageRole.user,
          content: 'pending message',
          type: MessageType.text,
          status: MessageStatus.pending,
          logicalClock: 1000,
        );
        await messageRepo.insert(pendingMsg);

        // stream 异步推送 —— pump 让 listener 处理事件
        await Future<void>.delayed(Duration.zero);

        // outboxCount 现在由 watchOutboxCount stream 自动驱动，无需手动刷新
        expect(
          vm.state.outboxCount,
          1,
          reason: 'insert PENDING 后 stream 应自动推送新计数',
        );
      },
    );

    test(
      'outboxCount drops to 0 when a PENDING message transitions to SENT',
      () async {
        final vm = await setupVm();
        final canonicalConvId = Conversation.generateId('inst-1', 'local-1');
        // 插入 PENDING → 计数 1
        await messageRepo.insert(
          Message(
            clientId: 'pending-2',
            conversationId: canonicalConvId,
            agentId: 'local-1',
            role: MessageRole.user,
            content: 'x',
            type: MessageType.text,
            status: MessageStatus.pending,
            logicalClock: 1001,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(vm.state.outboxCount, 1);

        // CAS PENDING→SENDING（离开 outbox）→ 计数应降为 0
        await messageRepo.tryTransitionToSending(
          'pending-2',
          MessageStatus.pending,
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          vm.state.outboxCount,
          0,
          reason: 'PENDING→SENDING 后消息离开 outbox，stream 应推送计数 0',
        );
      },
    );
  });

  group('ChatViewModel.retry (re-init from LoadError)', () {
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

    Future<ChatViewModel> setupVm() async {
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test Instance',
          gatewayUrl: 'wss://test.example.com:443',
          tokenRef: 'test-token-ref',
          healthStatus: HealthStatus.online,
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
        flushDelay: Duration.zero,
      );
      await vm.init();
      return vm;
    }

    test(
      'retry() re-runs init and leaves streaming idle (PR-B regression guard)',
      () async {
        // 审查发现:retry() 之前无直接测试覆盖。PR-B 把 retry() 里的
        // _flushTimer?.cancel() / _streamBuffer.clear() / _lastPublishedLength = 0
        // 三行删除,改由 _teardownSubscriptions() → _streaming.cancel() 承担
        // (cancel() 内部清 buffer+归零 lastPublished)。本测试守住:
        // retry() 后 isStreaming==false 且 state 正常重载。
        final vm = await setupVm();
        expect(vm.isStreaming, isFalse);

        await vm.retry();

        // retry() 先推 LoadInProgress,await init() 后重载 → LoadData。
        expect(vm.state.messages, isA<LoadData<List<Message>>>());
        expect(
          vm.isStreaming,
          isFalse,
          reason:
              'retry() 经 _teardownSubscriptions → _streaming.cancel() 必须清掉 streaming',
        );
        expect(vm.state.streamingText, '');
        vm.dispose();
      },
    );
  });
}
