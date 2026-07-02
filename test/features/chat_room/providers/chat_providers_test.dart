// US-021 AC8 响应式 (provider 层):
// 验证 chatViewModelProvider 的 `ref.listen(agentSyncTickerProvider)` 真的会在
// ticker 递增时调用 vm.refreshAgent()，且 refreshAgent 内部抛出的异常不会
// 从 fire-and-forget 监听器泄漏为未处理异步错误。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';

class _MockAgentRepo extends Mock implements IAgentRepo {}

class _MockGatewayClient extends Mock implements IGatewayClient {}

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

void main() {
  late _MockAgentRepo agentRepo;
  late InMemoryInstanceRepo instanceRepo;
  late InMemoryConversationRepo conversationRepo;
  late InMemoryMessageRepo messageRepo;
  late _MockGatewayClient gatewayClient;
  late _MockAchievementChecker achievementChecker;

  final activeAgent = Agent(
    localId: 'local-a',
    remoteId: 'remote-a',
    instanceId: 'inst-1',
    name: '产品虾',
    themeColor: '#6c5ce7',
  );

  setUp(() {
    agentRepo = _MockAgentRepo();
    instanceRepo = InMemoryInstanceRepo();
    conversationRepo = InMemoryConversationRepo();
    messageRepo = InMemoryMessageRepo(conversationRepo: conversationRepo);
    gatewayClient = _MockGatewayClient();
    achievementChecker = _MockAchievementChecker();

    // Gateway streams: empty is enough for init to subscribe safely.
    when(
      () => gatewayClient.connectionStateStream(any()),
    ).thenAnswer((_) => Stream.empty());
    when(
      () => gatewayClient.messageStream(any()),
    ).thenAnswer((_) => Stream.empty());
    when(
      () => gatewayClient.toolCallStream(any()),
    ).thenAnswer((_) => Stream.empty());
    when(
      () => gatewayClient.streamingDeltaStream(any()),
    ).thenAnswer((_) => Stream.empty());
    when(
      () => gatewayClient.pairingInfoStream(any()),
    ).thenAnswer((_) => Stream.empty());
    // Gap #6 收尾: vm._initStreamsAndHistory now subscribes to
    // gatewayNoticeStream (chat_view_model.dart:756). mocktail's Mock
    // bypasses the interface's `=> const Stream.empty()` default (Dart only
    // inherits default impls via extends/with, not implements), so an
    // unstubbed call returns null → `.listen` throws → caught at the outer
    // try → _teardownSubscriptions cancels the other 5 subs. The 5 tests
    // below still pass (they assert ticker wiring, not streams) but the VM
    // is left with zero active gateway subs and CI output gains a stack
    // trace. Stubbing mirrors the other 5 stream stubs above.
    when(
      () => gatewayClient.gatewayNoticeStream(any()),
    ).thenAnswer((_) => Stream<GatewayNotice>.empty());
    // watchById is invoked by _initStreamsAndHistory (chat_view_model.dart
    // :478) inside its own try/catch — an unstubbed call throws there too
    // (logged, non-fatal). Stub it to keep CI output clean, matching
    // chat_view_model_large_payload_test.dart's setUp rationale.
    when(
      () => agentRepo.watchById(any()),
    ).thenAnswer((_) => Stream<Agent?>.empty());
    when(
      () => gatewayClient.fetchMessageHistory(
        instanceId: any(named: 'instanceId'),
        agentId: any(named: 'agentId'),
        cursor: any(named: 'cursor'),
      ),
    ).thenAnswer((_) async => (messages: <Message>[], nextCursor: null));
    when(() => achievementChecker.check(any())).thenReturn(null);
  });

  Future<void> waitForInitComplete(ProviderContainer container) async {
    final vm = container.read(
      chatViewModelProvider((
        instanceId: 'inst-1',
        agentId: 'local-a',
      )).notifier,
    );
    for (var i = 0; i < 100; i++) {
      if (vm.state.messages is! LoadInProgress) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('vm.init() did not complete within 1s');
  }

  ProviderContainer createContainer() {
    final sendUseCase = SendMessageUseCase(
      messageRepo: messageRepo,
      conversationRepo: conversationRepo,
      instanceRepo: instanceRepo,
      gatewayClient: gatewayClient,
    );

    final container = ProviderContainer(
      overrides: [
        agentRepoProvider.overrideWithValue(agentRepo),
        instanceRepoProvider.overrideWithValue(instanceRepo),
        conversationRepoProvider.overrideWithValue(conversationRepo),
        messageRepoProvider.overrideWithValue(messageRepo),
        gatewayClientProvider.overrideWithValue(gatewayClient),
        sendMessageUseCaseProvider.overrideWithValue(sendUseCase),
        achievementCheckerProvider.overrideWithValue(achievementChecker),
      ],
    );
    addTearDown(() {
      runZonedGuarded(() => container.dispose(), (error, stack) {
        // Swallow the double-dispose AssertionError from Riverpod's
        // StateNotifierProviderElement.runOnDispose (same pattern as
        // agent_profile_provider_test).
      });
    });
    return container;
  }

  test(
    'ref.listen(agentSyncTickerProvider) triggers vm.refreshAgent on ticker bump',
    () async {
      var calls = 0;
      when(() => agentRepo.getById('local-a')).thenAnswer((_) async {
        calls++;
        return activeAgent;
      });
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );

      final container = createContainer();
      container.read(
        chatViewModelProvider((instanceId: 'inst-1', agentId: 'local-a')),
      );
      await waitForInitComplete(container);

      final initCalls = calls;
      expect(initCalls, 1);

      // BUG B 修复:ticker 携带 instanceId,listener 过滤本实例才触发。
      // bump 时指定与 VM 相同的 instanceId → refreshAgent 应被调。
      final notifier = container.read(agentSyncTickerProvider.notifier);
      notifier.state = AgentSyncTick(
        revision: (notifier.state?.revision ?? 0) + 1,
        instanceId: 'inst-1',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        calls,
        2,
        reason: 'ticker bump 后 listener 应触发 refreshAgent → getById 第 2 次',
      );
    },
  );

  // BUG B 修复:跨实例 ticker bump 不应触发本实例的 refreshAgent。
  // 原实现 ticker = StateProvider<int> 无 payload,任何实例 sync 都会触发
  // 所有 ChatRoom 的 getById —— N 个实例 + 1 sync = N 次冗余 SQLite read。
  // 修复后 ticker = StateProvider<String?>,listener 按 instanceId 过滤。
  test(
    'cross-instance ticker bump is filtered out (Law 6 / N+1 prevention)',
    () async {
      var calls = 0;
      when(() => agentRepo.getById('local-a')).thenAnswer((_) async {
        calls++;
        return activeAgent;
      });
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );

      final container = createContainer();
      container.read(
        chatViewModelProvider((instanceId: 'inst-1', agentId: 'local-a')),
      );
      await waitForInitComplete(container);
      expect(calls, 1, reason: 'init 阶段 getById 调 1 次');

      // bump ticker 携带**不同**的 instanceId('inst-2'),本 VM 应跳过
      final notifier = container.read(agentSyncTickerProvider.notifier);
      notifier.state = AgentSyncTick(
        revision: (notifier.state?.revision ?? 0) + 1,
        instanceId: 'inst-2',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        calls,
        1,
        reason:
            '跨实例 ticker bump 不应触发本实例的 refreshAgent,'
            '避免 N 个 ChatRoom 全量冗余查询。'
            '当前 calls=$calls(预期 1)',
      );
    },
  );

  test(
    'refreshAgent error from fire-and-forget listen is swallowed (no unhandled async error)',
    () async {
      var calls = 0;
      when(() => agentRepo.getById('local-a')).thenAnswer((_) async {
        calls++;
        if (calls > 1) throw Exception('DB error on refresh');
        return activeAgent;
      });
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );

      final container = createContainer();
      final vm = container.read(
        chatViewModelProvider((
          instanceId: 'inst-1',
          agentId: 'local-a',
        )).notifier,
      );
      await waitForInitComplete(container);

      // 触发 refreshAgent，内部 getById 会抛异常。
      // ticker 携带本实例 instanceId 才能命中 listener 过滤。
      final notifier = container.read(agentSyncTickerProvider.notifier);
      notifier.state = AgentSyncTick(
        revision: (notifier.state?.revision ?? 0) + 1,
        instanceId: 'inst-1',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // 如果异常从 fire-and-forget 监听器泄漏，测试框架会捕获到未处理异步错误。
      // 此处断言 VM 仍在工作且状态未因异常而损坏。
      expect(vm.agent?.isRemoved ?? false, isFalse);
      expect(calls, greaterThan(1));
    },
  );

  test(
    'consecutive same-instance sync ticks both trigger refreshAgent',
    () async {
      var calls = 0;
      when(() => agentRepo.getById('local-a')).thenAnswer((_) async {
        calls++;
        return activeAgent;
      });
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
          isLocalNetwork: false,
        ),
      );

      final container = createContainer();
      container.read(
        chatViewModelProvider((instanceId: 'inst-1', agentId: 'local-a')),
      );
      await waitForInitComplete(container);
      expect(calls, 1, reason: 'init 阶段 getById 调 1 次');

      final notifier = container.read(agentSyncTickerProvider.notifier);
      notifier.state = AgentSyncTick(
        revision: (notifier.state?.revision ?? 0) + 1,
        instanceId: 'inst-1',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      notifier.state = AgentSyncTick(
        revision: (notifier.state?.revision ?? 0) + 1,
        instanceId: 'inst-1',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        calls,
        3,
        reason:
            '连续两次同实例 sync 都必须触发 refreshAgent；'
            '旧 String? ticker 第二次同值写入会被 Riverpod 去重。',
      );
    },
  );

  // `if (initFuture == null) return;` 会让 init 未跑的窗口期内
  // vm._agent 维持 null,用户看到的是普通 ChatRoom UI 而不是占位页。
  //
  // 直接构造 ChatViewModel (绕过 provider 的自动 init 调用) 来模拟
  // "refreshAgent 在 init 之前被调用"的场景。
  test('refreshAgent syncs tombstone when init was never called '
      '(initFuture == null, US-021 v1.2 简化)', () async {
    final tombstonedAgent = Agent(
      localId: 'local-a',
      remoteId: 'remote-a',
      instanceId: 'inst-1',
      name: '产品虾',
      themeColor: '#6c5ce7',
      removedAt: DateTime.now().millisecondsSinceEpoch,
    );
    when(
      () => agentRepo.getById('local-a'),
    ).thenAnswer((_) async => tombstonedAgent);

    // 直接构造 VM,不调 init() —— _initFuture 字段保持 null。
    final vm = ChatViewModel(
      agentRepo: agentRepo,
      conversationRepo: InMemoryConversationRepo(),
      messageRepo: InMemoryMessageRepo(),
      instanceRepo: instanceRepo,
      gatewayClient: gatewayClient,
      sendMessageUseCase: SendMessageUseCase(
        messageRepo: messageRepo,
        conversationRepo: conversationRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gatewayClient,
      ),
      instanceId: 'inst-1',
      agentId: 'local-a',
      achievementChecker: _MockAchievementChecker(),
      flushDelay: Duration.zero,
    );
    expect(vm.agent?.isRemoved ?? false, isFalse);

    await vm.refreshAgent();

    expect(
      vm.agent?.isRemoved ?? false,
      isTrue,
      reason:
          'initFuture == null 时,refreshAgent 不能早退,'
          '必须直接 fetch agent 并同步 tombstone 状态',
    );
  });

  // Gap #6 收尾回归守卫: vm._initStreamsAndHistory 现在订阅
  // gatewayNoticeStream (chat_view_model.dart:756)。若 mock 未 stub 该方法,
  // mocktail 返回 null → `.listen` 抛 → 外层 try 捕获 → _teardownSubscriptions
  // 取消全部已建立的订阅,_streamsInitialized 永远停在 false。5 个 ticker
  // 测试因只断言 getById 次数而仍通过,故此前回归被掩盖。本测试直接断言
  // init 走到末尾 (_streamsInitialized == true),把"订阅被静默拆掉"钉成红。
  test('vm.init() subscribes all gateway streams (gatewayNoticeStream stubbed, '
      'no teardown)', () async {
    when(() => agentRepo.getById('local-a')).thenAnswer((_) async {
      return activeAgent;
    });
    await instanceRepo.save(
      Instance(
        id: 'inst-1',
        name: 'Test',
        gatewayUrl: 'wss://test:18789',
        tokenRef: 'tok',
        healthStatus: HealthStatus.online,
        isLocalNetwork: false,
      ),
    );

    final container = createContainer();
    final vm = container.read(
      chatViewModelProvider((
        instanceId: 'inst-1',
        agentId: 'local-a',
      )).notifier,
    );

    // Poll up to 1s for _initStreamsAndHistory to reach its tail
    // (_streamsInitialized = true). Before the gatewayNoticeStream stub,
    // this never becomes true (init throws at the notice sub).
    for (var i = 0; i < 100; i++) {
      if (vm.streamsInitializedForTesting) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      vm.streamsInitializedForTesting,
      isTrue,
      reason:
          'init must reach _streamsInitialized=true — all 6 gateway streams '
          '(incl. gatewayNoticeStream) subscribed. A false value means init '
          'threw mid-way and _teardownSubscriptions tore the subs down.',
    );
  });
}
