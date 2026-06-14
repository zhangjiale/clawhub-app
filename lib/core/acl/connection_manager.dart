import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

import '../utils/retry_strategy.dart';
import 'i_gateway_client.dart';
import 'gateway_protocol.dart';

/// Injectable timer factory — defaults to [Timer.new].
///
/// Tests inject a fake factory to control time-dependent behavior
/// (tick timeout, reconnect backoff, pairing retry) without real delays.
@visibleForTesting
typedef TimerFactory = Timer Function(Duration, void Function());

/// 管理单个 OpenClaw Gateway 实例的 WebSocket 连接生命周期。
///
/// 实现 OpenClaw Gateway Protocol v4：
/// - 握手：challenge → connect 请求 → hello-ok
/// - 保活：被动监听服务端 `tick` 事件（默认 15s 间隔，2× 超时）
/// - 请求-响应：`req`/`res` 帧 + Completer 关联
/// - 事件：`event` 帧路由到 [events] 流
/// - 重连：指数退避（1→2→4→8→16→30s max）
class ConnectionManager {
  final String _instanceId;
  final String _gatewayUrl;
  final String _token;
  final Uuid _uuid;

  int _reconnectAttempt = 0;
  final RetryStrategy _retryStrategy;

  static const _tickTimeoutMultiplier = 2;

  /// 服务端 tick 间隔（毫秒），由 hello-ok.policy.tickIntervalMs 设置
  int _tickIntervalMs = 15000;

  // --- WebSocket ---
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _incomingSubscription;

  // --- Timers ---
  Timer? _reconnectTimer;
  Timer? _tickTimeoutTimer;
  Timer? _connectTimeoutTimer;

  // --- 请求关联 ---
  /// Map from request ID to pending response completer.
  final Map<String, Completer<ResponseFrame>> _pendingRequests = {};

  // --- 流控制器 ---
  final StreamController<GatewayConnectionState> _connectionStateController =
      StreamController<GatewayConnectionState>.broadcast();

  final StreamController<EventFrame> _eventController =
      StreamController<EventFrame>.broadcast();

  final StreamController<GatewayPairingInfo?> _pairingInfoController =
      StreamController<GatewayPairingInfo?>.broadcast();

  // --- 公开流 ---
  Stream<GatewayConnectionState> get connectionState =>
      _connectionStateController.stream;

  Stream<EventFrame> get events => _eventController.stream;

  /// 配对信息流 — 当连接因 PAIRING_REQUIRED 被拒绝时发出。
  Stream<GatewayPairingInfo?> get pairingInfo => _pairingInfoController.stream;

  GatewayConnectionState _state = GatewayConnectionState.disconnected;
  GatewayConnectionState get state => _state;

  bool _intentionalDisconnect = false;

  /// Serialize _doConnect calls so a reconnect-timer firing cannot race
  /// with a user-triggered connect() while the previous attempt is in flight.
  bool _inDoConnect = false;

  /// 配对重试定时器 — 固定间隔（比通用重连更频繁）。
  Timer? _pairingRetryTimer;
  static const _pairingRetrySeconds = 10;

  final String _deviceId;
  final ConnectionConfig _config;

  /// WebSocket 创建工厂 — 可注入以在测试中替换 WebSocket。
  final WebSocketChannel Function(Uri) _webSocketFactory;

  /// Timer 创建工厂 — 可注入以在测试中控制定时器行为。
  final TimerFactory _createTimer;

  /// challenge nonce，收到 connect.challenge 后设置
  String? _challengeNonce;

  ConnectionManager({
    required String instanceId,
    required String gatewayUrl,
    required String token,
    required String deviceId,
    required ConnectionConfig config,
    Uuid? uuid,
    WebSocketChannel Function(Uri)? webSocketFactory,
    @visibleForTesting TimerFactory? timerFactory,
    RetryStrategy? retryStrategy,
  }) : _retryStrategy = retryStrategy ?? RetryStrategy.networkReconnect,
       _instanceId = instanceId,
       _gatewayUrl = gatewayUrl,
       _token = token,
       _deviceId = deviceId,
       _config = config,
       _webSocketFactory = webSocketFactory ?? WebSocketChannel.connect,
       _createTimer = timerFactory ?? Timer.new,
       _uuid = uuid ?? const Uuid() {
    _connectionStateController.add(GatewayConnectionState.disconnected);
  }

