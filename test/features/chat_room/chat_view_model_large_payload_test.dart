// Finding #9 fix: Gateway 诊断事件不再走 ChatSessionState (== 排除字段
// 导致 StateNotifier.state setter 去重,ref.listen 永不触发——toast 不弹)。
// 改为 gatewayNoticeProvider (StreamProvider.family<GatewayNotice, String>)
// 直接把 gatewayClient.gatewayNoticeStream 暴露给 UI,page 用 ref.listen
// 弹 toast。VM 不再订阅 notice stream。
//
// 本文件验证:
// 1. gatewayNoticeProvider 把 mock 的 gatewayNoticeStream 事件转发为 AsyncValue
// 2. chatViewModelProvider create body 在 vm.init() 之前订阅 gatewayNoticeProvider
//    (broadcast stream 无 replay,fetch RTT 期间 notice 不会丢)
// 3. formatGatewayNotice 文案契约 (Step 4 视觉锁)

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart' show HealthStatus;
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';

class _MockAgentRepo extends Mock implements IAgentRepo {}

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// MockGatewayClient variant that emits a [GatewayNotice] mid-
/// [fetchMessageHistory], reproducing the race (Finding #1) where a notice
/// arrives while the VM is still awaiting the history RPC — before its
/// gatewayNoticeStream subscription exists in the buggy order.
class _NoticeDuringHistoryMock extends MockGatewayClient {
  GatewayNotice? noticeToEmitDuringHistory;

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) async {
    // Emit synchronously while the VM is still suspended at the
    // `await fetchMessageHistory` call — i.e. before the notice
    // subscription is created (buggy order) or after it (fixed order).
    final notice = noticeToEmitDuringHistory;
    if (notice != null) {
      emitGatewayNoticeForTesting(instanceId, notice);
    }
    return (messages: <Message>[], nextCursor: null);
  }
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('gatewayNoticeProvider (Finding #9 fix)', () {
    test(
      'emits notices from gatewayClient.gatewayNoticeStream as AsyncData',
      () async {
        final gateway = MockGatewayClient();
        final container = ProviderContainer(
          overrides: [gatewayClientProvider.overrideWithValue(gateway)],
        );
        addTearDown(container.dispose);

        // Initial read: stream subscribed, no emission yet -> AsyncLoading.
        expect(
          container.read(gatewayNoticeProvider(_instanceId)).isLoading,
          isTrue,
        );

        gateway.emitGatewayNoticeForTesting(
          _instanceId,
          LargePayloadNotice(
            sessionKey: 'agent:r-1:main',
            size: 30_000_000,
            limit: 26_214_400,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final next = container.read(gatewayNoticeProvider(_instanceId));
        expect(next.value, isA<LargePayloadNotice>());
        expect((next.value as LargePayloadNotice).size, 30_000_000);
        expect((next.value as LargePayloadNotice).limit, 26_214_400);
      },
    );

    test('chatViewModelProvider subscribes gatewayNoticeProvider BEFORE '
        'vm.init() fetches history (broadcast no-replay invariant)', () async {
      final gateway = _NoticeDuringHistoryMock();
      final notice = LargePayloadNotice(
        sessionKey: 'agent:r-1:main',
        size: 30_000_000,
        limit: 26_214_400,
      );
      gateway.noticeToEmitDuringHistory = notice;

      final agentRepo = _MockAgentRepo();
      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final instanceRepo = InMemoryInstanceRepo();
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
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _activeAgent());
      when(
        () => agentRepo.watchById(_agentId),
      ).thenAnswer((_) => Stream<Agent?>.empty());

      final sendUseCase = SendMessageUseCase(
        messageRepo: messageRepo,
        conversationRepo: conversationRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
      );

      final container = ProviderContainer(
        overrides: [
          agentRepoProvider.overrideWithValue(agentRepo),
          instanceRepoProvider.overrideWithValue(instanceRepo),
          conversationRepoProvider.overrideWithValue(conversationRepo),
          messageRepoProvider.overrideWithValue(messageRepo),
          gatewayClientProvider.overrideWithValue(gateway),
          sendMessageUseCaseProvider.overrideWithValue(sendUseCase),
          achievementCheckerProvider.overrideWithValue(
            _MockAchievementChecker(),
          ),
        ],
      );
      addTearDown(() {
        runZonedGuarded(() => container.dispose(), (_, _) {});
      });

      // Read chatViewModelProvider -> triggers create body ->
      // ref.listen(gatewayNoticeProvider) [forces StreamProvider to
      // subscribe to gatewayNoticeStream] -> vm.init() ->
      // _initStreamsAndHistory -> fetchMessageHistory [_NoticeDuringHistoryMock
      // emits notice]. The notice must be captured because the StreamProvider
      // was subscribed BEFORE fetchMessageHistory ran.
      final vm = container.read(
        chatViewModelProvider((
          instanceId: _instanceId,
          agentId: _agentId,
        )).notifier,
      );
      for (var i = 0; i < 100; i++) {
        if (vm.streamsInitializedForTesting) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        vm.streamsInitializedForTesting,
        isTrue,
        reason:
            'init must complete — if it threw mid-way the notice '
            'subscription test below is meaningless',
      );

      // The notice emitted during fetchMessageHistory must have been
      // captured by gatewayNoticeProvider (subscribed before fetch).
      final noticeAsync = container.read(gatewayNoticeProvider(_instanceId));
      expect(
        noticeAsync.value,
        equals(notice),
        reason:
            'broadcast stream has no replay — if gatewayNoticeProvider '
            'were subscribed AFTER fetchMessageHistory, the notice emitted '
            'during fetch RTT would be permanently lost',
      );
    });
  });

  // Step 4 视觉契约锁：formatGatewayNotice 是顶层纯函数,锁定 toast 文案
  // 必含 size/limit 字节数。等价于 golden snapshot,但无需 golden 基建,
  // 跑在 CI 快测里。重构文案时这层断言会先红,防止视觉回归静默溜走。
  group('formatGatewayNotice (Step 4 toast copy contract)', () {
    test(
      'LargePayloadNotice formats a message containing size + limit bytes',
      () {
        final message = formatGatewayNotice(
          LargePayloadNotice(
            sessionKey: 'agent:r-1:main',
            size: 30_000_000,
            limit: 26_214_400,
          ),
        );
        expect(message, contains('30000000'));
        expect(message, contains('26214400'));
      },
    );

    test('formatGatewayNotice is exhaustive over the sealed union '
        '(future subtypes force a branch here)', () {
      // 没有显式 default 兜底——编译期穷尽性即契约。新增 RateLimitNotice
      // 等子类型时,若忘了在 formatGatewayNotice 补分支,本测试文件连同
      // 整个编译都会红。
      final formatted = formatGatewayNotice(
        LargePayloadNotice(sessionKey: 'k', size: 1, limit: 2),
      );
      expect(formatted, isA<String>());
      expect(formatted, isNotEmpty);
    });

    // F-4: 缓冲满翻译成的诊断事件。文案契约：只定性 + 安抚「自动重试」，
    // 不暴露字节数（用户看不懂也无从操作；缓冲满是瞬态，等在途请求收完即恢复）。
    test('BufferOverflowNotice formats a non-actionable retry message', () {
      final message = formatGatewayNotice(BufferOverflowNotice());
      expect(message, isA<String>());
      expect(message, isNotEmpty);
      expect(message, contains('自动重试'));
      // 与 LargePayloadNotice 的定量文案区分 —— 不含字节数。
      expect(message, isNot(contains('字节')));
    });
  });
}
