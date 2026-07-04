import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';
import 'gateway_protocol.dart';
import 'i_gateway_client.dart';
import 'replayable_connection_state.dart';
import '../../domain/models/models.dart';

/// Mock Gateway 客户端
/// 对齐: 架构 vFinal 7.1 (Mock 服务架构)
///
/// 从 assets/mock/agents.json 读取预设数据，模拟 Gateway 行为。
/// 支持在开发阶段无需真实 OpenClaw 实例即可开发和测试全功能。
class MockGatewayClient implements IGatewayClient {
  final Uuid _uuid = const Uuid();
  final Random _random = Random();

  /// 连接状态流 + last 缓存封装（与 WsGatewayClient 对齐）。
  /// 所有发射点必须通过 [ReplayableConnectionState.emit] 单入口。
  final Map<String, ReplayableConnectionState> _connectionStates = {};
  final Map<String, StreamController<Message>> _messageControllers = {};
  final Map<String, StreamController<ToolCall>> _toolCallControllers = {};
  final Map<String, StreamController<StreamingEvent>> _streamingControllers =
      {};

  /// Gap #6: per-instance diagnostic stream (sealed union). Cache mirrors
  /// [_streamingControllers] — same scope/cleanup pattern. Element type is
  /// [GatewayNotice] so future subtypes flow without retyping.
  final Map<String, StreamController<GatewayNotice>> _gatewayNoticeControllers =
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
    final state = _getOrCreateConnectionState(instance.id);
    // Schedule events on the event queue (Future) rather than emitting
    // synchronously, so ConnectionOrchestrator has time to subscribe to
    // the stream before the events arrive.
    Future(() => state.emit(GatewayConnectionState.connecting));
    await Future.delayed(const Duration(milliseconds: 500));
    Future(() => state.emit(GatewayConnectionState.connected));
  }

  @override
  Future<void> disconnect(String instanceId) async {
    _getOrCreateConnectionState(
      instanceId,
    ).emit(GatewayConnectionState.disconnected);
  }

  /// Remove all per-instance resources (broadcast controllers, connection state).
  ///
  /// Mirrors WsGatewayClient's `_cleanup` semantics so callers can drop a
  /// removed instance's streams without disposing the whole client.  Without
  /// this path, the `_gatewayNoticeControllers` (and the older controllers)
  /// for removed instances would leak broadcast StreamControllers indefinitely.
  Future<void> removeInstance(String instanceId) async {
    final state = _connectionStates.remove(instanceId);
    await state?.dispose();
    final msgCtrl = _messageControllers.remove(instanceId);
    if (msgCtrl != null) await msgCtrl.close();
    final tcCtrl = _toolCallControllers.remove(instanceId);
    if (tcCtrl != null) await tcCtrl.close();
    final streamCtrl = _streamingControllers.remove(instanceId);
    if (streamCtrl != null) await streamCtrl.close();
    final noticeCtrl = _gatewayNoticeControllers.remove(instanceId);
    if (noticeCtrl != null) await noticeCtrl.close();
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

      final fullText = _generateMockReplyFor(userMessage);

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

  /// 按消息类型生成 Mock 回复。image/file 消息的 content 是本地路径,
  /// 不能直接喂给 [_generateMockReply](会得到针对路径文本的无关回复),
  /// 故按类型给出确认性回复。Agent 回图(mock)也在此分支返回 image 消息。
  String _generateMockReplyFor(Message userMessage) {
    switch (userMessage.type) {
      case MessageType.image:
        final name = userMessage.fileName ?? '图片';
        return '收到图片「$name」,我看了一下。这是一张图片,需要我帮你分析或处理吗?';
      case MessageType.file:
        final name = userMessage.fileName ?? '文件';
        return '收到文件「$name」。我已经读取了内容,需要我帮你做什么?';
      case MessageType.text:
      case MessageType.toolCall:
        return _generateMockReply(userMessage.content ?? '');
    }
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
      themeColor: a['themeColor'] as String? ?? '#4F83FF',
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
      (name: '默认助手', desc: '通用 AI 助手，可处理各类任务', color: '#4F83FF'),
      (name: '代码助手', desc: '编程辅助、代码审查与调试', color: '#34C759'),
    ];

    return defaults.map((d) {
      return Agent(
        localId: _uuid.v4(),
        remoteId: '$instanceId-default-${d.name}',
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
    return _getOrCreateConnectionState(instanceId).stream;
  }

  @override
  void resetConnectionState(String instanceId) {
    final state = _connectionStates[instanceId];
    if (state != null) {
      state.emit(GatewayConnectionState.disconnected);
    }
  }

  /// 工厂：惰性创建封装实例。
  ReplayableConnectionState _getOrCreateConnectionState(String instanceId) {
    return _connectionStates.putIfAbsent(
      instanceId,
      () => ReplayableConnectionState(),
    );
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
  Stream<GatewayNotice> gatewayNoticeStream(String instanceId) {
    // Gap #6: 统一诊断流（sealed union）。Mock 正常路径不触发诊断条件，
    // 但仍需真实 broadcast stream 以免订阅者拿到每次新建的 Stream.empty()
    // 实例（会静默丢晚订阅者的事件）。每实例缓存一个 controller，与其余
    // stream accessor 同款。元素类型为 GatewayNotice。
    return _getOrCreateGatewayNoticeController(instanceId).stream;
  }

  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId) {
    // Mock 环境永不触发配对流程。
    // asBroadcastStream delivers null to every subscriber, survives hot-reload
    // disconnect/reconnect cycles in development.
    return Stream<GatewayPairingInfo?>.value(null).asBroadcastStream();
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

  StreamController<GatewayNotice> _getOrCreateGatewayNoticeController(
    String instanceId,
  ) {
    return _gatewayNoticeControllers.putIfAbsent(
      instanceId,
      () => StreamController<GatewayNotice>.broadcast(),
    );
  }

  /// Test-only hook: pushes a synthetic diagnostic [GatewayNotice] (e.g.
  /// [LargePayloadNotice]) onto the per-instance broadcast stream. Mirrors
  /// what a real Gateway would emit when it rejects an oversized frame.
  /// Used by `chat_view_model_large_payload_test.dart` to drive the UI
  /// wiring. Production code must never call this — it bypasses any
  /// precondition check the real ACL applies before publishing the notice.
  @visibleForTesting
  void emitGatewayNoticeForTesting(String instanceId, GatewayNotice notice) {
    _getOrCreateGatewayNoticeController(instanceId).add(notice);
  }

  /// Test-only hook: pushes a synthetic [Message] onto the per-instance
  /// broadcast stream. Used to drive ChatViewModel's messageStream listener
  /// (e.g. tool-call re-key tests). Production code must never call this.
  @visibleForTesting
  void emitMessageForTesting(String instanceId, Message message) {
    _getOrCreateMessageController(instanceId).add(message);
  }

  /// Test-only hook: pushes a synthetic [ToolCall] onto the per-instance
  /// broadcast stream. Used to drive ChatViewModel's toolCallStream listener.
  /// Production code must never call this.
  @visibleForTesting
  void emitToolCallForTesting(String instanceId, ToolCall toolCall) {
    _getOrCreateToolCallController(instanceId).add(toolCall);
  }

  StreamController<ToolCall> _getOrCreateToolCallController(String instanceId) {
    return _toolCallControllers.putIfAbsent(
      instanceId,
      () => StreamController<ToolCall>.broadcast(),
    );
  }

  @override
  Future<void> dispose() async {
    for (final s in _connectionStates.values) {
      await s.dispose();
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
    for (final c in _gatewayNoticeControllers.values) {
      await c.close();
    }
    // Clear maps so that subsequent _getOrCreateXxxController calls
    // (via putIfAbsent) create fresh controllers instead of returning
    // the closed ones.
    _connectionStates.clear();
    _messageControllers.clear();
    _toolCallControllers.clear();
    _streamingControllers.clear();
    _gatewayNoticeControllers.clear();
  }
}
