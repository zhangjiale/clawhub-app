import 'dart:async';

import 'package:claw_hub/core/acl/gateway_protocol.dart' show StreamingEvent;
import 'package:claw_hub/core/acl/i_gateway_client.dart'
    show GatewayConnectionState;
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// Gateway whose `sendMessage` returns immediately with a synthetic ack and
/// does NOT auto-simulate an agent reply (so thinking stays armed). Stream
/// controllers are exposed for injecting messages / connection-state.
class _ReviewGroup2Gateway extends MockGatewayClient {
  final Map<String, StreamController<Message>> messageCtrls = {};
  final Map<String, StreamController<GatewayConnectionState>> stateCtrls = {};
  final Map<String, StreamController<StreamingEvent>> streamingCtrls = {};

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async {
    return (
      serverId: 'server-${message.clientId}',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

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
    return (messages: const <Message>[], nextCursor: null);
  }

  void emitMessage(String instanceId, Message msg) {
    messageCtrls[instanceId]?.add(msg);
  }
}

/// Throws on insert only for agent messages — so the user message (role=user)
/// inserts cleanly (send() succeeds, thinking arms) but the agent reply insert
/// fails (exercises the messageStream catch).
class _ThrowOnAgentInsertRepo extends InMemoryMessageRepo {
  @override
  Future<Message> insert(Message message) {
    if (message.role == MessageRole.agent) {
      throw StateError('insert failed (FK constraint)');
    }
    return super.insert(message);
  }
}

Message _agentMsg(String id, int timestamp, String content) => Message(
  clientId: id,
  serverId: null,
  conversationId: '',
  agentId: 'r-1',
  role: MessageRole.agent,
  content: content,
  type: MessageType.text,
  status: MessageStatus.delivered,
  logicalClock: timestamp < 1577836800000 ? 1 : timestamp,
  timestamp: timestamp,
);

void main() {
  group('ChatViewModel review group 2 (#6, #10)', () {
    late InMemoryAgentRepo agentRepo;
    late InMemoryMessageRepo messageRepo;
    late InMemoryConversationRepo conversationRepo;
    late InMemoryInstanceRepo instanceRepo;
    late _ReviewGroup2Gateway gateway;
    late IAchievementChecker achievementChecker;

    Future<ChatViewModel> setupVm({InMemoryMessageRepo? repo}) async {
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '虾',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://t:443',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
        ),
      );
      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: repo ?? messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: repo ?? messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: achievementChecker,
        flushDelay: Duration.zero,
        overallTimeoutDelay: const Duration(milliseconds: 50),
      );
      await vm.init();
      return vm;
    }

    setUp(() {
      agentRepo = InMemoryAgentRepo();
      messageRepo = InMemoryMessageRepo();
      conversationRepo = InMemoryConversationRepo();
      instanceRepo = InMemoryInstanceRepo();
      gateway = _ReviewGroup2Gateway();
      achievementChecker = _MockAchievementChecker();
    });

    test(
      '#6 agent reply that fails to merge stops the thinking spinner',
      () async {
        final vm = await setupVm(repo: _ThrowOnAgentInsertRepo());
        await vm.send('hi');
        expect(vm.state.thinkingState, ThinkingState.thinking);

        // Agent reply whose insert throws (FK constraint after cache clear).
        // Pre-fix: the listener returns from the catch without stopping
        // thinking, so the spinner runs until the 60s/120s timer. Post-fix:
        // the agent-path catch calls _streaming.onReplyArrived() +
        // _stopThinking(), mirroring the normal reply path.
        gateway.emitMessage('inst-1', _agentMsg('reply-1', 1, '回复'));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(
          vm.state.thinkingState,
          ThinkingState.idle,
          reason:
              'a failed agent-reply merge must still stop the thinking '
              'spinner — pre-fix it spun until the timeout timer',
        );
        vm.dispose();
      },
    );

    test(
      '#10 future-skewed catch-up message does not freeze conversation preview',
      () async {
        final vm = await setupVm();
        final canonicalConvId = Conversation.generateId('inst-1', 'local-1');
        final now = DateTime.now().millisecondsSinceEpoch;

        // A normal agent reply lands — sets lastMessageTime ≈ now.
        gateway.emitMessage('inst-1', _agentMsg('a', now, 'normal reply'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        var conv = await conversationRepo.getById(canonicalConvId);
        final baseTime = conv!.lastMessageTime;

        // A catch-up replay with a +10min server-clock-skewed timestamp.
        // Pre-fix: passes the rewind guard (timestamp > lastMessageTime) and
        // overwrites lastMessageTime to now+10min, freezing the preview until
        // a real-time message with an even-larger timestamp arrives.
        // Post-fix: the future-skew guard skips the update.
        final skewed = now + 10 * 60 * 1000;
        gateway.emitMessage('inst-1', _agentMsg('b', skewed, 'skewed reply'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        conv = await conversationRepo.getById(canonicalConvId);
        expect(
          conv!.lastMessageTime,
          baseTime,
          reason:
              'a future-skewed message must not push lastMessageTime into '
              'the future (would freeze the preview)',
        );

        // A subsequent normal real-time message (timestamp ≈ now+1s) must
        // still advance the preview — proving it is not frozen at the skewed
        // value. Pre-fix this was rejected by the rewind guard against the
        // skewed future lastMessageTime.
        final later = now + 1000;
        gateway.emitMessage('inst-1', _agentMsg('c', later, 'later reply'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        conv = await conversationRepo.getById(canonicalConvId);
        expect(
          conv!.lastMessageTime,
          later,
          reason:
              'preview must not be frozen — a later normal message must '
              'still advance lastMessageTime',
        );
        vm.dispose();
      },
    );
  });
}
