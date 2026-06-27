import 'dart:convert';

import 'package:claw_hub/core/utils/copy_with_nullable.dart';

/// OpenClaw Gateway WebSocket 协议 v4 — 消息帧定义与解析。
///
/// 对齐官方协议文档：https://docs.openclaw.ai/gateway/protocol
///
/// 协议帧格式（三种）：
/// - **req**（请求）：`{"type":"req","id":"<uuid>","method":"<method>","params":{...}}`
/// - **res**（响应）：`{"type":"res","id":"<uuid>","ok":true|false,"payload":{...}}`
/// - **event**（事件）：`{"type":"event","event":"<name>","payload":{...}}`
///
/// 本文件负责 JSON ↔ Dart 的序列化/反序列化，业务代码不触碰原始 JSON。

// ============================================================================
// 协议常量
// ============================================================================

/// 协议版本（v4 = 当前最新）
const protocolVersion = 4;

/// 最小兼容协议版本（保持向前兼容）
const minProtocolVersion = 3;

/// 请求超时（毫秒）
const requestTimeoutMs = 30000;

/// 预握手 tick 间隔（毫秒）
const preHandshakeTickIntervalMs = 30000;

/// Gap #2: 默认 maxPayload（spec §2.2 = 26_214_400 bytes / 25MB）。
///
/// 在 hello-ok.policy.maxPayload 缺失或 hello-ok 还未到达时用作降级值。
/// 客户端在 [ConnectionManager.sendRequest] 序列化前守门，超过此大小
/// 抛 [PayloadTooLargeException]，避免 OOM。
const defaultMaxPayloadBytes = 26214400;

/// Gap #2: 默认 maxBufferedBytes（spec §2.2 = 52_428_800 bytes / 50MB）。
///
/// Gateway 限制出站缓冲区的总字节数；客户端用来判断何时停止读 WebSocket
/// 防止内存爆。
const defaultMaxBufferedBytes = 52428800;

// ============================================================================
// 连接参数常量（对齐 docs/technical/api-protocol.md §2.2–2.4）
// ============================================================================

/// Operator scope 列表（与官方 iOS 客户端一致）。
const operatorScopes = <String>[
  'operator.admin',
  'operator.read',
  'operator.write',
  'operator.approvals',
  'operator.pairing',
];

/// OpenClaw 客户端标识枚举值（§2.3）。
class ClientIds {
  ClientIds._();
  static const String ios = 'openclaw-ios';
  static const String android = 'openclaw-android';
  static const String macos = 'openclaw-macos';
  static const String controlUi = 'openclaw-control-ui';
  static const String cli = 'cli';
  static const String gatewayClient = 'gateway-client';

  /// 根据平台字符串返回对应的 client.id。
  static String forPlatform(String platform) {
    return switch (platform) {
      'ios' => ios,
      'android' => android,
      'macos' => macos,
      _ => gatewayClient,
    };
  }
}

// ============================================================================
// 帧类型
// ============================================================================

enum FrameType { req, res, event }

// ============================================================================
// 方法名常量
// ============================================================================

/// 协议定义的方法名（对齐 docs/technical/api-protocol.md §4）。
class Methods {
  Methods._();
  static const String connect = 'connect';
  static const String agentsList = 'agents.list';
  static const String chatSend = 'chat.send';
  static const String chatHistory = 'chat.history';
  static const String chatAbort = 'chat.abort';
  static const String agentWait = 'agent.wait';
  static const String sessionsList = 'sessions.list';
  static const String sessionsResolve = 'sessions.resolve';
  static const String sessionsCreate = 'sessions.create';
  static const String health = 'health';
  static const String deviceTokenRotate = 'device.token.rotate';
  static const String deviceTokenRevoke = 'device.token.revoke';
}

/// 协议定义的事件名（对齐 OpenClaw Gateway v2026.6.6 实测）。
///
/// 真实 Gateway 推送两类核心事件：
/// - **chat**：UI 面向前端的事件，`state: "delta"|"final"`，final 时携带完整 message
/// - **agent**：详细的后端事件，`stream: "assistant"|"tool"|"lifecycle"|"item"`
class Events {
  Events._();
  static const String connectChallenge = 'connect.challenge';
  static const String chat = 'chat';
  static const String agent = 'agent';
  static const String tick = 'tick';
  static const String presence = 'presence';
  static const String health = 'health';
  static const String shutdown = 'shutdown';

