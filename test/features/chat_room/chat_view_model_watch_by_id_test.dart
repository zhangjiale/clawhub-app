// US-021 follow-up: ChatViewModel 应订阅 IAgentRepo.watchById，
// 任何 DB 写入（本地 updateFullProfile / updateLocalProfile / Gateway
// syncFromGateway）触发 emit 后，自动同步 _agent，使 UI 经 vm.agent
// getter 立即看到最新值（quickCommands / nickname 等）—— 无需发消息
// 触发 reloadMessages 才看到刷新。
//
// 4 个测试覆盖：
// 1. local save 触发 vm.agent 更新
// 2. nickname 改动触发 vm.agent 更新
// 3. dispose 后订阅取消
// 4. watchById stream 抛错时 init 不崩溃
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

class _MockAgentRepo extends Mock implements IAgentRepo {}

const _agentId = 'local-1';
const _instanceId = 'inst-1';
const _remoteId = 'r-1';

Agent _activeAgent({List<QuickCommand>? quickCommands}) => Agent(
  localId: _agentId,
  remoteId: _remoteId,
  instanceId: _instanceId,
  name: '产品虾',
  themeColor: '#6c5ce7',
  quickCommands: quickCommands ?? const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InMemoryAgentRepo agentRepo;
  late InMemoryMessageRepo messageRepo;
  late InMemoryConversationRepo conversationRepo;
  late InMemoryInstanceRepo instanceRepo;
  late MockGatewayClient gateway;

  setUp(() async {
    agentRepo = InMemoryAgentRepo();
    messageRepo = InMemoryMessageRepo();
    conversationRepo = InMemoryConversationRepo();
    instanceRepo = InMemoryInstanceRepo();
    gateway = MockGatewayClient();

    await instanceRepo.save(
      Instance(
        id: _instanceId,
        name: 'Test',
        gatewayUrl: 'wss://test.example.com:443',
        tokenRef: 'test-token-ref',
        healthStatus: HealthStatus.online,
        isLocalNetwork: false,
      ),
    );
  });

  ChatViewModel createViewModel() {
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
      instanceId: _instanceId,
      agentId: _agentId,
      achievementChecker: _MockAchievementChecker(),
      flushDelay: Duration.zero,
    );
  }

  group('ChatViewModel.watchById reactivity', () {
    test('init() subscribes to watchById (covers bug: local profile save '
        'must reflect immediately in chat room)', () async {
      await agentRepo.syncFromGateway(_instanceId, [_activeAgent()]);

      final vm = createViewModel();
      await vm.init();

      expect(vm.agent, isNotNull);
      expect(vm.agent!.quickCommands, isEmpty);

      // 模拟 AgentConfigPage 保存快捷指令
      await agentRepo.updateFullProfile(
        _agentId,
        quickCommands: [
          QuickCommand(
            id: 'c1',
            agentId: _agentId,
            label: '状态',
            payload: '/status',
            sortOrder: 0,
          ),
        ],
      );

      // 关键: 不需要发消息, vm.agent 应该已经反映新值
      expect(
        vm.agent!.quickCommands.length,
        1,
        reason: 'watchById 应让 vm.agent 在保存后立刻反映新 quickCommands',
      );
      expect(vm.agent!.quickCommands.first.payload, '/status');
      // ★ state.quickCommands 镜像必须同步,否则 ChatRoomPage.build()
      //   不会 rebuild(Riverpod state.== dedup)。
      expect(
        vm.state.quickCommands.length,
        1,
        reason:
            'state.quickCommands must update so ChatRoomPage.build() re-runs',
      );
      expect(vm.state.quickCommands.first.payload, '/status');
    });

    test(
      'state.quickCommands changes when watchById emits new quickCommands '
      '(regression: Riverpod == dedup would otherwise suppress rebuild)',
      () async {
        await agentRepo.syncFromGateway(_instanceId, [_activeAgent()]);
        final vm = createViewModel();
        await vm.init();
        final beforeState = vm.state;
        expect(beforeState.quickCommands, isEmpty);

        await agentRepo.updateFullProfile(
          _agentId,
          quickCommands: [
            QuickCommand(
              id: 'c1',
              agentId: _agentId,
              label: 'X',
              payload: '/x',
              sortOrder: 0,
            ),
          ],
        );

        // 关键断言: state 引用必须不同 (Riverpod 会触发 rebuild)
        expect(
          identical(vm.state, beforeState),
          isFalse,
          reason: 'state must be a new instance so Riverpod notifies listeners',
        );
        expect(vm.state.quickCommands.length, 1);
        expect(vm.state.quickCommands.first.payload, '/x');
      },
    );

    test('init() subscribes to watchById for nickname change', () async {
      await agentRepo.syncFromGateway(_instanceId, [_activeAgent()]);

      final vm = createViewModel();
      await vm.init();

      expect(vm.agent!.nickname, isNull);

      await agentRepo.updateLocalProfile(_agentId, nickname: '小虾');

      expect(vm.agent!.nickname, '小虾');
    });

    test('dispose() cancels agent subscription', () async {
      await agentRepo.syncFromGateway(_instanceId, [_activeAgent()]);

      final vm = createViewModel();
      await vm.init();
      vm.dispose();

      // dispose 后再更新, vm.agent 不应再变化
      final agentBefore = vm.agent;
      await agentRepo.updateLocalProfile(_agentId, nickname: 'after-dispose');

      expect(
        vm.agent,
        same(agentBefore),
        reason: 'dispose 后订阅取消, vm.agent 不再变',
      );
    });

    test(
      'watchById error does not crash init or other subscriptions',
      () async {
        // 用 mocktail 模拟 watchById 抛异常
        final mockRepo = _MockAgentRepo();
        when(
          () => mockRepo.getById(_agentId),
        ).thenAnswer((_) async => _activeAgent());
        when(() => mockRepo.watchById(_agentId)).thenAnswer(
          (_) => Stream<Agent?>.error(Exception('simulated stream error')),
        );

        final vm = ChatViewModel(
          agentRepo: mockRepo,
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
          achievementChecker: _MockAchievementChecker(),
          flushDelay: Duration.zero,
        );

        // init 应不崩溃 (Law 8: catch 必有 debugPrint, 不影响其他订阅)
        await vm.init();

        // agent 已加载
        expect(vm.agent, isNotNull);

        vm.dispose();
      },
    );
  });
}
