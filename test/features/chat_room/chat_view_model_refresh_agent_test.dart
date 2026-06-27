// US-021 AC8 响应式修复：验证 refreshAgent() 把后台 sync 的 tombstone 状态
// 同步进 vm._agent —— UI 经 ref.watch(chatViewModelProvider) 触发 rebuild 后
// 读 vm.agent.isRemoved 显示占位页。
//
// Step 4 改造:tombstone 不再用 state.isAgentRemoved bool 字段，改读
// vm.agent.isRemoved。refreshAgent 内部走 _setAgent 路径更新 _agent +
// bump contentRevision,本测试断言改为验证 vm.agent.isRemoved 而非
// state.isAgentRemoved。
//
// 场景：用户停在 ChatRoom，后台 syncFromGateway 把 agent 标记 tombstone。
// provider 侧 ref.listen(agentSyncTickerProvider) 调 vm.refreshAgent()，
// VM 重查 DB 并更新 vm._agent → contentRevision bump → UI 重建显示占位页。
//
// 用 mocktail mock IAgentRepo：可精确控制 getById 在多次调用中返回的 agent
// 状态（active / tombstoned / null），不受 InMemoryAgentRepo（legacy，未实现
// tombstone diff）行为影响。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

class _MockAgentRepo extends Mock implements IAgentRepo {}

const _agentId = 'local-1';
const _instanceId = 'inst-1';
const _remoteId = 'r-1';

Agent _activeAgent() => Agent(
  localId: _agentId,
  remoteId: _remoteId,
  instanceId: _instanceId,
  name: '产品虾',
  themeColor: '#6c5ce7',
);

