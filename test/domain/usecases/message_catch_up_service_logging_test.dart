// 验证 MessageCatchUpService 在 catch-up 路径上有结构化诊断日志
// (logStateChange('merge:...'))。
//
// 背景：与 chat_view_model_merge_logging_test.dart 同源 —— 「重启 App 后历史
// 变两份」类 bug 反复复发，catch-up 是断线重连后的 dedup 主入口。本测试为
// 可观测性回归测试,确保 catch-up 路径的 merge 决策也被结构化记录。
//
// 这是 RED 状态:测试期望 MessageCatchUpService 接受 apiLogger 参数(目前
// 尚未接受),编译将失败 —— 等 GREEN 步骤实施后转为 GREEN。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_conversation_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/domain/usecases/message_catch_up_service.dart';

class _MockAgentRepo extends Mock implements IAgentRepo {}

class _MockMessageRepo extends Mock implements IMessageRepo {}

class _MockConversationRepo extends Mock implements IConversationRepo {}

class _MockGatewayClient extends Mock implements IGatewayClient {}

/// RecordingApiLogger — 同步实现 IApiLogger,记录 logStateChange 调用。
class RecordingApiLogger implements IApiLogger {
  final List<({String? state, String message})> states = [];

  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) {}

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) {}

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
    String? payloadPreview,
  }) {
    states.add((state: state, message: message));
  }

  Iterable<({String? state, String message})> get mergeStates =>
      states.where((s) => s.state != null && s.state!.startsWith('merge:'));
}

class _NoopLogger implements ILogger {
  @override
  void info(String message) {}
  @override
  void error(String message, [StackTrace? stackTrace]) {}
}

const _testInstanceId = 'inst-test';
const _testAgentLocalId = 'agent-local';
const _testAgentRemoteId = 'agent-remote';

Agent _testAgent() => Agent(
  localId: _testAgentLocalId,
  remoteId: _testAgentRemoteId,
  instanceId: _testInstanceId,
  name: '产品虾',
);

