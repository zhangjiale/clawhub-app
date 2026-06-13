import 'dart:convert';

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

/// 协议定义的方法名。
class Methods {
  Methods._();
  static const String connect = 'connect';
  static const String agentsList = 'agents.list';
  static const String agent = 'agent';
  static const String agentWait = 'agent.wait';
  static const String chatHistory = 'chat.history';
  static const String sessionsList = 'sessions.list';
  static const String sessionsResolve = 'sessions.resolve';
  static const String sessionsCreate = 'sessions.create';
  static const String sessionsSend = 'sessions.send';
  static const String health = 'health';
}

/// 协议定义的事件名。
class Events {
  Events._();
  static const String connectChallenge = 'connect.challenge';
  static const String agent = 'agent';
  static const String tick = 'tick';
  static const String presence = 'presence';
  static const String health = 'health';
  static const String shutdown = 'shutdown';
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
  required String locale,
  required String deviceId,
  String clientId = 'openclaw-ios',
  String clientMode = 'ui',
  String? clientDisplayName,
  String clientVersion = '1.0.0',
  String platform = 'flutter',
  String? deviceFamily,
  String? modelIdentifier,
  String? devicePublicKey,
  String? signature,
  int? signedAt,
  String? nonce,
  List<String> caps = const [],
  List<String> commands = const [],
  Map<String, bool> permissions = const {},
  String role = 'operator',
  List<String> scopes = operatorScopes,
}) {
  final client = <String, dynamic>{
    'id': clientId,
    'version': clientVersion,
    'platform': platform,
    'mode': clientMode,
  };
  if (clientDisplayName != null) {
    client['displayName'] = clientDisplayName;
  }
  if (deviceFamily != null) {
    client['deviceFamily'] = deviceFamily;
  }
  if (modelIdentifier != null) {
    client['modelIdentifier'] = modelIdentifier;
  }

  final params = <String, dynamic>{
    'minProtocol': minProtocolVersion,
    'maxProtocol': protocolVersion,
    'client': client,
    'role': role,
    'scopes': scopes,
    'caps': caps,
    'commands': commands,
    'permissions': permissions,
    'device': {
      'id': deviceId,
      if (devicePublicKey != null) 'publicKey': devicePublicKey,
      if (signature != null) 'signature': signature,
      if (signedAt != null) 'signedAt': signedAt,
      if (nonce != null) 'nonce': nonce,
    },
    'auth': {'token': token},
    'locale': locale,
    'userAgent': 'xiahub/$clientVersion',
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
  final scopesStr = scopes.join(',');
  return 'v3|$deviceId|$clientId|$clientMode|$role|$scopesStr'
      '|$signedAtMs|$token|$nonce|${platform.toLowerCase()}|${deviceFamily.toLowerCase()}';
}

/// 构造 agents.list 请求。
String buildAgentsListRequest(String id) {
  return buildRequest(id: id, method: Methods.agentsList, params: {});
}

/// 构造 agent 请求（执行一次 agent turn，发送消息并等待回复）。
String buildAgentRequest({
  required String id,
  required String agentId,
  required String message,
  String? sessionId,
  Map<String, dynamic>? overrides,
}) {
  final params = <String, dynamic>{'agentId': agentId, 'message': message};
  if (sessionId != null) params['sessionId'] = sessionId;
  if (overrides != null) params['overrides'] = overrides;

  return buildRequest(id: id, method: Methods.agent, params: params);
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

  factory ProtocolError.fromJson(Map<String, dynamic> json) => ProtocolError(
    code: json['code'] as String? ?? 'UNKNOWN',
    message: json['message'] as String? ?? 'Unknown error',
    retryable: json['retryable'] as bool?,
    retryAfterMs: json['retryAfterMs'] as int?,
    details: json['details'] as Map<String, dynamic>?,
  );
}

/// Agent 事件中的流类型。
enum AgentStreamType { thinking, message, tool, lifecycle, unknown }

/// 解析后的 agent 事件数据。
class AgentEventData {
  final String? runId;
  final AgentStreamType stream;
  final Map<String, dynamic> data;

  const AgentEventData({this.runId, required this.stream, required this.data});
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

/// 从 agent 事件的 payload 中提取 [AgentEventData]。
AgentEventData parseAgentEvent(Map<String, dynamic> payload) {
  final streamStr = payload['stream'] as String? ?? 'unknown';
  return AgentEventData(
    runId: payload['runId'] as String?,
    stream: switch (streamStr) {
      'thinking' => AgentStreamType.thinking,
      'message' => AgentStreamType.message,
      'tool' => AgentStreamType.tool,
      'lifecycle' => AgentStreamType.lifecycle,
      _ => AgentStreamType.unknown,
    },
    data: payload['data'] as Map<String, dynamic>? ?? payload,
  );
}
