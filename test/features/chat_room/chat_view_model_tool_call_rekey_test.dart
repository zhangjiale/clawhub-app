import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// Review #1 (Option C): the processor tags agent messages with
/// `metadata['sessionKey']`; the VM must re-key the turn's ToolCall from
/// `sessionKey` → `clientId` so the page's `toolCalls[message.clientId]`
/// lookup finds it. Before the fix, ToolCall.messageId = sessionKey while
/// the page queried by clientId → keys never matched → ToolCallCard never
/// rendered.
void main() {
  group('ChatViewModel tool-call re-key (review #1, Option C)', () {
    late InMemoryAgentRepo agentRepo;
    late InMemoryMessageRepo messageRepo;
    late InMemoryConversationRepo conversationRepo;
    late InMemoryInstanceRepo instanceRepo;
    late MockGatewayClient gateway;

    setUp(() {
      agentRepo = InMemoryAgentRepo();
      conversationRepo = InMemoryConversationRepo();
      messageRepo = InMemoryMessageRepo(conversationRepo: conversationRepo);
      instanceRepo = InMemoryInstanceRepo();
      gateway = MockGatewayClient();
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
          name: 'Test',
          gatewayUrl: 'wss://t.example.com:443',
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
      );
      await vm.init();
      return vm;
    }

    test(
      'agent message re-keys ToolCall from sessionKey to clientId',
      () async {
        final vm = await setupVm();
        const sessionKey = 'agent:r-1:main';

        // 1. Tool call arrives keyed by sessionKey (the processor sets
        //    ToolCall.messageId = event.sessionKey).
        gateway.emitToolCallForTesting(
          'inst-1',
          ToolCall(
            id: 'tc-1',
            messageId: sessionKey,
            toolName: 'search',
            status: ToolCallStatus.success,
            outputResult: '{}',
          ),
        );
        // Mock broadcast controllers are async (sync:false) — pump so the
        // tool listener fires and stores the call before the message arrives.
        for (var i = 0; i < 2; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(
          vm.state.toolCalls.containsKey(sessionKey),
          isTrue,
          reason: 'sanity: tool call stored by sessionKey',
        );
        expect(vm.state.toolCalls[sessionKey]!.messageId, sessionKey);

        // 2. Final agent message arrives, tagged with metadata.sessionKey.
        gateway.emitMessageForTesting(
          'inst-1',
          Message(
            clientId: 'msg-1',
            conversationId: '',
            agentId: 'r-1',
            role: MessageRole.agent,
            content: 'reply',
            type: MessageType.text,
            status: MessageStatus.delivered,
            logicalClock: 1700000000000,
            timestamp: 1700000000000,
            metadata: const {'sessionKey': sessionKey},
          ),
        );
        // Message listener is async (await merge) — pump microtasks so it
        // progresses past the merge into the agent branch (re-key).
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // 3. Re-keyed: toolCalls now keyed by clientId, ToolCall.messageId
        //    updated to match.
        expect(
          vm.state.toolCalls.containsKey('msg-1'),
          isTrue,
          reason: 'tool call re-keyed to message clientId',
        );
        expect(
          vm.state.toolCalls.containsKey(sessionKey),
          isFalse,
          reason: 'sessionKey entry removed after re-key',
        );
        expect(vm.state.toolCalls['msg-1']!.messageId, 'msg-1');
        expect(vm.state.toolCalls['msg-1']!.id, 'tc-1');
        vm.dispose();
      },
    );

    test(
      'agent message without sessionKey metadata is a no-op (no crash)',
      () async {
        // History / untagged messages have no sessionKey → re-key must skip
        // gracefully (no StateError, no spurious toolCalls mutation).
        final vm = await setupVm();
        gateway.emitMessageForTesting(
          'inst-1',
          Message(
            clientId: 'msg-2',
            conversationId: '',
            agentId: 'r-1',
            role: MessageRole.agent,
            content: 'history',
            type: MessageType.text,
            status: MessageStatus.delivered,
            logicalClock: 1700000000001,
            timestamp: 1700000000001,
          ),
        );
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(vm.state.toolCalls, isEmpty);
        vm.dispose();
      },
    );
  });
}