  /// Gap #6: diagnostic event emitted by the Gateway when an incoming
  /// payload exceeds `policy.maxPayload`. The client surfaces this as a
  /// [LargePayloadNotice] on the diagnostic stream so the UI can show
  /// a user-visible hint ("message too large, reduce size"). Spec §2.7.
  static const String payloadLarge = 'payload.large';
}

// ============================================================================
// 请求构造
// ============================================================================

/// 构造一个请求帧 JSON。
String buildRequest({
  required String id,
  required String method,
  required Map<String, dynamic> params,
}) {
  return jsonEncode({
    'type': 'req',
    'id': id,
    'method': method,
    'params': params,
  });
}

/// 构造 connect 请求参数（握手第二步）。
///
/// 对齐 docs/technical/api-protocol.md §2.2 完整的 connect 请求格式。
///
/// [locale] 为客户端地区（如 `zh-CN`、`en-US`），由调用方从设备获取。
/// [clientId]/[clientVersion]/[platform] 来自设备信息。
/// [clientMode] 为客户端模式（§2.3），operator 客户端应使用 `ui`。
/// [role] 为客户端角色，operator 客户端固定为 `operator`。
/// [scopes] 为请求的 operator 权限列表（§2.4）。
Map<String, dynamic> buildConnectParams({
  required String token,
  required String deviceId,
  required ConnectionConfig config,
  String? signature,
  int? signedAt,
  String? nonce,
  List<String> caps = const [],
  List<String> commands = const [],
  Map<String, bool> permissions = const {},
}) {
  final client = <String, dynamic>{
    'id': config.clientId,
    'version': config.clientVersion,
    'platform': config.platform,
    'mode': config.clientMode,
  };
  if (config.clientDisplayName != null) {
    client['displayName'] = config.clientDisplayName;
  }
  // deviceFamily is non-nullable on ConnectionConfig (default 'phone')
  // and is part of the v3 signature payload — always write to wire so
  // the server-side signature reconstruction matches the client payload.
  client['deviceFamily'] = config.deviceFamily;
  if (config.modelIdentifier != null) {
    client['modelIdentifier'] = config.modelIdentifier;
  }

  final params = <String, dynamic>{
    'minProtocol': minProtocolVersion,
    'maxProtocol': protocolVersion,
    'client': client,
    'role': config.role,
    'scopes': config.scopes,
    'caps': caps,
    'commands': commands,
    'permissions': permissions,
    'device': {
      'id': deviceId,
      if (config.devicePublicKey != null) 'publicKey': config.devicePublicKey,
      if (signature != null) 'signature': signature,
      if (signedAt != null) 'signedAt': signedAt,
      if (nonce != null) 'nonce': nonce,
    },
    'auth': {'token': token},
    'locale': config.locale,
    'userAgent': 'xiahub/${config.clientVersion}',
  };
  return params;
}

/// 构造 Ed25519 V3 签名 Payload（§2.5）。
///
/// 格式：
/// ```
/// "v3|{deviceId}|{clientId}|{clientMode}|{role}|{scopes}|{signedAtMs}|{token}|{nonce}|{platform}|{deviceFamily}"
/// ```
///
/// 其中 scopes 为逗号分隔字符串，platform 和 deviceFamily 必须小写。
String buildV3SignaturePayload({
  required String deviceId,
  required String clientId,
  required String clientMode,
  required String role,
  required List<String> scopes,
  required int signedAtMs,
  required String token,
  required String nonce,
  required String platform,
  String deviceFamily = 'phone',
}) {
  // Light defense: spec §2.5 mandates an 11-segment pipe-separated
  // payload with a non-empty deviceFamily at the end. A null/empty
  // deviceFamily would emit a literal "|null|" or "||" segment, which
  // the server-side parser would reject. ConnectionConfig defaults
  // deviceFamily to 'phone' so this only fires if a caller explicitly
  // nulls the field — fail-fast in dev/test, no runtime cost in release.
  assert(
    deviceFamily.isNotEmpty,
    'deviceFamily must be a non-empty string — DI must inject a '
    'platformOS()-derived value (e.g. "phone" or "desktop")',
  );
  final scopesStr = scopes.join(',');
  return 'v3|$deviceId|$clientId|$clientMode|$role|$scopesStr'
      '|$signedAtMs|$token|$nonce|${platform.toLowerCase()}|${deviceFamily.toLowerCase()}';
}

