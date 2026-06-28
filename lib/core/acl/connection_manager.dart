import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

import '../utils/retry_strategy.dart';
import 'i_device_token_store.dart';
import 'i_gateway_client.dart';
import 'gateway_protocol.dart';

/// Injectable timer factory — defaults to [Timer.new].
///
/// Used by both [ConnectionManager] and [WsGatewayClient] (the latter
/// forwards it via DI). Tests inject a fake factory to control
/// time-dependent behavior (tick timeout, reconnect backoff, pairing
/// retry) without real delays. Not annotated `@visibleForTesting`
/// because it is part of the cross-class production API.
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

  /// Gap #2: 服务端 maxPayload 上限（字节），由 hello-ok.policy.maxPayload 设置。
  /// 客户端在 [sendRequest] 序列化前守门，超过此大小抛 [PayloadTooLargeException]。
  /// 默认 25MB（spec §2.2 默认值），hello-ok 到达后用 policy 字段覆盖。
  int _maxPayloadBytes = defaultMaxPayloadBytes;

  /// Gap #2: 服务端 maxBufferedBytes 上限（字节），由 hello-ok.policy.maxBufferedBytes
  /// 设置。当前实现仅记录供诊断使用；后续可作为出站缓冲监控阈值。
  /// 默认 50MB（spec §2.2 默认值）。
  int _maxBufferedBytes = defaultMaxBufferedBytes;

  /// Test/diagnostic read of the effective maxPayload cap. The value is
  /// negotiated from hello-ok.policy.maxPayload at connect time, falling
  /// back to [defaultMaxPayloadBytes] (25MB) when the server omits the
  /// field. Used by tests to assert policy parsing without driving a
  /// full sendRequest cycle.
  @visibleForTesting
  int get maxPayloadBytesForTesting => _maxPayloadBytes;

  /// Test/diagnostic read of the effective maxBufferedBytes cap. See
  /// [maxPayloadBytesForTesting] for the negotiation semantics.
  @visibleForTesting
  int get maxBufferedBytesForTesting => _maxBufferedBytes;

  /// Set of event types the Gateway declared it will push, populated
  /// from `hello-ok.features.events` (spec §2.2 / Gap #3).
  ///
  /// Empty until the first hello-ok handshake completes; stays empty
  /// forever for old Gateway builds that don't send `features`.  UI can
  /// check `supportedEvents.contains('chat')` to decide whether to
  /// render a "Gateway doesn't push chat events" fallback.
  Set<String> _supportedEvents = const <String>{};

  /// Read-only view of [supportedEvents].
  ///
  /// Returns an [UnmodifiableSetView] (zero-copy wrapper) so callers cannot
  /// mutate the internal set through the getter without paying the per-call
  /// allocation cost of [Set.unmodifiable].  See [supportedEvents] for
  /// semantics.
  Set<String> get supportedEvents => UnmodifiableSetView(_supportedEvents);

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

  /// 设备令牌（deviceToken）存储 — 持久化 Gateway 签发的设备令牌。
  ///
  /// 如果注入，则在握手时优先用缓存令牌（避免重复走配对审批），
  /// 并在 hello-ok 时把新签发的令牌落盘（spec §2.2 / §4.11）。
  final IDeviceTokenStore? _deviceTokenStore;

  /// Effective bearer token used for the current connect attempt.
  ///
  /// Resolved once at the start of [_doConnect] by [_resolveBearerToken]
  /// and read by [onConnectChallenge] for the V3 signature payload and the
  /// `connect.auth.token` field (all three sites must match).  Lifecycle:
  /// refreshed at the top of each [_doConnect]; stale after the connect
  /// completes but never read post-connect.
  ///
  /// Seeded to [token] in the constructor so that a misordered read
  /// (e.g. a future debug log or public getter) sees the pairing code
  /// instead of `''`.  The three legitimate read sites — URL query,
  /// V3 signature payload, `auth.token` — all live inside [_doConnect]
  /// and are guaranteed to see the resolved value; this is a safety net.
  String _effectiveToken = '';

  /// Gap #5: detect clock drift between server and client using
  /// `tick.payload.ts` (spec §2.8).
  ///
  /// Records the signed drift into [_lastObservedClockDriftMs] for
  /// diagnostic UIs / provider reads.  If the magnitude exceeds
  /// [_clockDriftWarningThresholdMs] (default 5000), emits a
  /// [debugPrint] warning so release builds retain a breadcrumb
  /// for DEVICE_AUTH_SIGNATURE_EXPIRED root-cause analysis.
  ///
  /// Silent on missing/invalid ts — old Gateway builds don't send
  /// the field and we must remain backward-compatible.
  void _detectClockDrift(Map<String, dynamic>? payload) {
    if (payload == null) return;
    final tsRaw = payload['ts'];
    // Accept both `int` and `double`: jsonDecode yields `double` for numbers
    // carrying a fractional/exponent part (e.g. `1719500000000.0`), and a
    // strict `is! int` would silently skip drift detection for those.
    if (tsRaw is! num) return;

    final serverTs = tsRaw.toInt();
    final clientTs = DateTime.now().millisecondsSinceEpoch;
    final drift = serverTs - clientTs;
    _lastObservedClockDriftMs = drift;

    if (drift.abs() >= _clockDriftWarningThresholdMs) {
      debugPrint(
        '[CM] Clock drift detected for $_instanceId: '
        'serverTs=$serverTs, clientTs=$clientTs, '
        'drift=${drift}ms (threshold ${_clockDriftWarningThresholdMs}ms). '
        'If you see DEVICE_AUTH_SIGNATURE_EXPIRED, this is the likely cause.',
      );
    }
  }

  /// Gap #1+: per-connection flag that gates the single allowed
  /// deviceToken retry on AUTH_TOKEN_MISMATCH (spec §A.9).
  ///
  /// Set true when the first AUTH_TOKEN_MISMATCH triggers a retry;
  /// reset to false on successful hello-ok so a later session can
  /// retry again if it hits the same race.  Also reset to false at the
  /// start of a manual [connect()] — a user-initiated reconnect is a fresh
  /// connection attempt that §A.9 promises its own retry budget.  Limits
  /// retry count to 1 per connection attempt, matching the spec's "尝试一次"
  /// wording.
  bool _hasAttemptedDeviceTokenRetry = false;

  /// Gap #5: most recently observed clock drift in milliseconds, signed
  /// (server - client).  `null` until the first `tick` event with
  /// `payload.ts` arrives.
  ///
  /// Drift > [_clockDriftWarningThresholdMs] (default 5000) is also
  /// logged via [debugPrint] so release builds retain a diagnostic
  /// breadcrumb for DEVICE_AUTH_SIGNATURE_EXPIRED root-cause analysis.
  int? _lastObservedClockDriftMs;

  /// Threshold (ms) above which a drift is considered worth warning
  /// about.  5 seconds is small enough to catch real clock problems
  /// (NTP drift is typically < 1s) but large enough to ignore normal
  /// round-trip jitter between server and client.
  static const int _clockDriftWarningThresholdMs = 5000;

  /// Test-only read of [_lastObservedClockDriftMs].  Returns `null`
  /// until the first `tick` with `payload.ts` arrives.
  @visibleForTesting
  int? get lastObservedClockDriftMsForTesting => _lastObservedClockDriftMs;

  /// Test-only read of the resolved bearer token.  Used by the
  /// `_effectiveToken initialized to constructor token` regression test
  /// to verify the constructor-side seeding without forcing a connect.
  @visibleForTesting
  String get effectiveTokenForTesting => _effectiveToken;

  /// WebSocket 创建工厂 — 可注入以在测试中替换 WebSocket。
  final WebSocketChannel Function(Uri) _webSocketFactory;

  /// Timer 创建工厂 — 可注入以在测试中控制定时器行为。
  final TimerFactory _createTimer;

  /// challenge nonce，收到 connect.challenge 后设置
  String? _challengeNonce;

  /// Default reconnect strategy: exponential backoff capped at 3 consecutive
  /// failures (US-016 AC-3).  After 3 failed attempts the state machine
  /// transitions to [GatewayConnectionState.reconnectExhausted] and stops
  /// auto-reconnecting until the user triggers a manual reconnect.
  static const _defaultRetryStrategy = RetryStrategy.networkReconnectLimited;

  ConnectionManager({
    required String instanceId,
    required String gatewayUrl,
    required String token,
    required String deviceId,
    required ConnectionConfig config,
    Uuid? uuid,
    WebSocketChannel Function(Uri)? webSocketFactory,
    TimerFactory? timerFactory,
    RetryStrategy? retryStrategy,
    IDeviceTokenStore? deviceTokenStore,
  }) : _retryStrategy = retryStrategy ?? _defaultRetryStrategy,
       _instanceId = instanceId,
       _gatewayUrl = gatewayUrl,
       _token = token,
       _deviceId = deviceId,
       _config = config,
       _deviceTokenStore = deviceTokenStore,
       _webSocketFactory = webSocketFactory ?? WebSocketChannel.connect,
       _createTimer = timerFactory ?? Timer.new,
       _uuid = uuid ?? const Uuid() {
    _connectionStateController.add(GatewayConnectionState.disconnected);
    // Seed _effectiveToken to the constructor-provided pairing code so a
    // pre-_doConnect read returns [token] instead of ''. See the field
    // docstring for the read-site guarantees.
    _effectiveToken = token;
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
    // Re-arm the AUTH_TOKEN_MISMATCH retry budget (spec §A.9 "1 retry per
    // connection attempt"). connect() is the manual-attempt entry point;
    // the budget is otherwise reset only on a successful hello-ok, so
    // without this a failed-then-manually-reconnected session would be
    // denied its one retry. The auto-retry path goes through
    // _scheduleDoConnect → _doConnect (not connect()), so resetting here
    // does NOT re-arm the budget mid-retry (which would loop forever).
    _hasAttemptedDeviceTokenRetry = false;
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

    // Gap #2: client-side guard against payloads larger than the
    // server-declared maxPayload (spec §2.2 + §3.5). Without this,
    // serialising a 100MB chat message and writing it to the socket
    // would either be accepted (and OOM us) or rejected by the server
    // with a `payload.large` event that we'd silently drop — either
    // way the user sees "message disappeared". Throwing here gives
    // the ViewModel a typed error to surface.
    //
    // Always compute the precise UTF-8 byte count. `String.length`
    // (UTF-16 code units) is a LOWER bound on byte count for non-ASCII
    // content — e.g. CJK characters encode to 3 UTF-8 bytes per code
    // unit, so a 25M-char CJK payload reads as ~25M code units but
    // ~75M bytes on the wire. A previous "cheap upper-bound" attempt
    // using String.length was wrong for non-ASCII and silently bypassed
    // the guard (regression test: connection_manager_policy_test.dart
    // "CJK payload is measured in UTF-8 bytes, not code units").
    // Allocating the Uint8List is negligible vs. the network write
    // that follows — typical chat messages are < 100KB.
    final maxPayload = _maxPayloadBytes;
    final payloadSize = utf8.encode(requestJson).length;
    if (payloadSize > maxPayload) {
      throw PayloadTooLargeException(
        message:
            'Request $method payload size $payloadSize exceeds '
            'maxPayload $maxPayload',
        actualSize: payloadSize,
        maxSize: maxPayload,
      );
    }

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

  /// 解析本次 connect 使用的 bearer token（差距 #1）。
  ///
  /// 优先级：[IDeviceTokenStore.load] 返回的缓存 deviceToken（spec §2.2
  /// 后续重连复用）→ 构造时传入的 [_token]（首次配对 pairing code）。
  /// 加载失败不会抛 — 静默回退到 [_token]，并在 debug 日志中记录原因。
  Future<String> _resolveBearerToken() async {
    if (_deviceTokenStore == null) return _token;
    try {
      final cached = await _deviceTokenStore!.load(_instanceId);
      if (cached != null && cached.isNotEmpty) {
        // Cache-hit is a routine success-path trace on the reconnect hot
        // path — gate behind kDebugMode so release logs don't carry it
        // on every reconnect.  Error path below stays unconditional.
        if (kDebugMode) {
          debugPrint(
            '[CM] Using cached deviceToken for $_instanceId '
            '(spec §2.2 reconnect path)',
          );
        }
        return cached;
      }
    } catch (e, st) {
      debugPrint(
        '[CM] deviceTokenStore.load failed for $_instanceId: $e\n'
        'Falling back to instance.tokenRef.\n$st',
      );
    }
    return _token;
  }

  Future<void> _doConnect() async {
    if (_inDoConnect) return;
    _inDoConnect = true;

    // Fix 5 (post-Fix-1 audit): cancel any stale connect-timeout timer
    // from a previous attempt. Without this, if attempt #1 entered
    // authenticating but the handshake never completed (e.g. transport
    // error mid-handshake), T1 (15s timeout) is still alive. When
    // attempt #2 starts after reconnect, T2 overwrites T1's reference
    // at line ~451 but T1's callback is still scheduled in the event
    // loop. If T1 fires during attempt #2's authenticating phase,
    // `if (_state == authenticating)` passes and we falsely trigger
    // `_handleAuthFailure('Handshake timeout')` — masking the recovery
    // with a terminal auth failure.
    //
    // Regression test: connection_manager_test.dart
    // "connect-timeout timer is cancelled when _doConnect restarts".
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;

    _setState(GatewayConnectionState.connecting);

    try {
      // Resolve the bearer token for this connect attempt and stash it for
      // [onConnectChallenge] to read (URL query + V3 signature + auth.token
      // must all match).  See [_resolveBearerToken] for the policy.
      _effectiveToken = await _resolveBearerToken();

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
        queryParameters: {
          ...originalUri.queryParameters,
          'token': _effectiveToken,
        },
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

  /// Test-only entry point that exercises [_handleEvent] without driving a
  /// real WebSocket frame.  Used by Gap #4 shutdown tests to inject events
  /// in pre-conditions where the channel has already been torn down
  /// (e.g. after [disconnect] or after forcing a terminal state).
  @visibleForTesting
  void handleEventForTesting(String event, Map<String, dynamic>? payload) =>
      _handleEvent(event, payload);

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
        // Gap #5: tick.payload.ts carries the server's epoch ms
        // (spec §2.8).  Compare with local clock and warn if drift
        // exceeds the threshold.  Silent if ts is absent — old Gateway
        // builds don't send it and we must remain backward-compatible.
        _detectClockDrift(payload);

      case Events.shutdown:
        // Gap #4: server-initiated graceful shutdown (spec §2.6) —
        // server is expected to be ready again immediately, so skip
        // the exponential backoff used for network failures and
        // reconnect at once.  See [_handleGracefulShutdown].
        _handleGracefulShutdown();

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
        // _config.deviceFamily is non-nullable (defaults to 'phone'); this
        // matches the wire deviceFamily written by buildConnectParams.
        final v3Payload = buildV3SignaturePayload(
          deviceId: _deviceId,
          clientId: _config.clientId,
          clientMode: _config.clientMode,
          role: _config.role,
          scopes: _config.scopes,
          signedAtMs: nowMs,
          // Use the effective token (cached deviceToken if available,
          // else the constructor-provided pairing code) so the signed
          // payload matches what we send in `auth.token` (spec §2.5).
          token: _effectiveToken,
          nonce: _challengeNonce!,
          platform: _config.platform,
          deviceFamily: _config.deviceFamily,
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
      // Match the signed token: cached deviceToken if available, else the
      // original pairing code.  spec §2.2 + §2.5 alignment.
      token: _effectiveToken,
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

    // bug #8: .then() 返回的 Future 若 _handleConnectResponse 同步抛异常
    // 会成为未处理拒绝。链式 .catchError 记录日志，避免静默丢失。
    completer.future
        .then(
          (res) => _handleConnectResponse(res),
          onError: (error) =>
              _handleAuthFailure('Connect request failed: $error'),
        )
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            '[CM] Unhandled error in connect response handler '
            'for $_instanceId: $error\n$stackTrace',
          );
        });
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
          // Gap #2: read maxPayload / maxBufferedBytes from hello-ok
          // (spec §2.2). If the server omits either field OR sends a
          // non-positive value (0 / negative — seen in misconfigured /
          // dev environments), fall back to the spec default. Without
          // the `> 0` guard, maxPayload=0 would wedge every sendRequest
          // because any non-empty payload exceeds 0 bytes.
          // (Regression test: connection_manager_policy_test.dart
          // "maxPayload=0 from server falls back to defaultMaxPayloadBytes")
          final serverMaxPayload = policy['maxPayload'];
          _maxPayloadBytes = (serverMaxPayload is num && serverMaxPayload > 0)
              ? serverMaxPayload.toInt()
              : defaultMaxPayloadBytes;
          final serverMaxBuffered = policy['maxBufferedBytes'];
          _maxBufferedBytes =
              (serverMaxBuffered is num && serverMaxBuffered > 0)
              ? serverMaxBuffered.toInt()
              : defaultMaxBufferedBytes;
        }

        // Gap #3: read features.events (spec §2.2).  Old Gateway builds
        // don't send `features` at all — keep the empty set as the
        // backward-compat default.  Schema-drift defense: filter to
        // strings only so a future Gateway that sends rich event
        // descriptors (e.g. `{"name": "chat", "version": 2}`) doesn't
        // crash the parse (same spirit as F-1 `details` type guard).
        final features = payload['features'] as Map<String, dynamic>?;
        final eventsRaw = features?['events'];
        if (eventsRaw is List) {
          _supportedEvents = eventsRaw.whereType<String>().toSet();
        } else {
          _supportedEvents = const <String>{};
        }

        // Routine connect-success trace — gated to keep release logs clean
        // on the reconnect hot path.  Error logs elsewhere stay unconditional.
        if (kDebugMode) {
          debugPrint(
            '[CM] Connected to $_instanceId (protocol: ${payload['protocol']})',
          );
        }

        // 差距 #1: persist the issued deviceToken (spec §2.2 务必持久化).
        // Best-effort — a failed save doesn't break the current connection;
        // the worst case is a re-pair on next reconnect.  Errors are
        // logged and swallowed.
        final auth = payload['auth'] as Map<String, dynamic>?;
        final newDeviceToken = auth?['deviceToken'] as String?;
        if (newDeviceToken != null &&
            newDeviceToken.isNotEmpty &&
            _deviceTokenStore != null) {
          unawaited(
            _deviceTokenStore.save(_instanceId, newDeviceToken).catchError((
              Object e,
              StackTrace st,
            ) {
              debugPrint(
                '[CM] deviceTokenStore.save failed for $_instanceId: $e\n'
                'Future reconnects may need to re-pair.\n$st',
              );
            }),
          );
        }

        _resetTickTimeout();
        // Gap #1+: reset the per-session retry budget on successful
        // hello-ok so a future AUTH_TOKEN_MISMATCH can retry again.
        _hasAttemptedDeviceTokenRetry = false;
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
        unawaited(
          Future.sync(() => _handlePairingRequired(res.error!)).catchError(
            (e, st) => debugPrint('[CM] _handlePairingRequired error: $e\n$st'),
          ),
        );
      } else if (errorCode == 'DEVICE_AUTH_DEVICE_ID_MISMATCH') {
        unawaited(
          Future.sync(() => _handleDeviceIdMismatch(res.error!)).catchError(
            (e, st) =>
                debugPrint('[CM] _handleDeviceIdMismatch error: $e\n$st'),
          ),
        );
      } else if (errorCode == 'AUTH_TOKEN_MISMATCH' &&
          _canRetryAuthTokenMismatch(res.error!)) {
        // Gap #1+: spec §A.9 allows ONE retry using the cached
        // deviceToken when the server signals
        // `canRetryWithDeviceToken=true`.  Retry budget tracked by
        // [_hasAttemptedDeviceTokenRetry] — cleared on hello-ok so a
        // future session can retry again.
        unawaited(
          _handleAuthTokenMismatchRetry().catchError((e, st) {
            debugPrint('[CM] _handleAuthTokenMismatchRetry error: $e\n$st');
          }),
        );
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
    // Guard: same race fixed in `_handleAuthTokenMismatchRetry` (Fix 3).
    // A stale NOT_PAIRED response arriving while state has already
    // moved to a terminal (authFailed / disconnected / etc.) must NOT
    // override the terminal state with pairingRequired + a pairing-retry
    // timer — that would mask the real failure from the user and create
    // a zombie retry after explicit disconnect.
    //
    // The pairingInfo stream emit is intentionally gated by this guard
    // too, so a stale NOT_PAIRED can't surface a phantom pairing
    // request after the user has disconnected.
    //
    // Regression tests: connection_manager_test.dart
    //   - "NOT_PAIRED in terminal state (authFailed) does NOT override state"
    //   - "NOT_PAIRED in terminal state (disconnected) does NOT schedule retry"
    if (_state.isTerminal) {
      debugPrint(
        '[CM] NOT_PAIRED pairing handler skipped for $_instanceId '
        '(terminal state: $_state)',
      );
      return;
    }

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
    // Guard: same race fixed in `_handleAuthTokenMismatchRetry` (Fix 3).
    // A stale DEVICE_ID_MISMATCH response arriving while state has
    // already moved to a terminal (authFailed / disconnected / etc.)
    // must NOT override the terminal state with recovering + a 2s
    // retry — that would mask the real failure from the user and
    // create a zombie retry after explicit disconnect.
    //
    // Regression test: connection_manager_test.dart
    //   - "DEVICE_ID_MISMATCH in terminal state (authFailed) does NOT retry"
    if (_state.isTerminal) {
      debugPrint(
        '[CM] DEVICE_ID_MISMATCH handler skipped for $_instanceId '
        '(terminal state: $_state)',
      );
      return;
    }

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

  /// Gap #1+: returns true iff the AUTH_TOKEN_MISMATCH error is
  /// retryable per spec §A.9 — server explicitly opts in via
  /// `details.canRetryWithDeviceToken == true`, AND the client still
  /// has a retry budget (`_hasAttemptedDeviceTokenRetry == false`).
  ///
  /// F-1 type guard: details may be null or a non-Map value; both
  /// collapse to "no hint" → fail closed (no retry).
  bool _canRetryAuthTokenMismatch(ProtocolError error) {
    if (_hasAttemptedDeviceTokenRetry) return false;
    final details = error.details;
    if (details == null) return false;
    final hint = details['canRetryWithDeviceToken'];
    return hint == true;
  }

  /// Gap #1+: handle the retry side of AUTH_TOKEN_MISMATCH (spec §A.9).
  ///
  /// Mirrors [_handleGracefulShutdown]'s "reconnect at once, no backoff"
  /// pattern — server has signalled it can accept a retry, so we
  /// immediately try again using the cached deviceToken
  /// ([_resolveBearerToken] re-reads from [_deviceTokenStore] on the
  /// next [_doConnect]).
  ///
  /// Limitation: we don't yet have `isLocalNetwork` / `tlsFingerprint`
  /// fields on [ConnectionConfig] (see F-3), so the trust check is
  /// delegated to the server's `canRetryWithDeviceToken` flag.  If
  /// the server is misconfigured and always returns canRetry=true,
  /// we'd loop forever — guarded by [_hasAttemptedDeviceTokenRetry]
  /// limiting us to 1 retry per connect attempt, and that flag resets
  /// only on successful hello-ok.
  Future<void> _handleAuthTokenMismatchRetry() async {
    // Guard: if the CM is already in a terminal state (authFailed /
    // pairingRequired / reconnectExhausted / disconnected) when a
    // stale AUTH_TOKEN_MISMATCH response arrives (race window —
    // another code path may have terminated the state while the
    // connect response was still in flight), we MUST NOT retry.
    //
    // Retrying here would:
    //   1. Overwrite the terminal state with `disconnected` via
    //      _immediateReconnect, masking the original failure from
    //      the user.
    //   2. Schedule a fresh connect over a state that has explicit
    //      user-action semantics (e.g. pairingRequired = "user must
    //      approve", disconnected = "user clicked disconnect").
    //   3. Burn the retry budget for the next legitimate session
    //      (a future AUTH_TOKEN_MISMATCH would find the budget
    //      already consumed and skip the retry spec §A.9 promises).
    //
    // Regression test: connection_manager_auth_retry_test.dart
    // "AUTH_TOKEN_MISMATCH in terminal state (authFailed) does NOT retry".
    if (_state.isTerminal) {
      debugPrint(
        '[CM] AUTH_TOKEN_MISMATCH retry skipped for $_instanceId '
        '(terminal state: $_state)',
      );
      return;
    }

    debugPrint(
      '[CM] AUTH_TOKEN_MISMATCH for $_instanceId — retrying with cached '
      'deviceToken (spec §A.9)',
    );
    _hasAttemptedDeviceTokenRetry = true;

    await _immediateReconnect(
      pendingFailReason: 'AUTH_TOKEN_MISMATCH (retrying)',
      scheduleReason: 'AUTH_TOKEN_MISMATCH retry',
    );
  }

  /// Shared "reset and reconnect with zero delay" primitive for
  /// [_handleGracefulShutdown] and [_handleAuthTokenMismatchRetry].
  ///
  /// Both handlers want the same outcome: fail pending requests, cancel
  /// timers, await-close-socket (errors logged but not propagated), bail
  /// if a user-initiated disconnect arrived during the await, transition
  /// to [GatewayConnectionState.disconnected], then schedule an immediate
  /// reconnect.  The variation between the two callers is captured by the
  /// reason strings; the lifecycle sequence is identical.
  Future<void> _immediateReconnect({
    required String pendingFailReason,
    required String scheduleReason,
  }) async {
    _failAllPending(pendingFailReason);
    _cancelTimers();
    await _closeWebSocket().catchError((error, stackTrace) {
      debugPrint(
        '[CM] Error closing WebSocket during $scheduleReason: '
        '$error\n$stackTrace',
      );
    });

    // Don't paper over a user-initiated disconnect.
    if (_intentionalDisconnect) return;

    _setState(GatewayConnectionState.disconnected);
    _scheduleDoConnect(
      delaySeconds: 0,
      reason: scheduleReason,
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

  /// 处理 spec §2.6 server-initiated graceful shutdown.
  ///
  /// 与"网络瞬断"+"对端崩溃"区分：服务端 shutdown 是**主动的、可预期的**，
  /// 服务端 ready 后即可用（滚动重启、维护窗口），应立即重连而非
  /// 走通用 1→30s 退避。否则用户等完整退避链，体验糟糕。
  ///
  /// 关键约束：
  /// - 不退避（[Duration.zero] 而不是 [_retryStrategy.delayForAttempt]）
  /// - 不递增 [_reconnectAttempt]，避免反复 graceful shutdown 触发
  ///   [GatewayConnectionState.reconnectExhausted]（滚动重启会循环 shutdown）
  /// - 用户主动 disconnect 期间收到 shutdown → 不重连（实例已删除不该复活）
  /// - 终态（authFailed / pairingRequired / reconnectExhausted）期间收到
  ///   shutdown → 不重连（终端错误不该被覆盖）
  Future<void> _handleGracefulShutdown() async {
    debugPrint(
      '[CM] Graceful shutdown for $_instanceId — reconnecting immediately',
    );

    if (_intentionalDisconnect) {
      debugPrint(
        '[CM] Ignoring shutdown for $_instanceId '
        '(intentional disconnect)',
      );
      return;
    }

    // Pre-check terminal state BEFORE we mutate to disconnected — otherwise
    // our own _setState(disconnected) below would make _state.isTerminal
    // true and we'd skip the reconnect we actually want to perform.
    // Genuine terminal states (authFailed / pairingRequired /
    // reconnectExhausted) must NOT be papered over by a shutdown event;
    // the user needs to see the underlying error.
    if (_state.isTerminal) {
      debugPrint(
        '[CM] Graceful shutdown skipped for $_instanceId '
        '(terminal state: $_state)',
      );
      return;
    }

    await _immediateReconnect(
      pendingFailReason: 'Gateway graceful shutdown',
      scheduleReason: 'graceful shutdown reconnect',
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
        _closeWebSocket().then((_) => _onWebSocketClosed()).catchError((
          error,
          stackTrace,
        ) {
          debugPrint(
            '[CM] Tick timeout close failed for $_instanceId: '
            '$error\n$stackTrace',
          );
          _onWebSocketClosed();
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 内部：重连
  // ---------------------------------------------------------------------------

  void _scheduleReconnect() {
    // AC-3: stop auto-reconnecting after maxAttempts consecutive failures.
    // Manual reconnect (connect() resets _reconnectAttempt to 0) is unaffected.
    if (!_retryStrategy.shouldRetry(_reconnectAttempt)) {
      debugPrint(
        '[CM] Reconnect exhausted for $_instanceId '
        'after $_reconnectAttempt consecutive failures',
      );
      _setState(GatewayConnectionState.reconnectExhausted);
      return;
    }

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
    //
    // Fix 3 (post-Fix-1 audit): we ALSO schedule a reconnect here,
    // mirroring `_onWebSocketClosed`. The previous design relied on
    // `_onConnectionDone` firing after `onError` to schedule the
    // reconnect — but some platforms / scenarios emit `onError`
    // without a follow-up `done`, leaving the connection stuck in
    // `recovering` indefinitely. Making `_onConnectionError`
    // self-sufficient closes that gap. `_scheduleDoConnect` cancels
    // any existing `_reconnectTimer` before scheduling, so if both
    // fire the second is a no-op (no double-schedule).
    //
    // Regression tests: connection_manager_test.dart
    //   - "_onConnectionError from connected → recovering + reconnect"
    //   - "_onConnectionError alone (no follow-up done) leaves system
    //     recoverable"
    if (!_state.isTerminal) {
      _setState(GatewayConnectionState.recovering);
      _scheduleReconnect();
    }
  }

  void _onConnectionDone() {
    debugPrint('[CM] WebSocket closed for $_instanceId');

    _cancelTimers();
    _failAllPending('Connection closed');

    // Only attempt recovery from non-terminal states.
    // Terminal states (authFailed, pairingRequired, reconnectExhausted) must
    // not be clobbered back to recovering — that would prevent the Orchestrator
    // from emitting the correct terminal event.
    if (!_intentionalDisconnect && !_state.isTerminal) {
      _setState(GatewayConnectionState.recovering);
      _scheduleReconnect();
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：辅助方法
  // ---------------------------------------------------------------------------

  /// Shared recovery hook for tick timeout and WebSocket close paths.
  ///
  /// Called after [_closeWebSocket] completes or errors — transitions to
  /// recovering and schedules a reconnect attempt unless the disconnect was
  /// intentional or the state machine is already in a terminal state.
  void _onWebSocketClosed() {
    if (_intentionalDisconnect) return;
    if (_state.isTerminal) return;
    _setState(GatewayConnectionState.recovering);
    _scheduleReconnect();
  }

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
