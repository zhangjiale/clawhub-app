import 'dart:async';

import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

class _RecordingLogger implements ILogger {
  final List<String> errors = [];
  @override
  void info(String message) {}
  @override
  void error(String message, [StackTrace? stackTrace]) => errors.add(message);
}

/// Overrides only [connectionStateStream] with a controllable broadcast
/// controller so the test can inject a stream error. All other gateway
/// behavior (messageStream, fetchMessageHistory, sendMessage, …) is inherited
/// from [MockGatewayClient].
class _ConnectionErrorGateway extends MockGatewayClient {
  final StreamController<GatewayConnectionState> connCtrl =
      StreamController<GatewayConnectionState>.broadcast();

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) =>
      connCtrl.stream;
}

/// Review #4: `_connectionSubscription.listen` previously had no `onError`
/// handler (unlike the message/tool/outbox/agent listeners). A
/// connectionStateStream error vanished to the zone and the subscription could
/// auto-cancel, freezing the connection banner on the last known state. The
/// fix logs it like the sibling listeners.
void main() {
  test(
    'connectionStateStream error is logged, not swallowed (review #4)',
    () async {
      final logger = _RecordingLogger();
      final gateway = _ConnectionErrorGateway();
      final agentRepo = InMemoryAgentRepo();
      final conversationRepo = InMemoryConversationRepo();
      final messageRepo = InMemoryMessageRepo(
        conversationRepo: conversationRepo,
      );
      final instanceRepo = InMemoryInstanceRepo();

      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '虾',
        ),
      ]);
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
        achievementChecker: _MockAchievementChecker(),
        flushDelay: Duration.zero,
        logger: logger,
      );
      await vm.init();

      // Emit an error on the connection state stream.
      gateway.connCtrl.addError(Exception('conn boom'));
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        logger.errors.any((m) => m.contains('connection state stream error')),
        isTrue,
        reason: 'connectionStateStream 错误必须经 onError 记录，不能静默丢到 zone',
      );
      vm.dispose();
      await gateway.connCtrl.close();
    },
  );
}