  // ---------------------------------------------------------------------------
  // 公开方法
  // ---------------------------------------------------------------------------

  /// 建立连接：WebSocket 握手 → challenge → connect 请求 → hello-ok。
  Future<void> connect() async {
    if (_state == GatewayConnectionState.connecting ||
        _state == GatewayConnectionState.authenticating) {
      return;
    }

    _intentionalDisconnect = false;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _doConnect();
  }

  /// 断开连接，停止重连和 keepalive。
  ///
  /// 与 [dispose] 的区别：本方法不关闭 StreamController，允许后续调用
  /// [connect] 重用同一个 ConnectionManager 实例。
  /// 当前上层代码（WsGatewayClient）总是走 [dispose] 路径并重建
  /// ConnectionManager，因此本方法暂无调用者，但保留作为公开 API。
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _cancelTimers();
    _failAllPending('Connection closed');
    await _closeWebSocket();
    _setState(GatewayConnectionState.disconnected);
    _reconnectAttempt = 0;
  }

  /// 发送请求并等待响应。
  ///
  /// 返回 [ResponseFrame]（ok=true 时 payload 有值，否则 error 有值）。
  Future<ResponseFrame> sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (_state != GatewayConnectionState.connected) {
      throw NotConnectedException('WebSocket not connected (state: $_state)');
    }

    final id = _uuid.v4();
    final requestJson = buildRequest(id: id, method: method, params: params);
    final completer = Completer<ResponseFrame>();
    _pendingRequests[id] = completer;

    try {
      _channel!.sink.add(requestJson);

      return await completer.future.timeout(
        const Duration(milliseconds: requestTimeoutMs),
        onTimeout: () => throw TimeoutException('Request $method timed out'),
      );
    } finally {
      _pendingRequests.remove(id);
    }
  }

  /// 释放所有资源。
  Future<void> dispose() async {
    _intentionalDisconnect = true;
    _cancelTimers();
    _failAllPending('Connection disposed');
    await _closeWebSocket();
    await _connectionStateController.close();
    await _eventController.close();
    await _pairingInfoController.close();
  }

  // ---------------------------------------------------------------------------
  // 内部：连接与握手
  // ---------------------------------------------------------------------------

  Future<void> _doConnect() async {
    if (_inDoConnect) return;
    _inDoConnect = true;

    _setState(GatewayConnectionState.connecting);

    try {
      final originalUri = Uri.parse(_gatewayUrl);
      // Validate the scheme early — web_socket_channel wraps permanent
      // configuration errors (wrong scheme, invalid host) as
      // WebSocketChannelException, indistinguishable from transient
      // network errors.  Catching bad schemes here ensures they are
      // treated as permanent (authFailed / no reconnect).
      if (originalUri.scheme != 'ws' && originalUri.scheme != 'wss') {
        throw FormatException(
          'Invalid WebSocket scheme "${originalUri.scheme}". '
          'Only ws: and wss: are supported.',
          _gatewayUrl,
        );
      }
      // 对齐 docs/technical/api-protocol.md §2.1–2.2：
      // Gateway 在 WebSocket 握手阶段通过 URL query 验证 token，
      // 不在握手中携带 token 会导致连接被拒绝。
      final uri = originalUri.replace(
        queryParameters: {...originalUri.queryParameters, 'token': _token},
      );
      final ws = _webSocketFactory(uri);
      await ws.ready.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('WebSocket handshake timed out');
        },
      );

      _channel = ws;
      _setState(GatewayConnectionState.authenticating);

      _incomingSubscription = _channel!.stream.listen(
        _onIncomingData,
        onError: _onConnectionError,
        onDone: _onConnectionDone,
        cancelOnError: false,
      );

      // 握手总超时 15 秒
      _connectTimeoutTimer = _createTimer(const Duration(seconds: 15), () {
        if (_state == GatewayConnectionState.authenticating) {
          debugPrint('[CM] Connect handshake timeout for $_instanceId');
          _handleAuthFailure('Handshake timeout');
        }
      });
    } on FormatException catch (error, stackTrace) {
      // URL 格式错误是永久性配置问题，不应重连
      debugPrint('[CM] Bad gateway URL for $_instanceId: $error\n$stackTrace');
      _handleAuthFailure('Bad gateway URL: $error');
    } on WebSocketChannelException catch (error, stackTrace) {
      // DNS resolution failures, connection refused, TLS handshake timeouts,
      // and other transport-level errors are transient — treat as recoverable
      // network failures.
      debugPrint(
        '[CM] WebSocket channel error for $_instanceId: $error\n$stackTrace',
      );
      _setState(GatewayConnectionState.disconnected);
      _scheduleReconnect();
    } catch (error, stackTrace) {
      debugPrint('[CM] Connect failed for $_instanceId: $error\n$stackTrace');
      _setState(GatewayConnectionState.disconnected);
      _scheduleReconnect();
    } finally {
      _inDoConnect = false;
    }
  }

  void _onIncomingData(dynamic data) {
    try {
      final raw = data as String;
      final frame = parseFrame(raw);

      switch (frame) {
        case ResponseFrame(:final id, :final ok):
          if (!ok) {
            debugPrint('[CM] Incoming ERROR response — id=$id, raw=$raw');
          }
          final completer = _pendingRequests.remove(id);
          if (completer != null && !completer.isCompleted) {
            completer.complete(frame);
          }

        case EventFrame(:final event, :final payload):
          _handleEvent(event, payload);
      }
    } catch (error, stackTrace) {
      debugPrint('[CM] Failed to handle incoming data: $error\n$stackTrace');
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：事件处理
  // ---------------------------------------------------------------------------

  void _handleEvent(String event, Map<String, dynamic>? payload) {
    switch (event) {
      case Events.connectChallenge:
        onConnectChallenge(payload).catchError((error, stackTrace) {
          debugPrint(
            '[CM] Unhandled error in onConnectChallenge: $error\n$stackTrace',
          );
        });

      case Events.tick:
        _resetTickTimeout();

      case Events.shutdown:
        debugPrint('[CM] Gateway shutdown for $_instanceId');
        _setState(GatewayConnectionState.disconnected);

      case Events.chat:
      case Events.agent:
      case Events.presence:
      case Events.health:
        // Route application-level events to the upper layer (WsGatewayClient).
        // ConnectionManager handles only protocol lifecycle events
        // (challenge, tick, shutdown); business events are forwarded as-is.
        _eventController.add(EventFrame(event: event, payload: payload));

      default:
        // Forward-compatibility: unrecognized event types (future Gateway
        // protocol extensions) are forwarded upstream so WsGatewayClient
        // can handle them or log them.
        _eventController.add(EventFrame(event: event, payload: payload));
    }
  }

  @visibleForTesting
  Future<void> onConnectChallenge(Map<String, dynamic>? payload) async {
    debugPrint('[CM] Received connect.challenge for $_instanceId');

    // 从 challenge 中提取 nonce
    _challengeNonce = payload?['nonce'] as String?;

    // 签名 nonce（如果设备密钥可用）
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    String? signature;
    if (_config.signPayload != null && _challengeNonce != null) {
      try {
        // 构造 V3 签名 payload（§2.5）
        final v3Payload = buildV3SignaturePayload(
          deviceId: _deviceId,
          clientId: _config.clientId,
          clientMode: _config.clientMode,
          role: _config.role,
          scopes: _config.scopes,
          signedAtMs: nowMs,
          token: _token,
          nonce: _challengeNonce!,
          platform: _config.platform,
          deviceFamily: _config.deviceFamily ?? 'phone',
        );
        signature = await _config.signPayload!(v3Payload);
        debugPrint('[CM] Signed V3 challenge payload');
      } catch (error, stackTrace) {
        debugPrint('[CM] Failed to sign V3 payload: $error\n$stackTrace');
      }
    }

    // Guard: connection may have been closed/timed out during async signing.
    // _closeWebSocket() sets _channel=null; _onConnectionDone changes _state
    // away from authenticating. In either case, abort — don't write to a
    // stale/null channel or leak a completer.
    if (_channel == null || _state != GatewayConnectionState.authenticating) {
      debugPrint('[CM] Connection changed during challenge signing, aborting');
      return;
    }

    final id = _uuid.v4();
    final params = buildConnectParams(
      token: _token,
      deviceId: _deviceId,
      config: _config,
      signature: signature,
      signedAt: signature != null ? nowMs : null,
      nonce: _challengeNonce,
    );
    debugPrint('[CM] Sending connect request — params keys: ${params.keys}');
    final requestJson = buildRequest(
      id: id,
      method: Methods.connect,
      params: params,
    );

    final completer = Completer<ResponseFrame>();
    _pendingRequests[id] = completer;

    _channel!.sink.add(requestJson);

    completer.future.then(
      (res) => _handleConnectResponse(res),
      onError: (error) => _handleAuthFailure('Connect request failed: $error'),
    );
  }

  void _handleConnectResponse(ResponseFrame res) {
    _connectTimeoutTimer?.cancel();

    if (res.ok && res.payload != null) {
      final payload = res.payload!;
      final payloadType = payload['type'] as String?;

      if (payloadType == 'hello-ok') {
        _reconnectAttempt = 0;
        _pairingRetryTimer?.cancel();
        _pairingRetryTimer = null;
        _setState(GatewayConnectionState.connected);

        // 配对成功 — 清除配对信息
        if (!_pairingInfoController.isClosed) {
          _pairingInfoController.add(null);
        }

        final policy = payload['policy'] as Map<String, dynamic>?;
        if (policy != null) {
          _tickIntervalMs = policy['tickIntervalMs'] as int? ?? 15000;
        }

        debugPrint(
          '[CM] Connected to $_instanceId (protocol: ${payload['protocol']})',
        );

        _resetTickTimeout();
      } else {
        _handleAuthFailure('Unexpected hello payload type: $payloadType');
      }
    } else {
      final errorCode = res.error?.code;
      debugPrint(
        '[CM] Connect response ERROR — '
        'code=$errorCode, message=${res.error?.message}, '
        'retryable=${res.error?.retryable}, '
        'retryAfterMs=${res.error?.retryAfterMs}',
      );

      if (errorCode == 'NOT_PAIRED') {
        _handlePairingRequired(res.error!);
      } else if (errorCode == 'DEVICE_AUTH_DEVICE_ID_MISMATCH') {
        _handleDeviceIdMismatch(res.error!);
      } else {
        _handleAuthFailure(
          res.error?.message ?? 'Authentication rejected',
          errorCode: errorCode,
        );
      }
    }
  }

  /// 处理 NOT_PAIRED — 设备待审批，进入配对等待模式并定期重试。
  Future<void> _handlePairingRequired(ProtocolError error) async {
    final details = error.details;
    final requestId = details?['requestId'] as String?;
    final deviceId = details?['deviceId'] as String?;
    final requestedRole = details?['requestedRole'] as String?;
    final requestedScopes = (details?['requestedScopes'] as List<dynamic>?)
        ?.cast<String>();

    debugPrint(
      '[CM] Pairing required for $_instanceId — '
      'requestId=$requestId, deviceId=$deviceId',
    );

    final info = GatewayPairingInfo(
      requestId: requestId ?? '',
      deviceId: deviceId ?? _deviceId,
      requestedRole: requestedRole,
      requestedScopes: requestedScopes,
    );

    if (!_pairingInfoController.isClosed) {
      _pairingInfoController.add(info);
    }

    _failAllPending('Pairing required');
    _cancelTimers();
    await _closeWebSocket();

    // 若在 _closeWebSocket() 等待期间外部调用了 disconnect()/dispose()，
    // 必须检查 _intentionalDisconnect，避免覆盖已断开的连接状态并创建
    // 新的配对重试定时器（配对重试不该在用户主动断开后继续）。
    if (_intentionalDisconnect) return;

    _setState(GatewayConnectionState.pairingRequired);

    // 定期重试（每 10s），等待用户在服务器审批
    _schedulePairingRetry();
  }

  /// 处理 DEVICE_AUTH_DEVICE_ID_MISMATCH — 设备凭据冲突的瞬时竞态。
  ///
  /// 发生在 [testConnection] 刚释放连接、正式连接立即使用相同设备凭据重连时。
  /// Gateway 需要数秒释放旧 session。与 [NOT_PAIRED] 不同，这是已知的瞬时错误
  /// ——短时间后自动恢复，不应标记为 [GatewayConnectionState.authFailed]。
  Future<void> _handleDeviceIdMismatch(ProtocolError error) async {
    debugPrint(
      '[CM] Device ID mismatch for $_instanceId — '
      'retrying in 2s (transient race)',
    );
    _failAllPending('Device ID mismatch: ${error.message}');
    _cancelTimers();
    await _closeWebSocket();

    // 若在 _closeWebSocket() 等待期间外部调用了 disconnect()/dispose()，
    // 必须检查 _intentionalDisconnect（对齐 _handlePairingRequired）。
    if (_intentionalDisconnect) return;

    _setState(GatewayConnectionState.recovering);
    _scheduleDoConnect(
      delaySeconds: 2,
      reason: 'device ID mismatch retry',
      timerRef: 'reconnect',
    );
  }

  void _schedulePairingRetry() {
    _scheduleDoConnect(
      delaySeconds: _pairingRetrySeconds,
      reason: 'pairing retry',
      timerRef: 'pairingRetry',
    );
  }

  // ---------------------------------------------------------------------------
  // 内部：保活（tick）
  // ---------------------------------------------------------------------------

  void _resetTickTimeout() {
    _tickTimeoutTimer?.cancel();
    _tickTimeoutTimer = _createTimer(
      Duration(milliseconds: _tickIntervalMs * _tickTimeoutMultiplier),
      () {
        debugPrint('[CM] Tick timeout for $_instanceId — connection lost');
        // _closeWebSocket() is async (StreamSubscription.cancel /
        // WebSocketSink.close may take non-trivial time).  The Timer
        // callback is void, so we MUST sequence via .then() — a bare
        // _closeWebSocket() without await would let _scheduleReconnect()
        // fire a new _doConnect() while the old channel is still being
        // torn down, creating a race where the delayed cleanup nulls
        // the newly-established _channel/_incomingSubscription.
        _closeWebSocket()
            .then((_) {
              if (_intentionalDisconnect) return;
              _setState(GatewayConnectionState.recovering);
              _scheduleReconnect();
            })
            .catchError((error, stackTrace) {
              debugPrint(
                '[CM] Tick timeout close failed for $_instanceId: '
                '$error\n$stackTrace',
              );
              if (_intentionalDisconnect) return;
              _setState(GatewayConnectionState.recovering);
              _scheduleReconnect();
            });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 内部：重连
  // ---------------------------------------------------------------------------

  void _scheduleReconnect() {
    _scheduleDoConnect(
      delaySeconds: _retryStrategy.delayForAttempt(_reconnectAttempt).inSeconds,
      reason: 'reconnect (attempt ${_reconnectAttempt + 1})',
      timerRef: 'reconnect',
      onFire: () => _reconnectAttempt++,
    );
  }

  /// 在 [delaySeconds] 后调用 [_doConnect]，带抢占保护和日志。
  ///
  /// [timerRef] 区分配对重试定时器（"pairingRetry"）和通用重连定时器
  /// （"reconnect"），确保两个定时器互相抢占时各自正确取消。
  void _scheduleDoConnect({
    required int delaySeconds,
    String reason = 'retry',
    String timerRef = 'reconnect',
    void Function()? onFire,
  }) {
    if (_intentionalDisconnect) return;

    // 取消该定时器类型的已有实例，防止两个定时器堆积
    if (timerRef == 'pairingRetry') {
      _pairingRetryTimer?.cancel();
    } else {
      _reconnectTimer?.cancel();
    }

    debugPrint('[CM] Scheduling $reason for $_instanceId in ${delaySeconds}s');

    final timer = _createTimer(Duration(seconds: delaySeconds), () {
      onFire?.call();
      _doConnect().catchError((Object error, StackTrace stackTrace) {
        debugPrint(
          '[CM] $reason failed for $_instanceId: '
          '$error\n$stackTrace',
        );
      });
    });

    if (timerRef == 'pairingRetry') {
      _pairingRetryTimer = timer;
    } else {
      _reconnectTimer = timer;
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：错误处理
  // ---------------------------------------------------------------------------

  void _handleAuthFailure(
    String reason, {
    String? errorCode,
    Map<String, dynamic>? errorDetails,
  }) {
    debugPrint('[CM] Auth failed for $_instanceId: $reason');
    if (errorCode != null) debugPrint('[CM] Auth error code: $errorCode');
    if (errorDetails != null)
      debugPrint('[CM] Auth error details: $errorDetails');
    _failAllPending('Authentication failed: $reason');
    _cancelTimers();
    // Fire-and-forget with error logging — _closeWebSocket() is async but
    // _setState(authFailed) must happen synchronously so callers see the
    // terminal state immediately.  The .catchError prevents the unhandled
    // Future rejection that a bare _closeWebSocket() would cause.
    _closeWebSocket().catchError((error, stackTrace) {
      debugPrint(
        '[CM] Error closing WebSocket during auth failure: '
        '$error\n$stackTrace',
      );
    });
    _setState(GatewayConnectionState.authFailed);
  }

  void _onConnectionError(Object error) {
    debugPrint('[CM] WebSocket error for $_instanceId: $error');
    // 在任何非终态下收到传输层错误都应尝试恢复，而不仅仅是 connected。
    // 认证阶段的协议错误若被忽略，会等到 15s 握手超时才处理。
    if (_state != GatewayConnectionState.disconnected &&
        _state != GatewayConnectionState.authFailed) {
      _setState(GatewayConnectionState.recovering);
    }
  }

  void _onConnectionDone() {
    debugPrint('[CM] WebSocket closed for $_instanceId');

    _cancelTimers();
    _failAllPending('Connection closed');

    if (!_intentionalDisconnect &&
        _state != GatewayConnectionState.authFailed) {
      _setState(GatewayConnectionState.recovering);
      _scheduleReconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：辅助方法
  // ---------------------------------------------------------------------------

  void _setState(GatewayConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    _connectionStateController.add(newState);
  }

  /// Test-only entry point to set internal connection state without a real
  /// WebSocket handshake.  Annotated [@visibleForTesting] — never call from
  /// production code.
  @visibleForTesting
  void setTestState(GatewayConnectionState state) => _setState(state);

  /// Test-only entry point to set internal WebSocket channel without a real
  /// connection.  Annotated [@visibleForTesting] — never call from
  /// production code.  The channel must remain private to prevent external
  /// code from bypassing [_doConnect] and breaking the state machine.
  @visibleForTesting
  void setTestChannel(WebSocketChannel? channel) => _channel = channel;

  void _cancelTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _tickTimeoutTimer?.cancel();
    _tickTimeoutTimer = null;
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    _pairingRetryTimer?.cancel();
    _pairingRetryTimer = null;
  }

  Future<void> _closeWebSocket() async {
    // Capture locals BEFORE the first await so a reconnect that fires
    // while we are waiting for cancel/close won't have its fresh
    // _incomingSubscription / _channel clobbered by this stale cleanup.
    final incomingSub = _incomingSubscription;
    final channel = _channel;
    await incomingSub?.cancel();
    if (identical(_incomingSubscription, incomingSub)) {
      _incomingSubscription = null;
    }
    await channel?.sink.close();
    if (identical(_channel, channel)) {
      _channel = null;
    }
  }

  void _failAllPending(String reason) {
    final error = ResponseFrame(
      id: '',
      ok: false,
      error: ProtocolError(code: 'CONNECTION_LOST', message: reason),
    );
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(error);
      }
    }
    _pendingRequests.clear();
  }
}