Message _newMsg({required String serverId, required String clientId}) =>
    Message(
      clientId: clientId,
      serverId: serverId,
      conversationId: '',
      agentId: _testAgentRemoteId,
      role: MessageRole.agent,
      content: 'Hello from $serverId',
      type: MessageType.text,
      status: MessageStatus.delivered,
      logicalClock: 0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

void main() {
  late _MockAgentRepo agentRepo;
  late _MockMessageRepo messageRepo;
  late _MockConversationRepo conversationRepo;
  late _MockGatewayClient gatewayClient;
  late RecordingApiLogger apiLogger;
  late MessageCatchUpService service;

  setUpAll(() {
    registerFallbackValue(
      Message(
        clientId: 'fallback',
        conversationId: 'conv',
        agentId: 'agent',
        role: MessageRole.user,
        type: MessageType.text,
        logicalClock: 0,
      ),
    );
  });

  setUp(() {
    agentRepo = _MockAgentRepo();
    messageRepo = _MockMessageRepo();
    conversationRepo = _MockConversationRepo();
    gatewayClient = _MockGatewayClient();
    apiLogger = RecordingApiLogger();

    service = MessageCatchUpService(
      agentRepo: agentRepo,
      messageRepo: messageRepo,
      conversationRepo: conversationRepo,
      gatewayClient: gatewayClient,
      logger: _NoopLogger(),
      // ⚠️ RED: MessageCatchUpService 当前还没有 `apiLogger` 参数。
      apiLogger: apiLogger,
    );

    // Default: instance has one agent
    when(
      () => agentRepo.getByInstanceId(_testInstanceId),
    ).thenAnswer((_) async => [_testAgent()]);

    // Default: getOrCreate returns a valid conversation
    when(() => conversationRepo.getOrCreate(any(), any())).thenAnswer(
      (_) async => Conversation(
        id: Conversation.generateId(_testInstanceId, _testAgentLocalId),
        agentId: _testAgentLocalId,
        instanceId: _testInstanceId,
      ),
    );

    // Default: fetchMessageHistory returns empty (tests override)
    when(
      () => gatewayClient.fetchMessageHistory(
        instanceId: any(named: 'instanceId'),
        agentId: any(named: 'agentId'),
        cursor: any(named: 'cursor'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => (messages: <Message>[], nextCursor: null));

    // Default: all dedup paths miss → all 走 Branch 4 真新插入
    when(() => messageRepo.getByClientId(any())).thenAnswer((_) async => null);
    when(() => messageRepo.getByServerId(any())).thenAnswer((_) async => null);
    when(
      () => messageRepo.getByConversation(any(), limit: any(named: 'limit')),
    ).thenAnswer((_) async => []);
    when(
      () => messageRepo.insert(any()),
    ).thenAnswer((inv) async => inv.positionalArguments[0] as Message);
    when(
      () => messageRepo.dedupeConversation(any()),
    ).thenAnswer((_) async => 0);
  });

  group('MessageCatchUpService merge logging (US: 重启后历史变两份诊断)', () {
    test(
      'catch-up 全 dedup miss → 每条 logStateChange("merge:inserted:new")',
      () async {
        final msg1 = _newMsg(serverId: 's1', clientId: 'c1');
        final msg2 = _newMsg(serverId: 's2', clientId: 'c2');
        when(
          () => gatewayClient.fetchMessageHistory(
            instanceId: _testInstanceId,
            agentId: _testAgentRemoteId,
            cursor: null,
            limit: 50,
          ),
        ).thenAnswer((_) async => (messages: [msg1, msg2], nextCursor: null));

        final result = await service.catchUp(_testInstanceId);

        expect(result.inserted, 2);
        // 两条消息都走 Branch 4 真新插入 → 应有 2 条 merge:inserted:new。
        // 这是「重启后历史变两份」时 catch-up 路径上应该看到的 pattern。
        expect(
          apiLogger.mergeStates.length,
          equals(2),
          reason: '应有 2 条 merge log',
        );
        expect(
          apiLogger.mergeStates.every((s) => s.state == 'merge:inserted:new'),
          isTrue,
          reason:
              '全 miss 应记为 merge:inserted:new,实际: '
              '${apiLogger.mergeStates.map((s) => s.state).toList()}',
        );
        // message 应标注 path=catchUp(便于与 ChatViewModel 历史 pull 区分)
        expect(
          apiLogger.mergeStates.first.message.contains('path=catchUp'),
          isTrue,
          reason: 'message 应标注 path,便于诊断区分 catch-up vs 历史 pull',
        );
      },
    );

    test(
      'dedupeConversation 返回 >0 → logStateChange("merge:dedupeDeleted")',
      () async {
        final msg = _newMsg(serverId: 's1', clientId: 'c1');
        when(
          () => gatewayClient.fetchMessageHistory(
            instanceId: _testInstanceId,
            agentId: _testAgentRemoteId,
            cursor: null,
            limit: 50,
          ),
        ).thenAnswer((_) async => (messages: [msg], nextCursor: null));
        // 让 catch-up 结尾的 dedupeConversation 返回 2(模拟清理 2 条历史重复)
        when(
          () => messageRepo.dedupeConversation(any()),
        ).thenAnswer((_) async => 2);

        await service.catchUp(_testInstanceId);

        // 应有 1 条 merge:inserted:new(消息本身) + 1 条 merge:dedupeDeleted
        expect(apiLogger.mergeStates.length, equals(2));
        expect(
          apiLogger.mergeStates.any((s) => s.state == 'merge:dedupeDeleted'),
          isTrue,
          reason:
              'dedupeConversation 删除 N 行时应有 logStateChange,实际 states: '
              '${apiLogger.mergeStates.map((s) => s.state).toList()}',
        );
        // dedupeDeleted 的 message 应包含 count
        final dedupeLog = apiLogger.mergeStates.firstWhere(
          (s) => s.state == 'merge:dedupeDeleted',
        );
        expect(dedupeLog.message.contains('count=2'), isTrue);
      },
    );

    test('apiLogger 为 null 时 catchUp 不抛异常(兼容现有测试构造点)', () async {
      // 关键:不传 apiLogger(=null),验证新参数是 nullable,
      // 现有 catch-up 测试构造点不需要改。
      final serviceNoLogger = MessageCatchUpService(
        agentRepo: agentRepo,
        messageRepo: messageRepo,
        conversationRepo: conversationRepo,
        gatewayClient: gatewayClient,
        logger: _NoopLogger(),
      );

      // 不抛即过
      final result = await serviceNoLogger.catchUp(_testInstanceId);
      expect(result.inserted, 0);
    });
  });
}
