import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/models.dart';
import 'i_gateway_client.dart';
import 'connection_manager.dart';
import 'gateway_protocol.dart';

/// 真实 WebSocket Gateway 客户端 — 实现 [IGatewayClient] 接口。
///
/// 实现 OpenClaw Gateway Protocol v4：
/// - 帧格式：`req`/`res`/`event`
/// - 握手：challenge → connect → hello-ok
/// - 请求：`agents.list`、`agent`、`chat.history`
/// - 事件：`agent`（thinking / message / tool / lifecycle）、`tick`
///
/// 领域对象映射由本类完成（_parseAgent, _parseMessage, _parseToolCall）。
///
/// 每个实例的连接相关资源内聚于 [_InstanceConnection]。
class WsGatewayClient implements IGatewayClient {
  final Uuid _uuid = const Uuid();
  final String _locale;

  /// 创建 WebSocket Gateway 客户端。
  ///
  /// [locale] 为客户端地区标识（如 `zh-CN`），
  /// 将随 connect 握手发送给 Gateway。
  WsGatewayClient({String locale = 'zh-CN'}) : _locale = locale;

  /// instanceId → 实例连接（含 manager + 所有流控制器 + 事件订阅）
  final Map<String, _InstanceConnection> _connections = {};

  /// 防止同一 instanceId 的重入连接。
  final Set<String> _connecting = {};

  // ---------------------------------------------------------------------------
  // IGatewayClient 实现
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect(Instance instance) async {
    // 防止同一实例重入连接
    if (_connecting.contains(instance.id)) return;
    _connecting.add(instance.id);

    try {
      if (_connections.containsKey(instance.id)) {
        await disconnect(instance.id);
      }

      final manager = ConnectionManager(
        instanceId: instance.id,
        gatewayUrl: instance.gatewayUrl,
        token: instance.tokenRef,
        locale: _locale,
      );

      // 复用已有的流控制器（若有），否则创建新的
      final conn = _connections.putIfAbsent(
        instance.id,
        () => _InstanceConnection(
          connectionStateCtrl:
              StreamController<GatewayConnectionState>.broadcast(),
          messageCtrl: StreamController<Message>.broadcast(),
          toolCallCtrl: StreamController<ToolCall>.broadcast(),
        ),
      );
      conn.manager = manager;

      // 订阅连接状态
      conn._stateSub = manager.connectionState.listen((state) {
        if (!conn.connectionStateCtrl.isClosed) {
          conn.connectionStateCtrl.add(state);
        }
      });

      // 订阅 Gateway 事件
      conn._eventSub = manager.events.listen(
        (event) => _handleEvent(instance.id, conn, event),
      );

      await manager.connect();
    } finally {
      _connecting.remove(instance.id);
    }
  }

  @override
  Future<void> disconnect(String instanceId) async {
    final conn = _connections[instanceId];
    if (conn == null) return;

    // 仅清理 manager 和事件订阅，保留流控制器。
    // 流控制器在 disconnect 后仍然存活，以便重连时复用，
    // 仅在 WsGatewayClient.dispose() 时统一关闭。
    await conn._eventSub?.cancel();
    conn._eventSub = null;
    await conn._stateSub?.cancel();
    conn._stateSub = null;
    await conn.manager?.dispose();
    conn.manager = null;

    // 通知外部订阅者连接已断开
    if (!conn.connectionStateCtrl.isClosed) {
      conn.connectionStateCtrl.add(GatewayConnectionState.disconnected);
    }
  }

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async {
    final manager = _requireManager(instanceId);

    // 使用 `agent` 方法执行一次 agent turn
    final res = await manager.sendRequest(Methods.agent, {
      'agentId': agentId,
      'message': message.content ?? '',
      if (message.metadata != null) 'metadata': message.metadata,
    });

    if (!res.ok) {
      throw Exception(
        'Message send failed: ${res.error?.message ?? "unknown"}',
      );
    }

    final payload = res.payload ?? {};
    final serverId = payload['serverId'] as String? ?? _uuid.v4();
    final timestamp =
        payload['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    return (serverId: serverId, timestamp: timestamp);
  }

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async {
    final manager = _requireManager(instanceId);

    final res = await manager.sendRequest(Methods.agentsList, {});

    if (!res.ok) {
      throw Exception(
        'Failed to fetch agents: ${res.error?.message ?? "unknown"}',
      );
    }

    final agents = (res.payload?['agents'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    return agents.map((json) => _parseAgent(json, instanceId)).toList();
  }

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) async {
    final manager = _requireManager(instanceId);

    final params = <String, dynamic>{
      'agentId': agentId,
      'limit': limit,
    };
    if (cursor != null) params['cursor'] = cursor;

    final res = await manager.sendRequest(Methods.chatHistory, params);

    if (!res.ok) {
      throw Exception(
        'Failed to fetch history: ${res.error?.message ?? "unknown"}',
      );
    }

    final messages =
        (res.payload?['messages'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            .map((json) => _parseMessage(json))
            .toList() ??
            [];
    final nextCursor = res.payload?['nextCursor'] as String?;

    return (messages: messages, nextCursor: nextCursor);
  }

  @override
  Future<bool> testConnection(Instance instance) async {
    final testManager = ConnectionManager(
      instanceId: '__test_${instance.id}',
      gatewayUrl: instance.gatewayUrl,
      token: instance.tokenRef,
      locale: _locale,
    );

    try {
      final stateFuture = testManager.connectionState.firstWhere(
        (s) =>
            s == GatewayConnectionState.connected ||
            s == GatewayConnectionState.authFailed,
      );

      await testManager.connect().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Connection test timed out'),
      );

      final finalState = await stateFuture.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('State wait timed out'),
      );

      return finalState == GatewayConnectionState.connected;
    } catch (error, stackTrace) {
      debugPrint('[WsGateway] Connection test failed: $error\n$stackTrace');
      return false;
    } finally {
      await testManager.dispose();
    }
  }

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) {
    return _getOrCreateControllers(instanceId).connectionStateCtrl.stream;
  }

  @override
  void resetConnectionState(String instanceId) {
    final ctrl = _connections[instanceId]?.connectionStateCtrl;
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(GatewayConnectionState.disconnected);
    }
  }

