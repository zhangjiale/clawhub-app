import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';

// Mock implementations for testing
class MockInstanceRepo extends Mock implements IInstanceRepo {}

class MockAgentRepo extends Mock implements IAgentRepo {}

class MockMessageRepo extends Mock implements IMessageRepo {}

class MockConversationRepo extends Mock implements IConversationRepo {}

class MockGatewayClient extends Mock implements IGatewayClient {}

void main() {
  group('Repository Interfaces - 契约验证', () {
    late MockInstanceRepo instanceRepo;
    late MockAgentRepo agentRepo;
    late MockMessageRepo messageRepo;
    late MockConversationRepo conversationRepo;
    late MockGatewayClient gatewayClient;

    setUp(() {
      instanceRepo = MockInstanceRepo();
      agentRepo = MockAgentRepo();
      messageRepo = MockMessageRepo();
      conversationRepo = MockConversationRepo();
      gatewayClient = MockGatewayClient();
    });

    group('IInstanceRepo', () {
      test('getAll 返回实例列表', () async {
        when(() => instanceRepo.getAll()).thenAnswer((_) async => []);

        final result = await instanceRepo.getAll();
        expect(result, isEmpty);

        verify(() => instanceRepo.getAll()).called(1);
      });

      test('nameExists 检查重复', () async {
        when(
          () =>
              instanceRepo.nameExists('测试', excludeId: any(named: 'excludeId')),
        ).thenAnswer((_) async => false);

        final exists = await instanceRepo.nameExists('测试');
        expect(exists, isFalse);
      });

      test('updateHealthStatus 返回更新后的实例', () async {
        final instance = Instance(
          id: 'inst-001',
          name: '测试',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'ref-1',
        );
        when(
          () =>
              instanceRepo.updateHealthStatus('inst-001', HealthStatus.online),
        ).thenAnswer(
          (_) async => instance.copyWith(healthStatus: HealthStatus.online),
        );

        final updated = await instanceRepo.updateHealthStatus(
          'inst-001',
          HealthStatus.online,
        );
        expect(updated.healthStatus, HealthStatus.online);
      });
    });

    group('IAgentRepo', () {
      test('findByCompositeKey 使用复合键查找', () async {
        when(
          () => agentRepo.findByCompositeKey('inst-001', 'remote-1'),
        ).thenAnswer((_) async => null);

        final result = await agentRepo.findByCompositeKey(
          'inst-001',
          'remote-1',
        );
        expect(result, isNull);
      });
    });

    group('IMessageRepo', () {
      test('getOutbox 返回待发送消息', () async {
        when(
          () => messageRepo.getOutbox('agent-1'),
        ).thenAnswer((_) async => []);

        final outbox = await messageRepo.getOutbox('agent-1');
        expect(outbox, isEmpty);
      });

      test('search 执行全文搜索', () async {
        when(
          () => messageRepo.search('部署', limit: 20, offset: 0),
        ).thenAnswer((_) async => []);

        final results = await messageRepo.search('部署');
        expect(results, isEmpty);
      });
    });

    group('IConversationRepo', () {
      test('getOrCreate 幂等操作', () async {
        final conv = Conversation(agentId: 'a1', instanceId: 'i1');
        when(
          () => conversationRepo.getOrCreate('i1', 'a1'),
        ).thenAnswer((_) async => conv);

        final result1 = await conversationRepo.getOrCreate('i1', 'a1');
        final result2 = await conversationRepo.getOrCreate('i1', 'a1');
        expect(result1.id, result2.id); // 幂等
      });
    });

    group('IGatewayClient', () {
      test('连接状态流正常工作', () async {
        when(
          () => gatewayClient.connectionStateStream('inst-001'),
        ).thenAnswer((_) => Stream.value(GatewayConnectionState.disconnected));

        final stream = gatewayClient.connectionStateStream('inst-001');
        final state = await stream.first;
        expect(state, GatewayConnectionState.disconnected);
      });
    });
  });
}
