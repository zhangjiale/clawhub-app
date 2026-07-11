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

    test('晚订阅者在连接建立后应立即收到最后已知状态（与 WsGatewayClient 对齐）', () async {
      final instance = Instance(
        id: 'inst-late',
        name: '测试',
        gatewayUrl: 'wss://test.com:18789',
        tokenRef: 'ref',
      );

      // 1. 先连接，等连接完全建立
      await client.connect(instance);
      await Future.delayed(const Duration(seconds: 1));

      // 2. 连接已建立后再订阅 —— 模拟聊天页晚打开
      final states = <GatewayConnectionState>[];
      final subscription = client
          .connectionStateStream('inst-late')
          .listen(states.add);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        states,
        contains(GatewayConnectionState.connected),
        reason:
            'Mock 必须与 WsGatewayClient 行为一致：晚订阅者应立即收到最后已知 '
            '状态，否则离线开发模式下会复现"连接已断开"误报。',
      );

      await subscription.cancel();
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

    test(
      'fetchSingleMessage returns canned full content for a known id',
      () async {
        await client.loadMockData();
        final msg = await client.fetchSingleMessage(
          instanceId: 'inst-mock-001',
          agentId: 'agent-001',
          messageId: 'msg-mock-1',
        );
        expect(msg, isNotNull);
        expect(msg!.serverId, 'msg-mock-1');
        expect(msg.content, isNotEmpty);
      },
    );

    test('fetchSingleMessage returns null for unknown sentinel id', () async {
      await client.loadMockData();
      final msg = await client.fetchSingleMessage(
        instanceId: 'inst-mock-001',
        agentId: 'agent-001',
        messageId: '__not_found__',
      );
      expect(msg, isNull);
    });
  });

  group('gatewayNoticeStream (Gap #6 — sealed union diagnostic stream)', () {
    test('emits LargePayloadNotice typed as GatewayNotice', () async {
      final emitted = <GatewayNotice>[];
      final sub = client.gatewayNoticeStream('inst-notice').listen(emitted.add);

      final notice = LargePayloadNotice(
        sessionKey: 'agent:r-1:main',
        size: 30_000_000,
        limit: 26_214_400,
      );
      client.emitGatewayNoticeForTesting('inst-notice', notice);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // Value == (added in Step 1) makes this an equality check, not identity.
      expect(emitted, [notice]);
      expect(emitted.single, isA<LargePayloadNotice>());
      expect(emitted.single, isA<GatewayNotice>());
    });
  });
}
