// Bug #4 (Finding 4) 修复 (Law 6): ChatViewModel._loadHistory 循环里
// 调用 `_mergeUseCase.merge(fixedMsg)` 而不传 `recent` 参数,每次 merge()
// 内部都会触发 `getByConversation(convId, limit: 50)`,对 N 条历史消息
// 产生 N 次相同查询 —— 标准的 for-await-repo N+1。
//
// 修复:循环外预取一次 recent 列表,传给每条 merge() 调用。
//
// 验证方式:用 CountingMessageRepo 装饰 InMemoryMessageRepo,断言
// `getByConversation` 在 init 阶段恰好被调用 1 次(而非 N 次)。
//
// MessageCatchUpService 路径已经做了同样的优化,所以这个测试专门覆盖
// ChatViewModel 的并行实现。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';

class _MockAgentRepo extends Mock implements IAgentRepo {}

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// CountingMessageRepo —— 包装 InMemoryMessageRepo,统计 getByConversation
/// 调用次数。所有其他方法委托给底层实现。
class CountingMessageRepo extends InMemoryMessageRepo {
  int getByConversationCallCount = 0;

  @override
  Future<List<Message>> getByConversation(
    String conversationId, {
    String? before,
    int limit = 50,
  }) async {
    getByConversationCallCount++;
    return super.getByConversation(
      conversationId,
      before: before,
      limit: limit,
    );
  }
}

/// Fake gateway —— 所有不相关方法返回空/default。
/// 只覆盖 fetchMessageHistory 返回指定历史消息。
class _FakeGateway implements IGatewayClient {
  _FakeGateway(this._history);

  final List<Message> _history;

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) async {
    return (messages: List.of(_history), nextCursor: null);
  }

  @override
  Stream<Message> messageStream(String instanceId) =>
      const Stream<Message>.empty();

  @override
  Stream<ToolCall> toolCallStream(String instanceId) =>
      const Stream<ToolCall>.empty();

  @override
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) =>
      const Stream<StreamingEvent>.empty();

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) =>
      const Stream<GatewayConnectionState>.empty();

  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId) =>
      const Stream<GatewayPairingInfo?>.empty();

  @override
  Stream<LargePayloadNotice> largePayloadNoticeStream(String instanceId) =>
      const Stream<LargePayloadNotice>.empty();

  @override
  void resetConnectionState(String instanceId) {}

  @override
  Future<void> connect(Instance instance) async {}

  @override
  Future<void> disconnect(String instanceId) async {}

  @override
  bool get isConnected => false;

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async => (serverId: 'srv', timestamp: 0);

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async => const [];

  @override
  Future<bool> testConnection(Instance instance) async => true;

  @override
  Future<void> dispose() async {}
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

Message _histMsg(int i) => Message(
  clientId: 'hist-cid-$i',
  serverId: 'hist-srv-$i',
  conversationId: '',
  agentId: _remoteId,
  role: MessageRole.agent,
  content: 'history message $i',
  type: MessageType.text,
  status: MessageStatus.delivered,
  logicalClock: i,
  timestamp: 1718000000000 + i * 1000,
);

/// 用 N=5 跑一次 init,记录 getByConversation 调用次数作为 baseline;
/// 再用 N=30 跑一次,断言调用次数不随消息数增长(Law 6 N+1 反向证明)。
Future<int> _runHistoryInit({required int messageCount}) async {
  final agentRepo = _MockAgentRepo();
  when(
    () => agentRepo.getById(_agentId),
  ).thenAnswer((_) async => _activeAgent());
  when(
    () => agentRepo.syncFromGateway(any(), any()),
  ).thenAnswer((_) async => <Agent>[]);

  final messageRepo = CountingMessageRepo();
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

  final history = List.generate(messageCount, _histMsg);
  final gateway = _FakeGateway(history);
  final sendUseCase = SendMessageUseCase(
    messageRepo: messageRepo,
    conversationRepo: conversationRepo,
    instanceRepo: instanceRepo,
    gatewayClient: gateway,
  );
  final vm = ChatViewModel(
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

  await vm.init();
  await Future<void>.delayed(Duration.zero);
  final calls = messageRepo.getByConversationCallCount;
  vm.dispose();
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ChatViewModel._loadHistory: getByConversation call count is '
      'INDEPENDENT of history length (Law 6 — no N+1)', () async {
    // 基线:5 条历史。
    final calls5 = await _runHistoryInit(messageCount: 5);
    // 验证:30 条历史不应比 5 条触发更多 getByConversation。
    // (修复前:N 条 = N+2 次;修复后:固定 ~3 次,与 N 无关)
    final calls30 = await _runHistoryInit(messageCount: 30);

    expect(
      calls30,
      equals(calls5),
      reason:
          'Bug #4 (Law 6): getByConversation 调用次数应与历史消息数无关。\n'
          '  N=5 时: $calls5 次\n'
          '  N=30 时: $calls30 次\n'
          '两者应相等 —— 若不等,说明每次 merge() 内部仍在触发 getByConversation。',
    );
    // 同时验证绝对值小(不是几十次)。
    expect(
      calls30,
      lessThanOrEqualTo(5),
      reason:
          'getByConversation 绝对调用次数应极少(prefetch + dedupe 内部 + '
          '_loadMessages),不应随 N 增长。实际 $calls30 次。',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));
}
