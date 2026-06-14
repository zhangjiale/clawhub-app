import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/models/models.dart';
import 'connection_manager.dart';
import 'device_identity.dart';
import 'gateway_protocol.dart';
import 'i_device_identity_provider.dart';
import 'i_gateway_client.dart';

/// 真实 WebSocket Gateway 客户端 — 实现 [IGatewayClient] 接口。
///
/// 实现 OpenClaw Gateway Protocol v4：
/// - 帧格式：`req`/`res`/`event`
/// - 握手：challenge → connect → hello-ok
/// - 请求：`agents.list`、`agent`、`chat.history`
/// - 事件：`agent`（thinking / message / tool / lifecycle）、`tick`
/// - 设备身份：委托给 [IDeviceIdentityProvider]（Ed25519 密钥对 + V3 签名）
///
/// 领域对象映射由本类完成（_parseAgent, _parseMessage, _parseToolCall）。
///
/// 每个实例的连接相关资源内聚于 [_InstanceConnection]。
class WsGatewayClient implements IGatewayClient {
  final Uuid _uuid = const Uuid();
  final IDeviceIdentityProvider _identityProvider;
  final ConnectionConfig _config;

  /// Optional: inject a custom WebSocket factory for testing.
  /// When null (production default), [ConnectionManager] creates real
  /// [WebSocket] channels.
  final WebSocketChannel Function(Uri)? _webSocketFactory;

  /// Optional: inject a custom timer factory for testing.
  /// When null (production default), [ConnectionManager] uses dart:async
  /// [Timer].
  final TimerFactory? _timerFactory;

  /// 创建 WebSocket Gateway 客户端。
  ///
  /// [identityProvider] 提供 Ed25519 设备身份和签名能力，
  /// 由 DI 容器注入（默认 [Ed25519IdentityProvider]）。
  ///
  /// [config] 提供客户端/设备/认证的静态配置参数，
  /// 由 DI 容器预构建后注入。
  ///
  /// [webSocketFactory] 和 [timerFactory] 仅供测试注入，
  /// 生产环境留空即可（委托 [ConnectionManager] 默认行为）。
  WsGatewayClient({
    required IDeviceIdentityProvider identityProvider,
    ConnectionConfig? config,
    WebSocketChannel Function(Uri)? webSocketFactory,
    TimerFactory? timerFactory,
  }) : _identityProvider = identityProvider,
       _config = config ?? ConnectionConfig(),
       _webSocketFactory = webSocketFactory,
       _timerFactory = timerFactory;

  /// instanceId → 实例连接
  final Map<String, _InstanceConnection> _connections = {};

  /// 防止同一 instanceId 的重入连接。
  final Set<String> _connecting = {};

  /// Delta 聚合缓冲区: sessionKey → StreamingBuffer。
  /// agent assistant 事件追加 delta，chat final 事件消费后移除。
  final Map<String, StreamingBuffer> _streamingBuffers = {};

  /// Explicit mapping from sessionKey → remoteAgentId.
  ///
  /// Populated by [sendMessage] (chat.send) response handler.
  /// Events dispatch look up agentId via this table instead
  /// of parsing the colon-separated sessionKey string — that heuristic is
  /// unreliable when Gateway uses alternative sessionKey formats.
  final Map<String, String> _sessionToAgentId = {};

  // 设备身份由 [IDeviceIdentityProvider] 管理，通过构造函数注入。

