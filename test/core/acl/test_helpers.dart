import 'dart:async';
import 'dart:convert';

import 'package:claw_hub/core/acl/i_device_token_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ============================================================================
// Extracted from connection_manager_test.dart & ws_gateway_client_test.dart
//
// These helpers were previously duplicated ~150 lines verbatim across both
// files.  When the ConnectionManager API or protocol JSON format changes,
// update this single file instead of two.
// ============================================================================

// ---------------------------------------------------------------------------
// Mocktail fakes
// ---------------------------------------------------------------------------

class MockWebSocketChannel extends Mock implements WebSocketChannel {}

class MockWebSocketSink extends Mock implements WebSocketSink {
  /// Override to ensure [close] returns a Future, not null.
  @override
  Future<dynamic> close([int? closeCode, String? closeReason]) =>
      Future.value();
}

// ---------------------------------------------------------------------------
// Fake timer — controllable [Timer] for unit-testing time-dependent behavior.
// Extracted from connection_manager_test.dart & connection_manager_shutdown_test.dart.
// ---------------------------------------------------------------------------

class FakeTimer implements Timer {
  final Duration duration;
  final void Function() _callback;
  bool _cancelled = false;
  bool _fired = false;

  FakeTimer(this.duration, this._callback);

  @override
  void cancel() {
    _cancelled = true;
  }

  @override
  bool get isActive => !_cancelled && !_fired;

  @override
  int get tick => 0;

  bool get isCancelled => _cancelled;
  bool get isFired => _fired;

  void fire() {
    if (_cancelled || _fired) return;
    _fired = true;
    _callback();
  }

  // ignore: non_constant_identifier_names
  static Timer Function(Duration, void Function()) NOOP = (_, _) =>
      FakeTimer(Duration.zero, () {});
}

class FakeTimerFactory {
  final List<FakeTimer> timers = [];

  Timer call(Duration duration, void Function() callback) {
    final timer = FakeTimer(duration, callback);
    timers.add(timer);
    return timer;
  }

  FakeTimer? get lastTimer => timers.isEmpty ? null : timers.last;
  Iterable<FakeTimer> get activeTimers => timers.where((t) => t.isActive);

  void fireLast() {
    final t = lastTimer;
    if (t != null && t.isActive) t.fire();
  }

  void fireAll() {
    for (final t in timers) {
      if (t.isActive) t.fire();
    }
  }

  void reset() => timers.clear();
}

// ---------------------------------------------------------------------------
// In-memory [IDeviceTokenStore] for tests.  Tracks call counts so retry tests
// can assert "load() was actually called during retry", not just "the manager
// emitted hello-ok eventually".  Extracted from connection_manager_auth_retry_test.dart
// and connection_manager_device_token_test.dart.
// ---------------------------------------------------------------------------

class FakeDeviceTokenStore implements IDeviceTokenStore {
  final Map<String, String> _store = {};

  int loadCalls = 0;
  int deleteCalls = 0;

  /// Read-only view of the backing map — tests use this to assert that the
  /// manager saved/deleted the expected keys without poking into private
  /// state. Public because the field's library-private (`_`) name is
  /// inaccessible from other test files.
  Map<String, String> get tokens => Map.unmodifiable(_store);

  /// Pre-populate the store without going through [save] — useful for tests
  /// that want to simulate "device already paired before this test ran".
  void seed(String instanceId, String deviceToken) {
    _store[instanceId] = deviceToken;
  }

  @override
  Future<void> save(String instanceId, String deviceToken) async {
    _store[instanceId] = deviceToken;
  }

  @override
  Future<String?> load(String instanceId) async {
    loadCalls++;
    final value = _store[instanceId];
    if (value == null || value.isEmpty) return null;
    return value;
  }

  @override
  Future<void> delete(String instanceId) async {
    deleteCalls++;
    _store.remove(instanceId);
  }
}

// ---------------------------------------------------------------------------
// Controllable WebSocket helper
// ---------------------------------------------------------------------------

class ControllableWebSocket {
  final MockWebSocketChannel channel = MockWebSocketChannel();
  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final Completer<WebSocketChannel> readyCompleter =
      Completer<WebSocketChannel>();
  final MockWebSocketSink sink = MockWebSocketSink();
  final List<String> sentFrames = [];

  ControllableWebSocket._();

  factory ControllableWebSocket.create() {
    final ws = ControllableWebSocket._();
    _wire(ws);
    when(() => ws.channel.ready).thenAnswer((_) => ws.readyCompleter.future);
    return ws;
  }

  factory ControllableWebSocket.ready() {
    final ws = ControllableWebSocket._();
    _wire(ws);
    // ignore: void_checks
    when(() => ws.channel.ready).thenAnswer((_) => Future.value(ws.channel));
    return ws;
  }

  static void _wire(ControllableWebSocket ws) {
    when(() => ws.channel.stream).thenAnswer((_) => ws.incoming.stream);
    when(() => ws.channel.sink).thenReturn(ws.sink);
    when(() => ws.sink.add(any())).thenAnswer((inv) {
      final data = inv.positionalArguments.first;
      if (data is String) ws.sentFrames.add(data);
    });
  }

  void simulateServerFrame(String json) => incoming.add(json);
  void simulateError(Object error) => incoming.addError(error);
  void simulateServerClose() => incoming.close();
  void completeHandshake() => readyCompleter.complete(channel);
}

