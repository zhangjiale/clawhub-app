// 调查 bug:exec 卡片位置错(在 user 消息下方才对,实际跑到 agent 下方)。
// 假设:VM 的 _rekeyToolCallForMessage 把 ToolCall 绑到 agent 消息的 clientId,
// 导致 chat_room_page 的 toolCalls[message.clientId] 查询命中 agent 行,
// ToolCallCard 渲染在 agent 气泡下方。期望:绑到触发该轮的 user 消息 clientId,
// 渲染在 user 气泡下方(user 和 agent 之间)。

import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
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

void main() {
  group('ChatViewModel tool-call position (review bug: should attach to '
      'user message, not agent message)', () {
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
      'BUG: ToolCall attaches to user message clientId (not agent) — '
      'exec card should render below user bubble, not below agent bubble',
      () async {
        final vm = await setupVm();
        const sessionKey = 'agent:r-1:main';
        const agentClientId = 'agent-msg-1';

        // 1. User sends a message via the realistic send path
        //    (vm.send → _sendCore → SendMessageUseCase → messageRepo.insert).
        //    This populates `_sessionKeyToUserClientId[sk] = userClientId`
        //    in _sendCore, which is what the re-key path reads.
        await vm.send('do X');
        // Pump for send() to complete (CAS + insert + _loadMessages).
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        // Look up the user message that was just inserted.
        final userMessages = await messageRepo.getByConversation(
          Conversation.generateId('inst-1', 'local-1'),
          limit: 10,
        );
        final userMsg = userMessages.firstWhere(
          (m) => m.role == MessageRole.user,
        );
        final userClientId = userMsg.clientId;

        // 2. ToolCall arrives, keyed by sessionKey (via _resolveToolMessageId).
        //    With the send-side registration in _sendCore, the ToolCall
        //    listener self-keys immediately to the user message's clientId
        //    (no need to wait for the final agent message). This is a
        //    behavioural upgrade over the previous re-key-on-agent path:
        //    the live render is correct from the first event.
        gateway.emitToolCallForTesting(
          'inst-1',
          ToolCall(
            id: 'tc-1',
            messageId: sessionKey,
            toolName: 'exec',
            status: ToolCallStatus.success,
            outputResult: 'ls output',
          ),
        );
        for (var i = 0; i < 2; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(
          vm.state.toolCalls.containsKey('tc-1'),
          isTrue,
          reason:
              'live ToolCall self-keys immediately to user message '
              'clientId via _sessionKeyToUserClientId (populated by '
              '_sendCore at send time)',
        );
        expect(vm.state.toolCalls['tc-1']!.messageId, userClientId);
        // The sessionKey entry must not exist — the ToolCall was
        // self-keyed, not stored as a sessionKey-keyed entry.
        expect(
          vm.state.toolCalls.containsKey(sessionKey),
          isFalse,
          reason: 'sessionKey entry should not exist after self-key',
        );

        // 3. Final agent message arrives, tagged with metadata.sessionKey.
        //    logicalClock > user message (assigned by SendMessageUseCase
        //    counter + 1, so it is strictly greater than user logicalClock).
        final agentLogicalClock = userMsg.logicalClock + 1;
        gateway.emitMessageForTesting(
          'inst-1',
          Message(
            clientId: agentClientId,
            conversationId: '',
            agentId: 'r-1',
            role: MessageRole.agent,
            content: 'reply',
            type: MessageType.text,
            status: MessageStatus.delivered,
            logicalClock: agentLogicalClock,
            timestamp: agentLogicalClock,
            metadata: const {'sessionKey': sessionKey},
          ),
        );
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // EXPECTED (after fix): ToolCall re-keyed to user message clientId
        // so chat_room_page's toolCalls[userMsg.clientId] lookup finds it
        // and renders ToolCallCard below the user bubble (between user
        // and agent in the visual list with reverse:true).
        expect(
          vm.state.toolCalls.containsKey('tc-1'),
          isTrue,
          reason:
              'ToolCall must be keyed by user message clientId so it '
              'renders below the user bubble. The page lookup at '
              'chat_room_page._buildMessageList line 691 does '
              '`final tc = toolCalls[message.clientId]` for each message '
              'and renders ToolCallCard in that message\'s Column.',
        );
        expect(
          vm.state.toolCalls['tc-1']!.messageId,
          userClientId,
          reason:
              'ToolCall.messageId must equal the user message clientId '
              'so the page lookup is consistent',
        );
        expect(vm.state.toolCalls['tc-1']!.id, 'tc-1');

        // The sessionKey-keyed entry must be removed after re-key.
        expect(
          vm.state.toolCalls.containsKey(sessionKey),
          isFalse,
          reason: 'sessionKey entry should be removed after re-key',
        );

        // The agent message should NOT have its own ToolCall entry —
        // the ToolCall belongs to the user message, not the agent.
        expect(
          vm.state.toolCalls.containsKey(agentClientId),
          isFalse,
          reason:
              'ToolCall should NOT be keyed by agent message clientId. '
              'Pre-fix behavior attached it to the agent, causing the exec '
              'card to render below the agent bubble instead of below the '
              'user bubble.',
        );
        vm.dispose();
      },
    );
  });
}
