import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

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

  /// 创建 WebSocket Gateway 客户端。
  ///
  /// [identityProvider] 提供 Ed25519 设备身份和签名能力，
  /// 由 DI 容器注入（默认 [Ed25519IdentityProvider]）。
  ///
  /// [config] 提供客户端/设备/认证的静态配置参数，
  /// 由 DI 容器预构建后注入。
  WsGatewayClient({
    required IDeviceIdentityProvider identityProvider,
    ConnectionConfig? config,
  }) : _identityProvider = identityProvider,
       _config = config ?? ConnectionConfig();

  /// instanceId → 实例连接
  final Map<String, _InstanceConnection> _connections = {};

  /// 防止同一 instanceId 的重入连接。
  final Set<String> _connecting = {};

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
  }

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) async {
    final manager = _requireManager(instanceId);

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
        break;
    }
  }

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
        break;

      case AgentStreamType.lifecycle:
        debugPrint(
          '[WsGateway] Agent lifecycle for $instanceId: ${eventData.data['phase']}',
        );

      case AgentStreamType.unknown:
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
      debugPrint('[WsGateway] Failed to parse message: $error\n$stackTrace');
    }
  }

  void _emitToolCall(_InstanceConnection conn, Map<String, dynamic> data) {
    if (conn.toolCallCtrl.isClosed) return;

    try {
      final toolCall = _parseToolCall(data);
      conn.toolCallCtrl.add(toolCall);
    } catch (error, stackTrace) {
      debugPrint('[WsGateway] Failed to parse tool call: $error\n$stackTrace');
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

  /// Returns `true` when [state] is terminal for [testConnection].
  ///
  /// Terminal states are those where the connection attempt has definitively
  /// resolved (success or failure).  [GatewayConnectionState.pairingRequired]
  /// is included so that new devices waiting for server-side approval return
  /// immediately rather than timing out after 30 s.
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

  StreamSubscription<EventFrame>? _eventSub;
  StreamSubscription<GatewayConnectionState>? _stateSub;
  StreamSubscription<GatewayPairingInfo?>? _pairingSub;

  _InstanceConnection({
    required this.connectionStateCtrl,
    required this.messageCtrl,
    required this.toolCallCtrl,
    required this.pairingInfoCtrl,
  });
}