/// 构造 agents.list 请求。
String buildAgentsListRequest(String id) {
  return buildRequest(id: id, method: Methods.agentsList, params: {});
}

/// 构造 chat.send 请求（发送消息并接收流式响应）。
///
/// 对齐 OpenClaw Gateway v2026.6.6 实测：
/// - 方法：`chat.send`
/// - 必填：`sessionKey`（格式 `agent:{agentId}:{scope}`）+ `message`
/// - 幂等键：`idempotencyKey`（防重复执行，§3.6）
String buildChatSendRequest({
  required String id,
  required String sessionKey,
  required String message,
  required String idempotencyKey,
  Map<String, dynamic>? overrides,
}) {
  final params = <String, dynamic>{
    'sessionKey': sessionKey,
    'message': message,
    'idempotencyKey': idempotencyKey,
  };
  if (overrides != null) params['overrides'] = overrides;

  return buildRequest(id: id, method: Methods.chatSend, params: params);
}

/// 构造 chat.history 请求。
String buildChatHistoryRequest({
  required String id,
  required String agentId,
  String? sessionId,
  String? cursor,
  int limit = 50,
}) {
  final params = <String, dynamic>{'agentId': agentId, 'limit': limit};
  if (sessionId != null) params['sessionId'] = sessionId;
  if (cursor != null) params['cursor'] = cursor;

  return buildRequest(id: id, method: Methods.chatHistory, params: params);
}

/// 构造 sessions.resolve 请求（将 agentId 解析为 sessionId）。
String buildSessionsResolveRequest({
  required String id,
  required String agentId,
}) {
  return buildRequest(
    id: id,
    method: Methods.sessionsResolve,
    params: {'agentId': agentId},
  );
}

// ============================================================================
// 响应解析
// ============================================================================

/// 已解析的 Gateway 帧。
sealed class GatewayFrame {
  const GatewayFrame();
}

/// 响应帧 — 对应 `{"type":"res",...}`。
class ResponseFrame extends GatewayFrame {
  final String id;
  final bool ok;
  final Map<String, dynamic>? payload;
  final ProtocolError? error;

  const ResponseFrame({
    required this.id,
    required this.ok,
    this.payload,
    this.error,
  });
}

/// 事件帧 — 对应 `{"type":"event",...}`。
class EventFrame extends GatewayFrame {
  final String event;
  final Map<String, dynamic>? payload;
  final int? seq;

  const EventFrame({required this.event, this.payload, this.seq});
}

/// 协议错误。
class ProtocolError {
  final String code;
  final String message;
  final bool? retryable;
  final int? retryAfterMs;
  final Map<String, dynamic>? details;

  const ProtocolError({
    required this.code,
    required this.message,
    this.retryable,
    this.retryAfterMs,
    this.details,
  });

