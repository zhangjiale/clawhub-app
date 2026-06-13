import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/models.dart';
import 'connection_manager.dart';
import 'gateway_protocol.dart';
import 'i_gateway_client.dart';

/// 真实 WebSocket Gateway 客户端 — 实现 [IGatewayClient] 接口。
///
/// 实现 OpenClaw Gateway Protocol v4：
/// - 帧格式：`req`/`res`/`event`
/// - 握手：challenge → connect → hello-ok
/// - 请求：`agents.list`、`agent`、`chat.history`
/// - 事件：`agent`（thinking / message / tool / lifecycle）、`tick`
/// - 设备身份：**Ed25519** 密钥对 + V3 签名 Payload（§2.5）
///
/// 领域对象映射由本类完成（_parseAgent, _parseMessage, _parseToolCall）。
///
/// 每个实例的连接相关资源内聚于 [_InstanceConnection]。
class WsGatewayClient implements IGatewayClient {
  final Uuid _uuid = const Uuid();
  final String _locale;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const _privateKeyKey = 'clawhub_device_ed25519_seed';
  static const _publicKeyKey = 'clawhub_device_ed25519_pubkey';

  // Legacy keys (ECDSA P-256) — for migration detection
  static const _legacyPrivateKeyKey = 'clawhub_device_private_key';
  static const _legacyPublicKeyKey = 'clawhub_device_public_key';

  /// 设备唯一标识（SHA256 of Ed25519 public key, 64 hex chars）。
  String? _deviceId;

  /// Ed25519 公钥（base64url，32 字节 raw）。
  String? _publicKeyB64;

  /// Ed25519 私钥种子（32 字节）。
  Uint8List? _seedBytes;
  bool _identityLoaded = false;
  Future<_DeviceIdentity>? _identityFuture;

  /// 平台标识（由调用方注入，默认 flutter）。
  final String _platform;

  /// 设备系列（android / ios / phone）。
  final String? _deviceFamily;

  /// 设备型号（如 Pixel 8）。
  final String? _modelIdentifier;

  /// 设备显示名称（如「我的手机」）。
  final String? _clientDisplayName;

  /// 客户端版本。
  final String _clientVersion;

  /// 客户端标识（§2.3 枚举值，由平台决定）。
  final String _clientId;

  /// 客户端模式（§2.3，operator 客户端固定为 ui）。
  final String _clientMode;

  /// 客户端角色（operator）。
  final String _role;

  /// 请求的 operator scope 列表（§2.4）。
  final List<String> _scopes;

  /// 创建 WebSocket Gateway 客户端。
  WsGatewayClient({
    String locale = 'zh-CN',
    String platform = 'flutter',
    String? deviceFamily,
    String? modelIdentifier,
    String? clientDisplayName,
    String clientVersion = '1.0.0',
    String? clientId,
    String clientMode = 'ui',
    String role = 'operator',
    List<String>? scopes,
  }) : _locale = locale,
       _platform = platform,
       _deviceFamily = deviceFamily,
       _modelIdentifier = modelIdentifier,
       _clientDisplayName = clientDisplayName,
       _clientVersion = clientVersion,
       _clientId = clientId ?? ClientIds.forPlatform(platform),
       _clientMode = clientMode,
       _role = role,
       _scopes = scopes ?? operatorScopes;

  /// instanceId → 实例连接
  final Map<String, _InstanceConnection> _connections = {};

  /// 防止同一 instanceId 的重入连接。
  final Set<String> _connecting = {};

