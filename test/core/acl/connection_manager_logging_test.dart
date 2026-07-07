import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

ConnectionConfig testConfig() => ConnectionConfig();

/// Records every logXxx call as a map for assertions.
class RecordingApiLogger implements IApiLogger {
  final List<({String method, String requestId, int byteSize})> requests = [];
  final List<({String requestId, bool ok, String? errorCode})> responses = [];
  final List<({String? state, String message})> states = [];

  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) {
    requests.add((method: method, requestId: requestId, byteSize: byteSize));
  }

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) {
    responses.add((requestId: requestId, ok: ok, errorCode: errorCode));
  }

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
  }) {
    states.add((state: state, message: message));
  }
}

/// Every logXxx throws — for the “logging must not break the protocol path” contract.
class ThrowingApiLogger implements IApiLogger {
  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) => throw StateError('boom');

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) => throw StateError('boom');

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
  }) => throw StateError('boom');
}

void main() {
  late ControllableWebSocket ws;
  late ConnectionManager cm;
  late RecordingApiLogger logger;

  ConnectionManager buildCm({IApiLogger? apiLogger}) => ConnectionManager(
    instanceId: 'test-instance',
    gatewayUrl: 'ws://localhost:9999/ws',
    token: 'test-token',
    deviceId: 'test-device',
    config: testConfig(),
    webSocketFactory: (uri) => ws.channel,
    apiLogger: apiLogger,
  );

  Future<void> connectToHelloOk(ConnectionManager cm) async {
    // ws is ControllableWebSocket.ready() — channel.ready already resolved,
    // so (unlike the .create() variant) we do NOT call completeHandshake().
    cm.connect();
    await pumpMicrotasks();
    ws.simulateServerFrame(challengeJson());
    await pumpMicrotasks();
    final connectId = extractReqId(ws.sentFrames.last);
    ws.simulateServerFrame(helloOkJson(connectId));
    await pumpMicrotasks();
  }

  setUp(() {
    ws = ControllableWebSocket.ready();
    logger = RecordingApiLogger();
    cm = buildCm(apiLogger: logger);
  });

  test(
    'sendRequest logs req with threaded method + res with duration',
    () async {
      await connectToHelloOk(cm);

      final resFuture = cm.sendRequest(Methods.chatHistory, {
        'sessionKey': 'agent:1:main',
      });
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.last);
      ws.simulateServerFrame(chatHistoryResponseJson(id: reqId));
      await resFuture;

      expect(
        logger.requests.any((r) => r.method == Methods.chatHistory),
        isTrue,
      );
      expect(logger.responses.any((r) => r.requestId == reqId && r.ok), isTrue);
    },
  );

  test(
    'logResponse is called AFTER completer.complete — throwing logger does not stall sendRequest',
    () async {
      final throwingCm = buildCm(apiLogger: ThrowingApiLogger());
      await connectToHelloOk(throwingCm);

      final resFuture = throwingCm
          .sendRequest(Methods.agentsList, {})
          .timeout(const Duration(seconds: 2));
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.last);
      ws.simulateServerFrame(
        '{"type":"res","id":"$reqId","ok":true,"payload":{}}',
      );
      // Must complete, not time out — proves logResponse (which throws) ran after complete.
      final res = await resFuture;
      expect(res.ok, isTrue);
    },
  );

  test(
    'handshake: connect req logged (method=connect) + hello-ok → state connected',
    () async {
      await connectToHelloOk(cm);
      expect(logger.requests.any((r) => r.method == Methods.connect), isTrue);
      expect(logger.states.any((s) => s.state == 'connected'), isTrue);
    },
  );

  test('tick timeout → state recovering + "Tick timeout" message', () async {
    // Use a FakeTimerFactory so we can deterministically fire the tick watchdog
    // (ConnectionManager defaults to Timer.new, which we can't fire from a test).
    final fakeTimers = FakeTimerFactory();
    final tickCm = ConnectionManager(
      instanceId: 'test-instance',
      gatewayUrl: 'ws://localhost:9999/ws',
      token: 'test-token',
      deviceId: 'test-device',
      config: testConfig(),
      webSocketFactory: (uri) => ws.channel,
      timerFactory: fakeTimers.call,
      apiLogger: logger,
    );
    await connectToHelloOk(tickCm);
    // Arm the tick watchdog by simulating a tick (resets the timeout timer).
    ws.simulateServerFrame(tickJson);
    await pumpMicrotasks();
    // The tick-watchdog FakeTimer is the latest active timer; fire it to
    // simulate a timeout (no further tick arrives within 2× tickInterval).
    fakeTimers.fireLast();
    await pumpMicrotasks();
    expect(
      logger.states.any(
        (s) => s.state == 'recovering' && s.message.contains('Tick timeout'),
      ),
      isTrue,
    );
  });

  test(
    '_immediateReconnect (graceful shutdown) → state disconnected logged',
    () async {
      await connectToHelloOk(cm);
      ws.simulateServerFrame(shutdownJson);
      await pumpMicrotasks();
      await pumpMicrotasks();
      expect(logger.states.any((s) => s.state == 'disconnected'), isTrue);
    },
  );

  test('buffer overflow → state-null "Buffer overflow" log', () async {
    // hello-ok with tiny maxBufferedBytes so a small request overflows.
    cm.connect();
    await pumpMicrotasks();
    ws.simulateServerFrame(challengeJson());
    await pumpMicrotasks();
    final connectId = extractReqId(ws.sentFrames.last);
    ws.simulateServerFrame(
      '{"type":"res","id":"$connectId","ok":true,'
      '"payload":{"type":"hello-ok","protocol":4,'
      '"policy":{"tickIntervalMs":15000,"maxPayload":26214400,"maxBufferedBytes":50}}}',
    );
    await pumpMicrotasks();

    // A request whose payloadSize > 50 → BufferOverflowException.
    await expectLater(
      cm.sendRequest(Methods.agentsList, {}),
      throwsA(isA<BufferOverflowException>()),
    );
    expect(
      logger.states.any((s) => s.message.contains('Buffer overflow')),
      isTrue,
    );
  });

  test('EventFrame (chat delta) → no log call (filtering)', () async {
    await connectToHelloOk(cm);
    final beforeReq = logger.requests.length;
    final beforeRes = logger.responses.length;
    final beforeState = logger.states.length;
    ws.simulateServerFrame(chatDeltaJson());
    await pumpMicrotasks();
    expect(logger.requests.length, beforeReq);
    expect(logger.responses.length, beforeRes);
    // chat delta may emit a state? No — only _handleEvent routes it; no state log.
    expect(logger.states.length, beforeState);
  });

  test(
    'throwing-logger contract: connect succeeds when every logXxx throws',
    () async {
      final throwingCm = buildCm(apiLogger: ThrowingApiLogger());
      await connectToHelloOk(
        throwingCm,
      ); // must not throw despite logger throwing
      expect(throwingCm.state, GatewayConnectionState.connected);
    },
  );
}