  factory ProtocolError.fromJson(Map<String, dynamic> json) {
    // F-1: details may be a non-Map value (e.g. AUTH_TOKEN_MISMATCH returns
    // `"details": "retry_with_device_token"` per spec §A.9). The previous
    // `as Map<String, dynamic>?` cast crashed with TypeError on those,
    // taking down the connect handshake. Narrow to Map only; non-Map payloads
    // coerce to null so downstream `details?['...']` stays safe.
    final rawDetails = json['details'];
    final details = rawDetails is Map
        ? Map<String, dynamic>.from(rawDetails)
        : null;
    return ProtocolError(
      code: json['code'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? 'Unknown error',
      retryable: json['retryable'] as bool?,
      retryAfterMs: json['retryAfterMs'] as int?,
      details: details,
    );
  }
}

// ============================================================================
// 帧解析器
// ============================================================================

/// 将原始 JSON 字符串解析为 [GatewayFrame]。
///
/// 解析失败时返回 [ResponseFrame] 携带解析错误信息。
GatewayFrame parseFrame(String rawJson) {
  try {
    final json = jsonDecode(rawJson) as Map<String, dynamic>;
    final type = json['type'] as String?;

    return switch (type) {
      'res' => _parseResponse(json),
      'event' => _parseEvent(json),
      _ => ResponseFrame(
        id: json['id'] as String? ?? '',
        ok: false,
        error: const ProtocolError(
          code: 'PARSE_ERROR',
          message: 'Unknown frame type',
        ),
      ),
    };
  } catch (e) {
    return ResponseFrame(
      id: '',
      ok: false,
      error: ProtocolError(
        code: 'PARSE_ERROR',
        message: 'Failed to parse frame: $e',
      ),
    );
  }
}

ResponseFrame _parseResponse(Map<String, dynamic> json) {
  final ok = json['ok'] as bool? ?? false;
  return ResponseFrame(
    id: json['id'] as String? ?? '',
    ok: ok,
    payload: ok ? (json['payload'] as Map<String, dynamic>?) : null,
    error: !ok && json['error'] != null
        ? ProtocolError.fromJson(json['error'])
        : null,
  );
}

EventFrame _parseEvent(Map<String, dynamic> json) {
  return EventFrame(
    event: json['event'] as String? ?? 'unknown',
    payload: json['payload'] as Map<String, dynamic>?,
    seq: json['seq'] as int?,
  );
}

// ============================================================================
// Chat 事件解析（对齐 OpenClaw Gateway v2026.6.6 实测）
// ============================================================================

/// `chat` 事件的状态（实测 Gateway v2026.6.6）。
enum ChatState { delta, final_, unknown }

/// 解析后的 `chat` 事件数据。
class ChatEventData {
  final String? runId;
  final String sessionKey;
  final ChatState state;

  /// `state: "delta"` 时的增量文本。
  final String? deltaText;

  /// `state: "final"` 时的完整消息 payload（含 agentId, content, role 等）。
  final Map<String, dynamic>? message;

  final int? seq;

  const ChatEventData({
    this.runId,
    required this.sessionKey,
    required this.state,
    this.deltaText,
    this.message,
    this.seq,
  });
}

/// `agent` 事件的子流类型（实测 Gateway v2026.6.6）。
enum AgentStreamType { assistant, tool, lifecycle, item, message, unknown }

/// 解析后的 `agent` 事件数据。
class AgentEventData {
  final String? runId;
  final String sessionKey;
  final AgentStreamType stream;
  final Map<String, dynamic> data;

