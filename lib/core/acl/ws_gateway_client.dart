import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/models/models.dart';
import '../debug_print_logger.dart';
import '../i_api_logger.dart';
import '../i_logger.dart';
import 'connection_manager.dart';
import 'device_identity.dart';
import 'outbound_request_builder.dart';
import 'gateway_domain_mapper.dart';
import 'gateway_event_processor.dart';
import 'gateway_instance_connection.dart';
import 'gateway_protocol.dart';
import 'i_device_identity_provider.dart';
import 'i_device_token_store.dart';
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
/// 领域对象映射委托给 [GatewayDomainMapper]。
///
/// 每个实例的连接相关资源内聚于 [GatewayInstanceConnection]。
class WsGatewayClient implements IGatewayClient {
  final Uuid _uuid = const Uuid();
  final GatewayDomainMapper _mapper = GatewayDomainMapper();
  final GatewayEventProcessor _eventProcessor;
  final OutboundRequestBuilder _outboundRequestBuilder =
      const OutboundRequestBuilder();
  final IDeviceIdentityProvider _identityProvider;
  final ConnectionConfig _config;
  final ILogger _logger;

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

  /// Optional: structured API/生命周期日志采集 sink (spec §2.3).
  /// Forwarded to every per-instance [ConnectionManager] constructed in
  /// [connect] / [testConnection]. When null (background isolate default),
  /// no logging occurs — the [ApiLogStore] lives in the main isolate only.
  final IApiLogger? _apiLogger;

  /// Optional WebSocket / timer factories — test injection only. Production
  /// leaves them null (ConnectionManager defaults). Passed straight through to
  /// each per-instance [ConnectionManager] constructed in [connect] /
  /// [testConnection].
  final WebSocketChannel Function(Uri)? _webSocketFactory;
  final TimerFactory? _timerFactory;

  /// 创建 WebSocket Gateway 客户端。
  ///
  /// [_identityProvider] 提供 Ed25519 设备身份和签名能力，
  /// 由 DI 容器注入（默认 [Ed25519IdentityProvider]）。
  ///
  /// [config] 提供客户端/设备/认证的静态配置参数，
  /// 由 DI 容器预构建后注入。
  ///
  /// [_webSocketFactory] 和 [_timerFactory] 仅供测试注入，
  /// 生产环境留空即可（委托 [ConnectionManager] 默认行为）。
  ///
  /// [_deviceTokenStore] 持久化 Gateway 签发的 deviceToken；后续重连
  /// 时优先复用缓存令牌（spec §2.2）。当未注入时，退化为每次连接
  /// 都使用 `instance.tokenRef`（每次都走配对流程）。
  WsGatewayClient({
    required this._identityProvider,
    ConnectionConfig? config,
    this._webSocketFactory,
    this._timerFactory,
    this._modelIdentifierLoader,
    this._deviceTokenStore,
    this._apiLogger,
    ILogger? logger,
  }) : _config = config ?? ConnectionConfig(),
       _logger = logger ?? const DebugPrintLogger(),
       _eventProcessor = GatewayEventProcessor(
         uuid: const Uuid(),
         mapper: GatewayDomainMapper(),
         logger: logger ?? const DebugPrintLogger(),
       );

  /// instanceId → 实例连接
  final Map<String, GatewayInstanceConnection> _connections = {};

  /// 防止同一 instanceId 的重入连接。
  final Set<String> _connecting = {};

  /// Prevent use-after-dispose — [connect] returns early when true.
  bool _isDisposed = false;

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
  /// `@visibleForTesting` static seam 模式对齐（`isTestTerminalState`）。
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

  /// 测试缝隙 — 返回 [_sessionToAgentId] 当前条目数。
  ///
  /// 用于验证实例断开后映射被正确清理（防内存泄漏）。只在测试中调用。
  /// 返回 size 而不是整个 map，避免泄露每个 entry 的 sessionKey 字符串。
  @visibleForTesting
  int get sessionToAgentIdSizeForTesting =>
      _eventProcessor.sessionToAgentIdSizeForTesting;