  /// 构建携带设备身份信息的运行时 [ConnectionConfig]。
  ///
  /// 从 [IDeviceIdentityProvider] 派生 `devicePublicKey` 和 `signPayload`，
  /// 避免 [connect] 与 [testConnection] 中的重复配置构建代码。
  ConnectionConfig _buildConfig(DeviceIdentity identity) => _config.copyWith(
    devicePublicKey: identity.publicKeyB64,
    signPayload: _identityProvider.signPayload,
  );

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
        await _cleanupConnection(instance.id);
      }

      final identity = await _identityProvider.ensureDeviceIdentity();
      final config = _buildConfig(identity);

      final manager = ConnectionManager(
        instanceId: instance.id,
        gatewayUrl: instance.gatewayUrl,
        token: instance.tokenRef,
        deviceId: identity.deviceId,
        config: config,
        webSocketFactory: _webSocketFactory,
        timerFactory: _timerFactory,
      );

      // 复用已有的流控制器（若有），否则创建新的
      final conn = _connections.putIfAbsent(
        instance.id,
        () => _InstanceConnection(
          connectionStateCtrl:
              StreamController<GatewayConnectionState>.broadcast(),
          messageCtrl: StreamController<Message>.broadcast(),
          toolCallCtrl: StreamController<ToolCall>.broadcast(),
          pairingInfoCtrl: StreamController<GatewayPairingInfo?>.broadcast(),
          streamingCtrl: StreamController<StreamingEvent>.broadcast(),
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

      // 订阅配对信息
      conn._pairingSub = manager.pairingInfo.listen((info) {
        if (!conn.pairingInfoCtrl.isClosed) {
          conn.pairingInfoCtrl.add(info);
        }
      });

      await manager.connect();
    } finally {
      _connecting.remove(instance.id);
    }
  }

  @override
  Future<void> disconnect(String instanceId) async {
    await _cleanup(instanceId, emitDisconnected: true);
  }

  /// 取消订阅并释放 manager — 与 [disconnect] 相同但**不发出 disconnected 事件**。
  Future<void> _cleanupConnection(String instanceId) async {
    await _cleanup(instanceId);
  }

  Future<void> _cleanup(
    String instanceId, {
    bool emitDisconnected = false,
  }) async {
    final conn = _connections[instanceId];
    if (conn == null) return;

    await conn._eventSub?.cancel();
    conn._eventSub = null;
    await conn._stateSub?.cancel();
    conn._stateSub = null;
    await conn._pairingSub?.cancel();
    conn._pairingSub = null;
    await conn.manager?.dispose();
    conn.manager = null;

    if (emitDisconnected && !conn.connectionStateCtrl.isClosed) {
      conn.connectionStateCtrl.add(GatewayConnectionState.disconnected);
    }

    // 断开连接时清理该实例相关的 streaming buffer，防止残留
    // Keys are scoped as '$instanceId:$sessionKey' since commit XXXXXX.
    if (emitDisconnected) {
      _streamingBuffers.removeWhere((key, _) => key.startsWith('$instanceId:'));
    }
  }

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async {
    final manager = _requireManager(instanceId);

    // sessionKey format: agent:{agentId}:main (ref doc §7.2)
    final sessionKey = 'agent:$agentId:main';
    // Populate mapping so event dispatch can resolve agentId without string parsing
    _sessionToAgentId[sessionKey] = agentId;

    final res = await manager.sendRequest(Methods.chatSend, {
      'sessionKey': sessionKey,
      'message': message.content ?? '',
      'idempotencyKey': message.clientId,
      if (message.metadata != null) 'metadata': message.metadata,
    });

    if (!res.ok) {
      throw Exception(
        'Message send failed: ${res.error?.message ?? "unknown"}',
      );
    }

    // chat.send 响应中没有 serverId，用 runId 作为追踪标识
    final payload = res.payload ?? {};
    final serverId = payload['runId'] as String? ?? _uuid.v4();
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

    final agents =
        (res.payload?['agents'] as List<dynamic>?)
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

    final params = <String, dynamic>{'agentId': agentId, 'limit': limit};
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
    final testId = '__test_${instance.id}';
    final identity = await _identityProvider.ensureDeviceIdentity();
    final config = _buildConfig(identity);
    final testManager = ConnectionManager(
      instanceId: testId,
      gatewayUrl: instance.gatewayUrl,
      token: instance.tokenRef,
      deviceId: identity.deviceId,
      config: config,
      webSocketFactory: _webSocketFactory,
      timerFactory: _timerFactory,
    );

    try {
      final stateFuture = testManager.connectionState.firstWhere(
        isTestTerminalState,
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
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) {
    return _getOrCreateControllers(instanceId).streamingCtrl.stream;
  }

  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId) {
    return _getOrCreateControllers(instanceId).pairingInfoCtrl.stream;
  }

  @override
  Future<void> dispose() async {
    for (final conn in _connections.values) {
      await conn._eventSub?.cancel();
      await conn._stateSub?.cancel();
      await conn._pairingSub?.cancel();
      await conn.manager?.dispose();
      await conn.connectionStateCtrl.close();
      await conn.messageCtrl.close();
      await conn.toolCallCtrl.close();
      await conn.pairingInfoCtrl.close();
      await conn.streamingCtrl.close();
    }
    _connections.clear();
    _streamingBuffers.clear();
    _sessionToAgentId.clear();
  }

  // ---------------------------------------------------------------------------
  // 内部：事件路由
  // ---------------------------------------------------------------------------

  void _handleEvent(
    String instanceId,
    _InstanceConnection conn,
    EventFrame event,
  ) {
    final payload = event.payload;
    if (payload == null) return;

    switch (event.event) {
      case Events.chat:
        _onChatEvent(instanceId, conn, payload);

      case Events.agent:
        _onAgentEvent(instanceId, conn, payload);

      default:
        break;
    }
  }

  /// `chat` 事件 — Gateway v2026.6.6 UI 面向前端事件。
  ///
  /// - `state: "delta"` → 增量文本（含 deltaText）
  /// - `state: "final"` → 响应完成，携带完整 message 对象
  void _onChatEvent(
    String instanceId,
    _InstanceConnection conn,
    Map<String, dynamic> payload,
  ) {
    final event = parseChatEvent(payload);
    // Scope streaming buffers by instanceId to prevent per-instance
    // disconnect from dropping other instances' in-progress aggregation.
    final bufferKey = '$instanceId:${event.sessionKey}';

    switch (event.state) {
      case ChatState.delta:
        if (event.deltaText != null && event.deltaText!.isNotEmpty) {
          // Resolve agentId from sessionKey (explicit mapping → string parse)
          final agentId = resolveAgentId(event.sessionKey, _sessionToAgentId);
          if (agentId == null) return; // unresolvable, drop event

          // Push typed streaming event to UI
          if (!conn.streamingCtrl.isClosed) {
            conn.streamingCtrl.add(
              StreamingDelta(agentId: agentId, text: event.deltaText!),
            );
          }
          // Also maintain aggregation buffer (fallback)
          _streamingBuffers
              .putIfAbsent(
                bufferKey,
                () => StreamingBuffer(sessionKey: event.sessionKey),
              )
              .append(event.deltaText!);
        }

      case ChatState.final_:
        // 响应完成 — 优先用 message 对象，回退到聚合文本
        if (conn.messageCtrl.isClosed) return;

        String? agentId;

        try {
          final msgJson = event.message;
          agentId =
              msgJson?['agentId'] as String? ??
              resolveAgentId(event.sessionKey, _sessionToAgentId);

          if (msgJson != null) {
            // chat final event 自带完整 message，直接解析
            final message = _parseMessage(msgJson);
            conn.messageCtrl.add(message);
          } else {
            // 没有 message 对象时，用聚合文本构建
            final buffer = _streamingBuffers.remove(bufferKey);
            if (buffer != null && buffer.text.isNotEmpty) {
              // Use agentId for conversationId lookup alignment with
              // ChatViewModel._conversationId = Conversation.generateId(...)
              // agentId may be null if unresolvable; downstream uses
              // `?? ''` or `?? event.sessionKey` as fallback.
              final conversationId = (agentId ?? '').isNotEmpty
                  ? 'agent:$agentId'
                  : event.sessionKey;
              final message = Message(
                clientId: _uuid.v4(),
                conversationId: conversationId,
                agentId: agentId ?? '',
                role: MessageRole.agent,
                content: buffer.text,
                type: MessageType.text,
                status: MessageStatus.delivered,
                logicalClock: DateTime.now().millisecondsSinceEpoch,
              );
              conn.messageCtrl.add(message);
            }
          }
        } catch (error, stackTrace) {
          debugPrint(
            '[WsGateway] Failed to handle chat final: $error\n$stackTrace',
          );
        }
        _streamingBuffers.remove(bufferKey);

        // Notify UI that streaming is complete (with agentId for routing)
        if (!conn.streamingCtrl.isClosed) {
          conn.streamingCtrl.add(StreamingDone(agentId: agentId ?? ''));
        }

      case ChatState.unknown:
        break;
    }
  }

  /// `agent` 事件 — Gateway v2026.6.6 后端事件。
  ///
  /// - `stream: "tool"` → 工具调用 (phase: "start" = 开始, "result" = 结束)
  /// - `stream: "assistant"` → 助手文本生成
  /// - `stream: "lifecycle"` → 生命周期 (phase: "start"/"end")
  /// - `stream: "item"` → 工具调用项
  void _onAgentEvent(
    String instanceId,
    _InstanceConnection conn,
    Map<String, dynamic> payload,
  ) {
    final event = parseAgentEvent(payload);
    final bufferKey = '$instanceId:${event.sessionKey}';

    switch (event.stream) {
      case AgentStreamType.tool:
        if (event.data['phase'] == 'result') {
          // tool 结束 — 发出带结果的 ToolCall
          if (!conn.toolCallCtrl.isClosed) {
            try {
              final tc = ToolCall(
                id: event.data['toolCallId'] as String? ?? _uuid.v4(),
                messageId: event.sessionKey,
                toolName: event.data['name'] as String? ?? 'unknown',
                status: ToolCallStatus.success,
                outputResult: event.data.toString(),
                endedAt: DateTime.now().millisecondsSinceEpoch,
              );
              conn.toolCallCtrl.add(tc);
            } catch (error, stackTrace) {
              debugPrint(
                '[WsGateway] Failed to parse tool result: $error\n$stackTrace',
              );
            }
          }
        } else {
          // tool 开始 — 发出 running 状态的 ToolCall
          if (!conn.toolCallCtrl.isClosed) {
            try {
              final tc = ToolCall(
                id: event.data['toolCallId'] as String? ?? _uuid.v4(),
                messageId: event.sessionKey,
                toolName: event.data['name'] as String? ?? 'unknown',
                status: ToolCallStatus.running,
                startedAt: DateTime.now().millisecondsSinceEpoch,
              );
              conn.toolCallCtrl.add(tc);
            } catch (error, stackTrace) {
              debugPrint(
                '[WsGateway] Failed to parse tool call: $error\n$stackTrace',
              );
            }
          }
        }

      case AgentStreamType.message:
        // v3 protocol "message" type — semantically equivalent to v4 "assistant".
        // Both carry delta text in data.delta for streaming display.
        {
          final delta = event.data['delta'] as String?;
          if (delta != null && delta.isNotEmpty) {
            final agentId = resolveAgentId(event.sessionKey, _sessionToAgentId);
            if (agentId == null) break;
            if (!conn.streamingCtrl.isClosed) {
              conn.streamingCtrl.add(
                StreamingDelta(agentId: agentId, text: delta),
              );
            }
            _streamingBuffers
                .putIfAbsent(
                  bufferKey,
                  () => StreamingBuffer(sessionKey: event.sessionKey),
                )
                .append(delta);
          }
        }

      case AgentStreamType.assistant:
        // 助手文本 delta / message event — 仅用于 streaming 缓冲
        // chat 事件已经在推 deltaText，这里做补充
        final delta = event.data['delta'] as String?;
        if (delta != null && delta.isNotEmpty) {
          _streamingBuffers
              .putIfAbsent(
                bufferKey,
                () => StreamingBuffer(sessionKey: event.sessionKey),
              )
              .append(delta);
        }

      case AgentStreamType.lifecycle:
      case AgentStreamType.item:
        break;
      case AgentStreamType.unknown:
        debugPrint(
          '[WsGateway] Unknown agent stream type for $instanceId: '
          '${event.data['stream']}',
        );
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：领域对象映射
  // ---------------------------------------------------------------------------

  Agent _parseAgent(Map<String, dynamic> json, String instanceId) {
    final remoteId = json['remoteId'] as String? ?? json['id'] as String? ?? '';
    final rawCommands = json['quickCommands'] as List<dynamic>?;
    final quickCommands = <QuickCommand>[];
    if (rawCommands != null) {
      for (var i = 0; i < rawCommands.length; i++) {
        final cmd = rawCommands[i] as Map<String, dynamic>;
        quickCommands.add(
          QuickCommand(
            id: _uuid.v4(),
            agentId: remoteId,
            label: cmd['label'] as String? ?? '',
            payload: cmd['payload'] as String? ?? '',
            sortOrder: i,
          ),
        );
      }
    }

    // Agent name fallback chain:
    //   json['name'] → identity.name → id
    // Gateway 的默认 agent (如 "main") 通常没有 name 字段，
    // 只有 id，此时以 id 作为显示名（协议文档 §A.6 实测验证）。
    final identity = json['identity'] as Map<String, dynamic>?;
    String? _nonEmpty(String? s) =>
        (s != null && s.trim().isNotEmpty) ? s.trim() : null;
    final name =
        _nonEmpty(json['name'] as String?) ??
        _nonEmpty(identity?['name'] as String?) ??
        remoteId;

    final description =
        json['description'] as String? ?? identity?['description'] as String?;

    return Agent(
      localId: _uuid.v4(),
      remoteId: remoteId,
      instanceId: instanceId,
      name: name,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      themeColor: json['themeColor'] as String? ?? '#007AFF',
      description: description,
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
      outputResult:
          json['output'] as String? ?? json['outputResult'] as String?,
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

  /// Resolve a [sessionKey] to its remote agent ID.
  ///
  /// 1. Explicit mapping (primary path — populated by chat.send)
  /// 2. String parsing fallback (backward compat — parses "agent:{id}:{scope}")
  /// 3. Returns `null` when unresolvable; callers MUST handle null by dropping
  ///    the event (logging is done here already).
  ///
  /// Internal helper — tested indirectly via [streamingDeltaStream] integration
  /// tests, with direct unit coverage via `@visibleForTesting`.
  @visibleForTesting
  static String? resolveAgentId(
    String sessionKey,
    Map<String, String> mapping,
  ) {
    // 1. Explicit mapping (primary path)
    final mapped = mapping[sessionKey];
    if (mapped != null) return mapped;

    // 2. String parsing fallback (backward compat with Gateway < v2026.6.6)
    final parts = sessionKey.split(':');
    if (parts.length >= 2 && parts[0] == 'agent' && parts[1].isNotEmpty) {
      return parts[1];
    }

    // 3. Unresolvable — log and return null
    debugPrint(
      '[WsGateway] Cannot resolve agentId from sessionKey: '
      '"$sessionKey" — mapping contains ${mapping.length} entries',
    );
    return null;
  }

  @visibleForTesting
  static bool isTestTerminalState(GatewayConnectionState state) {
    return state == GatewayConnectionState.connected ||
        state == GatewayConnectionState.authFailed ||
        state == GatewayConnectionState.disconnected ||
        state == GatewayConnectionState.pairingRequired;
  }

  ConnectionManager _requireManager(String instanceId) {
    final conn = _connections[instanceId];
    if (conn == null || conn.manager == null) {
      throw NotConnectedException(
        'No connection for instance $instanceId. Call connect() first.',
      );
    }
    return conn.manager!;
  }

  _InstanceConnection _getOrCreateControllers(String instanceId) {
    return _connections.putIfAbsent(
      instanceId,
      () => _InstanceConnection(
        connectionStateCtrl:
            StreamController<GatewayConnectionState>.broadcast(),
        messageCtrl: StreamController<Message>.broadcast(),
        toolCallCtrl: StreamController<ToolCall>.broadcast(),
        pairingInfoCtrl: StreamController<GatewayPairingInfo?>.broadcast(),
        streamingCtrl: StreamController<StreamingEvent>.broadcast(),
      ),
    );
  }
}

// ============================================================================
// 内部：实例连接资源聚合
// ============================================================================

class _InstanceConnection {
  ConnectionManager? manager;

  final StreamController<GatewayConnectionState> connectionStateCtrl;
  final StreamController<Message> messageCtrl;
  final StreamController<ToolCall> toolCallCtrl;
  final StreamController<GatewayPairingInfo?> pairingInfoCtrl;
  final StreamController<StreamingEvent> streamingCtrl;

  StreamSubscription<EventFrame>? _eventSub;
  StreamSubscription<GatewayConnectionState>? _stateSub;
  StreamSubscription<GatewayPairingInfo?>? _pairingSub;

  _InstanceConnection({
    required this.connectionStateCtrl,
    required this.messageCtrl,
    required this.toolCallCtrl,
    required this.pairingInfoCtrl,
    required this.streamingCtrl,
  });
}