  const AgentEventData({
    this.runId,
    required this.sessionKey,
    required this.stream,
    required this.data,
  });
}

// ---------- 解析函数 ----------

/// 从 `chat` 事件的 payload 中解析 [ChatEventData]。
ChatEventData parseChatEvent(Map<String, dynamic> payload) {
  final stateStr = payload['state'] as String? ?? 'unknown';
  return ChatEventData(
    runId: payload['runId'] as String?,
    sessionKey: payload['sessionKey'] as String? ?? '',
    state: switch (stateStr) {
      'delta' => ChatState.delta,
      'final' => ChatState.final_,
      _ => ChatState.unknown,
    },
    deltaText: payload['deltaText'] as String?,
    message: payload['message'] as Map<String, dynamic>?,
    seq: payload['seq'] as int?,
  );
}

/// 从 `agent` 事件的 payload 中解析 [AgentEventData]。
AgentEventData parseAgentEvent(Map<String, dynamic> payload) {
  final streamStr = payload['stream'] as String? ?? 'unknown';
  return AgentEventData(
    runId: payload['runId'] as String?,
    sessionKey: payload['sessionKey'] as String? ?? '',
    stream: switch (streamStr) {
      'assistant' => AgentStreamType.assistant,
      'tool' => AgentStreamType.tool,
      'lifecycle' => AgentStreamType.lifecycle,
      'item' => AgentStreamType.item,
      'message' => AgentStreamType.message,
      _ => AgentStreamType.unknown,
    },
    data: payload['data'] as Map<String, dynamic>? ?? payload,
  );
}

// ============================================================================
// 流式事件（公开类，跨 agent 路由）
// ============================================================================

/// 流式事件基类 — 携带 agentId 用于多 Agent 场景下的精确路由。
sealed class StreamingEvent {
  final String agentId;
  const StreamingEvent({required this.agentId});
}

/// 增量文本片段。
class StreamingDelta extends StreamingEvent {
  final String text;
  const StreamingDelta({required super.agentId, required this.text});
}

/// 流式结束信号。
class StreamingDone extends StreamingEvent {
  const StreamingDone({required super.agentId});
}

// ============================================================================
// 诊断事件（公开类，跨 agent 路由）
// ============================================================================

/// Gap #6: payload.large 事件的解析结果（spec §2.7）。
///
/// 当客户端发出超过 `policy.maxPayload` 的请求时，Gateway 主动发此事件
/// 给客户端，告知"这条消息被拒收"。客户端应通过 [IGatewayClient] 上的
/// 诊断 stream 转发给 UI 层，让用户知道消息没成功（而不是静默失败）。
///
/// 字段对齐 spec §2.7 描述：
/// - [sessionKey]: 关联的会话 key（用于回查是哪条消息被拒）
/// - [size]: 实际负载字节数
/// - [limit]: Gateway 的 maxPayload 上限（客户端可用来做文案"超过 X 上限"）
class LargePayloadNotice {
  final String sessionKey;
  final int size;
  final int limit;

  const LargePayloadNotice({
    required this.sessionKey,
    required this.size,
    required this.limit,
  });
}

/// 从 `payload.large` 事件的 payload 中解析 [LargePayloadNotice]。
///
/// 容错策略：缺失字段降级为 0 / 空串，调用方决定如何展示。
LargePayloadNotice parseLargePayloadEvent(Map<String, dynamic> payload) {
  return LargePayloadNotice(
    sessionKey: payload['sessionKey'] as String? ?? '',
    size: payload['size'] as int? ?? 0,
    limit: payload['limit'] as int? ?? 0,
  );
}

// ============================================================================
// Delta 聚合缓冲（公开类，可独立单元测试）
// ============================================================================

/// Accumulates incremental text deltas from streaming events.
///
/// Used for either `chat` deltaText or `agent` assistant data.delta.
///
/// Uses [StringBuffer] for amortized O(1) append — consistent with
/// [ChatViewModel._streamBuffer] (see perf fix #12).
class StreamingBuffer {
  final String sessionKey;
  final StringBuffer _buffer = StringBuffer();

  StreamingBuffer({required this.sessionKey});

  /// Append a delta fragment.
  void append(String delta) {
    _buffer.write(delta);
  }

  /// The full accumulated text so far.
  String get text => _buffer.toString();

  /// Reset to empty.
  void reset() {
    _buffer.clear();
  }

  /// Whether no delta has been received yet.
  bool get isEmpty => _buffer.isEmpty;
}

// ============================================================================
// Session key → agent ID resolution
// ============================================================================

/// Resolve a [sessionKey] to its remote agent ID.
///
/// Resolution order:
/// 1. Explicit mapping (primary path — populated by chat.send)
/// 2. String parsing fallback (backward compat — parses "agent:{id}:{scope}")
/// 3. Returns `null` when unresolvable; callers MUST handle null by dropping
///    the event and logging.
///
/// This is a pure protocol-level function — no dependency on any client
/// implementation, so it lives here rather than on [WsGatewayClient].
/// Callers are responsible for logging unresolvable session keys.
String? resolveAgentId(String sessionKey, Map<String, String> mapping) {
  // 1. Explicit mapping (primary path)
  final mapped = mapping[sessionKey];
  if (mapped != null) return mapped;

  // 2. String parsing fallback (backward compat with Gateway < v2026.6.6)
  final parts = sessionKey.split(':');
  if (parts.length >= 2 && parts[0] == 'agent' && parts[1].isNotEmpty) {
    return parts[1];
  }

  // 3. Unresolvable — caller should log and drop
  return null;
}

// ============================================================================
// 连接配置值对象
// ============================================================================

/// 不可变值对象，聚合 [ConnectionManager] 所需的客户端/设备/认证配置参数。
///
/// 将 [ConnectionManager] 构造函数从 17 个参数收敛为 6 个，
/// 消除 [WsGatewayClient] 在 [connect] 和 [testConnection] 中的重复参数复制。
///
/// 字段对齐 docs/technical/api-protocol.md §2.2–2.5。
class ConnectionConfig {
  final String locale;
  final String platform;

