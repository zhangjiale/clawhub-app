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

  group('ChatSessionState equality', () {
    test('includes content revision (sole rebuild trigger after Step 4)', () {
      // Step 4: tombstone 不再是独立 bool 字段，UI 改读 vm.agent.isRemoved。
      // contentRevision 是唯一驱动 ref.watch rebuild 的"agent 变化"信号。
      expect(
        const ChatSessionState(contentRevision: 1),
        isNot(const ChatSessionState(contentRevision: 2)),
        reason: 'agent data changes must bump contentRevision to bypass dedup',
      );
    });
  });

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
      // ★ state.contentRevision 必须递增,否则 ChatRoomPage.build()
      //   不会 rebuild(Riverpod state.== dedup)。UI 实际读取 vm.agent。
      // Step 2: 此时已经走完 init (revision=1) + updateFullProfile
      // 触发一次 watchById 真实内容变更 (revision=2)。若 filter 失效，
      // seed event 会让 init 阶段多 bump 一次，revision=3。
      expect(
        vm.state.contentRevision,
        equals(2),
        reason:
            'After init (1) + one real content change via updateFullProfile '
            '(+1), revision must be exactly 2. If >2, the contentEquals '
            'filter is letting the seed event through.',
      );
    });

    test(
      'state.contentRevision changes when watchById emits non-identity agent fields '
      '(regression: Riverpod == dedup would otherwise suppress rebuild)',
      () async {
        await agentRepo.syncFromGateway(_instanceId, [_activeAgent()]);
        final vm = createViewModel();
        await vm.init();
        final beforeState = vm.state;
        final beforeRevision = beforeState.contentRevision;

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
        // Step 2: 断言精确化 —— 必须是 beforeRevision + 1（一次 bump），
        // 而不是 greaterThan（多次 bump 也能过）。过滤后真实内容变更只
        // 触发一次 _setAgent，revision 应恰好 +1。
        expect(vm.state.contentRevision, equals(beforeRevision + 1));
        expect(vm.agent!.quickCommands.first.payload, '/x');
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

    test('seed event with identical content does NOT bump contentRevision '
        '(Step 2: contentEquals filter suppresses no-op emits)', () async {
      await agentRepo.syncFromGateway(_instanceId, [_activeAgent()]);

      final vm = createViewModel();
      await vm.init();

      // init() 已经走完 _setAgent(getById) + watchById seed 两条路径。
      // 若 filter 生效，revision 应该是 1（一次 _setAgent）。
      // 若 filter 失效（旧逻辑），revision 会是 2（init + seed 各 bump 一次）。
      final revisionAfterInit = vm.state.contentRevision;
      expect(
        revisionAfterInit,
        equals(1),
        reason:
            'After init, only one _setAgent call should have fired. '
            'If this is >1, the contentEquals filter on watchById is broken.',
      );

      // 手动 emit 一次内容完全相同的 agent（模拟 Drift watchSingleOrNull
      // 在某些时序下重发 seed）。filter 应再次抑制。
      await agentRepo.updateLocalProfile(_agentId, nickname: null);
      // updateLocalProfile 即便参数相同也会 emit（仓库实现细节），关键是
      // 我们的 filter 应确保相同内容不触发 _setAgent 链路。
      expect(
        vm.state.contentRevision,
        equals(revisionAfterInit),
        reason:
            'A content-equal emit must be filtered out; contentRevision '
            'must NOT bump (was: '
            '$revisionAfterInit, now: ${vm.state.contentRevision})',
      );
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
