// Tests for [ChatViewModel.loadFullMessage] - lazy on-demand backfill of
// chat.history omitted placeholders via chat.message.get.
//
// Setup: an omitted message (metadata.contentOmitted = true, content = the
// Gateway placeholder) is inserted directly into the repo. loadFullMessage
// should call fetchSingleMessage, persist the real content (clearing the flag),
// and reload. Guards: missing serverId, non-omitted message, double-tap dedup,
// fetch failure (throw + null), and gateway-without-backfill-capability.
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart' show StreamingEvent;
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// Backfill-capable gateway: extends [MockGatewayClient] (which implements
/// [IMessageBackfillClient]) and overrides [fetchSingleMessage] to be
/// controllable from the test.
class _BackfillGateway extends MockGatewayClient {
  int fetchCallCount = 0;
  String? lastMessageId;
  Message? returnMessage;
  Object? throwOnFetch;

  @override
  Future<Message?> fetchSingleMessage({
    required String instanceId,
    required String agentId,
    required String messageId,
  }) async {
    fetchCallCount++;
    lastMessageId = messageId;
    if (throwOnFetch != null) {
      throw throwOnFetch!;
    }
    return returnMessage;
  }
}

/// Minimal [IGatewayClient] that does NOT implement [IMessageBackfillClient] -
/// used to exercise the "gateway lacks backfill capability" degradation path.
class _NonBackfillGateway implements IGatewayClient {
  @override
  Future<void> connect(Instance instance) async {}
  @override
  Future<void> disconnect(String instanceId) async {}
  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async => (serverId: 'srv', timestamp: 0);
  @override
  Future<List<Agent>> fetchAgents(String instanceId) async => const [];
  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) async => (messages: const <Message>[], nextCursor: null);
  @override
  Future<bool> testConnection(Instance instance) async => true;
  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) =>
      const Stream<GatewayConnectionState>.empty();
  @override
  void resetConnectionState(String instanceId) {}
  @override
  Stream<Message> messageStream(String instanceId) =>
      const Stream<Message>.empty();
  @override
  Stream<ToolCall> toolCallStream(String instanceId) =>
      const Stream<ToolCall>.empty();
  @override
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) =>
      const Stream<StreamingEvent>.empty();
  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId) =>
      const Stream<GatewayPairingInfo?>.empty();
  @override
  Stream<GatewayNotice> gatewayNoticeStream(String instanceId) =>
      const Stream<GatewayNotice>.empty();
  @override
  Future<void> dispose() async {}
}

const _agentId = 'local-1';
const _instanceId = 'inst-1';
const _remoteId = 'r-1';
const _omittedContent = '[chat.history omitted: message too large]';