  /// Device family (e.g. `phone`, `desktop`). Non-nullable with default
  /// `'phone'` so that [buildConnectParams] always writes a non-null
  /// deviceFamily field on the wire — matching the v3 signature payload
  /// (which always includes the deviceFamily segment per spec §2.5).
  /// This is Bug #1 fix: previously nullable default caused the wire
  /// field to be omitted while the signed payload still contained
  /// `|phone|`, so the server-side signature reconstruction mismatched
  /// and the connection was rejected with DEVICE_AUTH_SIGNATURE_INVALID.
  final String deviceFamily;
  final String? modelIdentifier;
  final String? clientDisplayName;
  final String clientVersion;
  final String clientId;
  final String clientMode;
  final String role;
  final List<String> scopes;
  final String? devicePublicKey;
  final Future<String> Function(String v3Payload)? signPayload;

  ConnectionConfig({
    this.locale = 'zh-CN',

    /// Default platform string. Spec §2.3 lists valid `client.id` enum
    /// values; 'flutter' is a framework name, not a platform. The DI path
    /// in `lib/app/di/providers.dart` always overrides this with the real
    /// OS string from [platformOS], so the default only matters for mock
    /// and unit-test paths. Picked 'web' because:
    ///  - it's a legal [platformOS] return value (kIsWeb branch);
    ///  - it routes to 'gateway-client' via [ClientIds.forPlatform]
    ///    (same as the old 'flutter' default).
    /// See Bug #3 in `docs/technical/api-protocol.md` audit history.
    this.platform = 'web',
    this.deviceFamily = 'phone',
    this.modelIdentifier,
    this.clientDisplayName,
    this.clientVersion = '1.0.0',
    String? clientId,
    this.clientMode = 'ui',
    this.role = 'operator',
    List<String>? scopes,
    this.devicePublicKey,
    this.signPayload,
  }) : clientId = clientId ?? ClientIds.forPlatform(platform),
       scopes = List<String>.unmodifiable(scopes ?? operatorScopes);

  /// 创建修改了部分字段的新 [ConnectionConfig]。
  ConnectionConfig copyWith({
    String? locale,
    String? platform,
    String? deviceFamily,
    Object? modelIdentifier = CopyWithSentinel.instance,
    Object? clientDisplayName = CopyWithSentinel.instance,
    String? clientVersion,
    String? clientId,
    String? clientMode,
    String? role,
    List<String>? scopes,
    Object? devicePublicKey = CopyWithSentinel.instance,
    Object? signPayload = CopyWithSentinel.instance,
  }) {
    return ConnectionConfig(
      locale: locale ?? this.locale,
      platform: platform ?? this.platform,
      deviceFamily: deviceFamily ?? this.deviceFamily,
      modelIdentifier: copyWithNullable(modelIdentifier, this.modelIdentifier),
      clientDisplayName: copyWithNullable(
        clientDisplayName,
        this.clientDisplayName,
      ),
      clientVersion: clientVersion ?? this.clientVersion,
      clientId: clientId ?? this.clientId,
      clientMode: clientMode ?? this.clientMode,
      role: role ?? this.role,
      scopes: scopes != null ? List<String>.unmodifiable(scopes) : this.scopes,
      devicePublicKey: copyWithNullable(devicePublicKey, this.devicePublicKey),
      signPayload: copyWithNullable(signPayload, this.signPayload),
    );
  }
}
