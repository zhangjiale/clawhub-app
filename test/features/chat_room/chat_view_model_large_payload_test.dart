// Gap #6 收尾 (Step 4): ChatViewModel 订阅 `gatewayClient.gatewayNoticeStream`
// (sealed union),把诊断事件映射为 ChatSessionState 上的单 seq +
// 单结构化 notice (gatewayNoticeSeq + lastGatewayNotice)。chat_room_page
// 通过 ref.listen 比较 seq 变化,按 notice 的 runtime type 经
// formatGatewayNotice 派生文案触发 toast。
//
// 4 cases:
// 1. 默认 ChatSessionState.gatewayNoticeSeq == 0 且 lastGatewayNotice == null
// 2. push 一条 notice → seq=1, lastGatewayNotice 持结构化 size/limit
//    (文案契约由下方 formatGatewayNotice 测试锁住)
// 3. push 第二条相同 notice → seq=2 (规避 Model==identity dedup, 见 model-equals-identity-blindspot memory)
// 4. dispose 后再 push → seq 不再增加 (订阅已取消)

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';

class _MockAgentRepo extends Mock implements IAgentRepo {}

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

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
  late _MockAgentRepo agentRepo;
  late InMemoryMessageRepo messageRepo;
  late InMemoryConversationRepo conversationRepo;
  late InMemoryInstanceRepo instanceRepo;
  late MockGatewayClient gateway;
  late SendMessageUseCase sendUseCase;

  setUp(() {
    agentRepo = _MockAgentRepo();
    messageRepo = InMemoryMessageRepo();
    conversationRepo = InMemoryConversationRepo();
    instanceRepo = InMemoryInstanceRepo();
    gateway = MockGatewayClient();
    sendUseCase = SendMessageUseCase(
      messageRepo: messageRepo,
      conversationRepo: conversationRepo,
      instanceRepo: instanceRepo,
      gatewayClient: gateway,
    );
  });

  ChatViewModel createViewModel() {
    return ChatViewModel(
      agentRepo: agentRepo,
      conversationRepo: conversationRepo,
      messageRepo: messageRepo,
      instanceRepo: instanceRepo,
      gatewayClient: gateway,
      sendMessageUseCase: sendUseCase,
      instanceId: _instanceId,
      agentId: _agentId,
      achievementChecker: _MockAchievementChecker(),
      flushDelay: Duration.zero,
    );
  }

  Future<void> seedAndInit(ChatViewModel vm) async {
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
    // VM.init() → _initStreamsAndHistory subscribes to watchById(agentId).
    // Without this stub mocktail throws MissingStubError (caught + logged
    // by the VM's try/catch) — tests pass but spam the output with a scary
    // stack trace. Return an empty stream: these tests don't assert on
    // agent-reactive updates.
    when(
      () => agentRepo.watchById(_agentId),
    ).thenAnswer((_) => Stream<Agent?>.empty());
    await vm.init();
  }

  group('ChatSessionState gateway notice fields (Gap #6 / Step 4)', () {
    test('default gatewayNoticeSeq is 0, lastGatewayNotice is null', () {
      final vm = createViewModel();
      expect(
        vm.state.gatewayNoticeSeq,
        0,
        reason: 'fresh VM must have seq=0 — no diagnostic event seen yet',
      );
      expect(
        vm.state.lastGatewayNotice,
        isNull,
        reason: 'fresh VM must have null notice',
      );
    });

    test('push payload.large notice → seq bumps to 1 and notice holds '
        'structured size/limit (文案由 UI 层 formatGatewayNotice 派生)', () async {
      final vm = createViewModel();
      await seedAndInit(vm);

      gateway.emitGatewayNoticeForTesting(
        _instanceId,
        LargePayloadNotice(
          sessionKey: 'agent:r-1:main',
          size: 30_000_000,
          limit: 26_214_400,
        ),
      );
      // Stream emission is broadcast — pump a frame to flush.
      await Future<void>.delayed(Duration.zero);

      expect(vm.state.gatewayNoticeSeq, 1);
      // State 持结构化 notice（不持本地化串）：UI 层按 runtime type 派生文案。
      final notice = vm.state.lastGatewayNotice;
      expect(notice, isNotNull);
      expect(notice, isA<LargePayloadNotice>());
      expect((notice as LargePayloadNotice).size, 30_000_000);
      expect(notice.limit, 26_214_400);
    });

    test('two identical notices bump seq to 2 (counter, not value)', () async {
      // Per memory model-equals-identity-blindspot: when the new value
      // would equal the old one, Riverpod suppresses the rebuild via
      // state ==.  But here the user-facing impact is "another oversized
      // frame was rejected" — they want a toast every time, even if the
      // payload looks the same.  Hence seq is a monotonic counter that
      // changes per push, and lastGatewayNotice 覆盖每次推送。
      final vm = createViewModel();
      await seedAndInit(vm);

      final notice = LargePayloadNotice(
        sessionKey: 'agent:r-1:main',
        size: 30_000_000,
        limit: 26_214_400,
      );

      gateway.emitGatewayNoticeForTesting(_instanceId, notice);
      await Future<void>.delayed(Duration.zero);
      expect(vm.state.gatewayNoticeSeq, 1);

      gateway.emitGatewayNoticeForTesting(_instanceId, notice);
      await Future<void>.delayed(Duration.zero);
      expect(
        vm.state.gatewayNoticeSeq,
        2,
        reason:
            'seq must increment per push even with identical notice data,'
            ' otherwise the second toast would be suppressed',
      );
    });

    test(
      'after dispose, further payload.large pushes do not bump seq',
      () async {
        final vm = createViewModel();
        await seedAndInit(vm);

        // Sanity: subscription is live and bumps seq on emission.
        gateway.emitGatewayNoticeForTesting(
          _instanceId,
          LargePayloadNotice(sessionKey: 'k', size: 100, limit: 50),
        );
        await Future<void>.delayed(Duration.zero);
        final seqAfterFirstPush = vm.state.gatewayNoticeSeq;
        expect(seqAfterFirstPush, 1);

        // StateNotifier forbids .state after dispose — observe externally
        // via addListener BEFORE dispose so we can capture the seq sequence.
        final observedSeqs = <int>[];
        void observer(ChatSessionState s) =>
            observedSeqs.add(s.gatewayNoticeSeq);
        vm.addListener(observer);

        vm.dispose();
        // After dispose(), .state would throw. We rely solely on the
        // captured observer list going forward.

        gateway.emitGatewayNoticeForTesting(
          _instanceId,
          LargePayloadNotice(sessionKey: 'k', size: 200, limit: 50),
        );
        await Future<void>.delayed(Duration.zero);

        // After dispose, the listener captured NO new seqs — the snapshot
        // was 1 (from before dispose), nothing fires afterwards because the
        // subscription was cancelled in _teardownSubscriptions.
        expect(
          observedSeqs,
          [1],
          reason:
              'after dispose() the subscription must be cancelled — further '
              'pushes must not bump the seq, otherwise navigating back and '
              'reopening the chat would resurrect a stale listener reference. '
              'The captured pre-dispose seq is [1]; an additional seq 2 would '
              'indicate a leak.',
        );
      },
    );
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
      final message = formatGatewayNotice(const BufferOverflowNotice());
      expect(message, isA<String>());
      expect(message, isNotEmpty);
      expect(message, contains('自动重试'));
      // 与 LargePayloadNotice 的定量文案区分 —— 不含字节数。
      expect(message, isNot(contains('字节')));
    });
  });
}