  @override
  Stream<Message> messageStream(String instanceId) {
    return _getOrCreateControllers(instanceId).messageCtrl.stream;
  }

  @override
  Stream<ToolCall> toolCallStream(String instanceId) {
    return _getOrCreateControllers(instanceId).toolCallCtrl.stream;
  }

  @override
  Future<void> dispose() async {
    for (final conn in _connections.values) {
      await conn._eventSub?.cancel();
      await conn._stateSub?.cancel();
      await conn.manager?.dispose();
      await conn.connectionStateCtrl.close();
      await conn.messageCtrl.close();
      await conn.toolCallCtrl.close();
    }
    _connections.clear();
  }

  // ---------------------------------------------------------------------------
  // 内部：事件路由
  // ---------------------------------------------------------------------------

  void _handleEvent(
    String instanceId,
    _InstanceConnection conn,
    EventFrame event,
  ) {
    switch (event.event) {
      case Events.agent:
        _onAgentEvent(instanceId, conn, event.payload);

      default:
        // tick, presence, health, shutdown 等已在 ConnectionManager 处理
        break;
    }
  }

  /// 处理 `agent` 事件 —— Gateway 推送的 agent 执行流。
  ///
  /// 包含四种流类型：
  /// - `message` — Agent 回复消息
  /// - `tool` — 工具调用/结果
  /// - `thinking` — 思考过程（可选展示）
  /// - `lifecycle` — run 生命周期（start/end/error）
  void _onAgentEvent(
    String instanceId,
    _InstanceConnection conn,
    Map<String, dynamic>? payload,
  ) {
    if (payload == null) return;

    final eventData = parseAgentEvent(payload);

    switch (eventData.stream) {
      case AgentStreamType.message:
        _emitMessage(conn, eventData.data);

      case AgentStreamType.tool:
        _emitToolCall(conn, eventData.data);

      case AgentStreamType.thinking:
        // 思考过程 — 暂不暴露为独立流，可在 UI 通过 thinkingState 展示
        break;

      case AgentStreamType.lifecycle:
        // Run 生命周期 — 可用于记录/调试
        debugPrint(
          '[WsGateway] Agent lifecycle for $instanceId: ${eventData.data['phase']}',
        );

      case AgentStreamType.unknown:
        // 新流类型 — 容错
        debugPrint(
          '[WsGateway] Unknown agent stream type for $instanceId: '
          '${payload['stream']}',
        );
    }
  }

  void _emitMessage(_InstanceConnection conn, Map<String, dynamic> data) {
    if (conn.messageCtrl.isClosed) return;

    try {
      final message = _parseMessage(data);
      conn.messageCtrl.add(message);
    } catch (error, stackTrace) {
      debugPrint(
        '[WsGateway] Failed to parse message: $error\n$stackTrace',
      );
    }
  }

