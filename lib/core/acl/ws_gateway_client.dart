import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/models/models.dart';
import 'connection_manager.dart';
import 'device_identity.dart';
import 'gateway_protocol.dart';
import 'i_device_identity_provider.dart';
import 'i_device_token_store.dart';
import 'i_gateway_client.dart';
import 'replayable_connection_state.dart';

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

  /// Optional: load device model identifier for protocol handshake.
  /// If null (production default when DI hasn't injected a loader), no
  /// `modelIdentifier` is sent in connect params — backward compatible.
  ///
  /// Injected by DI (`loadDeviceModelIdentifier` from
  /// `app/config/device_model_loader.dart`) so production code stays
  /// platform-agnostic and tests can substitute deterministic loaders.
  ///
  /// Loader exceptions are swallowed (Law 8 best-effort) — connect must
  /// never be blocked by device-info read failures.
  final Future<String?> Function()? _modelIdentifierLoader;

  /// Optional: persist the issued deviceToken (差距 #1 fix, spec §2.2).
  /// When null (no DI injection), ConnectionManager falls back to using
  /// the constructor-provided `instance.tokenRef` for every connect —
  /// first-time pairing path on every reconnect, which forces a full
  /// re-pair each time.  Production should always inject.
  final IDeviceTokenStore? _deviceTokenStore;

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
  ///
  /// [deviceTokenStore] 持久化 Gateway 签发的 deviceToken；后续重连
  /// 时优先复用缓存令牌（spec §2.2）。当未注入时，退化为每次连接
  /// 都使用 `instance.tokenRef`（每次都走配对流程）。
  WsGatewayClient({
    required IDeviceIdentityProvider identityProvider,
    ConnectionConfig? config,
    WebSocketChannel Function(Uri)? webSocketFactory,
    TimerFactory? timerFactory,
    Future<String?> Function()? modelIdentifierLoader,
    IDeviceTokenStore? deviceTokenStore,
  }) : _identityProvider = identityProvider,
       _config = config ?? ConnectionConfig(),
       _webSocketFactory = webSocketFactory,
       _timerFactory = timerFactory,
       _modelIdentifierLoader = modelIdentifierLoader,
       _deviceTokenStore = deviceTokenStore;

  /// instanceId → 实例连接
  final Map<String, _InstanceConnection> _connections = {};

  /// 防止同一 instanceId 的重入连接。
  final Set<String> _connecting = {};

  /// Prevent use-after-dispose — [connect] returns early when true.
  bool _isDisposed = false;

  /// Delta 聚合缓冲区: sessionKey → StreamingBuffer。
  /// agent assistant 事件追加 delta，chat final 事件消费后移除。
  final Map<String, StreamingBuffer> _streamingBuffers = {};

  /// Tracks sessions that have already been finalized (Message pushed +
  /// StreamingDone emitted) to prevent duplicate messages when both
  /// chat.final and agent.lifecycle.end arrive for the same session.
  ///
  /// Key format: `$instanceId:$sessionKey` (same as [_streamingBuffers]).
  /// The first handler to `add()` this key processes the session; the
  /// second handler sees the key already present and skips.
  final Set<String> _finalizedSessions = {};

  /// Tracks which event source serves streaming deltas per session.
  /// Value is 'chat' or 'agent'. Prevents duplicate deltas when a Gateway
  /// sends both `chat.delta` and `agent.assistant` events for the same
  /// response — whichever arrives first locks in the source, and deltas
  /// from the other source are dropped.
  final Map<String, String> _deltaSource = {};

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

  /// 解析本次连接尝试的 [ConnectionConfig],可选地调用
  /// [_modelIdentifierLoader] 填充 [ConnectionConfig.modelIdentifier]。
  ///
  /// **Major #3 修复**：原为 `@visibleForTesting` 实例方法,会扩大
  /// WsGatewayClient 的公共 API 表面（外部可合法访问）。改为私有方法
  /// + static seam `resolveConfigForTesting` 暴露给测试,与项目其他
  /// `@visibleForTesting` static seam 模式对齐（`extractTextContent`
  /// / `isTestTerminalState` / `setTestState` / `setTestChannel`）。
  ///
  /// Loader 抛异常或返回 null 都被吞掉:connect 路径始终拿到有效
  /// config,协议层在 `modelIdentifier` 为 null 时自动跳过该字段。
  Future<ConnectionConfig> _resolveEffectiveConfig(
    DeviceIdentity identity,
  ) async {
    final base = _buildConfig(identity);
    final loader = _modelIdentifierLoader;
    if (loader == null) return base;
    try {
      final modelId = await loader();
      return base.copyWith(modelIdentifier: modelId);
    } catch (_) {
      // iron-law-allow: Law8 -- loader 失败不能阻塞 connect
      return base;
    }
  }

  /// 测试缝隙 — 直接调用私有 [_resolveEffectiveConfig] 而不触发 WebSocket。
  ///
  /// 命名与项目惯例对齐（`extractXxx` / `isXxx` / `setXxx`）,无 `debug`
  /// 前缀。仅供 `test/core/acl/ws_gateway_client_test.dart` 使用。
  @visibleForTesting
  static Future<ConnectionConfig> resolveConfigForTesting(
    WsGatewayClient client,
    DeviceIdentity identity,
  ) => client._resolveEffectiveConfig(identity);

  // ---------------------------------------------------------------------------
  // IGatewayClient 实现
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect(Instance instance) async {
    if (_isDisposed) return;
    // 防止同一实例重入连接
    if (_connecting.contains(instance.id)) return;
    _connecting.add(instance.id);

    try {
      if (_connections.containsKey(instance.id)) {
        await _cleanupConnection(instance.id);
        if (_isDisposed) return;
      }

      final identity = await _identityProvider.ensureDeviceIdentity();
      if (_isDisposed) return;
      final config = await _resolveEffectiveConfig(identity);
      // **Minor #3 修复（Step 6 扩展）**：原代码在 L179 后直接构造 ConnectionManager
      // 没有 dispose 守门。用户在 await _resolveEffectiveConfig 期间 dispose client
      // 会导致 manager 被创建但永远不会加入 _connections，泄漏。
      if (_isDisposed) return;

      final manager = ConnectionManager(
        instanceId: instance.id,
        gatewayUrl: instance.gatewayUrl,
        token: instance.tokenRef,
        deviceId: identity.deviceId,
        config: config,
        webSocketFactory: _webSocketFactory,
        timerFactory: _timerFactory,
        deviceTokenStore: _deviceTokenStore,
      );

      // 复用已有的流控制器（若有），否则创建新的
      final conn = _connections.putIfAbsent(
        instance.id,
        () => _InstanceConnection(
          messageCtrl: StreamController<Message>.broadcast(),
          toolCallCtrl: StreamController<ToolCall>.broadcast(),
          pairingInfoCtrl: StreamController<GatewayPairingInfo?>.broadcast(),
          streamingCtrl: StreamController<StreamingEvent>.broadcast(),
        ),
      );
      conn.manager = manager;

      // 订阅连接状态
      conn._stateSub = manager.connectionState.listen(
        conn.connectionState.emit,
      );

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
      // **Minor #3 修复（Step 6 扩展）**：await manager.connect() 是长操作，
      // 用户可能在期间 dispose。manager 已注册到 conn，由 dispose() 清理，
      // 但提前退出可避免对已 dispose client 的流添加事件。
      if (_isDisposed) return;
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

    // Capture-and-null serves as a re-entrancy guard: if another call
    // arrives during an await below, conn.manager will already be null
    // and the call returns immediately.
    final manager = conn.manager;
    if (manager == null) return; // already being cleaned up
    conn.manager = null;

    await conn._eventSub?.cancel();
    conn._eventSub = null;
    await conn._stateSub?.cancel();
    conn._stateSub = null;
    // 清空 last 缓存必须在 _stateSub 取消「之后」、剩余 await（pairingSub
    // 取消、manager.dispose、buffer 清理）「之前」进行：
    //  - 之后：_stateSub 是唯一把旧 manager 的状态事件路由进
    //    conn.connectionState.emit 的通道；取消后旧 manager 不可能再写入
    //    _last，故 clear() 不会被迟到的 emit 重新污染。
    //  - 之前：manager.dispose()（关闭 WebSocket，可达毫秒级）等 await 期间
    //    若有晚订阅者（如正在打开的 ChatViewModel）调用
    //    connectionStateStream，_last 仍是 connected → 会拿到陈旧 connected
    //    seed，而真实底层 manager 已死。提前 clear() 关闭这个窗口。
    conn.connectionState.clear();
    await conn._pairingSub?.cancel();
    conn._pairingSub = null;
    await manager.dispose();

    // 清理该实例相关的 streaming buffer，防止重连时旧 session 的
    // 聚合文本污染新 session。Keys are scoped as '$instanceId:$sessionKey'.
    _streamingBuffers.removeWhere((key, _) => key.startsWith('$instanceId:'));
    _finalizedSessions.removeWhere((key) => key.startsWith('$instanceId:'));
    _deltaSource.removeWhere((key, _) => key.startsWith('$instanceId:'));

    if (emitDisconnected) {
      conn.connectionState.emit(GatewayConnectionState.disconnected);
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

    // Gateway 协议要求 sessionKey（格式 agent:{agentId}:main），
    // 而非 agentId。对齐 chat.send 的 sessionKey 构造方式。
    final sessionKey = 'agent:$agentId:main';
    final params = <String, dynamic>{'sessionKey': sessionKey, 'limit': limit};
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
    // Bug #2 fix: server spec uses 'cursor' (docs/technical/api-protocol.md
    // §5.4) but the client used to only read 'nextCursor', causing pagination
    // to deadlock at page 2. Read 'nextCursor' first (forward-compat with
    // future Gateway versions) and fall back to 'cursor'.
    final p = res.payload;
    final nextCursor = p?['nextCursor'] as String? ?? p?['cursor'] as String?;

    return (messages: messages, nextCursor: nextCursor);
  }

  /// 轮换当前实例的 cached deviceToken。
  ///
  /// 成功时把 Gateway 返回的新 token 持久化到 IDeviceTokenStore。
  Future<void> rotateDeviceToken(String instanceId) async {
    final manager = _requireManager(instanceId);
    final res = await manager.sendRequest(Methods.deviceTokenRotate, const {});
    if (!res.ok) {
      throw Exception(
        'Device token rotate failed: ${res.error?.message ?? "unknown"}',
      );
    }
    final token =
        res.payload?['deviceToken'] as String? ??
        res.payload?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('device.token.rotate response missing deviceToken');
    }
    await _deviceTokenStore?.save(instanceId, token);
  }

  /// 撤销当前实例的 cached deviceToken。
  ///
  /// 成功时从 IDeviceTokenStore 删除本实例 token。
  Future<void> revokeDeviceToken(String instanceId) async {
    final manager = _requireManager(instanceId);
    final res = await manager.sendRequest(Methods.deviceTokenRevoke, const {});
    if (!res.ok) {
      throw Exception(
        'Device token revoke failed: ${res.error?.message ?? "unknown"}',
      );
    }
    await _deviceTokenStore?.delete(instanceId);
  }

  @override
  Future<bool> testConnection(Instance instance) async {
    final testId = '__test_${instance.id}';
    final identity = await _identityProvider.ensureDeviceIdentity();
    // **Minor #3 修复（Step 6 扩展）**：用户在 identity 加载期间 dispose client
    // 会导致 _resolveEffectiveConfig 在 disposed client 上执行（虽然纯函数
    // 安全，但后续构造 ConnectionManager 仍会泄漏）。提前返回。
    if (_isDisposed) return false;
    final config = await _resolveEffectiveConfig(identity);
    // **Minor #3 修复（Step 6 扩展）**：同上，await 期间可能 dispose。
    if (_isDisposed) return false;
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
      // **Minor #3 修复（Step 6 扩展）**：await testManager.connect() 是长操作。
      // 如果用户在期间 dispose client，后续 stateFuture 等待无意义。
      if (_isDisposed) return false;

      final finalState = await stateFuture.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('State wait timed out'),
      );
      // **Minor #3 修复（Step 6 扩展）**：stateFuture 等待期间 dispose。
      if (_isDisposed) return false;

      return finalState == GatewayConnectionState.connected;
    } catch (error, stackTrace) {
      debugPrint('[WsGateway] Connection test failed: $error\n$stackTrace');
      return false;
    } finally {
      // testManager 是函数本地变量，无论 _isDisposed 都必须 dispose —
      // 它不属于 _connections，外部 dispose() 不会清理它。
      await testManager.dispose();
    }
  }

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) {
    // Seed 策略详见 [ReplayableConnectionState]。
    return _getOrCreateControllers(instanceId).connectionState.stream;
  }

  @override
  void resetConnectionState(String instanceId) {
    final conn = _connections[instanceId];
    if (conn != null) {
      // 经过封装以保持 last 缓存与广播事件原子同步 —— 直接 ctrl.add 会
      // 绕过缓存，让 connected 实例被 reset 后新订阅者拿到陈旧 connected。
      conn.connectionState.emit(GatewayConnectionState.disconnected);
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
  Stream<LargePayloadNotice> largePayloadNoticeStream(String instanceId) {
    // Gap #6: diagnostic stream for over-sized payloads (spec §2.7).
    // Use _getOrCreateControllers so callers can subscribe even before
    // connect() (e.g. UI eagerly wires a SnackBar listener at app start).
    return _getOrCreateControllers(instanceId).largePayloadCtrl.stream;
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _connecting.clear();

    for (final conn in _connections.values) {
      // Capture-and-null guard — same pattern as _cleanup().
      final manager = conn.manager;
      if (manager != null) {
        conn.manager = null;
        await conn._eventSub?.cancel();
        await conn._stateSub?.cancel();
        await conn._pairingSub?.cancel();
        await manager.dispose();
      }
      await conn.connectionState.dispose();
      if (!conn.messageCtrl.isClosed) {
        await conn.messageCtrl.close();
      }
      if (!conn.toolCallCtrl.isClosed) {
        await conn.toolCallCtrl.close();
      }
      if (!conn.pairingInfoCtrl.isClosed) {
        await conn.pairingInfoCtrl.close();
      }
      if (!conn.streamingCtrl.isClosed) {
        await conn.streamingCtrl.close();
      }
      if (!conn.largePayloadCtrl.isClosed) {
        await conn.largePayloadCtrl.close();
      }
    }
    _connections.clear();
    _streamingBuffers.clear();
    _sessionToAgentId.clear();
    _finalizedSessions.clear();
    _deltaSource.clear();
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

      case Events.payloadLarge:
        // Gap #6: Gateway told us we sent an over-sized payload. Surface
        // it on the diagnostic stream so the UI can show a user-visible
        // hint instead of silently dropping the message. Wrap in try/catch
        // so a downstream listener exception doesn't break the router
        // (which would also affect chat/agent events on the same channel).
        try {
          final notice = parseLargePayloadEvent(payload);
          if (!conn.largePayloadCtrl.isClosed) {
            conn.largePayloadCtrl.add(notice);
          }
        } catch (error, stackTrace) {
          debugPrint(
            '[WsGateway] Failed to handle payload.large for $instanceId: '
            '$error\n$stackTrace',
          );
        }

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
          // Dedup: if agent source already locked for this session, skip
          final source = _deltaSource.putIfAbsent(bufferKey, () => 'chat');
          if (source != 'chat') break;

          // Resolve agentId from sessionKey (explicit mapping → string parse)
          final agentId = _resolveAgentId(event.sessionKey, _sessionToAgentId);
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

        // Coordinate with agent.lifecycle.end — only one handler per
        // session may finalize (push Message + StreamingDone) to prevent
        // duplicate messages when a v3 Gateway sends both event types.
        if (!_finalizedSessions.add(bufferKey)) {
          _streamingBuffers.remove(bufferKey);
          return;
        }

        String? agentId;

        try {
          final msgJson = event.message;
          agentId =
              msgJson?['agentId'] as String? ??
              _resolveAgentId(event.sessionKey, _sessionToAgentId);

          if (msgJson != null) {
            // chat final event 自带完整 message，直接解析
            final message = _parseMessage(msgJson);
            conn.messageCtrl.add(message);
          } else {
            // 没有 message 对象时，用聚合文本构建
            final buffer = _streamingBuffers.remove(bufferKey);
            if (buffer != null && buffer.text.isNotEmpty) {
              conn.messageCtrl.add(
                _buildAgentFallbackMessage(agentId ?? '', buffer.text),
              );
            }
          }
        } catch (error, stackTrace) {
          debugPrint(
            '[WsGateway] Failed to handle chat final: $error\n$stackTrace',
          );
        }
        _streamingBuffers.remove(bufferKey);

        // Notify UI that streaming is complete — only when we have
        // a resolvable agentId; otherwise ChatViewModel silently drops
        // StreamingDone('') and a pending _flushTimer republishes the
        // stale buffer as a ghost bubble.
        if (agentId != null && !conn.streamingCtrl.isClosed) {
          conn.streamingCtrl.add(StreamingDone(agentId: agentId));
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
      case AgentStreamType.assistant:
        // v3 "message" / v4 "assistant" — semantically equivalent delta
        // streaming.  Both carry delta text in data.delta.  Push to UI
        // AND accumulate in buffer for fallback message construction
        // (v3 Gateway may send only agent events, no chat events).
        {
          final delta = event.data['delta'] as String?;
          if (delta != null && delta.isNotEmpty) {
            // Dedup: if chat source already locked for this session, skip
            final source = _deltaSource.putIfAbsent(bufferKey, () => 'agent');
            if (source != 'agent') break;

            final agentId = _resolveAgentId(
              event.sessionKey,
              _sessionToAgentId,
            );
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

      case AgentStreamType.lifecycle:
        // Gateway v3 protocol: lifecycle events signal agent run boundaries.
        {
          final phase = event.data['phase'] as String?;
          if (phase == 'start') {
            // A new agent run has begun — clear the previous turn's
            // dedup token so _finalizedSessions does not permanently
            // block subsequent messages to the same agent (the key is
            // `$instanceId:$sessionKey` which is identical across turns).
            // This also allows the next lifecycle.end or chat.final for
            // this session to process normally.
            _finalizedSessions.remove(bufferKey);
            _streamingBuffers.remove(bufferKey);
            _deltaSource.remove(bufferKey);
          } else if (phase == 'end') {
            // Coordinate with chat.final — only one handler per session
            // may finalize, preventing duplicate messages when a v3
            // Gateway sends both chat.final and agent.lifecycle.end.
            //
            // IMPORTANT: _finalizedSessions.add() must come AFTER the
            // buffer emptiness guard, not before.  If lifecycle.end
            // arrives without prior deltas (empty buffer), marking the
            // session as finalized here would cause chat.final — which
            // carries the complete msgJson — to see the key already
            // present and silently discard the full agent reply.
            final agentId = _resolveAgentId(
              event.sessionKey,
              _sessionToAgentId,
            );
            // Build final message from accumulated buffer.
            // Guard against empty buffer — matches _onChatEvent fallback
            // (line 476) to prevent empty agent bubbles when no deltas
            // were accumulated or chat.final already consumed the buffer.
            final buffer = _streamingBuffers.remove(bufferKey);
            if (buffer == null || buffer.text.isEmpty) break;
            if (!_finalizedSessions.add(bufferKey)) break;

            if (!conn.messageCtrl.isClosed) {
              conn.messageCtrl.add(
                _buildAgentFallbackMessage(agentId ?? '', buffer.text),
              );
            }
            // Notify UI that streaming is complete — only when we have
            // a resolvable agentId; otherwise ChatViewModel silently
            // drops StreamingDone('') and a pending _flushTimer
            // republishes the stale buffer as a ghost bubble.
            if (agentId != null && !conn.streamingCtrl.isClosed) {
              conn.streamingCtrl.add(StreamingDone(agentId: agentId));
            }
          }
        }

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
        final label = cmd['label'] as String? ?? '';
        final payload = cmd['payload'] as String? ?? '';
        final commandId = cmd['id'] as String?;
        quickCommands.add(
          QuickCommand(
            id: commandId != null && commandId.isNotEmpty
                ? commandId
                : '$remoteId:$i:${label.trim()}:${payload.trim()}',
            agentId: remoteId,
            label: label,
            payload: payload,
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
        json['description'] as String? ??
        identity?['description'] as String? ??
        identity?['name'] as String?;

    return Agent(
      localId: _uuid.v4(),
      remoteId: remoteId,
      instanceId: instanceId,
      name: name,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      themeColor: json['themeColor'] as String? ?? '#4F83FF',
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
      content:
          _extractTextContent(json['content']) ??
          _extractTextContent(json['text']),
      type: _parseMessageType(json['type'] as String?),
      status: MessageStatus.delivered,
      logicalClock:
          json['logicalClock'] as int? ?? DateTime.now().millisecondsSinceEpoch,
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

  /// Build a final [Message] from accumulated streaming buffer text.
  ///
  /// Shared by [chat.final] fallback and [agent.lifecycle.end] to avoid
  /// duplicating the 8-field Message literal. Both callers have already
  /// verified [agentId] is resolved (may be empty string if unresolvable)
  /// and [content] is non-empty.
  ///
  /// [conversationId] is intentionally left empty — the ChatViewModel
  /// normalises every message to the canonical SHA-256 hash via
  /// `msg.copyWith(conversationId: _conversationId)`.
  Message _buildAgentFallbackMessage(String agentId, String content) => Message(
    clientId: _uuid.v4(),
    conversationId: '', // normalised by ChatViewModel
    agentId: agentId,
    role: MessageRole.agent,
    content: content,
    type: MessageType.text,
    status: MessageStatus.delivered,
    logicalClock: DateTime.now().millisecondsSinceEpoch,
  );

  /// Extract plain-text content from a Gateway message field.
  ///
  /// The Gateway may send `content` as a plain [String] or as structured
  /// content blocks (`List<Map>` with `type`/`text` keys, OpenAI-style).
  /// This method normalises both formats to a single [String] (or `null`).
  @visibleForTesting
  static String? extractTextContent(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    if (raw is List) {
      if (raw.isEmpty) return null; // [] → null, avoid '[]' literal in content
      // Structured content blocks: [{"type": "text", "text": "..."}, ...]
      // Join all text-type blocks with empty separator.
      if (raw.first is Map) {
        return (raw)
            .whereType<Map<String, dynamic>>()
            .where((b) => b['type'] == 'text')
            .map((b) => (b['text'] as String?) ?? '')
            .join();
      }
      // Simple string list: ["a", "b"]
      // Note: null entries are filtered by whereType<String>();
      // empty strings silently contribute nothing to join('').
      return (raw).whereType<String>().join();
    }
    return raw.toString();
  }

  /// Convenience wrapper around [extractTextContent] for instance usage.
  String? _extractTextContent(dynamic raw) => extractTextContent(raw);

  // ---------------------------------------------------------------------------

  @visibleForTesting
  static bool isTestTerminalState(GatewayConnectionState state) {
    // Test-level concept of "settled" — includes connected (a steady state
    // from a test's perspective), unlike GatewayConnectionState.isTerminal
    // which excludes connected (it can transition to recovering on error).
    return state.isTerminal || state == GatewayConnectionState.connected;
  }

  /// Resolve a [sessionKey] to its remote agent ID, logging on failure.
  ///
  /// Delegates to the pure protocol-level [resolveAgentId] function, then
  /// logs via [debugPrint] when resolution fails — keeping the protocol
  /// function free of Flutter/side-effect dependencies.
  String? _resolveAgentId(String sessionKey, Map<String, String> mapping) {
    final result = resolveAgentId(sessionKey, mapping);
    if (result == null) {
      debugPrint(
        '[WsGateway] Cannot resolve agentId from sessionKey: '
        '"$sessionKey" — mapping contains ${mapping.length} entries',
      );
    }
    return result;
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
  /// Connection manager.  Set to null by [_cleanup] / [dispose] as a
  /// re-entrancy guard — callers check `manager == null` to skip
  /// already-cleaned-up connections.
  ConnectionManager? manager;

  /// 连接状态流 + last 缓存封装。所有发射点必须经过它（详见
  /// [ReplayableConnectionState]），不得直接持有 StreamController 另行 add。
  final ReplayableConnectionState connectionState = ReplayableConnectionState();

  final StreamController<Message> messageCtrl;
  final StreamController<ToolCall> toolCallCtrl;
  final StreamController<GatewayPairingInfo?> pairingInfoCtrl;
  final StreamController<StreamingEvent> streamingCtrl;

  /// Gap #6: per-instance diagnostic stream for `payload.large` events
  /// emitted by the Gateway when the client sends an over-sized payload.
  /// Surfaced via [IGatewayClient.largePayloadNoticeStream] so the UI
  /// layer can show a user-visible hint instead of silently failing.
  final StreamController<LargePayloadNotice> largePayloadCtrl =
      StreamController<LargePayloadNotice>.broadcast();

  StreamSubscription<EventFrame>? _eventSub;
  StreamSubscription<GatewayConnectionState>? _stateSub;
  StreamSubscription<GatewayPairingInfo?>? _pairingSub;

  _InstanceConnection({
    required this.messageCtrl,
    required this.toolCallCtrl,
    required this.pairingInfoCtrl,
    required this.streamingCtrl,
  });
}