  /// 加载或生成设备身份：Ed25519 密钥对。
  ///
  /// **deviceId = SHA256(publicKeyRaw).hex()** — 对齐 docs/technical/api-protocol.md §2.5:
  /// "生成 Ed25519 密钥对, deviceId = SHA256(publicKey)"
  ///
  /// 首次调用时从 [FlutterSecureStorage] 读取密钥对；
  /// 若不存在则生成新的 Ed25519 密钥对并持久化。
  /// 如检测到旧版 ECDSA P-256 密钥对，自动迁移到 Ed25519。
  /// deviceId 不持久化——它总是从 publicKey 实时计算。
  Future<_DeviceIdentity> _ensureDeviceIdentity() async {
    if (_identityLoaded) {
      return _DeviceIdentity(
        deviceId: _deviceId!,
        publicKeyB64: _publicKeyB64,
        seedBytes: _seedBytes,
      );
    }

    // 防止并发调用同时进入加载路径：用 _identityFuture 作为 pending gate，
    // 让后续调用者等待同一个加载操作完成，避免重复生成密钥或 TOCTOU 崩溃。
    if (_identityFuture != null) {
      return _identityFuture!;
    }
    final completer = Completer<_DeviceIdentity>();
    _identityFuture = completer.future;

    try {
      // 1. 尝试加载 Ed25519 密钥对
      final storedSeedB64 = await _secureStorage.read(key: _privateKeyKey);
      final storedPubKeyB64 = await _secureStorage.read(key: _publicKeyKey);

      if (storedSeedB64 != null &&
          storedSeedB64.isNotEmpty &&
          storedPubKeyB64 != null &&
          storedPubKeyB64.isNotEmpty) {
        _seedBytes = base64Url.decode(storedSeedB64);
        _publicKeyB64 = storedPubKeyB64;
        debugPrint('[WsGateway] Loaded existing Ed25519 keypair');
      } else {
        // 2. 检查旧版 ECDSA P-256 密钥（迁移检测）
        final legacySeed = await _secureStorage.read(key: _legacyPrivateKeyKey);
        if (legacySeed != null && legacySeed.isNotEmpty) {
          debugPrint(
            '[WsGateway] Detected legacy ECDSA P-256 keypair — migrating to Ed25519',
          );
          await _secureStorage.delete(key: _legacyPrivateKeyKey);
          await _secureStorage.delete(key: _legacyPublicKeyKey);
        }

        // 3. 生成新 Ed25519 密钥对
        await _generateAndPersistEd25519Keypair();
      }

      // deviceId = SHA256(publicKeyRaw) — 协议要求 §2.5
      final publicKeyBytes = base64Url.decode(_publicKeyB64!);
      _deviceId = sha256.convert(publicKeyBytes).toString();
      debugPrint('[WsGateway] deviceId (SHA256 of publicKey): $_deviceId');

      // _identityLoaded 必须在 _deviceId 赋值之后才能设为 true，
      // 否则快速路径 _DeviceIdentity(deviceId: _deviceId!) 会空指针崩溃。
      _identityLoaded = true;

      final identity = _DeviceIdentity(
        deviceId: _deviceId!,
        publicKeyB64: _publicKeyB64,
        seedBytes: _seedBytes,
      );
      completer.complete(identity);
      return identity;
    } catch (error) {
      _identityLoaded = false;
      completer.completeError(error);
      rethrow;
    } finally {
      _identityFuture = null;
    }
  }

  /// 生成 Ed25519 密钥对并持久化到安全存储。
  Future<void> _generateAndPersistEd25519Keypair() async {
    // generateKey() 返回 KeyPair，内含 privateKey (64B = 32B seed + 32B pubkey)
    // 和 publicKey (32B)。
    final keyPair = ed.generateKey();

    // 提取 32 字节种子用于持久化
    _seedBytes = ed.seed(keyPair.privateKey);
    // 提取 32 字节公钥
    _publicKeyB64 = base64Url.encode(
      Uint8List.fromList(keyPair.publicKey.bytes),
    );

    await _secureStorage.write(
      key: _privateKeyKey,
      value: base64Url.encode(_seedBytes!),
    );
    await _secureStorage.write(key: _publicKeyKey, value: _publicKeyB64);
    debugPrint('[WsGateway] Generated new Ed25519 keypair');
  }

  /// 用设备 Ed25519 私钥对 [v3Payload] 签名，返回 base64url 编码的签名。
  ///
  /// [v3Payload] 由 [buildV3SignaturePayload] 构造。
  Future<String> _signPayload(String v3Payload) async {
    final identity = await _ensureDeviceIdentity();
    // 从种子重建 PrivateKey（ed25519_edwards 的 PrivateKey = 64B seed+pubkey）
    final privateKey = ed.newKeyFromSeed(identity.seedBytes!);
    final message = Uint8List.fromList(v3Payload.codeUnits);

    // sign(PrivateKey, Uint8List) → 64 字节签名
    final sig = ed.sign(privateKey, message);
    return base64Url.encode(sig);
  }

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

      final identity = await _ensureDeviceIdentity();

      final manager = ConnectionManager(
        instanceId: instance.id,
        gatewayUrl: instance.gatewayUrl,
        token: instance.tokenRef,
        deviceId: identity.deviceId,
        devicePublicKey: identity.publicKeyB64,
        signPayload: (v3Payload) => _signPayload(v3Payload),
        deviceFamily: _deviceFamily,
        modelIdentifier: _modelIdentifier,
        clientVersion: _clientVersion,
        platform: _platform,
        clientId: _clientId,
        clientMode: _clientMode,
        role: _role,
        scopes: _scopes,
        clientDisplayName: _clientDisplayName,
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
    final identity = await _ensureDeviceIdentity();
    final testManager = ConnectionManager(
      instanceId: testId,
      gatewayUrl: instance.gatewayUrl,
      token: instance.tokenRef,
      deviceId: identity.deviceId,
      devicePublicKey: identity.publicKeyB64,
      signPayload: (v3Payload) => _signPayload(v3Payload),
      deviceFamily: _deviceFamily,
      modelIdentifier: _modelIdentifier,
      clientVersion: _clientVersion,
      platform: _platform,
      clientId: _clientId,
      clientMode: _clientMode,
      role: _role,
      scopes: _scopes,
      clientDisplayName: _clientDisplayName,
      locale: _locale,
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
// 内部：设备身份数据类
// ============================================================================

class _DeviceIdentity {
  final String deviceId;
  final String? publicKeyB64;
  final Uint8List? seedBytes;
  const _DeviceIdentity({
    required this.deviceId,
    this.publicKeyB64,
    this.seedBytes,
  });
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
