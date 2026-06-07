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
    registerFallbackValue(Message(
      clientId: 'fallback',
      conversationId: 'conv-fallback',
      agentId: 'agent-fallback',
      role: MessageRole.user,
      content: 'fallback',
      type: MessageType.text,
      logicalClock: 0,
    ));
    registerFallbackValue(Instance(
      id: 'fallback',
      name: 'fallback',
      gatewayUrl: 'wss://fallback.com:18789',
      tokenRef: 'fallback',
    ));
    registerFallbackValue(Conversation(agentId: 'a', instanceId: 'i'));
    registerFallbackValue(Agent(
      localId: 'l',
      remoteId: 'r',
      instanceId: 'i',
      name: 'fallback',
    ));
    registerFallbackValue(MessageStatus.pending);
    registerFallbackValue(MessageType.text);
    registerFallbackValue(MessageRole.user);
  });

  final testConversation = Conversation(agentId: 'agent-local', instanceId: 'inst-test');
  final testInstance = Instance(
    id: 'inst-test', name: '测试实例',
    gatewayUrl: 'wss://test.example.com:18789', tokenRef: 'ref-1',
    healthStatus: HealthStatus.online,
  );
  final testAgent = Agent(
    localId: 'agent-local', remoteId: 'agent-remote',
    instanceId: 'inst-test', name: '产品虾',
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
    when(() => conversationRepo.getOrCreate('inst-test', 'agent-local'))
        .thenAnswer((_) async => testConversation);
    when(() => conversationRepo.updateLastMessage(
          conversationId: any(named: 'conversationId'),
          messageId: any(named: 'messageId'),
          preview: any(named: 'preview'),
          timestamp: any(named: 'timestamp'),
        )).thenAnswer((_) async => testConversation);
    when(() => messageRepo.insert(any()))
        .thenAnswer((inv) async => inv.positionalArguments[0] as Message);
    when(() => messageRepo.updateStatus(any(), any()))
        .thenAnswer((inv) async => Message(
              clientId: inv.positionalArguments[0] as String,
              conversationId: testConversation.id,
              agentId: 'agent-local',
              role: MessageRole.user,
              content: 'placeholder',
              type: MessageType.text,
              status: inv.positionalArguments[1] as MessageStatus,
              logicalClock: 1,
            ));
    when(() => messageRepo.bindServerId(any(), any()))
        .thenAnswer((inv) async => Message(
              clientId: inv.positionalArguments[0] as String,
              conversationId: testConversation.id,
              agentId: 'agent-local',
              role: MessageRole.user,
              content: 'placeholder',
              type: MessageType.text,
              status: MessageStatus.sent,
              logicalClock: 1,
              serverId: inv.positionalArguments[1] as String,
            ));
  });

  group('SendMessageUseCase', () {
    test('正常发送文本消息', () async {
      when(() => instanceRepo.getById('inst-test'))
          .thenAnswer((_) async => testInstance);
      when(() => gatewayClient.sendMessage(
            instanceId: 'inst-test',
            agentId: 'agent-remote',
            message: any(named: 'message'),
          )).thenAnswer((_) async => (serverId: 'server-ack-1', timestamp: 1717766400000));

      final result = await useCase.execute(
        instanceId: 'inst-test',
        agent: testAgent,
        content: '你好',
        type: MessageType.text,
      );

      expect(result.status, MessageStatus.sent);
      expect(result.role, MessageRole.user);
      verify(() => messageRepo.insert(any())).called(1);
      verify(() => gatewayClient.sendMessage(
            instanceId: 'inst-test',
            agentId: 'agent-remote',
            message: any(named: 'message'),
          )).called(1);
    });

    test('实例离线时应标记消息为 PENDING', () async {
      final offlineInstance = testInstance.copyWith(healthStatus: HealthStatus.offline);
      when(() => instanceRepo.getById('inst-test'))
          .thenAnswer((_) async => offlineInstance);

      final result = await useCase.execute(
        instanceId: 'inst-test',
        agent: testAgent,
        content: '你好',
        type: MessageType.text,
      );

      expect(result.status, MessageStatus.pending);
      verifyNever(() => gatewayClient.sendMessage(
            instanceId: any(named: 'instanceId'),
            agentId: any(named: 'agentId'),
            message: any(named: 'message'),
          ));
    });

    test('Gateway 发送失败时应标记为 FAILED', () async {
      when(() => instanceRepo.getById('inst-test'))
          .thenAnswer((_) async => testInstance);
      when(() => gatewayClient.sendMessage(
            instanceId: 'inst-test',
            agentId: 'agent-remote',
            message: any(named: 'message'),
          )).thenThrow(Exception('Connection failed'));

      final result = await useCase.execute(
        instanceId: 'inst-test',
        agent: testAgent,
        content: '你好',
        type: MessageType.text,
      );

      expect(result.status, MessageStatus.failed);
      verify(() => messageRepo.updateStatus(any(), MessageStatus.failed)).called(1);
    });
  });
}