void main() {
  late InMemoryAgentRepo agentRepo;
  late InMemoryMessageRepo messageRepo;
  late InMemoryConversationRepo conversationRepo;
  late InMemoryInstanceRepo instanceRepo;
  late _BackfillGateway gateway;
  late IAchievementChecker achievementChecker;

  setUp(() {
    agentRepo = InMemoryAgentRepo();
    messageRepo = InMemoryMessageRepo();
    conversationRepo = InMemoryConversationRepo();
    instanceRepo = InMemoryInstanceRepo();
    gateway = _BackfillGateway();
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
    instanceId: _instanceId,
    agentId: _agentId,
    achievementChecker: achievementChecker,
    flushDelay: Duration.zero,
  );

  Future<ChatViewModel> setupVm() async {
    final agent = Agent(
      localId: _agentId,
      remoteId: _remoteId,
      instanceId: _instanceId,
      name: '产品虾',
    );
    await agentRepo.syncFromGateway(_instanceId, [agent]);
    await instanceRepo.save(
      Instance(
        id: _instanceId,
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

  /// Insert an omitted message directly into the repo (bypassing the mapper,
  /// whose detection is tested separately) and reload so the VM sees it.
  Future<Message> seedOmittedMessage({
    String clientId = 'omitted-1',
    String? serverId = 'srv-1',
  }) async {
    final canonicalConvId = Conversation.generateId(_instanceId, _agentId);
    final msg = Message(
      clientId: clientId,
      serverId: serverId,
      conversationId: canonicalConvId,
      agentId: _remoteId,
      role: MessageRole.agent,
      content: _omittedContent,
      type: MessageType.text,
      status: MessageStatus.delivered,
      logicalClock: 100,
      metadata: const {'contentOmitted': true},
    );
    await messageRepo.insert(msg);
    return msg;
  }

  List<Message> currentMessages(ChatViewModel vm) =>
      (vm.state.messages as LoadData<List<Message>>).value;

  group('ChatViewModel.loadFullMessage (chat.message.get backfill)', () {
    test(
      'happy path: fetches full content, persists, clears the omitted flag',
      () async {
        final vm = await setupVm();
        final omitted = await seedOmittedMessage();
        await vm.reloadMessages();
        expect(
          currentMessages(vm).first.metadata?['contentOmitted'],
          isTrue,
          reason: 'seeded message should be flagged omitted before backfill',
        );

        gateway.returnMessage = Message(
          clientId: omitted.clientId,
          serverId: 'srv-1',
          conversationId: omitted.conversationId,
          agentId: _remoteId,
          role: MessageRole.agent,
          content: 'the real backfilled content',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 100,
        );

        await vm.loadFullMessage(omitted.clientId);

        expect(gateway.fetchCallCount, 1);
        expect(gateway.lastMessageId, 'srv-1');

        final updated = currentMessages(
          vm,
        ).firstWhere((m) => m.clientId == omitted.clientId);
        expect(updated.content, 'the real backfilled content');
        expect(
          updated.metadata?['contentOmitted'],
          isNot(isTrue),
          reason: 'flag must be cleared after successful backfill',
        );
      },
    );

    test(
      'missing serverId surfaces retryFeedback and does not fetch',
      () async {
        final vm = await setupVm();
        final omitted = await seedOmittedMessage(serverId: null);
        await vm.reloadMessages();

        await vm.loadFullMessage(omitted.clientId);

        expect(gateway.fetchCallCount, 0);
        expect(
          vm.state.retryFeedback,
          isNotNull,
          reason: 'must tell the user why backfill was skipped',
        );
      },
    );

    test('non-omitted message is a no-op (no fetch)', () async {
      final vm = await setupVm();
      final canonicalConvId = Conversation.generateId(_instanceId, _agentId);
      await messageRepo.insert(
        Message(
          clientId: 'plain-1',
          serverId: 'srv-plain',
          conversationId: canonicalConvId,
          agentId: _remoteId,
          role: MessageRole.agent,
          content: 'a normal message',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 101,
        ),
      );
      await vm.reloadMessages();

      await vm.loadFullMessage('plain-1');

      expect(gateway.fetchCallCount, 0);
    });

    test(
      'fetch returning null rethrows (widget shows 加载失败) and no DB write',
      () async {
        final vm = await setupVm();
        final omitted = await seedOmittedMessage();
        await vm.reloadMessages();
        gateway.returnMessage = null; // server: message gone

        await expectLater(
          vm.loadFullMessage(omitted.clientId),
          throwsA(isA<Exception>()),
        );

        // Content unchanged - the placeholder is still there.
        final unchanged = currentMessages(
          vm,
        ).firstWhere((m) => m.clientId == omitted.clientId);
        expect(unchanged.content, _omittedContent);
      },
    );

    test('fetch throwing rethrows and leaves content unchanged', () async {
      final vm = await setupVm();
      final omitted = await seedOmittedMessage();
      await vm.reloadMessages();
      gateway.throwOnFetch = Exception('network down');

      await expectLater(
        vm.loadFullMessage(omitted.clientId),
        throwsA(isA<Exception>()),
      );

      final unchanged = currentMessages(
        vm,
      ).firstWhere((m) => m.clientId == omitted.clientId);
      expect(unchanged.content, _omittedContent);
    });

    test('double-call dedup: only one fetchSingleMessage in flight', () async {
      final vm = await setupVm();
      final omitted = await seedOmittedMessage();
      await vm.reloadMessages();
      gateway.returnMessage = Message(
        clientId: omitted.clientId,
        serverId: 'srv-1',
        conversationId: omitted.conversationId,
        agentId: _remoteId,
        role: MessageRole.agent,
        content: 'backfilled',
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: 100,
      );

      // Fire two concurrent loads; the in-flight guard must collapse them.
      await Future.wait([
        vm.loadFullMessage(omitted.clientId),
        vm.loadFullMessage(omitted.clientId),
      ]);

      expect(
        gateway.fetchCallCount,
        1,
        reason:
            'second concurrent call must be deduped while first is in flight',
      );
    });

    test('gateway without backfill capability degrades gracefully', () async {
      // Swap in a gateway that does NOT implement IMessageBackfillClient.
      final nonBackfill = _NonBackfillGateway();
      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: nonBackfill,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: nonBackfill,
        ),
        instanceId: _instanceId,
        agentId: _agentId,
        achievementChecker: achievementChecker,
        flushDelay: Duration.zero,
      );
      await vm.init();
      final omitted = await seedOmittedMessage();
      await vm.reloadMessages();

      await vm.loadFullMessage(omitted.clientId);

      expect(
        vm.state.retryFeedback,
        isNotNull,
        reason: 'must surface feedback when the gateway cannot backfill',
      );
      // Content unchanged.
      final unchanged = currentMessages(
        vm,
      ).firstWhere((m) => m.clientId == omitted.clientId);
      expect(unchanged.content, _omittedContent);
    });
  });
}
