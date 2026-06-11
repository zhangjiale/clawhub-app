import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

import 'i_gateway_client.dart';
import 'gateway_protocol.dart';

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

  static const _maxReconnectDelaySeconds = 30;
  static const _baseReconnectDelaySeconds = 1;
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

  // --- 公开流 ---
  Stream<GatewayConnectionState> get connectionState =>
      _connectionStateController.stream;

  Stream<EventFrame> get events => _eventController.stream;

  GatewayConnectionState _state = GatewayConnectionState.disconnected;
  GatewayConnectionState get state => _state;

  bool _intentionalDisconnect = false;

  /// Serialize _doConnect calls so a reconnect-timer firing cannot race
  /// with a user-triggered connect() while the previous attempt is in flight.
  bool _inDoConnect = false;

  final String _locale;

  ConnectionManager({
    required String instanceId,
    required String gatewayUrl,
    required String token,
    String locale = 'zh-CN',
    Uuid? uuid,
  })  : _instanceId = instanceId,
        _gatewayUrl = gatewayUrl,
        _token = token,
        _locale = locale,
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
      throw StateError('WebSocket not connected (state: $_state)');
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
  }

  // ---------------------------------------------------------------------------
  // 内部：连接与握手
  // ---------------------------------------------------------------------------

  Future<void> _doConnect() async {
    if (_inDoConnect) return;
    _inDoConnect = true;

    _setState(GatewayConnectionState.connecting);

    try {
      final uri = Uri.parse(_gatewayUrl);
      final ws = WebSocketChannel.connect(uri);
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
      _connectTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (_state == GatewayConnectionState.authenticating) {
          debugPrint('[CM] Connect handshake timeout for $_instanceId');
          _handleAuthFailure('Handshake timeout');
        }
      });
    } on FormatException catch (error, stackTrace) {
      // URL 格式错误是永久性配置问题，不应重连
      debugPrint(
        '[CM] Bad gateway URL for $_instanceId: $error\n$stackTrace',
      );
      _handleAuthFailure('Bad gateway URL: $error');
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
      final frame = parseFrame(data as String);

      switch (frame) {
        case ResponseFrame(:final id):
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
        _onConnectChallenge(payload);

      case Events.tick:
        _resetTickTimeout();

      case Events.agent:
        if (payload != null) {
          _eventController.add(EventFrame(event: event, payload: payload));
        }

      case Events.shutdown:
        debugPrint('[CM] Gateway shutdown for $_instanceId');
        _setState(GatewayConnectionState.disconnected);

      default:
        // presence, health 等事件路由到外部
        _eventController.add(EventFrame(event: event, payload: payload));
    }
  }

  void _onConnectChallenge(Map<String, dynamic>? payload) {
    debugPrint('[CM] Received connect.challenge for $_instanceId');

    final id = _uuid.v4();
    final params = buildConnectParams(
      token: _token,
      locale: _locale,
    );
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
        _setState(GatewayConnectionState.connected);

        final policy = payload['policy'] as Map<String, dynamic>?;
        if (policy != null) {
          _tickIntervalMs = policy['tickIntervalMs'] as int? ?? 15000;
        }

        debugPrint(
          '[CM] Connected to $_instanceId (protocol: ${payload['protocol']})',
        );

        _resetTickTimeout();
      } else {
        _handleAuthFailure(
          'Unexpected hello payload type: $payloadType',
        );
      }
    } else {
      _handleAuthFailure(
        res.error?.message ?? 'Authentication rejected',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：保活（tick）
  // ---------------------------------------------------------------------------

  void _resetTickTimeout() {
    _tickTimeoutTimer?.cancel();
    _tickTimeoutTimer = Timer(
      Duration(milliseconds: _tickIntervalMs * _tickTimeoutMultiplier),
      () {
        debugPrint('[CM] Tick timeout for $_instanceId — connection lost');
        _closeWebSocket();
        _setState(GatewayConnectionState.recovering);
        _scheduleReconnect();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 内部：重连
  // ---------------------------------------------------------------------------

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;

    _reconnectTimer?.cancel();

    final delaySeconds = _computeBackoff();
    debugPrint(
      '[CM] Scheduling reconnect for $_instanceId '
      'in ${delaySeconds}s (attempt ${_reconnectAttempt + 1})',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectAttempt++;
      _doConnect().catchError((Object error, StackTrace stackTrace) {
        debugPrint(
          '[CM] Reconnect attempt threw for $_instanceId: '
          '$error\n$stackTrace',
        );
      });
    });
  }

  int _computeBackoff() {
    var delay = _baseReconnectDelaySeconds;
    for (int i = 0; i < _reconnectAttempt; i++) {
      delay *= 2;
      if (delay >= _maxReconnectDelaySeconds) return _maxReconnectDelaySeconds;
    }
    return delay;
  }

  // ---------------------------------------------------------------------------
  // 内部：错误处理
  // ---------------------------------------------------------------------------

  void _handleAuthFailure(String reason) {
    debugPrint('[CM] Auth failed for $_instanceId: $reason');
    _failAllPending('Authentication failed: $reason');
    _cancelTimers();
    _closeWebSocket();
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

  void _cancelTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _tickTimeoutTimer?.cancel();
    _tickTimeoutTimer = null;
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
  }

  Future<void> _closeWebSocket() async {
    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await _channel?.sink.close();
    _channel = null;
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
