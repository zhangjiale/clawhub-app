import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';

class MockMessageRepo extends Mock implements IMessageRepo {}

class MockConversationRepo extends Mock implements IConversationRepo {}

class MockInstanceRepo extends Mock implements IInstanceRepo {}

class MockGatewayClient extends Mock implements IGatewayClient {}

void main() {
  late SendMessageUseCase useCase;
  late MockMessageRepo messageRepo;
  late MockConversationRepo conversationRepo;
  late MockInstanceRepo instanceRepo;
  late MockGatewayClient gatewayClient;

  setUpAll(() {
    registerFallbackValue(
      Message(
        clientId: 'fallback',
        conversationId: 'conv-fallback',
        agentId: 'agent-fallback',
        role: MessageRole.user,
        content: 'fallback',
        type: MessageType.text,
        logicalClock: 0,
      ),
    );
    registerFallbackValue(
      Instance(
        id: 'fallback',
        name: 'fallback',
        gatewayUrl: 'wss://fallback.com:18789',
        tokenRef: 'fallback',
      ),
    );
    registerFallbackValue(Conversation(agentId: 'a', instanceId: 'i'));
    registerFallbackValue(
      Agent(localId: 'l', remoteId: 'r', instanceId: 'i', name: 'fallback'),
    );
    registerFallbackValue(MessageStatus.pending);
    registerFallbackValue(MessageType.text);
    registerFallbackValue(MessageRole.user);
  });

  final testConversation = Conversation(
    agentId: 'agent-local',
    instanceId: 'inst-test',
  );
  final testInstance = Instance(
    id: 'inst-test',
    name: '测试实例',
    gatewayUrl: 'wss://test.example.com:18789',
    tokenRef: 'ref-1',
    healthStatus: HealthStatus.online,
  );
  final testAgent = Agent(
    localId: 'agent-local',
    remoteId: 'agent-remote',
    instanceId: 'inst-test',
    name: '产品虾',
  );

  setUp(() {
    messageRepo = MockMessageRepo();
    conversationRepo = MockConversationRepo();
    instanceRepo = MockInstanceRepo();
    gatewayClient = MockGatewayClient();
    useCase = SendMessageUseCase(
      messageRepo: messageRepo,
      conversationRepo: conversationRepo,
      instanceRepo: instanceRepo,
      gatewayClient: gatewayClient,
    );

    // Default stubs for all tests
    when(
      () => conversationRepo.getOrCreate('inst-test', 'agent-local'),
    ).thenAnswer((_) async => testConversation);
    when(
      () => conversationRepo.updateLastMessage(
        conversationId: any(named: 'conversationId'),
        messageId: any(named: 'messageId'),
        preview: any(named: 'preview'),
        timestamp: any(named: 'timestamp'),
        role: any(named: 'role'),
      ),
    ).thenAnswer((_) async => testConversation);
    when(
      () => messageRepo.insert(any()),
    ).thenAnswer((inv) async => inv.positionalArguments[0] as Message);
    // CAS 进入 SENDING 默认成功（execute / retry 共用闸口）。
    when(
      () => messageRepo.tryTransitionToSending(any(), any()),
    ).thenAnswer((_) async => true);
    when(() => messageRepo.getByClientId(any())).thenAnswer(
      (inv) async => Message(
        clientId: inv.positionalArguments[0] as String,
        conversationId: testConversation.id,
        agentId: 'agent-local',
        role: MessageRole.user,
        content: 'placeholder',
        type: MessageType.text,
        status: MessageStatus.sending,
        logicalClock: 1,
      ),
    );
    when(() => messageRepo.updateStatus(any(), any())).thenAnswer(
      (inv) async => Message(
        clientId: inv.positionalArguments[0] as String,
        conversationId: testConversation.id,
        agentId: 'agent-local',
        role: MessageRole.user,
        content: 'placeholder',
        type: MessageType.text,
        status: inv.positionalArguments[1] as MessageStatus,
        logicalClock: 1,
      ),
    );
    when(() => messageRepo.bindServerId(any(), any())).thenAnswer(
      (inv) async => Message(
        clientId: inv.positionalArguments[0] as String,
        conversationId: testConversation.id,
        agentId: 'agent-local',
        role: MessageRole.user,
        content: 'placeholder',
        type: MessageType.text,
        status: MessageStatus.sent,
        logicalClock: 1,
        serverId: inv.positionalArguments[1] as String,
      ),
    );
  });

  group('SendMessageUseCase', () {
    test('正常发送文本消息', () async {
      when(
        () => instanceRepo.getById('inst-test'),
      ).thenAnswer((_) async => testInstance);
      when(
        () => gatewayClient.sendMessage(
          instanceId: 'inst-test',
          agentId: 'agent-remote',
          message: any(named: 'message'),
        ),
      ).thenAnswer(
        (_) async => (serverId: 'server-ack-1', timestamp: 1717766400000),
      );

      final result = await useCase.execute(
        instanceId: 'inst-test',
        agent: testAgent,
        content: '你好',
        type: MessageType.text,
      );

      expect(result.status, MessageStatus.sent);
      expect(result.role, MessageRole.user);
      verify(() => messageRepo.insert(any())).called(1);
      verify(
        () => gatewayClient.sendMessage(
          instanceId: 'inst-test',
          agentId: 'agent-remote',
          message: any(named: 'message'),
        ),
      ).called(1);
    });

    test('实例离线时应标记消息为 PENDING', () async {
      final offlineInstance = testInstance.copyWith(
        healthStatus: HealthStatus.offline,
      );
      when(
        () => instanceRepo.getById('inst-test'),
      ).thenAnswer((_) async => offlineInstance);

      final result = await useCase.execute(
        instanceId: 'inst-test',
        agent: testAgent,
        content: '你好',
        type: MessageType.text,
      );

      expect(result.status, MessageStatus.pending);
      verifyNever(
        () => gatewayClient.sendMessage(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          message: any(named: 'message'),
        ),
      );
    });

    test('Gateway 发送失败时应标记为 FAILED', () async {
      when(
        () => instanceRepo.getById('inst-test'),
      ).thenAnswer((_) async => testInstance);
      when(
        () => gatewayClient.sendMessage(
          instanceId: 'inst-test',
          agentId: 'agent-remote',
          message: any(named: 'message'),
        ),
      ).thenThrow(Exception('Connection failed'));

      final result = await useCase.execute(
        instanceId: 'inst-test',
        agent: testAgent,
        content: '你好',
        type: MessageType.text,
      );

      expect(result.status, MessageStatus.failed);
      verify(
        () => messageRepo.updateStatus(any(), MessageStatus.failed),
      ).called(1);
    });

    test('CAS 失败（消息已被并发路径接管）时不重复发送', () async {
      // 场景：execute 插入 PENDING 后，在到达发送步骤前 OutboxProcessor
      // 已 CAS PENDING→SENDING 并发送到 SENT。execute 的 CAS 必须失败并
      // 直接返回当前实体，不得再次发送（避免重复发送 + FSM 冲突）。
      when(
        () => instanceRepo.getById('inst-test'),
      ).thenAnswer((_) async => testInstance);
      when(
        () => messageRepo.tryTransitionToSending(any(), MessageStatus.pending),
      ).thenAnswer((_) async => false);
      final alreadySent = Message(
        clientId: 'taken-over',
        conversationId: testConversation.id,
        agentId: 'agent-local',
        role: MessageRole.user,
        content: '你好',
        type: MessageType.text,
        status: MessageStatus.sent,
        logicalClock: 1,
        serverId: 'server-ack-x',
      );
      when(
        () => messageRepo.getByClientId(any()),
      ).thenAnswer((_) async => alreadySent);

      final result = await useCase.execute(
        instanceId: 'inst-test',
        agent: testAgent,
        content: '你好',
        type: MessageType.text,
      );

      expect(result.status, MessageStatus.sent, reason: '应返回并发路径推进后的当前状态');
      expect(result.serverId, 'server-ack-x');
      // 关键：没有重复发送，也没有再 updateStatus(sending) 触发 FSM 冲突
      verifyNever(
        () => gatewayClient.sendMessage(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          message: any(named: 'message'),
        ),
      );
      verifyNever(() => messageRepo.updateStatus(any(), MessageStatus.sending));
      verifyNever(() => messageRepo.updateStatus(any(), MessageStatus.failed));
    });
  });

  group('retry', () {
    test('发送失败时由 retry 统一标记 FAILED，sentNow=false', () async {
      when(
        () => instanceRepo.getById('inst-test'),
      ).thenAnswer((_) async => testInstance);
      when(
        () => messageRepo.tryTransitionToSending(any(), any()),
      ).thenAnswer((_) async => true);
      when(() => messageRepo.getByClientId(any())).thenAnswer(
        (inv) async => Message(
          clientId: inv.positionalArguments[0] as String,
          conversationId: testConversation.id,
          agentId: 'agent-local',
          role: MessageRole.user,
          content: 'x',
          type: MessageType.text,
          status: MessageStatus.sending,
          logicalClock: 1,
        ),
      );
      when(
        () => gatewayClient.sendMessage(
          instanceId: 'inst-test',
          agentId: 'agent-remote',
          message: any(named: 'message'),
        ),
      ).thenThrow(Exception('network down'));
      when(
        () => messageRepo.updateStatus(any(), MessageStatus.failed),
      ).thenAnswer(
        (inv) async => Message(
          clientId: inv.positionalArguments[0] as String,
          conversationId: testConversation.id,
          agentId: 'agent-local',
          role: MessageRole.user,
          content: 'x',
          type: MessageType.text,
          status: MessageStatus.failed,
          logicalClock: 1,
        ),
      );

      final result = await useCase.retry(
        clientId: 'm1',
        instanceId: 'inst-test',
        agentRemoteId: 'agent-remote',
        expectedStatus: MessageStatus.pending,
      );

      expect(result.sentNow, false);
      expect(result.message.status, MessageStatus.failed);
      // retry 是 FAILED 唯一权威 —— 恰好一次
      verify(
        () => messageRepo.updateStatus('m1', MessageStatus.failed),
      ).called(1);
    });

    test('超时后由 retry 统一标记 FAILED（不依赖调用方兜底）', () async {
      // gateway 永不完成 → retry 内部 .timeout 触发 → catch 标记 FAILED。
      // 关键断言：FAILED 由 retry 自己写入，调用方无需二次兜底。
      final completer = Completer<({String serverId, int timestamp})>();
      when(
        () => instanceRepo.getById('inst-test'),
      ).thenAnswer((_) async => testInstance);
      when(
        () => messageRepo.tryTransitionToSending(any(), any()),
      ).thenAnswer((_) async => true);
      when(() => messageRepo.getByClientId(any())).thenAnswer(
        (inv) async => Message(
          clientId: inv.positionalArguments[0] as String,
          conversationId: testConversation.id,
          agentId: 'agent-local',
          role: MessageRole.user,
          content: 'x',
          type: MessageType.text,
          status: MessageStatus.sending,
          logicalClock: 1,
        ),
      );
      when(
        () => gatewayClient.sendMessage(
          instanceId: 'inst-test',
          agentId: 'agent-remote',
          message: any(named: 'message'),
        ),
      ).thenAnswer((_) => completer.future);
      when(
        () => messageRepo.updateStatus(any(), MessageStatus.failed),
      ).thenAnswer(
        (inv) async => Message(
          clientId: inv.positionalArguments[0] as String,
          conversationId: testConversation.id,
          agentId: 'agent-local',
          role: MessageRole.user,
          content: 'x',
          type: MessageType.text,
          status: MessageStatus.failed,
          logicalClock: 1,
        ),
      );

      final result = await useCase.retry(
        clientId: 'm1',
        instanceId: 'inst-test',
        agentRemoteId: 'agent-remote',
        expectedStatus: MessageStatus.pending,
        timeout: const Duration(milliseconds: 50),
      );

      expect(result.sentNow, false, reason: '超时应导致 sentNow=false');
      expect(result.message.status, MessageStatus.failed);
      // retry 自己标记 FAILED —— 调用方无需兜底
      verify(
        () => messageRepo.updateStatus('m1', MessageStatus.failed),
      ).called(1);
      // gateway 调用确实发生了（只是没在超时内完成）
      verify(
        () => gatewayClient.sendMessage(
          instanceId: 'inst-test',
          agentId: 'agent-remote',
          message: any(named: 'message'),
        ),
      ).called(1);
    });

    test('CAS 失败时返回当前状态且不发送', () async {
      when(
        () => messageRepo.tryTransitionToSending('m1', MessageStatus.failed),
      ).thenAnswer((_) async => false);
      when(() => messageRepo.getByClientId('m1')).thenAnswer(
        (_) async => Message(
          clientId: 'm1',
          conversationId: testConversation.id,
          agentId: 'agent-local',
          role: MessageRole.user,
          content: 'x',
          type: MessageType.text,
          status: MessageStatus.sent,
          logicalClock: 1,
          serverId: 's-1',
        ),
      );

      final result = await useCase.retry(
        clientId: 'm1',
        instanceId: 'inst-test',
        agentRemoteId: 'agent-remote',
        expectedStatus: MessageStatus.failed,
      );

      expect(result.sentNow, false);
      expect(
        result.message.status,
        MessageStatus.sent,
        reason: '应返回并发路径推进后的当前状态',
      );
      verifyNever(
        () => gatewayClient.sendMessage(
          instanceId: any(named: 'instanceId'),
          agentId: any(named: 'agentId'),
          message: any(named: 'message'),
        ),
      );
      verifyNever(() => messageRepo.updateStatus(any(), any()));
    });
  });
}