  /// 测试缝隙 — 返回反向索引中的 sessionKey 总数。
  ///
  /// 用于验证失败的 sendMessage 不会泄露反向索引条目（与
  /// [sessionToAgentIdSizeForTesting] 配对，覆盖两个映射）。只在测试中调用。
  @visibleForTesting
  int get sessionKeysByInstanceSizeForTesting =>
      _eventProcessor.sessionKeysByInstanceSizeForTesting;

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
        apiLogger: _apiLogger,
      );

      // 复用已有的流控制器（若有），否则创建新的
      var conn = _connections[instance.id];
      if (conn == null) {
        conn = GatewayInstanceConnection(
          messageCtrl: StreamController<Message>.broadcast(),
          toolCallCtrl: StreamController<ToolCall>.broadcast(),
          pairingInfoCtrl: StreamController<GatewayPairingInfo?>.broadcast(),
          streamingCtrl: StreamController<StreamingEvent>.broadcast(),
        );
        _connections[instance.id] = conn;
      }
      conn.wire(
        manager: manager,
        onEvent: (event) =>
            _eventProcessor.processEvent(instance.id, conn!, event),
      );

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

    await conn.cleanupManager(emitDisconnected: emitDisconnected);

    // 清理该实例在事件处理器中的 streaming buffer、runId 状态与 session 映射。
    _eventProcessor.cleanupInstance(instanceId);
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

    // PROTOCOL-VERIFY (appendix F, 2026-07-03): chat.send 的 `message` 必须是字符串,
    // 多模态走顶层 `attachments` 数组(元素弱约束,推荐 {mimeType, content: base64, filename?})。
    // Gateway 拒绝 `metadata`(实测 "unexpected property")。图片/文件字节由
    // worker isolate 从 message.content(本地路径)读取 base64 并直接完成序列化，
    // 主 isolate 只接收最终 JSON 字符串与字节数，避免大 base64 在主 isolate 上
    // jsonEncode + utf8.encode 造成 jank。
    final requestId = _uuid.v4();
    final outbound = await _outboundRequestBuilder.buildChatSendRequest(
      message: message,
      sessionKey: sessionKey,
      idempotencyKey: message.clientId,
      requestId: requestId,
    );

    final ResponseFrame res;
    try {
      res = await manager.sendRawRequest(
        id: requestId,
        requestJson: outbound.requestJson,
        payloadSize: outbound.payloadSize,
        method: Methods.chatSend,
      );
    } on BufferOverflowException catch (e) {
      // F-4: 在途缓冲满（reject-new，spec §2.2 maxBufferedBytes）。把 ACL
      // 内部的背压信号翻译成 [BufferOverflowNotice] 推上诊断流，UI 层据此
      // 弹「网关繁忙，将自动重试」toast —— 避免用户面对无说明的 FAILED。
      //
      // 异常仍 rethrow：[SendMessageUseCase.execute] / [.retry] 的 catch 照常
      // 标 FAILED（可重试），OutboxProcessor 在缓冲排空后自动重发，不丢数据。
      // reject-new 在 sendRequest 内部发生于 _channel.sink.add 之前、completer
      // 注册之前，故无 socket 写入 / pending 条目需清理；_sessionToAgentId 与
      // 反向索引只在下方 res.ok 成功路径写入，此处早退不泄漏映射（由
      // ws_gateway_client_test "sendMessage failure does not leak" 覆盖）。
      //
      // 诊断面包屑：异常携带 buffered/attempted/max 字节数，但下游每个 catch
      // （execute / retry）都丢弃了它们。这里是在作用域内能读到这些字段的
      // 唯一站点 —— 留一行 debugPrint，让用户上报「网关繁忙」时有可诊断的
      // 日志轨迹。行为不变（仍 emit notice + rethrow）。
      _logger.error(
        '[WsGateway] Buffer overflow on sendMessage for $instanceId: '
        'buffered=${e.bufferedBytes}, attempted=${e.attemptedSize}, '
        'max=${e.maxSize}',
      );
      final conn = _connections[instanceId];
      if (conn != null && !conn.gatewayNoticeCtrl.isClosed) {
        conn.gatewayNoticeCtrl.add(BufferOverflowNotice());
      }
      rethrow;
    }

    if (!res.ok) {
      throw Exception(
        'Message send failed: ${res.error?.message ?? "unknown"}',
      );
    }

    // chat.send 响应中没有 serverId，用 runId 作为追踪标识
    final payload = res.payload ?? {};
    final serverRunId = payload['runId'] as String?;
    final serverId = serverRunId ?? _uuid.v4();
    final timestamp =
        payload['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    // Populate the sessionKey → agentId mapping ONLY on a successful send.
    // Event dispatch for any delta still resolves via string-parsing fallback
    // (`split(':')[1]`), so this is behavior-preserving on the success path.
    // The processor owns the mapping and turn-boundary reset; deferring the
    // write to the success path means a failed send leaves nothing behind.
    _eventProcessor.registerSend(
      instanceId: instanceId,
      sessionKey: sessionKey,
      agentId: agentId,
      runId: serverRunId,
    );

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
    return agents.map((json) => _mapper.parseAgent(json, instanceId)).toList();
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
            .map((json) => _mapper.parseMessage(json))
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
      deviceTokenStore: _deviceTokenStore,
      apiLogger: _apiLogger,
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
      _logger.error('[WsGateway] Connection test failed: $error', stackTrace);
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
  Stream<GatewayNotice> gatewayNoticeStream(String instanceId) {
    // Gap #6: 统一诊断流（sealed union, spec §2.7）。Use
    // _getOrCreateControllers so callers can subscribe even before connect()
    // (e.g. UI eagerly wires a toast listener at app start). Controller 元素
    // 类型为 GatewayNotice——后续新诊断事件直接 .add() 入此 controller。
    return _getOrCreateControllers(instanceId).gatewayNoticeCtrl.stream;
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _connecting.clear();

    for (final conn in _connections.values) {
      await conn.dispose();
    }
    _connections.clear();
    _eventProcessor.dispose();
  }

  // ---------------------------------------------------------------------------
  // 内部：辅助方法
  // ---------------------------------------------------------------------------

  @visibleForTesting
  static bool isTestTerminalState(GatewayConnectionState state) {
    // Test-level concept of "settled" — includes connected (a steady state
    // from a test's perspective), unlike GatewayConnectionState.isTerminal
    // which excludes connected (it can transition to recovering on error).
    return state.isTerminal || state == GatewayConnectionState.connected;
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

  GatewayInstanceConnection _getOrCreateControllers(String instanceId) {
    return _connections.putIfAbsent(
      instanceId,
      () => GatewayInstanceConnection(
        messageCtrl: StreamController<Message>.broadcast(),
        toolCallCtrl: StreamController<ToolCall>.broadcast(),
        pairingInfoCtrl: StreamController<GatewayPairingInfo?>.broadcast(),
        streamingCtrl: StreamController<StreamingEvent>.broadcast(),
      ),
    );
  }
}
