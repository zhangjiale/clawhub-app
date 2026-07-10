// 验证 ChatViewModel 在 merge / dedupeConversation 路径上有结构化诊断日志
// (logStateChange('merge:...'))。
//
// 背景：「重启 App 后历史消息变两份」类 bug 反复复发，根因是 dedup 路径完全
// 黑盒 —— AI 修复时看不到真实数据下哪一层 miss。本测试为可观测性回归测试,
// 验证 merge 决策确实被结构化记录,以便 DiagnosticsPage 能直接看到决策分支。
//
// 这是 RED 状态:测试期望 ChatViewModel 接受 apiLogger 参数(目前尚未接受),
// 编译将失败 —— 等 GREEN 步骤实施后转为 GREEN。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/core/i_api_logger.dart';
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

/// RecordingApiLogger — 同步实现 IApiLogger,记录 logStateChange 调用。
/// 与 connection_manager_logging_test.dart 同模式。
class RecordingApiLogger implements IApiLogger {
  final List<({String? state, String message})> states = [];
  final List<({String? state, String message, String? payloadPreview})>
  stateCalls = [];
  final List<String> logRequestCalls = [];
  final List<String> logResponseCalls = [];

  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) {
    logRequestCalls.add('$method:$requestId');
  }

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) {
    logResponseCalls.add('$requestId:$ok');
  }

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
    String? payloadPreview,
  }) {
    states.add((state: state, message: message));
    stateCalls.add((
      state: state,
      message: message,
      payloadPreview: payloadPreview,
    ));
  }

  /// 过滤出 merge decision 条目(state 以 'merge:' 开头)。
  Iterable<({String? state, String message})> get mergeStates =>
      states.where((s) => s.state != null && s.state!.startsWith('merge:'));
  Iterable<({String? state, String message, String? payloadPreview})>
  get mergeStateCalls =>
      stateCalls.where((s) => s.state != null && s.state!.startsWith('merge:'));
}

/// Fake gateway — fetchMessageHistory 返回固定列表,其余 stream 返回 empty。
/// 与 chat_view_model_history_no_n_plus_1_test.dart 同模式。
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
  Stream<GatewayNotice> gatewayNoticeStream(String instanceId) =>
      const Stream<GatewayNotice>.empty();

  @override
  void resetConnectionState(String instanceId) {}

  @override
  Future<void> connect(Instance instance) async {}

  @override
  Future<void> disconnect(String instanceId) async {}

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async => (serverId: 'srv-fake', timestamp: 0);

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

Message _histMsg(
  int i, {
  String? clientId,
  String? serverId,
  String? content,
  MessageRole role = MessageRole.agent,
}) => Message(
  clientId: clientId ?? 'hist-cid-$i',
  serverId: serverId ?? 'hist-srv-$i',
  conversationId: '',
  agentId: _remoteId,
  role: role,
  content: content ?? 'history message $i',
  type: MessageType.text,
  status: MessageStatus.delivered,
  logicalClock: i,
  timestamp: 1718000000000 + i * 1000,
);

