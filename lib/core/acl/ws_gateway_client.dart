import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/models/models.dart';
import '../debug_print_logger.dart';
import '../i_logger.dart';
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
/// 领域对象映射由本类完成（_parseAgent, _parseMessage）。
///
/// 每个实例的连接相关资源内聚于 [_InstanceConnection]。
class WsGatewayClient implements IGatewayClient {
  final Uuid _uuid = const Uuid();
  final IDeviceIdentityProvider _identityProvider;
  final ConnectionConfig _config;
  final ILogger _logger;

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
    ILogger? logger,
  }) : _config = config ?? ConnectionConfig(),
       _logger = logger ?? const DebugPrintLogger();

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

  /// Active server-assigned `runId` for the current turn, per session.
  ///
  /// Key format: `$instanceId:$sessionKey` (same as [_streamingBuffers]).
  /// `runId` is the server-authoritative per-turn identifier (parsed on
  /// `chat`/`agent` events and returned by the `chat.send` response).
  ///
  /// A streaming buffer belongs to exactly one turn. `sessionKey` is
  /// stable across turns for the same agent, so without this pointer a
  /// turn aborted before its `lifecycle.end`/`chat.final` (e.g. a
  /// graceful-shutdown reconnect, which lives inside `ConnectionManager`
  /// and never reaches `_cleanup`) leaves a non-empty buffer that the
  /// next turn's deltas `.append()` to — corrupting the reply with
  /// `stale_turn1 + turn2`.
  ///
  /// When the `runId` for a session changes, the prior buffer is
  /// irrecoverably stale and is dropped (see [_resetTurnForSession]).
  /// A missing `runId` (older Gateways) leaves this map untouched — the
  /// degradation path preserves the no-runId behavior pinned by the
  /// "chat.delta arriving before lifecycle.start is not dropped" test.
  final Map<String, String> _activeRunIdBySession = {};

  /// Explicit mapping from sessionKey → remoteAgentId.
  ///
  /// Populated by [sendMessage] (chat.send) response handler.
  /// Events dispatch look up agentId via this table instead
  /// of parsing the colon-separated sessionKey string — that heuristic is
  /// unreliable when Gateway uses alternative sessionKey formats.
  ///
  /// Keys are bare sessionKeys (e.g. `agent:r-1:main`), NOT prefixed with
  /// instanceId. The reverse index [_sessionKeysByInstance] tracks which
  /// keys belong to which instance so [_cleanup] can drop the right ones
  /// when an instance is removed — see the memory-leak fix in _cleanup.
  final Map<String, String> _sessionToAgentId = {};

  /// Reverse index: instanceId → set of sessionKeys owned by that instance.
  ///
  /// Used by [_cleanup] to remove the instance's entries from
  /// [_sessionToAgentId]. Without this index, _sessionToAgentId would
  /// only be cleared in [dispose], leaking entries across instance
  /// churn (add → remove → add → …).
  final Map<String, Set<String>> _sessionKeysByInstance = {};

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

  /// 测试缝隙 — 返回 [_sessionToAgentId] 当前条目数。
  ///
  /// 用于验证实例断开后映射被正确清理（防内存泄漏）。只在测试中调用。
  /// 返回 size 而不是整个 map，避免泄露每个 entry 的 sessionKey 字符串。
  @visibleForTesting
  int get sessionToAgentIdSizeForTesting => _sessionToAgentId.length;

  /// 测试缝隙 — 返回 [_sessionKeysByInstance] 反向索引中的 sessionKey 总数。
  ///
  /// 用于验证失败的 sendMessage 不会泄露反向索引条目（与
  /// [sessionToAgentIdSizeForTesting] 配对，覆盖两个映射）。只在测试中调用。
  @visibleForTesting
  int get sessionKeysByInstanceSizeForTesting =>
      _sessionKeysByInstance.values.fold<int>(0, (n, s) => n + s.length);

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
    _activeRunIdBySession.removeWhere(
      (key, _) => key.startsWith('$instanceId:'),
    );

    // _sessionToAgentId uses BARE sessionKeys (no instanceId prefix) — it
    // would never match the prefix filter above.  Drop the entries via
    // the reverse index to avoid leaking across instance churn (the map
    // was previously only cleared in dispose(), so add→remove→add→…
    // grew it unbounded).  Regression test:
    // ws_gateway_client_test.dart "disconnect clears _sessionToAgentId
    // entries for that instance".
    final ownedKeys = _sessionKeysByInstance.remove(instanceId);
    if (ownedKeys != null) {
      for (final key in ownedKeys) {
        _sessionToAgentId.remove(key);
      }
    }

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

    // PROTOCOL-VERIFY (appendix F, 2026-07-03): chat.send 的 `message` 必须是字符串,
    // 多模态走顶层 `attachments` 数组(元素弱约束,推荐 {mimeType, content: base64, filename?})。
    // Gateway 拒绝 `metadata`(实测 "unexpected property")。图片/文件字节由
    // _readFileBase64 从 message.content(本地路径)读取 base64,DB 只存路径。
    // 大小限制(F.6):图片 <10MB、文件 <5MB,超限 _readFileBase64 抛错 → FAILED。
    final base64Data = await _readFileBase64(message);
    final sendPayload = serializeChatSendPayload(
      message,
      base64Data: base64Data,
    );

    final ResponseFrame res;
    try {
      res = await manager.sendRequest(Methods.chatSend, {
        'sessionKey': sessionKey,
        'message': sendPayload.message,
        'idempotencyKey': message.clientId,
        if (sendPayload.attachments != null)
          'attachments': sendPayload.attachments,
      });
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
        conn.gatewayNoticeCtrl.add(const BufferOverflowNotice());
      }
      rethrow;
    }

    if (!res.ok) {
      throw Exception(
        'Message send failed: ${res.error?.message ?? "unknown"}',
      );
    }

    // Populate the sessionKey → agentId mapping ONLY on a successful send.
    // Writing it before `sendRequest` (the old code) leaked the entry when
    // the await threw or the response was `ok:false` — the entries were
    // never removed until disconnect, and the reverse-index made the leak
    // grow across different failed agents. Deferring the write to the
    // success path means a failed send leaves nothing behind. Event
    // dispatch for any delta still resolves via `_resolveAgentId`'s
    // string-parsing fallback (`split(':')[1]`), so this is
    // behavior-preserving on the success path.
    _sessionToAgentId[sessionKey] = agentId;
    // Reverse-index so _cleanup can remove this entry when the instance
    // disconnects (fixes the memory leak — bare sessionKeys don't match
    // the '$instanceId:' prefix filter used by the other maps).
    (_sessionKeysByInstance[instanceId] ??= {}).add(sessionKey);

    // chat.send 响应中没有 serverId，用 runId 作为追踪标识
    final payload = res.payload ?? {};
    final serverRunId = payload['runId'] as String?;
    final serverId = serverRunId ?? _uuid.v4();
    final timestamp =
        payload['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    // runId turn-token (primary turn boundary): the server assigns runId
    // here, before any chat.delta / lifecycle.start. When present this is
    // the earliest, most reliable turn boundary — drop any lingering
    // buffer / finalized / delta-source state for this session so an
    // aborted prior turn (no lifecycle.end ever arrived — e.g. a mid-turn
    // graceful-shutdown reconnect) cannot corrupt this turn's reply.
    // Only the server-sent value counts; the `_uuid.v4()` fallback above
    // is not server-authoritative and must not be treated as a runId.
    if (serverRunId != null) {
      _resetTurnForSession('$instanceId:$sessionKey', serverRunId);
    }

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
      if (!conn.gatewayNoticeCtrl.isClosed) {
        await conn.gatewayNoticeCtrl.close();
      }
    }
    _connections.clear();
    _streamingBuffers.clear();
    _sessionToAgentId.clear();
    _sessionKeysByInstance.clear();
    _finalizedSessions.clear();
    _deltaSource.clear();
    _activeRunIdBySession.clear();
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
          if (!conn.gatewayNoticeCtrl.isClosed) {
            conn.gatewayNoticeCtrl.add(notice);
          }
        } catch (error, stackTrace) {
          _logger.error(
            '[WsGateway] Failed to handle payload.large for $instanceId: '
            '$error',
            stackTrace,
          );
        }

      default:
        break;
    }
  }

  /// Drop all per-session streaming state for [bufferKey] and stamp [runId]
  /// as the active turn.
  ///
  /// Called at a turn boundary — most authoritatively from the `chat.send`
  /// response (the server assigns `runId` before any deltas), and as a
  /// fallback from `lifecycle.start` / a differing-`runId` delta when a
  /// turn begins without a fresh `chat.send`. Dropping the buffer here
  /// prevents an aborted prior turn (no `lifecycle.end`/`chat.final`
  /// ever arrived) from corrupting the new turn's reply.
  ///
  /// [runId] must be the server-sent value (non-null). Callers gate on
  /// null themselves so the no-`runId` degradation path is preserved.
  void _resetTurnForSession(String bufferKey, String runId) {
    _streamingBuffers.remove(bufferKey);
    _finalizedSessions.remove(bufferKey);
    _deltaSource.remove(bufferKey);
    _activeRunIdBySession[bufferKey] = runId;
  }

  /// Record [runId] as the active turn for [bufferKey].
  ///
  /// - [runId] `null` → no-op (degradation for older Gateways that don't
  ///   send `runId`; current behavior is preserved).
  /// - [runId] differs from the active turn → turn boundary: drop the
  ///   prior turn's streaming state via [_resetTurnForSession].
  /// - [runId] equals the active turn (or none is recorded yet) → just
  ///   stamp it as active; buffer is untouched.
  void _applyRunId(String bufferKey, String? runId) {
    if (runId == null) return;
    final active = _activeRunIdBySession[bufferKey];
    if (active != null && active != runId) {
      _resetTurnForSession(bufferKey, runId);
    } else {
      _activeRunIdBySession[bufferKey] = runId;
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
          // runId turn-token: a differing runId means a new turn began
          // without a fresh chat.send (agent self-branch / tool
          // continuation). Drop the stale prior-turn buffer before
          // appending. Absent runId → degradation (keep current behavior).
          _applyRunId(bufferKey, event.runId);

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
          _logger.error(
            '[WsGateway] Failed to handle chat final: $error',
            stackTrace,
          );
        }
        _streamingBuffers.remove(bufferKey);
        // Turn complete — clear the active runId so the next turn starts
        // clean (also reset by _resetTurnForSession on the next boundary).
        _activeRunIdBySession.remove(bufferKey);

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
              _logger.error(
                '[WsGateway] Failed to parse tool result: $error',
                stackTrace,
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
              _logger.error(
                '[WsGateway] Failed to parse tool call: $error',
                stackTrace,
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
            // runId turn-token (see _onChatEvent delta branch): a differing
            // runId signals a new turn began without a fresh chat.send.
            _applyRunId(bufferKey, event.runId);

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
            // runId turn-token (secondary boundary): if the server emits
            // a lifecycle.start whose runId differs from the active turn,
            // a new turn began — drop the stale prior-turn buffer. This
            // is the case Fix 7's conditional clear below could not
            // handle (it only cleared empty buffers). Same/absent runId
            // falls through to the existing conditional clear, preserving
            // the "chat.delta arriving before lifecycle.start is not
            // dropped" regression test.
            _applyRunId(bufferKey, event.runId);

            // A new agent run has begun — clear the previous turn's
            // dedup token so _finalizedSessions does not permanently
            // block subsequent messages to the same agent (the key is
            // `$instanceId:$sessionKey` which is identical across turns).
            // This also allows the next lifecycle.end or chat.final for
            // this session to process normally.
            _finalizedSessions.remove(bufferKey);
            _deltaSource.remove(bufferKey);

            // Fix 7 (post-Fix-1 audit): conditionally clear the
            // streaming buffer. If a `chat.delta` event arrived in
            // the SAME microtask as this `lifecycle.start` (server
            // misorder), the buffer was populated by that delta.
            // Clearing it unconditionally would drop the first chunk
            // of the new turn on the floor. Only clear if the buffer
            // is empty — a non-empty buffer is either in-flight data
            // for the new turn or stale data from a prior turn that
            // never sent an end event (rare; the next chat.final or
            // lifecycle.end will consume it).
            //
            // Regression test: ws_gateway_client_test.dart
            // "chat.delta arriving before lifecycle.start is not
            // dropped".
            final existing = _streamingBuffers[bufferKey];
            if (existing == null || existing.text.isEmpty) {
              _streamingBuffers.remove(bufferKey);
            }
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

            // Turn complete — clear the active runId (mirrors chat.final).
            _activeRunIdBySession.remove(bufferKey);

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
        _logger.error(
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
    String? nonEmpty(String? s) =>
        (s != null && s.trim().isNotEmpty) ? s.trim() : null;
    final name =
        nonEmpty(json['name'] as String?) ??
        nonEmpty(identity?['name'] as String?) ??
        remoteId;

    // Agent description fallback chain:
    //   json['description'] → identity.theme → identity.description
    //
    // 真实 Gateway 的 agents.list API 不返回顶层 description（API 简化版，
    // 仅含路由必要字段）；配置 schema 支持 description（openclaw config get
    // agents.list 可查完整结构）。兜底到 identity.theme（部分 agent 的角色描述
    // 字段，jvsclaw/xinqing/zhishi 等已配）和 identity.description（未来字段
    // 预留）。**不再**回退到 identity.name —— identity.name 是 display name
    // （短名/昵称，如 "Bob"、"行远"），不是角色描述，回退会导致 name/description
    // 在 UI 上完全撞车（这是 9503d5f 引入的 bug，已修复）。
    //
    // 协议文档参考：api-protocol.md §A.6 (probe-verified); §5.2 示意图已过时。
    // ACL gap 记录：docs/technical/acl-protocol-gaps.md → "agents.list 不返回 description"。
    final description =
        nonEmpty(json['description'] as String?) ??
        nonEmpty(identity?['theme'] as String?) ??
        nonEmpty(identity?['description'] as String?);

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

  /// Reads the local attachment file at `message.content` (image/file path)
  /// and returns its base64-encoded bytes. Throws if the path is missing, the
  /// file can't be read, or it exceeds the Gateway's inline-attachment size
  /// limit (appendix F.6: image <10MB, file <5MB) — the caller ([sendMessage])
  /// lets this propagate so the message is marked FAILED.
  ///
  /// Returns null for text/toolCall messages (no file to read).
  Future<String?> _readFileBase64(Message message) async {
    if (!message.isImage && !message.isFile) return null;
    final path = message.content;
    if (path == null || path.isEmpty) {
      throw AttachmentReadException('path missing for ${message.type} message');
    }
    final file = File(path);
    final limit = message.isImage ? 10 * 1024 * 1024 : 5 * 1024 * 1024;
    try {
      // P3 fix: async length (was lengthSync — blocked the isolate), and
      // moved INSIDE the try so a missing file's FileSystemException is
      // caught and rethrown as a typed AttachmentReadException. Previously
      // lengthSync sat OUTSIDE the try → raw FileSystemException bypassed
      // the catch below, and `throw Exception('...$e')` lost the original
      // exception type by wrapping it in a string.
      final size = await file.length();
      if (size > limit) {
        throw AttachmentReadException.tooLarge(
          size: size,
          limit: limit,
          type: message.type,
        );
      }
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } on AttachmentReadException {
      rethrow; // already typed — preserve cause, let it propagate
    } catch (e) {
      _logger.error('[WsGateway] Failed to read attachment $path: $e');
      throw AttachmentReadException.readFailed(path, e);
    }
  }

  Message _parseMessage(Map<String, dynamic> json) {
    final role = _parseMessageRole(json['role'] as String?);
    // Bug #2 (重启错乱): 时间戳归一化为毫秒。Gateway 历史可能用秒级时间戳
    // (doc §5.4 示意图: 1718000000)；与本地消息(DateTime.now().ms, ~1.7e12)
    // 不同量级会导致软匹配 ±60s 永不命中 + 排序错乱。< 1e12 视为秒级(1e12 ms
    // ≈ 2001 年,任何真实毫秒时间戳都 >= 1e12),×1000 归一化。
    final timestamp = _normalizeEpochMs(json['timestamp'] as int?);
    // 响应侧图片捕获(PROTOCOL-VERIFY):若 content 是结构化 blocks 且含 image
    // block,提升 type=image,把 imageUrl 写入 metadata。content 保留文本(作为
    // 图片说明);imagePath getter 靠 imageUrl==null 区分用户本地图 vs Agent 回图,
    // 故无需 null content。详见 extractImageRef。
    final textContent =
        _extractTextContent(json['content']) ??
        _extractTextContent(json['text']);
    final imageRef =
        extractImageRef(json['content']) ?? extractImageRef(json['text']);
    final parsedType = _parseMessageType(json['type'] as String?);
    final type = parsedType == MessageType.toolCall
        ? parsedType
        : (imageRef != null ? MessageType.image : parsedType);
    final incomingMetadata = json['metadata'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['metadata'] as Map<String, dynamic>)
        : <String, dynamic>{};
    if (imageRef != null) {
      incomingMetadata['imageUrl'] = imageRef;
    }
    return Message(
      clientId: json['clientId'] as String? ?? _uuid.v4(),
      serverId: json['serverId'] as String? ?? json['id'] as String?,
      conversationId: json['conversationId'] as String? ?? '',
      agentId: json['agentId'] as String? ?? '',
      role: role,
      content: textContent,
      type: type,
      // Bug #1 (双对号): 入站消息按角色赋状态，不再一律 delivered。
      // 回传/历史中的 user 消息若被标 delivered，右下角会渲染双对号
      // (Icons.done_all)。user 消息最多到 sent（已送达网关）；delivered
      // 保留给 agent/system（已读/已处理）。
      status: role == MessageRole.user
          ? MessageStatus.sent
          : MessageStatus.delivered,
      // Bug #2: gateway 省略 logicalClock 时回退到「消息自身时间戳」(归一化),
      // 而非 DateTime.now()。旧实现让所有历史消息聚到重启时刻 → 错乱。
      // gateway 显式给的 logicalClock 保持原样(不二次猜测,向后兼容)。
      logicalClock:
          json['logicalClock'] as int? ??
          timestamp ??
          DateTime.now().millisecondsSinceEpoch,
      timestamp: timestamp,
      metadata: incomingMetadata.isEmpty ? null : incomingMetadata,
    );
  }

  /// 把可能是秒级的 epoch 时间戳归一化为毫秒。< 1e12 视为秒级(1e12 ms ≈ 2001 年)。
  /// null 透传(null)，由调用方决定兜底。
  int? _normalizeEpochMs(int? value) {
    if (value == null) return null;
    return value < 1000000000000 ? value * 1000 : value;
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

  /// PROTOCOL-VERIFY (appendix F, 2026-07-03): chat.send 的 `message` 必须是字符串,
  /// 多模态走顶层 `attachments` 数组。Gateway 拒绝 content-blocks 形态的 `message`
  /// (实测 "at /message: must be string")与顶层 `metadata`("unexpected property")。
  ///
  /// 返回 record:`(message, attachments?)`。
  /// - text/toolCall → message=content, attachments=null
  /// - image → message=caption(可空), attachments=[{mimeType, content: base64, filename?}]
  ///   无 base64(读文件失败)→ 降级 message="[图片]", attachments=null
  /// - file → message=""(空), attachments=[{mimeType, content: base64, filename?}]
  ///   无 base64 → 降级 message="[文件] name", attachments=null
  ///
  /// ⚠️ attachment 元素字段名 `mimeType` vs `mime` 有歧义(appendix F.2 两处来源不一),
  /// 当前用 `mimeType`(testing-live.md 示例)。生产前需 capture 确认 —— 只改本方法。
  @visibleForTesting
  static ({String message, List<Map<String, dynamic>>? attachments})
  serializeChatSendPayload(Message message, {String? base64Data}) {
    switch (message.type) {
      case MessageType.text:
      case MessageType.toolCall:
        return (message: message.content ?? '', attachments: null);
      case MessageType.image:
        final caption = message.caption ?? '';
        if (base64Data == null) {
          return (
            message: caption.isNotEmpty ? caption : '[图片]',
            attachments: null,
          );
        }
        return (
          message: caption,
          attachments: [_buildAttachment(message, base64Data)],
        );
      case MessageType.file:
        if (base64Data == null) {
          return (
            message: '[文件] ${message.fileName ?? '文件'}',
            attachments: null,
          );
        }
        return (
          message: '',
          attachments: [_buildAttachment(message, base64Data)],
        );
    }
  }

  /// 构造单个 attachment 元素:{mimeType, content: base64, filename?}。
  static Map<String, dynamic> _buildAttachment(
    Message message,
    String base64Data,
  ) {
    final att = <String, dynamic>{
      'mimeType':
          message.mimeType ??
          (message.isImage ? 'image/jpeg' : 'application/octet-stream'),
      'content': base64Data,
    };
    if (message.fileName != null) att['filename'] = message.fileName;
    return att;
  }

  /// PROTOCOL-VERIFY (appendix F.5, 2026-07-03): chat.history 响应的 image block
  /// 实测形态是 `{"type":"image","url":"..."}`(url 在 block 根)。同时防御性兼容
  /// OpenAI `image_url` 嵌套形态。用于 [_parseMessage] 提升入站消息为 image 类型 +
  /// 写 metadata.imageUrl,让 UI 渲染 Agent 回图。
  @visibleForTesting
  static String? extractImageRef(dynamic raw) {
    if (raw is! List) return null;
    for (final block in raw) {
      if (block is! Map<String, dynamic>) continue;
      if (block['type'] == 'image_url') {
        final url = (block['image_url'] as Map?)?['url'];
        if (url is String && url.isNotEmpty) return url;
      } else if (block['type'] == 'image') {
        // F.5 实测:url 直接在 block 根。
        final url = block['url'];
        if (url is String && url.isNotEmpty) return url;
        // 防御性兼容:嵌套在 image:{url}(未见实测,但 extractTextContent 旧测试用过)。
        final img = block['image'];
        if (img is Map) {
          final innerUrl = img['url'];
          if (innerUrl is String && innerUrl.isNotEmpty) return innerUrl;
        }
      }
    }
    return null;
  }

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
  /// logs via [_logger] when resolution fails — keeping the protocol
  /// function free of Flutter/side-effect dependencies.
  String? _resolveAgentId(String sessionKey, Map<String, String> mapping) {
    final result = resolveAgentId(sessionKey, mapping);
    if (result == null) {
      _logger.error(
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
// AttachmentReadException — typed exception for attachment (image/file) read
// failures in the ACL. Replaces the previous `throw Exception('...$e')`
// pattern that lost the original exception type by wrapping it in a string.
// Thrown by [WsGatewayClient._readFileBase64] when:
//   - the attachment path is missing/empty
//   - the file doesn't exist or can't be read (original cause preserved)
//   - the file exceeds the inline-attachment size limit (appendix F.6:
//     image <10MB, file <5MB)
//
// Propagates out of [WsGatewayClient.sendMessage] (the call site sits before
// sendMessage's try block) and is caught by the UseCase layer, which marks
// the message FAILED. Implementing [Exception] preserves backward-compat
// with broad `catch (e)` / `on Exception` handlers in the UseCase.
// ============================================================================

/// Typed exception for attachment read failures. See file-level comment.
class AttachmentReadException implements Exception {
  final String reason;
  final String? path;
  final Object? cause;

  AttachmentReadException(this.reason, {this.path, this.cause});

  /// File size exceeds the inline-attachment limit.
  factory AttachmentReadException.tooLarge({
    required int size,
    required int limit,
    required MessageType type,
  }) {
    return AttachmentReadException(
      'Attachment too large (${size ~/ 1024 ~/ 1024}MB > '
      '${limit ~/ 1024 ~/ 1024}MB limit for $type; see appendix F.6 — '
      'use OSS URL for large files)',
    );
  }

  /// File read failed (missing, permission, I/O). Preserves [cause].
  factory AttachmentReadException.readFailed(String path, Object cause) {
    return AttachmentReadException(
      'Failed to read attachment $path',
      path: path,
      cause: cause,
    );
  }

  @override
  String toString() {
    final p = path != null ? ', path: $path' : '';
    final c = cause != null ? ', cause: $cause' : '';
    return 'AttachmentReadException($reason$p$c)';
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

  /// Gap #6: per-instance diagnostic stream for Gateway `payload.large`
  /// (and future diagnostic) events. Surfaced via
  /// [IGatewayClient.gatewayNoticeStream] so the UI layer can show a
  /// user-visible hint instead of silently failing. Element type is the
  /// sealed [GatewayNotice] union so new subtypes flow without retyping.
  final StreamController<GatewayNotice> gatewayNoticeCtrl =
      StreamController<GatewayNotice>.broadcast();

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
