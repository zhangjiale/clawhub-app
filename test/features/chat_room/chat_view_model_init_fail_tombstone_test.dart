// US-021 AC8 robustness: verify init failure path resets state.isAgentRemoved
// to false, preventing stale tombstone state from prior sync from triggering
// the AC8 placeholder after a failed init.
//
// Failure scenario (from code review #4):
//   1. init succeeds with tombstoned agent → isAgentRemoved = true
//   2. sync un-tombstones agent in DB
//   3. subsequent init fails (transient DB error)
//   4. catch block sets _agent = null but skips _syncAgentRemoved()
//   5. AC8 placeholder renders for now-live agent → bug
//
// This test fixes the catch block to call _syncAgentRemoved() so step 4
// is impossible.

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

Agent _tombstonedAgent() => Agent(
  localId: _agentId,
  remoteId: 'r-1',
  instanceId: _instanceId,
  name: '产品虾',
  themeColor: '#6c5ce7',
  removedAt: 1719200000000,
);

void main() {
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

  test('init failure resets isAgentRemoved to false even when prior '
      'tombstone state was true', () async {
    // Arrange: VM constructor pattern from chat_view_model.dart:start_chat
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

    final vm = createViewModel();

    // Force prior state.isAgentRemoved = true (simulate prior sync tombstone).
    // 这是上轮 sync 把 agent 标记 tombstone 的快照残留 —— 测试在 init 失败
    // 时 catch 块是否把此 stale true 重置回 false。
    vm.state = vm.state.copyWith(isAgentRemoved: true);
    expect(
      vm.state.isAgentRemoved,
      isTrue,
      reason: 'sanity: 预设上轮 tombstone 状态成功',
    );

    // 配置 next init() 调用 getById 时抛 transient DB error。
    when(
      () => agentRepo.getById(_agentId),
    ).thenThrow(Exception('DB transient error'));

    // Act: 触发 init() —— 第一行 _agent = await _agentRepo.getById(agentId)
    // 会抛异常，进入 catch 块。
    await vm.init();

    // Assert: state.isAgentRemoved 必须重置为 false（不残留上轮 true）。
    expect(
      vm.state.isAgentRemoved,
      isFalse,
      reason:
          'init 失败时 catch 块必须调 _syncAgentRemoved() 重置 '
          'isAgentRemoved，避免上轮 tombstone 状态残留导致 AC8 '
          '占位页错乱',
    );
  });
}
