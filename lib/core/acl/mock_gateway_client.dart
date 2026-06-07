import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';
import 'i_gateway_client.dart';
import '../../domain/models/models.dart';

/// Mock Gateway 客户端
/// 对齐: 架构 vFinal 7.1 (Mock 服务架构)
///
/// 从 assets/mock/agents.json 读取预设数据，模拟 Gateway 行为。
/// 支持在开发阶段无需真实 OpenClaw 实例即可开发和测试全功能。
class MockGatewayClient implements IGatewayClient {
  final Uuid _uuid = const Uuid();
  final Random _random = Random();
  final Map<String, StreamController<GatewayConnectionState>>
  _connectionControllers = {};
  final Map<String, StreamController<Message>> _messageControllers = {};
  final Map<String, StreamController<ToolCall>> _toolCallControllers = {};

  List<Map<String, dynamic>> _mockAgents = [];
  List<Map<String, dynamic>> _mockInstances = [];
  bool _loaded = false;

  /// 加载 mock 数据
  Future<void> loadMockData() async {
    if (_loaded) return;
    final jsonStr = await rootBundle.loadString('assets/mock/agents.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    _mockInstances = List<Map<String, dynamic>>.from(data['instances'] ?? []);
    _mockAgents = List<Map<String, dynamic>>.from(data['agents'] ?? []);
    _loaded = true;
  }

  @override
  Future<void> connect(Instance instance) async {
    await loadMockData();
    _getOrCreateConnectionController(
      instance.id,
    ).add(GatewayConnectionState.connecting);
    await Future.delayed(const Duration(milliseconds: 500));
    _getOrCreateConnectionController(
      instance.id,
    ).add(GatewayConnectionState.connected);
  }

  @override
  Future<void> disconnect(String instanceId) async {
    _getOrCreateConnectionController(
      instanceId,
    ).add(GatewayConnectionState.disconnected);
  }

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async {
    // 模拟网络延迟
    await Future.delayed(Duration(milliseconds: 300 + _random.nextInt(500)));

    final serverId = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // 模拟 Agent 回复（异步发送到 messageStream）
    _simulateAgentReply(instanceId, agentId, message);

    return (serverId: serverId, timestamp: timestamp);
  }

  void _simulateAgentReply(
    String instanceId,
    String agentId,
    Message userMessage,
  ) {
    final controller = _messageControllers[instanceId];
    if (controller == null || !controller.hasListener) return;

    Future.delayed(Duration(milliseconds: 800 + _random.nextInt(1200)), () {
      if (controller.isClosed) return; // 防止 dispose 后执行
      final agentMsg = Message(
        clientId: _uuid.v4(),
        serverId: _uuid.v4(),
        conversationId: userMessage.conversationId,
        agentId: agentId,
        role: MessageRole.agent,
        content: _generateMockReply(userMessage.content ?? ''),
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: DateTime.now().millisecondsSinceEpoch,
      );
      controller.add(agentMsg);

      // 10% 概率模拟工具调用
      if (_random.nextDouble() < 0.1) {
        _simulateToolCall(instanceId, agentMsg.clientId);
      }
    });
  }

  String _generateMockReply(String userContent) {
    final replies = [
      '好的，我理解你的需求了。让我帮你分析一下...\n\n这个问题可以从以下几个角度来看：\n\n1. **技术可行性**：完全可行\n2. **实现难度**：中等\n3. **建议方案**：分阶段实施\n\n需要我详细展开哪个方面？',
      '收到！这是个好问题。\n\n```dart\n// 示例代码\nvoid main() {\n  print("Hello, ClawHub!");\n}\n```\n\n以上是参考实现，需要我调整吗？',
      '明白了。根据你的描述，我建议：\n\n- 先做 A/B 测试验证假设\n- 收集用户反馈后再迭代\n- 注意边界情况处理\n\n还有其他问题吗？',
      '让我想想... 🤔\n\n分析结果如下：\n\n| 维度 | 评分 | 说明 |\n|------|------|------|\n| 优先级 | ⭐⭐⭐⭐ | 核心需求 |\n| 工作量 | ⭐⭐⭐ | 中等 |\n| 风险 | ⭐⭐ | 可控 |',
    ];
    return replies[_random.nextInt(replies.length)];
  }

  void _simulateToolCall(String instanceId, String messageId) {
    final toolController = _toolCallControllers[instanceId];
    if (toolController == null || !toolController.hasListener) return;

    final toolId = _uuid.v4();
    final toolCall = ToolCall(
      id: toolId,
      messageId: messageId,
      toolName: '数据分析工具',
      status: ToolCallStatus.running,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
    toolController.add(toolCall);

    // 2秒后完成
    Future.delayed(const Duration(seconds: 2), () {
      if (toolController.isClosed) return; // 防止 dispose 后执行
      toolController.add(
        toolCall.complete(
          success: true,
          output: '{"result": "ok", "processed": 1247}',
        ),
      );
    });
  }

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async {
    await loadMockData();
    await Future.delayed(const Duration(milliseconds: 300));

    return _mockAgents
        .where((a) => a['instanceId'] == instanceId)
        .map(
          (a) => Agent(
            localId: _uuid.v4(),
            remoteId: a['remoteId'] as String,
            instanceId: a['instanceId'] as String,
            name: a['name'] as String,
            themeColor: a['themeColor'] as String? ?? '#007AFF',
            description: a['description'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) async {
    await loadMockData();
    // 返回空历史（mock 环境不保留历史）
    return (messages: <Message>[], nextCursor: null);
  }

  @override
  Future<bool> testConnection(Instance instance) async {
    await loadMockData();
    await Future.delayed(const Duration(milliseconds: 800));

    // 检查 mock instances 中是否有匹配的
    final matched = _mockInstances.any(
      (inst) =>
          inst['gatewayUrl'] == instance.gatewayUrl ||
          inst['status'] == 'online',
    );

    // 远端URL总是模拟在线（开发环境）
    if (instance.gatewayUrl.startsWith('wss://')) return true;
    // 其他随机结果
    return matched || _random.nextDouble() > 0.3;
  }

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) {
    return _getOrCreateConnectionController(instanceId).stream;
  }

  @override
  Stream<Message> messageStream(String instanceId) {
    return _getOrCreateMessageController(instanceId).stream;
  }

  @override
  Stream<ToolCall> toolCallStream(String instanceId) {
    return _getOrCreateToolCallController(instanceId).stream;
  }

  StreamController<GatewayConnectionState> _getOrCreateConnectionController(
    String instanceId,
  ) {
    return _connectionControllers.putIfAbsent(instanceId, () {
      final ctrl = StreamController<GatewayConnectionState>.broadcast();
      ctrl.add(GatewayConnectionState.disconnected);
      return ctrl;
    });
  }

  StreamController<Message> _getOrCreateMessageController(String instanceId) {
    return _messageControllers.putIfAbsent(
      instanceId,
      () => StreamController<Message>.broadcast(),
    );
  }

  StreamController<ToolCall> _getOrCreateToolCallController(String instanceId) {
    return _toolCallControllers.putIfAbsent(
      instanceId,
      () => StreamController<ToolCall>.broadcast(),
    );
  }

  @override
  Future<void> dispose() async {
    for (final c in _connectionControllers.values) {
      await c.close();
    }
    for (final c in _messageControllers.values) {
      await c.close();
    }
    for (final c in _toolCallControllers.values) {
      await c.close();
    }
  }
}