/// 用 mock 仓库 + RecordingApiLogger 构造 ChatViewModel 并跑完 init。
///
/// [apiLogger] 可为 null —— 现有 ~15 个测试不传 apiLogger,这个 helper 让
/// "兼容 null" 测试能复用同一构造逻辑。
Future<ChatViewModel> _buildAndInit({
  required List<Message> history,
  InMemoryMessageRepo? messageRepoOverride,
  IApiLogger? apiLogger,
}) async {
  final agentRepo = _MockAgentRepo();
  when(
    () => agentRepo.getById(_agentId),
  ).thenAnswer((_) async => _activeAgent());
  when(
    () => agentRepo.syncFromGateway(any(), any()),
  ).thenAnswer((_) async => <Agent>[]);

  final messageRepo = messageRepoOverride ?? InMemoryMessageRepo();
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
    // ⚠️ 这就是 RED: ChatViewModel 当前还没有 `apiLogger` 参数。
    apiLogger: apiLogger,
    flushDelay: Duration.zero,
  );

  await vm.init();
  await Future<void>.delayed(Duration.zero);
  return vm;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatViewModel merge logging (US: 重启后历史变两份诊断)', () {
    test(
      '历史 pull 路径:全 dedup miss → 每条 logStateChange("merge:inserted:new")',
      () async {
        final logger = RecordingApiLogger();
        final history = List.generate(3, (i) => _histMsg(i));

        final vm = await _buildAndInit(history: history, apiLogger: logger);

        // 3 条历史在空 DB 里,identity miss + 软匹配 miss → 全部 inserted:new。
        // 这是「重启后历史变两份」场景下应该看到的 pattern:大量 inserted:new
        // 表示 Branch 4 命中,问题在前 3 层去重全 miss。
        expect(
          logger.mergeStates.length,
          equals(3),
          reason: '应有一条 merge log per 入站消息',
        );
        expect(
          logger.mergeStates.every((s) => s.state == 'merge:inserted:new'),
          isTrue,
          reason:
              '所有 dedup miss 应记为 merge:inserted:new,实际: '
              '${logger.mergeStates.map((s) => s.state).toList()}',
        );
        // message 应包含 path + clientId 等上下文(诊断关键)
        expect(
          logger.mergeStates.first.message.contains('path=history'),
          isTrue,
          reason: 'message 应标注 path,便于区分实时流 vs 历史 pull',
        );

        vm.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      '历史 pull 路径:clientId 命中 → logStateChange("merge:hit:dedup")',
      () async {
        final logger = RecordingApiLogger();

        // 预存一条同 clientId 的消息 —— 模拟"重启前已有 user/agent 消息"
        final messageRepo = InMemoryMessageRepo();
        final preExisting = _histMsg(0, clientId: 'shared-cid');
        await messageRepo.insert(preExisting);

        // history 里也有一条同 clientId(但 serverId 不同)的消息 —— 模拟
        // Gateway 回传,身份(clientId)命中走 Branch 1。
        final history = [
          _histMsg(0, clientId: 'shared-cid', serverId: 'srv-A'),
        ];

        final vm = await _buildAndInit(
          history: history,
          messageRepoOverride: messageRepo,
          apiLogger: logger,
        );

        // 应命中 hit:dedup —— 这是「重启后历史不变两份」场景下应该看到的 pattern。
        expect(logger.mergeStates.length, equals(1));
        expect(
          logger.mergeStates.first.state,
          equals('merge:hit:dedup'),
          reason: 'clientId 命中应记为 merge:hit:dedup',
        );

        vm.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'apiLogger 为 null 时 init 不抛异常(兼容现有 ~15 个测试构造点)',
      () async {
        final history = [_histMsg(0)];

        // 关键:不传 apiLogger(=null)。这验证新参数是 nullable,
        // 现有 ~15 个 ChatViewModel 测试构造点不需要改。
        final vm = await _buildAndInit(history: history);

        // 不抛即过
        vm.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'merge log 携带 payloadPreview (=message.content),diagnostics 可点 ▼ 展开',
      () async {
        // 「重启后多出 agent 消息」bug 的核心诊断可见性:用户点 ▼ 能看到
        // 入站消息的 content,判断「extra」到底是 toolResult 还是 agent text。
        final logger = RecordingApiLogger();
        final history = [
          _histMsg(0, content: 'hello-from-history-A'),
          _histMsg(1, content: 'hello-from-history-B'),
        ];

        final vm = await _buildAndInit(history: history, apiLogger: logger);

        final mergeLogs = logger.mergeStateCalls.toList();
        expect(mergeLogs.length, equals(2));
        // 每条 merge log 都应带 content(让 diagnostics ▼ 按钮能展开)
        expect(mergeLogs[0].payloadPreview, equals('hello-from-history-A'));
        expect(mergeLogs[1].payloadPreview, equals('hello-from-history-B'));

        vm.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
