// US-021 AC9 close signal: 当 ChatViewModel.send() 检测到 agent 已被
// Gateway 删除（tombstoned）时，必须设置 ChatSessionState.closeRequested = true，
// 让 chat_room_page 能通过 ref.listen 触发 Navigator.pop() 回上一页面。
//
// 当前实现（chat_view_model.dart:757-802）只设置 LoadError 不触发关闭信号，
// UI 切到错误视图但不 pop —— 与 spec AC9 不符。
//
// 测试覆盖两种 tombstone 检测路径：
// 1. _agent 缓存已被 init 标记为 tombstoned（init 短路留下 _agent.isRemoved=true）
// 2. _tombstoneSuspect 标志为 true 时 send 重查 freshAgent → 仍 tombstoned
//
// 复用 chat_view_model_send_no_redundant_getbyid_test.dart 的 mock 风格。

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
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

  Future<void> seedInstance() async {
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

  group('US-021 AC9: ChatSessionState.closeRequested', () {
    test('default value is false (not requesting close on fresh VM)', () {
      final vm = createViewModel();
      expect(
        vm.state.closeRequested,
        isFalse,
        reason: 'fresh VM 必须 closeRequested=false,不应误触发页面关闭',
      );
    });

    test('send() sets closeRequested=true when cached _agent is tombstoned '
        '(init short-circuit path)', () async {
      await seedInstance();
      // Arrange: agentRepo.getById 在 init 时返回 tombstoned agent →
      // init 短路，_agent.isRemoved=true 留在缓存。
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _tombstonedAgent());

      final vm = createViewModel();
      await vm.init();
      expect(vm.agent?.isRemoved, isTrue, reason: 'sanity: init 已标记 tombstone');

      // Act: 用户点击发送
      await vm.send('Hello');

      // Assert: closeRequested 必须为 true,触发页面关闭
      expect(
        vm.state.closeRequested,
        isTrue,
        reason:
            'cached tombstoned agent 检测时 send() 必须设置 closeRequested=true,'
            '让 chat_room_page 触发 Navigator.pop() (US-021 AC9)',
      );
    });

    test('send() sets closeRequested=true when tombstone-suspect recheck '
        'detects fresh tombstone', () async {
      await seedInstance();
      // init 返回 active agent → _agent 缓存 active
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _activeAgent());

      final vm = createViewModel();
      await vm.init();
      expect(vm.agent?.isRemoved, isFalse, reason: 'sanity: init 标记 active');

      // 模拟 ticker 触发：markTombstoneSuspectAndRefresh 会
      // (a) 置 _tombstoneSuspect=true
      // (b) refreshAgent() 调 getById,因 stub 仍返回 active,
      //     contentEquals 守卫过滤,_agent 保持 active
      await vm.markTombstoneSuspectAndRefresh();
      expect(
        vm.agent?.isRemoved,
        isFalse,
        reason: 'sanity: refreshAgent 后 _agent 仍 active',
      );

      // 重新 stub getById：ticker 后的 send 重查发现 agent 已被 tombstone
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _tombstonedAgent());

      // Act: 用户点击发送
      await vm.send('Hello');

      // Assert: 重查后 freshAgent.isRemoved → closeRequested 必须为 true
      expect(
        vm.state.closeRequested,
        isTrue,
        reason:
            'tombstone-suspect recheck 后 freshAgent tombstoned 检测时 '
            'send() 必须设置 closeRequested=true (US-021 AC9)',
      );
    });

    test('send() does NOT set closeRequested when agent is active '
        '(happy path regression)', () async {
      await seedInstance();
      when(
        () => agentRepo.getById(_agentId),
      ).thenAnswer((_) async => _activeAgent());

      final vm = createViewModel();
      await vm.init();
      await vm.send('Hello');

      expect(
        vm.state.closeRequested,
        isFalse,
        reason: 'active agent 发消息不应触发 closeRequested',
      );
    });
  });
}
