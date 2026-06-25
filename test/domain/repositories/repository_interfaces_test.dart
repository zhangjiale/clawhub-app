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

      // US-021 N+1 修复：批量取实例，契约对齐 IAgentRepo.getByIds ——
      // 未找到的 ID 不出现在结果 Map，空列表返回空 Map（不查 DB）。
      test('getByIds 批量返回实例 Map，缺失 ID 不出现', () async {
        final i1 = Instance(
          id: 'inst-1',
          name: 'A',
          gatewayUrl: 'wss://a.test:18789',
          tokenRef: 'r',
        );
        final i2 = Instance(
          id: 'inst-2',
          name: 'B',
          gatewayUrl: 'wss://b.test:18789',
          tokenRef: 'r',
        );
        when(
          () => instanceRepo.getByIds(['inst-1', 'inst-2', 'ghost']),
        ).thenAnswer((_) async => {'inst-1': i1, 'inst-2': i2});

        final result = await instanceRepo.getByIds([
          'inst-1',
          'inst-2',
          'ghost',
        ]);
        expect(result, hasLength(2));
        expect(result.keys, containsAll(['inst-1', 'inst-2']));
        expect(result.containsKey('ghost'), isFalse, reason: '缺失的 ID 不应出现在结果中');
      });

      test('getByIds 空列表返回空 Map（不查 DB）', () async {
        when(() => instanceRepo.getByIds([])).thenAnswer((_) async => {});

        final result = await instanceRepo.getByIds([]);
        expect(result, isEmpty);
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

      // US-021: SaveInstanceUseCase 的 host 切换警告需要统计 tombstoned agent，
      // 因此接口暴露不过滤版本，与默认过滤的 getByInstanceId 并存。
      test('getAllByInstanceId 返回实例下所有 agent（含 tombstoned/hidden）', () async {
        final a1 = Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-001',
          name: 'A',
          removedAt: 1719200000000,
        );
        when(
          () => agentRepo.getAllByInstanceId('inst-001'),
        ).thenAnswer((_) async => [a1]);

        final result = await agentRepo.getAllByInstanceId('inst-001');
        expect(result.length, 1);
        expect(result.first.isRemoved, isTrue);
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

      test('updateStatuses 批量更新状态（OutboxProcessor Law 6 入口）', () async {
        final updated = [
          Message(
            clientId: 'm1',
            conversationId: 'c1',
            agentId: 'a1',
            role: MessageRole.user,
            type: MessageType.text,
            status: MessageStatus.expired,
            logicalClock: 1,
          ),
        ];
        when(
          () => messageRepo.updateStatuses(['m1', 'm2'], MessageStatus.expired),
        ).thenAnswer((_) async => updated);

        final result = await messageRepo.updateStatuses([
          'm1',
          'm2',
        ], MessageStatus.expired);
        expect(result, same(updated));
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
