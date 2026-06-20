import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart'
    show GatewayConnectionState;
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// Law 17: ChatViewModel 新增 highlight 方法的测试契约。
void main() {
  group('ChatViewModel highlight', () {
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
        flushDelay: Duration.zero,
      );
    }

    // -----------------------------------------------------------------------
    // Law 17: loadHighlightWindow — 状态转换契约
    // -----------------------------------------------------------------------
    test(
      'loadHighlightWindow sets highlightedMessageId and highlightedQuery',
      () async {
        // Setup: add agent so init succeeds
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
            gatewayUrl: 'wss://test:443',
            tokenRef: 'tok',
            healthStatus: HealthStatus.online,
          ),
        );

        final vm = createViewModel(instanceId: 'inst-1', agentId: 'local-1');
        await vm.init();

        // Insert messages around the target so getAnchorWindow returns results
        final convId = Conversation.generateId('inst-1', 'local-1');
        for (var i = 0; i < 5; i++) {
          await messageRepo.insert(
            Message(
              clientId: 'msg-before-$i',
              conversationId: convId,
              agentId: 'local-1',
              role: MessageRole.agent,
              content: 'before $i',
              type: MessageType.text,
              logicalClock: i,
              timestamp: 1000 + i,
            ),
          );
        }
        // Target message
        await messageRepo.insert(
          Message(
            clientId: 'msg-target',
            conversationId: convId,
            agentId: 'local-1',
            role: MessageRole.agent,
            content: 'target message',
            type: MessageType.text,
            logicalClock: 5,
            timestamp: 2000,
          ),
        );
        for (var i = 0; i < 10; i++) {
          await messageRepo.insert(
            Message(
              clientId: 'msg-after-$i',
              conversationId: convId,
              agentId: 'local-1',
              role: MessageRole.agent,
              content: 'after $i',
              type: MessageType.text,
              logicalClock: 6 + i,
              timestamp: 3000 + i,
            ),
          );
        }

        await vm.loadHighlightWindow('msg-target', 'target');

        expect(vm.state.highlightedMessageId, 'msg-target');
        expect(vm.state.highlightedQuery, 'target');
        expect(vm.state.messages, isA<LoadData>());
      },
    );

    // -----------------------------------------------------------------------
    // Law 17: clearHighlight — 清空状态 + 恢复消息列表
    // -----------------------------------------------------------------------
    test(
      'clearHighlight clears highlightedMessageId and highlightedQuery',
      () async {
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
            gatewayUrl: 'wss://test:443',
            tokenRef: 'tok',
            healthStatus: HealthStatus.online,
          ),
        );

        final vm = createViewModel(instanceId: 'inst-1', agentId: 'local-1');
        await vm.init();

        // First set highlight state (simulating loadHighlightWindow)
        await vm.loadHighlightWindow('msg-target', 'keyword');

        // Then clear it
        vm.clearHighlight();

        // clearHighlight is sync — state update is immediate
        expect(vm.state.highlightedMessageId, isNull);
        expect(vm.state.highlightedQuery, isNull);
        // _highlightActive should be false — new messages will trigger reloads
        expect(vm.state.messages, isA<LoadData>());
      },
    );

    // -----------------------------------------------------------------------
    // Law 17: loadHighlightWindow handles error gracefully (fallback)
    // -----------------------------------------------------------------------
    test(
      'loadHighlightWindow sets highlight even when getAnchorWindow fails',
      () async {
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
            gatewayUrl: 'wss://test:443',
            tokenRef: 'tok',
            healthStatus: HealthStatus.online,
          ),
        );

        final vm = createViewModel(instanceId: 'inst-1', agentId: 'local-1');
        await vm.init();

        // getAnchorWindow on empty DB with non-existent target still works
        // (it returns an empty list as fallback in the in-memory impl)
        await vm.loadHighlightWindow('non-existent-msg', 'missing');

        // Even in fallback, highlight state is set
        expect(vm.state.highlightedMessageId, 'non-existent-msg');
        expect(vm.state.highlightedQuery, 'missing');
      },
    );
  });
}