Agent _tombstonedAgent() => Agent(
  localId: _agentId,
  remoteId: _remoteId,
  instanceId: _instanceId,
  name: '产品虾',
  themeColor: '#6c5ce7',
  removedAt: 1719200000000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MockAgentRepo agentRepo;
  late InMemoryMessageRepo messageRepo;
  late InMemoryConversationRepo conversationRepo;
  late InMemoryInstanceRepo instanceRepo;
  late MockGatewayClient gateway;

  setUp(() {
    agentRepo = _MockAgentRepo();
    messageRepo = InMemoryMessageRepo();
    conversationRepo = InMemoryConversationRepo();
    instanceRepo = InMemoryInstanceRepo();
    gateway = MockGatewayClient();
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

  Future<void> setupInstance() async {
    await instanceRepo.save(
      Instance(
        id: _instanceId,
        name: 'Test',
        gatewayUrl: 'wss://t.example.com:443',
        tokenRef: 'tok',
        healthStatus: HealthStatus.online,
        isLocalNetwork: false,
      ),
    );
  }

  group('ChatViewModel.refreshAgent (US-021 AC8 响应式)', () {
    test(
      'WHEN agent was active at init THEN vm.agent.isRemoved is false',
      () async {
        await setupInstance();
        when(
          () => agentRepo.getById(_agentId),
        ).thenAnswer((_) async => _activeAgent());
        final vm = createViewModel();
        await vm.init();

        expect(vm.agent?.isRemoved ?? false, isFalse);
      },
    );

    test('WHEN agent is tombstoned in DB after init THEN refreshAgent sets '
        'vm.agent.isRemoved=true', () async {
      await setupInstance();
      // init 时 active；refreshAgent 重查时已 tombstone
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _activeAgent());
      final vm = createViewModel();
      await vm.init();
      expect(vm.agent?.isRemoved ?? false, isFalse);

      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _tombstonedAgent());

      await vm.refreshAgent();

      expect(
        vm.agent?.isRemoved ?? false,
        isTrue,
        reason:
            'refreshAgent 应把后台 tombstone 同步进 vm._agent，'
            '使 AC8 占位页响应式出现',
      );
    });

    test('WHEN tombstoned agent reappears on Gateway THEN refreshAgent '
        'clears vm.agent.isRemoved=false (复活)', () async {
      await setupInstance();
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _tombstonedAgent());
      final vm = createViewModel();
      await vm.init();
      expect(vm.agent?.isRemoved ?? false, isTrue);

      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _activeAgent());
      await vm.refreshAgent();

      expect(
        vm.agent?.isRemoved ?? false,
        isFalse,
        reason: '复活后 refreshAgent 应清除 tombstone 标记',
      );
    });

    test('WHEN init has not started AND agent is tombstoned THEN refreshAgent '
        'still syncs vm.agent.isRemoved=true (US-021 v1.2 简化)', () async {
      await setupInstance();
      // init 未启动（_initFuture 仍为 null），后台 sync 已 tombstone。
      // 简化后 refreshAgent 不再等 initFuture,直接 fetch + 同步 tombstone。
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _tombstonedAgent());
      final vm = createViewModel();
      // 故意不调 init —— 模拟 ticker 在 init 启动前触发的竞态

      await vm.refreshAgent();

      expect(vm.agent?.isRemoved ?? false, isTrue);
      verify(() => agentRepo.getById(_agentId)).called(1);
    });

    test('WHEN agent becomes null in DB after init THEN refreshAgent sets '
        'vm.agent.isRemoved=false (agent not found ≠ tombstoned)', () async {
      await setupInstance();
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _activeAgent());
      final vm = createViewModel();
      await vm.init();

      when(() => agentRepo.getById(_agentId)).thenAnswer((_) async => null);
      await vm.refreshAgent();

      expect(
        vm.agent?.isRemoved ?? false,
        isFalse,
        reason: 'agent 查不到（null）不是 tombstone —— 不应误显示占位页',
      );
    });

    test('WHEN getById throws during refreshAgent THEN error is swallowed '
        'and state is not changed', () async {
      await setupInstance();
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _activeAgent());
      final vm = createViewModel();
      await vm.init();
      expect(vm.agent?.isRemoved ?? false, isFalse);

      when(() => agentRepo.getById(_agentId)).thenThrow(Exception('DB error'));
      await expectLater(vm.refreshAgent(), completes);

      expect(vm.agent?.isRemoved ?? false, isFalse);
    });
  });

  // Bug 2 修复回归测试：tombstone→alive 转换后必须重新订阅 streams，
  // 否则入站 agent 回复 / 连接状态驱动的 reload 会静默丢失。
  group(
    'ChatViewModel.refreshAgent tombstone→alive stream resubscribe (Bug 2)',
    () {
      test(
        'WHEN init on tombstoned agent THEN streamsInitializedForTesting is false',
        () async {
          await setupInstance();
          when(
            () => agentRepo.getById(_agentId),
          ).thenAnswer((_) async => _tombstonedAgent());
          final vm = createViewModel();
          await vm.init();

          expect(
            vm.streamsInitializedForTesting,
            isFalse,
            reason:
                'init 在 tombstone 上早退，6 个 stream 订阅都应未建立；'
                '占位页正常显示，但流不消耗资源',
          );
        },
      );

      test('WHEN tombstoned init THEN refreshAgent with alive agent '
          'THEN streamsInitializedForTesting flips to true', () async {
        await setupInstance();
        when(
          () => agentRepo.getById(_agentId),
        ).thenAnswer((_) async => _tombstonedAgent());
        final vm = createViewModel();
        await vm.init();
        expect(vm.streamsInitializedForTesting, isFalse);

        // 后台 syncFromGateway 复活 agent —— refreshAgent 必须在 tombstone→alive
        // 时触发 _initStreamsAndHistory()，否则 6 个 stream 订阅仍是 null，
        // 用户发消息时入站 agent 回复 / 连接状态变化全部丢失。
        when(
          () => agentRepo.getById(_agentId),
        ).thenAnswer((_) async => _activeAgent());
        await vm.refreshAgent();

        expect(
          vm.streamsInitializedForTesting,
          isTrue,
          reason:
              'refreshAgent 检测到 tombstone→alive 转换，必须重新订阅 stream；'
              '否则 ChatRoom 显示正常聊天但流全断（Bug 2）',
        );
        expect(vm.agent?.isRemoved ?? false, isFalse);
      });

      test(
        'WHEN already-alive init THEN refreshAgent stays a no-op '
        '(streamsInitializedForTesting stays true, no double-subscribe)',
        () async {
          await setupInstance();
          when(
            () => agentRepo.getById(_agentId),
          ).thenAnswer((_) async => _activeAgent());
          final vm = createViewModel();
          await vm.init();
          expect(vm.streamsInitializedForTesting, isTrue);

          // agent 仍然 active，refreshAgent 不应触发新的 _initStreamsAndHistory
          // (否则会重复订阅 6 个 stream)
          await vm.refreshAgent();

          expect(vm.streamsInitializedForTesting, isTrue);
        },
      );
    },
  );
}
