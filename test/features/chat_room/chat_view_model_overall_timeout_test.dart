import 'dart:async';

import 'package:claw_hub/core/acl/gateway_protocol.dart'
    show StreamingDelta, StreamingEvent;
import 'package:claw_hub/core/acl/i_gateway_client.dart'
    show GatewayConnectionState;
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// A gateway whose `sendMessage` returns immediately with a synthetic ack and
/// does NOT auto-simulate an agent reply — so thinking state stays armed and
/// the overall-timeout path can be exercised without a 500-2000ms mock reply
/// racing the assertions. Stream controllers are exposed for injecting deltas
/// and connection-state transitions.
class _ImmediateAckGateway extends MockGatewayClient {
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

  void emitStreamingEvent(String instanceId, StreamingEvent event) {
    streamingCtrls[instanceId]?.add(event);
  }

  void emitConnectionState(String instanceId, GatewayConnectionState state) {
    stateCtrls[instanceId]?.add(state);
  }
}

/// Reviews #4 and #11: the 120s `_overallTimeoutTimer` is the hard ceiling
/// that prevents a trickling gateway from keeping the user waiting forever.
/// #4: a mid-stream disconnect must cancel it (no timeout banner on an offline
///     page). #11: `continueWaiting()` must re-arm it (the trickle invariant
///     must survive a user-dismissed timeout).
///
/// The 120s duration is injected as `overallTimeoutDelay` so the timer can be
/// exercised in real async without FakeAsync (mirrors the `flushDelay` seam).
void main() {
  group('ChatViewModel overall timeout (#4, #11)', () {
    late InMemoryAgentRepo agentRepo;
    late InMemoryMessageRepo messageRepo;
    late InMemoryConversationRepo conversationRepo;
    late InMemoryInstanceRepo instanceRepo;
    late _ImmediateAckGateway gateway;
    late IAchievementChecker achievementChecker;

    Future<ChatViewModel> setupVm() async {
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
      gateway = _ImmediateAckGateway();
      achievementChecker = _MockAchievementChecker();
    });

    test('#4 disconnect mid-stream cancels _overallTimeoutTimer '
        '(no timeout banner on an offline page)', () async {
      final vm = await setupVm();
      await vm.send('hi');

      // A delta flips isStreaming=true so the disconnect branch fires.
      gateway.emitStreamingEvent(
        'inst-1',
        StreamingDelta(agentId: 'r-1', text: 'd'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(vm.isStreaming, isTrue);

      // Connection drops mid-stream.
      gateway.emitConnectionState(
        'inst-1',
        GatewayConnectionState.disconnected,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Wait past the overall-timeout duration (50ms). Pre-fix the timer
      // kept running and flipped thinkingState to timeout on an already-
      // offline page (with no delta ever coming). Post-fix it is cancelled
      // alongside _timeoutTimer in the disconnect branch.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        vm.state.thinkingState,
        ThinkingState.thinking,
        reason:
            'disconnect must cancel _overallTimeoutTimer — a timeout '
            'banner on an offline page is confusing and unrecoverable '
            '(continueWaiting only re-arms the 60s per-delta timer)',
      );
      vm.dispose();
    });

    test('#11 continueWaiting re-arms _overallTimeoutTimer '
        '(trickle protection restored)', () async {
      final vm = await setupVm();
      await vm.send('hi');

      // Overall timer (50ms) fires → timeout banner.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        vm.state.thinkingState,
        ThinkingState.timeout,
        reason: 'overall timeout should fire after the delay',
      );

      // User dismisses the banner and chooses to keep waiting.
      vm.continueWaiting();
      expect(
        vm.state.thinkingState,
        ThinkingState.thinking,
        reason: 'continueWaiting should reset to thinking',
      );

      // Wait past the overall-timeout duration again. Pre-fix
      // continueWaiting only re-armed the 60s per-delta timer; the overall
      // timer never fired again, so a trickling gateway (one char every <60s)
      // could keep the user waiting indefinitely after a single dismissal.
      // Post-fix the overall timer is re-armed.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        vm.state.thinkingState,
        ThinkingState.timeout,
        reason:
            'continueWaiting must re-arm _overallTimeoutTimer — the '
            'documented "no indefinite trickle" invariant must hold',
      );
      vm.dispose();
    });
  });
}