// ---------------------------------------------------------------------------
// Protocol JSON builders
// ---------------------------------------------------------------------------

Future<void> pumpMicrotasks() => Future.delayed(Duration.zero);

String challengeJson({String nonce = 'test-nonce'}) =>
    '{"type":"event","event":"connect.challenge","payload":{"nonce":"$nonce"}}';

String helloOkJson(String id) =>
    '{"type":"res","id":"$id","ok":true,'
    '"payload":{"type":"hello-ok","protocol":4,"policy":{"tickIntervalMs":15000}}}';

/// Build a `hello-ok` response that also carries a freshly issued
/// `auth.deviceToken` (OpenClaw spec §2.2 — first pairing).
///
/// Used by deviceToken persistence tests in
/// `connection_manager_device_token_test.dart` (差距 #1 fix).
String helloOkWithDeviceTokenJson(String id, String deviceToken) =>
    '{"type":"res","id":"$id","ok":true,'
    '"payload":{"type":"hello-ok","protocol":4,'
    '"auth":{"deviceToken":"$deviceToken","role":"operator",'
    '"scopes":["operator.read","operator.write"]},'
    '"policy":{"tickIntervalMs":15000}}}';

/// Extract the request ID from a sent JSON frame.
String extractReqId(String sentFrame) {
  final m = RegExp(r'"id":"([^"]+)"').firstMatch(sentFrame);
  return m!.group(1)!;
}

/// Extract the bearer token from `params.auth.token` in a sent connect frame.
String extractAuthToken(String sentFrame) {
  final decoded = jsonDecode(sentFrame) as Map<String, dynamic>;
  final params = decoded['params'] as Map<String, dynamic>;
  final auth = params['auth'] as Map<String, dynamic>;
  return auth['token'] as String;
}

/// Build a `chat` event frame with `state: "delta"` (Gateway v2026.6.6).
String chatDeltaJson({
  String sessionKey = 'agent:r-1:main',
  String deltaText = 'Hello!',
  int seq = 1,
}) =>
    '{"type":"event","event":"chat","payload":'
    '{"sessionKey":"$sessionKey","state":"delta",'
    '"deltaText":"$deltaText","seq":$seq}}';

/// Build a `chat` event frame with `state: "final"` (Gateway v2026.6.6).
/// [messageContent] is the complete message JSON embedded in the payload.
String chatFinalJson({
  String sessionKey = 'agent:r-1:main',
  String messageContent =
      '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
      '"content":"Hello World","role":"agent","type":"text"}',
  int seq = 10,
}) =>
    '{"type":"event","event":"chat","payload":'
    '{"sessionKey":"$sessionKey","state":"final",'
    '"message":$messageContent,"seq":$seq}}';

/// Build an `agent` event frame with `stream: "tool"` (Gateway v2026.6.6).
String agentToolJson({
  String sessionKey = 'agent:r-1:main',
  String phase = 'start',
  String toolName = 'search',
  String toolCallId = 'tc-1',
}) =>
    '{"type":"event","event":"agent","payload":'
    '{"sessionKey":"$sessionKey","stream":"tool",'
    '"data":{"phase":"$phase","name":"$toolName","toolCallId":"$toolCallId"}}}';

/// Build an `agent` event frame with `stream: "assistant"` (Gateway v2026.6.6).
String agentAssistantJson({
  String sessionKey = 'agent:r-1:main',
  String delta = 'Hello',
}) =>
    '{"type":"event","event":"agent","payload":'
    '{"sessionKey":"$sessionKey","stream":"assistant",'
    '"data":{"delta":"$delta"}}}';

/// Build an `agent` event frame with `stream: "message"` (v3 Gateway compat).
String agentMessageJson({
  String sessionKey = 'agent:r-1:main',
  String delta = 'Hello from v3',
}) =>
    '{"type":"event","event":"agent","payload":'
    '{"sessionKey":"$sessionKey","stream":"message",'
    '"data":{"delta":"$delta"}}}';

/// Build an `agent` event frame with `stream: "lifecycle"` (Gateway v2026.6.6).
String agentLifecycleJson({
  String sessionKey = 'agent:r-1:main',
  String phase = 'end',
}) =>
    '{"type":"event","event":"agent","payload":'
    '{"sessionKey":"$sessionKey","stream":"lifecycle",'
    '"data":{"phase":"$phase"}}}';

const String tickJson = '{"type":"event","event":"tick","payload":{}}';

const String shutdownJson = '{"type":"event","event":"shutdown","payload":{}}';

/// Build a `chat.history` response frame.
///
/// Pass [cursor] OR [nextCursor] to verify the defensive read in
/// `WsGatewayClient.fetchMessageHistory` (Bug #2). When both are
/// provided, [nextCursor] wins (forward-compat with future Gateway
/// versions that may switch to OpenAI-style `nextCursor` naming).
String chatHistoryResponseJson({
  required String id,
  String? cursor,
  String? nextCursor,
}) {
  final cursorField = cursor != null ? '"cursor":"$cursor",' : '';
  final nextCursorField = nextCursor != null
      ? '"nextCursor":"$nextCursor",'
      : '';
  return '{"type":"res","id":"$id","ok":true,'
      '"payload":{"messages":[],$cursorField$nextCursorField'
      '"hasMore":false}}';
}
