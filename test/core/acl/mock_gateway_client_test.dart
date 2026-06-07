import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/domain/models/models.dart';

void main() {
  late MockGatewayClient client;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    client = MockGatewayClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  group('MockGatewayClient', () {
    test('connect 后状态应变为 connected', () async {
      final states = <GatewayConnectionState>[];
      final subscription = client
          .connectionStateStream('inst-test')
          .listen(states.add);

      final instance = Instance(
        id: 'inst-test',
        name: '测试',
        gatewayUrl: 'wss://test.com:18789',
        tokenRef: 'ref',
      );

      await client.connect(instance);

      // 等待异步事件
      await Future.delayed(const Duration(seconds: 1));
      await subscription.cancel();

      expect(states, contains(GatewayConnectionState.connected));
    });

    test('testConnection wss:// 总是返回 true', () async {
      final instance = Instance(
        id: 'inst-test',
        name: '公网',
        gatewayUrl: 'wss://example.com:18789',
        tokenRef: 'ref',
      );

      final result = await client.testConnection(instance);
      expect(result, isTrue);
    });

    test('fetchAgents 返回 mock 数据', () async {
      final agents = await client.fetchAgents('inst-mock-001');

      expect(agents, isNotEmpty);
      expect(agents.length, 3); // 产品虾、代码虾、设计虾
      expect(agents.map((a) => a.name), contains('产品虾'));
      expect(agents.map((a) => a.name), contains('代码虾'));
      expect(agents.map((a) => a.name), contains('设计虾'));
    });

    test('sendMessage 返回 serverId', () async {
      await client.loadMockData();

      final message = Message(
        clientId: 'client-test',
        conversationId: 'conv-test',
        agentId: 'agent-test',
        role: MessageRole.user,
        content: 'Hello',
        type: MessageType.text,
        logicalClock: 1,
      );

      final instance = Instance(
        id: 'inst-mock-001',
        name: '测试',
        gatewayUrl: 'wss://test.com:18789',
        tokenRef: 'ref',
      );
      await client.connect(instance);

      final result = await client.sendMessage(
        instanceId: 'inst-mock-001',
        agentId: 'agent-001',
        message: message,
      );

      expect(result.serverId, isNotEmpty);
      expect(result.timestamp, isNotNull);
    });
  });
}
