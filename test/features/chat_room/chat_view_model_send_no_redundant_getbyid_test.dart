// BUG C 修复 (Law 6): ChatViewModel.send() 不应在每次发送时无条件
// _agentRepo.getById(agentId)。tombstone 仅由 syncFromGateway 写入,
// 而 syncFromGateway 必触发 AgentsSyncedEvent → ticker 监听器已调用
// refreshAgent → _agent 已是最新的。
//
// 因此 send() 的 getById 仅在"ticker 触发后到 send 之间存在窗口"时才有意义,
// 用 _tombstoneSuspect 标志门控。无 ticker fire 时复用 _agent 缓存。
//
// 用 mocktail mock IAgentRepo 精确计数 getById 调用。
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
    // MockGatewayClient 是真实类（提供默认流实现），不需要 when() stub。
    // fetchMessageHistory 也用默认空返回。
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

  group('ChatViewModel.send() — Law 6 / no redundant getById', () {
    test('WHEN no agentSyncTicker has fired since init THEN send() reuses '
        'cached _agent (no extra getById)', () async {
      var getByIdCalls = 0;
      when(() => agentRepo.getById(_agentId)).thenAnswer((_) async {
        getByIdCalls++;
        return _activeAgent();
      });
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
      await vm.init();
      expect(getByIdCalls, 1, reason: 'init 阶段 getById 调 1 次');

      // 无 ticker fire 直接 send
      await vm.send('Hello #1');
      expect(
        getByIdCalls,
        1,
        reason:
            '无 ticker fire 时 send() 应复用 _agent 缓存,'
            '不再调用 getById。BUG C 修复:实际看到 $getByIdCalls 次',
      );

      // 连续 send 多次,均不触发 getById
      await vm.send('Hello #2');
      await vm.send('Hello #3');
      expect(
        getByIdCalls,
        1,
        reason: '多次 send 在无 ticker fire 时累计仍为 1 次 getById',
      );
    });

    test('WHEN send is called BEFORE init THEN send awaits init '
        'and still does not extra-getById beyond init+1', () async {
      var getByIdCalls = 0;
      when(() => agentRepo.getById(_agentId)).thenAnswer((_) async {
        getByIdCalls++;
        return _activeAgent();
      });
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
      // 不调 init —— send 内部 await init
      await vm.send('Hello!');
      expect(
        getByIdCalls,
        1,
        reason: 'send 内部 init() 调 1 次 getById,无 ticker fire 不应再加 1 次',
      );
    });
  });
}