  void _emitToolCall(_InstanceConnection conn, Map<String, dynamic> data) {
    if (conn.toolCallCtrl.isClosed) return;

    try {
      final toolCall = _parseToolCall(data);
      conn.toolCallCtrl.add(toolCall);
    } catch (error, stackTrace) {
      debugPrint(
        '[WsGateway] Failed to parse tool call: $error\n$stackTrace',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：领域对象映射
  // ---------------------------------------------------------------------------

  Agent _parseAgent(Map<String, dynamic> json, String instanceId) {
    final rawCommands = json['quickCommands'] as List<dynamic>?;
    final quickCommands = <QuickCommand>[];
    if (rawCommands != null) {
      for (var i = 0; i < rawCommands.length; i++) {
        final cmd = rawCommands[i] as Map<String, dynamic>;
        quickCommands.add(
          QuickCommand(
            id: _uuid.v4(),
            agentId: json['remoteId'] as String? ?? '',
            label: cmd['label'] as String? ?? '',
            payload: cmd['payload'] as String? ?? '',
            sortOrder: i,
          ),
        );
      }
    }

    return Agent(
      localId: _uuid.v4(),
      remoteId: json['remoteId'] as String? ?? json['id'] as String? ?? '',
      instanceId: instanceId,
      name: json['name'] as String? ?? json['displayName'] as String? ?? '',
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      themeColor: json['themeColor'] as String? ?? '#007AFF',
      description: json['description'] as String?,
      isPinned: json['isPinned'] == true,
      quickCommands: quickCommands,
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }

  Message _parseMessage(Map<String, dynamic> json) {
    return Message(
      clientId: json['clientId'] as String? ?? _uuid.v4(),
      serverId: json['serverId'] as String? ?? json['id'] as String?,
      conversationId: json['conversationId'] as String? ?? '',
      agentId: json['agentId'] as String? ?? '',
      role: _parseMessageRole(json['role'] as String?),
      content: json['content'] as String? ?? json['text'] as String?,
      type: _parseMessageType(json['type'] as String?),
      status: MessageStatus.delivered,
      logicalClock: json['logicalClock'] as int? ?? 0,
      timestamp: json['timestamp'] as int?,
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : null,
    );
  }

  ToolCall _parseToolCall(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'] as String? ?? _uuid.v4(),
      messageId: json['messageId'] as String? ?? '',
      toolName:
          json['name'] as String? ?? json['toolName'] as String? ?? 'unknown',
      status: _parseToolCallStatus(json['status'] as String?),
      inputArgs: json['input'] as String? ?? json['inputArgs'] as String?,
      outputResult: json['output'] as String? ?? json['outputResult'] as String?,
      startedAt: json['startedAt'] as int?,
      endedAt: json['endedAt'] as int?,
    );
  }

  // ---------------------------------------------------------------------------
  // 内部：枚举映射
  // ---------------------------------------------------------------------------

  MessageRole _parseMessageRole(String? role) {
    return switch (role) {
      'agent' || 'assistant' => MessageRole.agent,
      'system' => MessageRole.system,
      _ => MessageRole.user,
    };
  }

  MessageType _parseMessageType(String? type) {
    return switch (type) {
      'image' => MessageType.image,
      'file' => MessageType.file,
      'tool_call' || 'toolCall' => MessageType.toolCall,
      _ => MessageType.text,
    };
  }

  ToolCallStatus _parseToolCallStatus(String? status) {
    return switch (status) {
      'running' || 'in_progress' => ToolCallStatus.running,
      'success' || 'completed' => ToolCallStatus.success,
      'failed' || 'error' => ToolCallStatus.failed,
      _ => ToolCallStatus.pending,
    };
  }

  // ---------------------------------------------------------------------------
  // 内部：辅助方法
  // ---------------------------------------------------------------------------

  ConnectionManager _requireManager(String instanceId) {
    final conn = _connections[instanceId];
    if (conn == null || conn.manager == null) {
      throw StateError(
        'No connection for instance $instanceId. Call connect() first.',
      );
    }
    return conn.manager!;
  }

  /// 获取或创建流控制器（不创建 ConnectionManager）。
  ///
  /// 用于 [connectionStateStream]、[messageStream]、[toolCallStream] —
  /// 这些流可能在 [connect] 之前被订阅，此时只需暴露 controller 即可。
  _InstanceConnection _getOrCreateControllers(String instanceId) {
    return _connections.putIfAbsent(
      instanceId,
      () => _InstanceConnection(
        connectionStateCtrl:
            StreamController<GatewayConnectionState>.broadcast(),
        messageCtrl: StreamController<Message>.broadcast(),
        toolCallCtrl: StreamController<ToolCall>.broadcast(),
      ),
    );
  }
}

// ============================================================================
// 内部：实例连接资源聚合
// ============================================================================

/// 聚合单个 Gateway 实例的所有连接相关资源。
///
/// 将原来分散的 5 组 Map 收敛到一个对象中：
/// - [manager] — WebSocket 连接生命周期管理
/// - [connectionStateCtrl] — 连接状态广播流
/// - [messageCtrl] — 消息事件广播流
/// - [toolCallCtrl] — 工具调用事件广播流
/// - [_eventSub] — Gateway 事件订阅
/// - [_stateSub] — manager → controller 状态转发订阅
///
/// 流控制器在 disconnect 后保留（允许重连复用），
/// 仅在 WsGatewayClient.dispose() 时关闭。
class _InstanceConnection {
  /// WebSocket 连接管理器（disconnect 时置 null，connect 时重新赋值）。
  ConnectionManager? manager;

  final StreamController<GatewayConnectionState> connectionStateCtrl;
  final StreamController<Message> messageCtrl;
  final StreamController<ToolCall> toolCallCtrl;

  StreamSubscription<EventFrame>? _eventSub;
  StreamSubscription<GatewayConnectionState>? _stateSub;

  _InstanceConnection({
    required this.connectionStateCtrl,
    required this.messageCtrl,
    required this.toolCallCtrl,
  });
}
