// 调查 bug：聊天中 exec 卡 (1) 有时不显示、重启后显示；(2) 有时只有一张、重启后变多张。
//
// 根因：实时路径 state.toolCalls 是 Map<String, ToolCall>，按 message-owner
// (clientId / sessionKey) 为 key -> 同一 turn 内多个工具调用共享同一 owner key，
// 后者覆盖前者，只剩一张卡。重载路径用 toolResult 消息行 (1:N) 渲染真相。
//
// 本文件复现实时路径的「多工具坍缩」：同 sessionKey 发两个不同 toolCallId 的
// ToolCall，实时应保留两张，pre-fix 只剩一张（覆盖）。

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
  group('ChatViewModel tool-call multi-per-turn (no collapse)', () {
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

    // 症状 2 实时侧：同 sessionKey 的两个工具调用不能互相覆盖。
    test(
      'two distinct tool calls sharing one sessionKey both survive (self-key path)',
      () async {
        final vm = await setupVm();
        const sessionKey = 'agent:r-1:main';

        // User sends -> _sendCore populates _sessionKeyToUserClientId[sk],
        // so live ToolCalls self-key to the user message clientId immediately.
        await vm.send('do X');
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        final userMsg = (await messageRepo.getByConversation(
          Conversation.generateId('inst-1', 'local-1'),
          limit: 10,
        )).firstWhere((m) => m.role == MessageRole.user);
        final userClientId = userMsg.clientId;

        // Two DISTINCT tool calls in the same turn. v2026.6.10 omits per-tool
        // sessionKey -> _resolveToolMessageId LIFO-fallback resolves both to
        // the same sessionKey. Pre-fix the listener keyed both by the same
        // owner -> the second overwrote the first -> only one card rendered.
        gateway.emitToolCallForTesting(
          'inst-1',
          ToolCall(
            id: 'tc-a',
            messageId: sessionKey,
            toolName: 'exec',
            status: ToolCallStatus.success,
            outputResult: 'ls output',
          ),
        );
        gateway.emitToolCallForTesting(
          'inst-1',
          ToolCall(
            id: 'tc-b',
            messageId: sessionKey,
            toolName: 'exec',
            status: ToolCallStatus.success,
            outputResult: 'pwd output',
          ),
        );
        for (var i = 0; i < 4; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // EXPECTED: both tool calls survive, each keyed by its own toolCallId,
        // both owned by the user message so the page renders two cards.
        expect(
          vm.state.toolCalls.length,
          2,
          reason:
              'two distinct tool calls in one turn must not collapse. '
              'Pre-fix the listener did current[userClientId] = tc for each, '
              'so tc-b overwrote tc-a and only one card rendered live '
              '(while history reload showed both -> symptom 2).',
        );
        expect(vm.state.toolCalls.containsKey('tc-a'), isTrue);
        expect(vm.state.toolCalls.containsKey('tc-b'), isTrue);
        expect(
          vm.state.toolCalls['tc-a']!.messageId,
          userClientId,
          reason: 'tc-a self-keyed to user message clientId',
        );
        expect(
          vm.state.toolCalls['tc-b']!.messageId,
          userClientId,
          reason: 'tc-b self-keyed to user message clientId',
        );
        vm.dispose();
      },
    );

    // 症状 1/2 rekey 侧：agent 消息到达时，同 sessionKey 的多个早期 ToolCall
    // 都要 rekey 到 clientId（不能只 rekey 一个）。
    test(
      're-key moves ALL early tool calls sharing one sessionKey to clientId',
      () async {
        final vm = await setupVm();
        const sessionKey = 'agent:r-1:main';

        // No vm.send -> _sessionKeyToUserClientId empty -> self-key misses ->
        // tool calls stored with messageId = sessionKey, pending rekey.
        gateway.emitToolCallForTesting(
          'inst-1',
          ToolCall(
            id: 'tc-a',
            messageId: sessionKey,
            toolName: 'exec',
            status: ToolCallStatus.running,
            outputResult: null,
          ),
        );
        gateway.emitToolCallForTesting(
          'inst-1',
          ToolCall(
            id: 'tc-b',
            messageId: sessionKey,
            toolName: 'exec',
            status: ToolCallStatus.running,
            outputResult: null,
          ),
        );
        for (var i = 0; i < 4; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        // Pre-fix: only tc-b survived (overwrote tc-a).
        expect(
          vm.state.toolCalls.length,
          2,
          reason: 'both early tool calls must be stored before rekey',
        );

        // Final agent message arrives, tagged with metadata.sessionKey.
        // Re-key must move BOTH tc-a and tc-b to the agent message clientId.
        gateway.emitMessageForTesting(
          'inst-1',
          Message(
            clientId: 'agent-msg-1',
            conversationId: '',
            agentId: 'r-1',
            role: MessageRole.agent,
            content: 'reply',
            type: MessageType.text,
            status: MessageStatus.delivered,
            logicalClock: 1700000000003,
            timestamp: 1700000000003,
            metadata: const {'sessionKey': sessionKey},
          ),
        );
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(
          vm.state.toolCalls.length,
          2,
          reason:
              're-key must not drop either tool call. Pre-fix '
              '_rekeyToolCallForMessage did state.toolCalls[sk] (single) '
              'and only re-keyed the survivor.',
        );
        expect(vm.state.toolCalls['tc-a']!.messageId, 'agent-msg-1');
        expect(vm.state.toolCalls['tc-b']!.messageId, 'agent-msg-1');
        // No tool call left stranded on the sessionKey (page lookup by
        // message.clientId would miss a stranded entry -> invisible card).
        expect(
          vm.state.toolCalls.values.any((tc) => tc.messageId == sessionKey),
          isFalse,
          reason: 'no tool call stranded on sessionKey after re-key',
        );
        vm.dispose();
      },
    );
  });
}
