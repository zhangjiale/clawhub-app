import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';
import 'gateway_protocol.dart';
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
  final Map<String, StreamController<StreamingEvent>> _streamingControllers =
      {};

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
    final ctrl = _getOrCreateConnectionController(instance.id);
    // Schedule events on the event queue (Future) rather than emitting
    // synchronously, so ConnectionOrchestrator has time to subscribe to
    // the stream before the events arrive.
    Future(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connecting);
    });
    await Future.delayed(const Duration(milliseconds: 500));
    Future(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connected);
    });
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

    // 模拟 Agent 思考延迟（500-2000ms）
    final delayMs = 500 + _random.nextInt(1500);
    Future.delayed(Duration(milliseconds: delayMs), () async {
      if (controller.isClosed) return;

      final fullText = _generateMockReply(userMessage.content ?? '');

      // 模拟流式 delta 推送（每次 2-8 个字符, 30-80ms 间隔）
      final chars = fullText.runes.toList();
      var i = 0;
      while (i < chars.length) {
        final chunkSize = 2 + _random.nextInt(7);
        final end = (i + chunkSize).clamp(0, chars.length);
        final chunk = String.fromCharCodes(chars.sublist(i, end));

        // Re-resolve streaming controller on each iteration so that an
        // instance switch (which replaces the controller) is honoured
        // immediately — avoids pushing deltas to a dead controller.
        final streamingCtrl = _streamingControllers[instanceId];
        if (!(streamingCtrl?.isClosed ?? true)) {
          streamingCtrl?.add(StreamingDelta(agentId: agentId, text: chunk));
        }

        i = end;
        if (i < chars.length) {
          await Future.delayed(
            Duration(milliseconds: 30 + _random.nextInt(50)),
          );
        }
      }

      // 发出完整 Message
      if (controller.isClosed) return;
      final agentMsg = Message(
        clientId: _uuid.v4(),
        serverId: _uuid.v4(),
        conversationId: userMessage.conversationId,
        agentId: agentId,
        role: MessageRole.agent,
        content: fullText,
        type: MessageType.text,
        status: MessageStatus.delivered,
        logicalClock: DateTime.now().millisecondsSinceEpoch,
      );
      controller.add(agentMsg);

      // 通知 UI 流式结束
      final streamingCtrl = _streamingControllers[instanceId];
      if (!(streamingCtrl?.isClosed ?? true)) {
        streamingCtrl?.add(StreamingDone(agentId: agentId));
      }

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

    final matched = _mockAgents
        .where((a) => a['instanceId'] == instanceId)
        .map(_parseMockAgent)
        .toList();

    if (matched.isNotEmpty) return matched;

    // For instances not in the mock fixture (e.g. manually created),
    // generate sensible synthetic agents so the UI isn't empty.
    return _generateDefaultAgents(instanceId);
  }

  /// Parse a mock agent JSON entry into a domain [Agent].
  Agent _parseMockAgent(Map<String, dynamic> a) {
    final qcList = <QuickCommand>[];
    final rawCommands = a['quickCommands'] as List<dynamic>?;
    if (rawCommands != null) {
      for (var i = 0; i < rawCommands.length; i++) {
        final cmd = rawCommands[i] as Map<String, dynamic>;
        qcList.add(
          QuickCommand(
            id: _uuid.v4(),
            agentId: a['remoteId'] as String,
            label: cmd['label'] as String,
            payload: cmd['payload'] as String,
            sortOrder: i,
          ),
        );
      }
    }
    return Agent(
      localId: _uuid.v4(),
      remoteId: a['remoteId'] as String,
      instanceId: a['instanceId'] as String,
      name: a['name'] as String,
      themeColor: a['themeColor'] as String? ?? '#007AFF',
      description: a['description'] as String?,
      quickCommands: qcList,
    );
  }

  /// Generate a set of default agents for an arbitrary instance ID.
  ///
  /// Used when the mock fixture doesn't contain a matching entry for
  /// a manually created instance, so the UI isn't left empty.
  List<Agent> _generateDefaultAgents(String instanceId) {
    final defaults = [
      (name: '默认助手', desc: '通用 AI 助手，可处理各类任务', color: '#007AFF'),
      (name: '代码助手', desc: '编程辅助、代码审查与调试', color: '#34C759'),
    ];

    return defaults.map((d) {
      return Agent(
        localId: _uuid.v4(),
        remoteId: '${instanceId}-default-${d.name}',
        instanceId: instanceId,
        name: d.name,
        themeColor: d.color,
        description: d.desc,
        quickCommands: const [],
      );
    }).toList();
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
  void resetConnectionState(String instanceId) {
    final ctrl = _connectionControllers[instanceId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(GatewayConnectionState.disconnected);
    }
  }

  @override
  Stream<Message> messageStream(String instanceId) {
    return _getOrCreateMessageController(instanceId).stream;
  }

  @override
  Stream<ToolCall> toolCallStream(String instanceId) {
    return _getOrCreateToolCallController(instanceId).stream;
  }

  @override
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) {
    return _getOrCreateStreamingController(instanceId).stream;
  }

  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId) {
    // Mock 环境永不触发配对流程
    return Stream.value(null);
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

  StreamController<StreamingEvent> _getOrCreateStreamingController(
    String instanceId,
  ) {
    return _streamingControllers.putIfAbsent(
      instanceId,
      () => StreamController<StreamingEvent>.broadcast(),
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
    for (final c in _streamingControllers.values) {
      await c.close();
    }
    // Clear maps so that subsequent _getOrCreateXxxController calls
    // (via putIfAbsent) create fresh controllers instead of returning
    // the closed ones.
    _connectionControllers.clear();
    _messageControllers.clear();
    _toolCallControllers.clear();
    _streamingControllers.clear();
  }
}
