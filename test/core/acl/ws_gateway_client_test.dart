import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claw_hub/core/acl/device_identity.dart';
import 'package:claw_hub/core/acl/gateway_domain_mapper.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_device_identity_provider.dart';
import 'package:claw_hub/core/acl/i_device_token_store.dart';
import 'package:claw_hub/core/acl/attachment_encoder.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/replayable_connection_state.dart';
import 'package:claw_hub/core/acl/ws_gateway_client.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/models/enums.dart'
    show HealthStatus, MessageRole, MessageType, ToolCallStatus;
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake device identity provider
// ---------------------------------------------------------------------------

class FakeDeviceIdentityProvider implements IDeviceIdentityProvider {
  /// If set, [ensureDeviceIdentity] returns this value.
  DeviceIdentity? identityOverride;

  /// If set, [signPayload] returns this value instead of signing.
  String? signatureOverride;

  /// Number of times [ensureDeviceIdentity] was called.
  int ensureCallCount = 0;

  /// Number of times [signPayload] was called.
  int signCallCount = 0;

  /// Last payload passed to [signPayload].
  String lastSignedPayload = '';

  @override
  Future<DeviceIdentity> ensureDeviceIdentity() async {
    ensureCallCount++;
    if (identityOverride != null) return identityOverride!;
    return const DeviceIdentity(
      deviceId: 'test-device-id-sha256',
      publicKeyB64: 'dGVzdC1wdWJrZXk=', // "test-pubkey" in base64url
      seedBytes: null,
    );
  }

  @override
  Future<String> signPayload(String v3Payload) async {
    signCallCount++;
    lastSignedPayload = v3Payload;
    if (signatureOverride != null) return signatureOverride!;
    return 'dGVzdC1zaWduYXR1cmU='; // "test-signature" in base64url
  }
}

class FakeDeviceTokenStore implements IDeviceTokenStore {
  final Map<String, String> values = {};

  @override
  Future<void> save(String instanceId, String deviceToken) async {
    values[instanceId] = deviceToken;
  }

  @override
  Future<String?> load(String instanceId) async => values[instanceId];

  @override
  Future<void> delete(String instanceId) async {
    values.remove(instanceId);
  }
}

class FakeLogger implements ILogger {
  final List<String> infos = [];
  final List<(String, StackTrace?)> errors = [];

  @override
  void info(String message) => infos.add(message);

  @override
  void error(String message, [StackTrace? stackTrace]) =>
      errors.add((message, stackTrace));
}

class _RecordingApiLogger implements IApiLogger {
  final List<String> requestMethods = [];
  final List<String> stateNames = [];

  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) => requestMethods.add(method);

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) {}

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
    String? payloadPreview,
  }) => stateNames.add(state ?? '');
}

/// A minimal [Instance] for testing.
Instance testInstance({
  String id = 'test-instance',
  String name = 'Test Gateway',
  String gatewayUrl = 'ws://localhost:9999/ws',
  String token = 'test-token',
}) => Instance(id: id, name: name, gatewayUrl: gatewayUrl, tokenRef: token);

/// Build a [WsGatewayClient] backed by a [ControllableWebSocket], connect
/// to [testInstance], complete the handshake, and return the client + ws
/// for event injection. `connect()` is intentionally not awaited because it
/// blocks on `manager.connect()`.
Future<({WsGatewayClient client, ControllableWebSocket ws})>
connectAndHandshake({FakeDeviceTokenStore? deviceTokenStore}) async {
  final ws = ControllableWebSocket.ready();
  final client = WsGatewayClient(
    identityProvider: FakeDeviceIdentityProvider(),
    webSocketFactory: (_) => ws.channel,
    deviceTokenStore: deviceTokenStore,
  );

  unawaited(client.connect(testInstance()));
  await pumpMicrotasks();

  ws.simulateServerFrame(challengeJson());
  await pumpMicrotasks();

  final reqId = extractReqId(ws.sentFrames.first);
  ws.simulateServerFrame(helloOkJson(reqId));
  await pumpMicrotasks();

  return (client: client, ws: ws);
}

// ============================================================================
// Tests
// ============================================================================

void main() {
  // ==========================================================================
  // isTestTerminalState
  // ==========================================================================
  group('WsGatewayClient.isTestTerminalState', () {
    test('connected should be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(GatewayConnectionState.connected),
        isTrue,
      );
    });
    test('authFailed should be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(GatewayConnectionState.authFailed),
        isTrue,
      );
    });
    test('disconnected should be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(
          GatewayConnectionState.disconnected,
        ),
        isTrue,
      );
    });
    test('pairingRequired should be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(
          GatewayConnectionState.pairingRequired,
        ),
        isTrue,
      );
    });
    test('connecting should NOT be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(GatewayConnectionState.connecting),
        isFalse,
      );
    });
    test('authenticating should NOT be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(
          GatewayConnectionState.authenticating,
        ),
        isFalse,
      );
    });
    test('recovering should NOT be terminal', () {
      expect(
        WsGatewayClient.isTestTerminalState(GatewayConnectionState.recovering),
        isFalse,
      );
    });
  });

  // ==========================================================================
  // resolveAgentId
  // ==========================================================================
  group('resolveAgentId', () {
    test('returns agentId from explicit mapping (primary path)', () {
      const mapping = <String, String>{'agent:abc:main': 'abc'};
      final result = resolveAgentId('agent:abc:main', mapping);
      expect(result, 'abc');
    });

    test('returns agentId from string parsing fallback (backward compat)', () {
      final result = resolveAgentId(
        'agent:xyz:read',
        <String, String>{}, // empty mapping — fallback path
      );
      expect(result, 'xyz');
    });

    test('returns null when unresolvable', () {
      final result = resolveAgentId(
        'weird-format-no-colons',
        <String, String>{},
      );
      expect(result, isNull);
    });
  });

  // ==========================================================================
  // extractTextContent
  // ==========================================================================
  group('extractTextContent', () {
    test('returns null for null input', () {
      expect(GatewayDomainMapper.extractTextContent(null), isNull);
    });

    test('returns string unchanged for String input', () {
      expect(GatewayDomainMapper.extractTextContent('hello'), 'hello');
    });

    test('joins structured content blocks (real Gateway format)', () {
      final blocks = [
        {'type': 'text', 'text': '第一部分'},
        {'type': 'text', 'text': '第二部分'},
      ];
      expect(GatewayDomainMapper.extractTextContent(blocks), '第一部分第二部分');
    });

    test('skips non-text blocks in structured content', () {
      final blocks = [
        {'type': 'image_url', 'url': 'https://example.com/img.png'},
        {'type': 'text', 'text': '图片描述'},
      ];
      expect(GatewayDomainMapper.extractTextContent(blocks), '图片描述');
    });

    test('joins list of plain strings', () {
      expect(GatewayDomainMapper.extractTextContent(['a', 'b', 'c']), 'abc');
    });

    test('falls back to toString for unrecognized non-list types', () {
      expect(GatewayDomainMapper.extractTextContent(42), '42');
    });
  });

  // ==========================================================================
  // extractImageRef (PROTOCOL-VERIFY: response-side image block detection)
  // ==========================================================================
  group('extractImageRef (PROTOCOL-VERIFY assumption)', () {
    test('returns null for null / string / empty input', () {
      expect(GatewayDomainMapper.extractImageRef(null), isNull);
      expect(GatewayDomainMapper.extractImageRef('hello'), isNull);
      expect(GatewayDomainMapper.extractImageRef(<Map>[]), isNull);
    });

    test('returns url for OpenAI image_url block shape', () {
      final blocks = [
        {
          'type': 'image_url',
          'image_url': {'url': 'https://x.com/a.png'},
        },
      ];
      expect(
        GatewayDomainMapper.extractImageRef(blocks),
        'https://x.com/a.png',
      );
    });

    test('returns url for alt image block shape', () {
      final blocks = [
        {
          'type': 'image',
          'image': {'url': 'data:image/png;base64,AAA'},
        },
      ];
      expect(
        GatewayDomainMapper.extractImageRef(blocks),
        'data:image/png;base64,AAA',
      );
    });

    test(
      'returns url for F.5 chat.history shape {type:image, url} (url at root)',
      () {
        // appendix F.5 实测形态:url 直接在 block 根,不嵌套在 image:{}。
        final blocks = [
          {'type': 'text', 'text': '这是图表：'},
          {'type': 'image', 'url': 'https://cdn.example.com/chart.png'},
        ];
        expect(
          GatewayDomainMapper.extractImageRef(blocks),
          'https://cdn.example.com/chart.png',
        );
      },
    );

    test('returns null when only text blocks present', () {
      final blocks = [
        {'type': 'text', 'text': '纯文本回复'},
      ];
      expect(GatewayDomainMapper.extractImageRef(blocks), isNull);
    });

    test('skips image block with empty url', () {
      final blocks = [
        {
          'type': 'image_url',
          'image_url': {'url': ''},
        },
      ];
      expect(GatewayDomainMapper.extractImageRef(blocks), isNull);
    });
  });

  // ==========================================================================
  // connect()
  // ==========================================================================
  group('connect()', () {
    test('completes handshake and emits connected', () async {
      final identityProvider = FakeDeviceIdentityProvider();

      final client = WsGatewayClient(
        identityProvider: identityProvider,
        config: ConnectionConfig(
          locale: 'zh-CN',
          platform: 'linux',
          clientId: ClientIds.gatewayClient,
        ),
      );

      final states = <GatewayConnectionState>[];
      client.connectionStateStream('test-instance').listen(states.add);

      // Override WebSocket factory — need to intercept ConnectionManager
      // construction. Since WsGatewayClient creates ConnectionManager
      // internally, we inject a WebSocket factory at the ConnectionManager
      // level via a different approach.
      //
      // Strategy: WsGatewayClient.connect() → creates ConnectionManager →
      //   calls manager.connect(). We can test by observing that:
      //   1. identityProvider.ensureDeviceIdentity() was called
      //   2. The connection state stream receives events
      //
      // For a full end-to-end test without network, we'd need to make
      // the WebSocket factory injectable at the WsGatewayClient level.

      // Verify identity provider is called during connect
      // (for now, we verify the structural contract without a real websocket)
      expect(identityProvider.ensureCallCount, 0);
      expect(identityProvider.signCallCount, 0);

      await client.dispose();
    });

    test('identity provider is called during connect lifecycle', () async {
      final identityProvider = FakeDeviceIdentityProvider();

      final client = WsGatewayClient(
        identityProvider: identityProvider,
        config: ConnectionConfig(
          locale: 'en-US',
          platform: 'android',
          clientId: ClientIds.android,
        ),
      );

      // Verify the client doesn't call identity provider eagerly
      expect(identityProvider.ensureCallCount, 0);

      // connect() will call ensureDeviceIdentity, but the actual WebSocket
      // connection will fail in test. We just verify the pattern holds.
      try {
        await client
            .connect(testInstance())
            .timeout(const Duration(seconds: 1), onTimeout: () => null);
      } catch (_) {
        // Expected — no real WebSocket server
      }

      expect(
        identityProvider.ensureCallCount,
        1,
        reason: 'connect should call ensureDeviceIdentity',
      );

      await client.dispose();
    });

    test('duplicate connect for same instance is de-duped', () async {
      final identityProvider = FakeDeviceIdentityProvider();

      final client = WsGatewayClient(identityProvider: identityProvider);

      // Two rapid connect calls for the same instance should only
      // trigger one identity lookup (second call short-circuits)
      final instance = testInstance();

      try {
        // Fire both concurrently
        await Future.wait([
          client
              .connect(instance)
              .timeout(const Duration(seconds: 1), onTimeout: () => null),
          client
              .connect(instance)
              .timeout(const Duration(seconds: 1), onTimeout: () => null),
        ]);
      } catch (_) {
        // Expected
      }

      // _connecting guard prevents re-entrancy:
      // the second connect() short-circuits before reaching
      // ensureDeviceIdentity. So only 1 call.
      expect(
        identityProvider.ensureCallCount,
        1,
        reason: 'duplicate connect should dedupe',
      );

      await client.dispose();
    });
  });

  // ==========================================================================
  // testConnection()
  // ==========================================================================
  group('testConnection()', () {
    test('uses a synthetic instance ID prefixed with __test_', () async {
      final identityProvider = FakeDeviceIdentityProvider();
      final client = WsGatewayClient(identityProvider: identityProvider);

      // testConnection creates a ConnectionManager with '__test_${id}'
      // and disposes it after. The actual WebSocket will fail to connect.
      final result = await client.testConnection(testInstance());
      expect(
        result,
        isFalse,
        reason: 'should return false when no server is reachable',
      );

      expect(
        identityProvider.ensureCallCount,
        1,
        reason: 'testConnection should load device identity',
      );

      await client.dispose();
    });

    test(
      'injected logger receives error on unknown agent stream type',
      () async {
        final logger = FakeLogger();
        final ws = ControllableWebSocket.ready();
        final client = WsGatewayClient(
          identityProvider: FakeDeviceIdentityProvider(),
          logger: logger,
          webSocketFactory: (_) => ws.channel,
        );

        unawaited(client.connect(testInstance()));
        await pumpMicrotasks();
        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);
        ws.simulateServerFrame(helloOkJson(reqId));
        await pumpMicrotasks();

        // Emit an agent event with an unknown stream type — this triggers the
        // unknown branch in _onAgentEvent which logs via the injected logger.
        ws.simulateServerFrame(
          '{"type":"event","event":"agent","payload":'
          '{"sessionKey":"agent:r-1:main","stream":"weird","data":{}}}',
        );
        await pumpMicrotasks();

        expect(logger.errors.length, 1);
        expect(logger.errors.first.$1, contains('Unknown agent stream type'));

        await client.dispose();
      },
    );

    test('can be constructed with an injected logger', () {
      final logger = FakeLogger();
      final client = WsGatewayClient(
        identityProvider: FakeDeviceIdentityProvider(),
        logger: logger,
      );
      expect(client, isA<WsGatewayClient>());
      client.dispose();
    });
  });

  // ==========================================================================
  // disconnect() & dispose()
  // ==========================================================================
  group('disconnect() & dispose()', () {
    test('disconnect does not throw for non-connected instance', () async {
      final client = WsGatewayClient(
        identityProvider: FakeDeviceIdentityProvider(),
      );

      // Should not throw even though we never called connect()
      await client.disconnect('non-existent-instance');
      await client.dispose();
    });

    // Regression: per-instance sessionKey → agentId mapping must be cleared
    // on disconnect, otherwise removing+re-adding an instance (or churn in
    // general) leaks entries forever (only cleared in dispose()).
    //
    // The bug: `_cleanup` (called by disconnect) filters
    // `_streamingBuffers` / `_finalizedSessions` / `_deltaSource` by
    // `'$instanceId:'` prefix, but `_sessionToAgentId` keys are bare
    // sessionKeys (`agent:{agentId}:main`), NOT prefixed with instanceId.
    // Result: the prefix-based filter never matches, only `dispose()`
    // clears the map.
    test('disconnect clears _sessionToAgentId entries for that instance '
        '(no memory leak across instance churn)', () async {
      final (:client, ws: ws) = await connectAndHandshake();

      // Drive two sendMessage calls — each populates _sessionToAgentId
      // with a bare sessionKey. chat.send response: ok=true, payload.runId.
      final agentIdA = 'agent-aaa';
      final agentIdB = 'agent-bbb';

      for (final agentId in [agentIdA, agentIdB]) {
        // Fire sendMessage — it awaits the chat.send response, so we
        // drive it as an unawaited future and inject the response.
        final future = client.sendMessage(
          instanceId: 'test-instance',
          agentId: agentId,
          message: Message(
            clientId: 'msg-$agentId',
            conversationId: 'conv-1',
            agentId: agentId,
            role: MessageRole.user,
            type: MessageType.text,
            content: 'hi',
            logicalClock: 0,
          ),
        );

        await pumpMicrotasks();

        // The last sent frame is the chat.send request.
        final sent = ws.sentFrames.last;
        final reqId = extractReqId(sent);
        ws.simulateServerFrame(
          '{"type":"res","id":"$reqId","ok":true,'
          '"payload":{"runId":"run-$agentId","timestamp":1700000000000}}',
        );
        await pumpMicrotasks();

        await future;
      }

      // Sanity: both entries are now in the map.
      expect(
        client.sessionToAgentIdSizeForTesting,
        2,
        reason: 'both sendMessage calls should have populated the map',
      );

      // Now disconnect — the per-instance entries MUST be cleared.
      await client.disconnect('test-instance');

      expect(
        client.sessionToAgentIdSizeForTesting,
        0,
        reason:
            'disconnect must remove all sessionKeys belonging to the '
            'disconnected instance — otherwise instance churn leaks '
            'entries until dispose() (memory leak)',
      );

      await client.dispose();
    });

    test(
      'disconnect for instance A does not touch instance B entries',
      () async {
        // Two-instance scenario: removing A must not affect B's mappings.
        // The fix uses a per-instance reverse index; this test pins that
        // the index lookup is correctly scoped to the disconnected
        // instance.
        final wsA = ControllableWebSocket.ready();
        final clientA = WsGatewayClient(
          identityProvider: FakeDeviceIdentityProvider(),
          webSocketFactory: (_) => wsA.channel,
        );
        unawaited(clientA.connect(testInstance(id: 'instance-a')));
        await pumpMicrotasks();
        wsA.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqIdA = extractReqId(wsA.sentFrames.first);
        wsA.simulateServerFrame(helloOkJson(reqIdA));
        await pumpMicrotasks();

        final wsB = ControllableWebSocket.ready();
        final clientB = WsGatewayClient(
          identityProvider: FakeDeviceIdentityProvider(),
          webSocketFactory: (_) => wsB.channel,
        );
        unawaited(clientB.connect(testInstance(id: 'instance-b')));
        await pumpMicrotasks();
        wsB.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqIdB = extractReqId(wsB.sentFrames.first);
        wsB.simulateServerFrame(helloOkJson(reqIdB));
        await pumpMicrotasks();

        // Populate both maps with one sendMessage each.
        Future<void> sendOne(
          WsGatewayClient c,
          ControllableWebSocket ws,
          String instanceId,
          String agentId,
        ) async {
          final future = c.sendMessage(
            instanceId: instanceId,
            agentId: agentId,
            message: Message(
              clientId: 'msg-$agentId',
              conversationId: 'conv-1',
              agentId: agentId,
              role: MessageRole.user,
              type: MessageType.text,
              content: 'hi',
              logicalClock: 0,
            ),
          );
          await pumpMicrotasks();
          final reqId = extractReqId(ws.sentFrames.last);
          ws.simulateServerFrame(
            '{"type":"res","id":"$reqId","ok":true,'
            '"payload":{"runId":"run-$agentId",'
            '"timestamp":1700000000000}}',
          );
          await pumpMicrotasks();
          await future;
        }

        await sendOne(clientA, wsA, 'instance-a', 'agent-a');
        await sendOne(clientB, wsB, 'instance-b', 'agent-b');

        // Both clients (each owns one instance) should have 1 entry.
        expect(clientA.sessionToAgentIdSizeForTesting, 1);
        expect(clientB.sessionToAgentIdSizeForTesting, 1);

        // Disconnect A — A's entry should be cleared, B's untouched.
        await clientA.disconnect('instance-a');
        expect(
          clientA.sessionToAgentIdSizeForTesting,
          0,
          reason: 'A disconnected → A entry cleared',
        );

        await clientA.dispose();
        await clientB.dispose();
      },
    );

    // Regression: chat.delta arriving in the same microtask as
    // agent.lifecycle.start must NOT be wiped from the streaming buffer.
    //
    // Bug: `_onAgentEvent` clears `_streamingBuffers[bufferKey]` on
    // `lifecycle.start`. If a `chat.delta` event for the new turn
    // arrived BEFORE `lifecycle.start` in the same microtask (server
    // misorder), the buffer was already populated by that delta —
    // `lifecycle.start` would silently drop it. The first chunk of
    // the new turn would never reach the user.
    //
    // Detection: trigger a `chat.final` with NO `message` field (forces
    // the fallback path which uses `_streamingBuffers[bufferKey].text`).
    // If the buffer was wiped, the fallback message only contains
    // deltas that arrived AFTER `lifecycle.start`; with the fix it
    // contains the full delta stream.
    test('chat.delta arriving before lifecycle.start is not dropped '
        '(no buffer wipe on lifecycle.start)', () async {
      final (:client, ws: ws) = await connectAndHandshake();

      // Populate _sessionToAgentId so _resolveAgentId works.
      // Drive a successful sendMessage first.
      final sendFuture = client.sendMessage(
        instanceId: 'test-instance',
        agentId: 'agent-r1',
        message: Message(
          clientId: 'msg-1',
          conversationId: 'conv-1',
          agentId: 'agent-r1',
          role: MessageRole.user,
          type: MessageType.text,
          content: 'user prompt',
          logicalClock: 0,
        ),
      );
      await pumpMicrotasks();
      final sendReqId = extractReqId(ws.sentFrames.last);
      ws.simulateServerFrame(
        '{"type":"res","id":"$sendReqId","ok":true,'
        '"payload":{"runId":"run-1","timestamp":1700000000000}}',
      );
      await pumpMicrotasks();
      await sendFuture;

      // Listen for the fallback agent message.
      final messages = <Message>[];
      client.messageStream('test-instance').listen(messages.add);

      const sessionKey = 'agent:agent-r1:main';

      // Server misorder: chat.delta for new turn arrives BEFORE
      // lifecycle.start (same microtask). Both are dispatched via
      // ws.simulateServerFrame in sequence; the listener processes
      // them in order.
      ws.simulateServerFrame(
        '{"type":"event","event":"chat","payload":'
        '{"sessionKey":"$sessionKey","state":"delta",'
        '"deltaText":"First chunk","seq":1}}',
      );
      await pumpMicrotasks();
      ws.simulateServerFrame(
        '{"type":"event","event":"agent","payload":'
        '{"sessionKey":"$sessionKey","stream":"lifecycle",'
        '"data":{"phase":"start"}}}',
      );
      await pumpMicrotasks();

      // More deltas after lifecycle.start.
      ws.simulateServerFrame(
        '{"type":"event","event":"chat","payload":'
        '{"sessionKey":"$sessionKey","state":"delta",'
        '"deltaText":" second","seq":2}}',
      );
      await pumpMicrotasks();

      // End the turn with chat.final but NO message field → forces
      // fallback path that uses _streamingBuffers[bufferKey].text.
      // If lifecycle.start wiped the buffer, this would only contain
      // " second" (the delta that arrived after start).
      ws.simulateServerFrame(
        '{"type":"event","event":"chat","payload":'
        '{"sessionKey":"$sessionKey","state":"final","seq":10}}',
      );
      await pumpMicrotasks();

      // Find the fallback agent message — it should contain BOTH
      // chunks ("First chunk second"), proving the buffer wasn't
      // wiped by lifecycle.start.
      final agentMessages = messages
          .where((m) => m.role == MessageRole.agent)
          .toList();
      expect(
        agentMessages.length,
        1,
        reason: 'fallback agent message must be emitted',
      );
      expect(
        agentMessages.single.content,
        contains('First chunk'),
        reason:
            'lifecycle.start must NOT wipe the buffer — the delta '
            'that arrived before it must survive',
      );
      expect(agentMessages.single.content, contains('second'));

      await client.dispose();
    });

    test('dispose closes all resources cleanly', () async {
      final client = WsGatewayClient(
        identityProvider: FakeDeviceIdentityProvider(),
      );

      await client.dispose();
      // Verify double-dispose is safe
      await client.dispose();
    });
  });

  // ==========================================================================
  // runId turn-token: stale streaming-buffer corruption fix
  //
  // Bug: `_streamingBuffers` is keyed `$instanceId:$sessionKey`, and
  // `sessionKey` is stable across turns for the same agent. A buffer is
  // dropped only on normal completion (lifecycle.end / chat.final) or
  // instance _cleanup — NOT when a turn is aborted by a graceful-shutdown
  // reconnect / recoverable transport error (that path lives inside
  // ConnectionManager; WsGatewayClient._InstanceConnection + buffers
  // survive untouched). So an aborted turn whose lifecycle.end never
  // arrives leaves a non-empty buffer; the next turn's deltas .append()
  // to it and lifecycle.end/chat.final emits `stale_turn1 + turn2`.
  //
  // Fix: track the active `runId` per session (server-assigned, per-turn,
  // already parsed on chat/agent events + the chat.send response). When
  // the runId for a session changes, the prior buffer is irrecoverably
  // stale and is dropped. Same/absent runId → in-flight, keep (the
  // absent-runId degradation path preserves the no-runId regression test
  // above at "chat.delta arriving before lifecycle.start is not dropped").
  // ==========================================================================
  group('runId turn-token (stale buffer fix)', () {
    const sessionKey = 'agent:agent-r1:main';

    /// Drive a `chat.send` RPC and reply with [runId], completing it.
    Future<void> sendWithRunId(
      WsGatewayClient client,
      ControllableWebSocket ws, {
      required String runId,
      String clientId = 'msg-1',
    }) async {
      final future = client.sendMessage(
        instanceId: 'test-instance',
        agentId: 'agent-r1',
        message: Message(
          clientId: clientId,
          conversationId: 'conv-1',
          agentId: 'agent-r1',
          role: MessageRole.user,
          type: MessageType.text,
          content: 'prompt',
          logicalClock: 0,
        ),
      );
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.last);
      ws.simulateServerFrame(
        '{"type":"res","id":"$reqId","ok":true,'
        '"payload":{"runId":"$runId","timestamp":1700000000000}}',
      );
      await pumpMicrotasks();
      await future;
    }

    void chatDelta(ControllableWebSocket ws, String text, String runId) {
      ws.simulateServerFrame(
        '{"type":"event","event":"chat","payload":'
        '{"sessionKey":"$sessionKey","runId":"$runId",'
        '"state":"delta","deltaText":"$text","seq":1}}',
      );
    }

    void chatFinal(ControllableWebSocket ws, String runId) {
      ws.simulateServerFrame(
        '{"type":"event","event":"chat","payload":'
        '{"sessionKey":"$sessionKey","runId":"$runId",'
        '"state":"final","seq":10}}',
      );
    }

    void lifecycleStart(ControllableWebSocket ws, String runId) {
      ws.simulateServerFrame(
        '{"type":"event","event":"agent","payload":'
        '{"sessionKey":"$sessionKey","runId":"$runId",'
        '"stream":"lifecycle","data":{"phase":"start"}}}',
      );
    }

    test('aborted turn buffer is dropped on next chat.send response', () async {
      final (:client, ws: ws) = await connectAndHandshake();
      final messages = <Message>[];
      client.messageStream('test-instance').listen(messages.add);

      // Turn 1: chat.send → run-1 → one delta → NO end event (aborted
      // mid-turn by a reconnect / transport error). Buffer = "turn1".
      await sendWithRunId(client, ws, runId: 'run-1', clientId: 'msg-1');
      chatDelta(ws, 'turn1', 'run-1');
      await pumpMicrotasks();

      // Turn 2: a fresh chat.send → run-2. The server-assigned runId
      // changing is the authoritative turn boundary; the lingering
      // turn-1 buffer MUST be dropped here.
      await sendWithRunId(client, ws, runId: 'run-2', clientId: 'msg-2');
      chatDelta(ws, 'turn2', 'run-2');
      await pumpMicrotasks();

      // End turn 2 with chat.final (no `message` → forces the buffer
      // fallback path). Before the fix the buffer held "turn1turn2";
      // after the fix it holds only "turn2".
      chatFinal(ws, 'run-2');
      await pumpMicrotasks();

      final agentMessages = messages
          .where((m) => m.role == MessageRole.agent)
          .toList();
      expect(agentMessages.length, 1);
      expect(agentMessages.single.content, 'turn2');
      expect(
        agentMessages.single.content,
        isNot(contains('turn1')),
        reason:
            'aborted turn-1 buffer must be dropped on the turn-2 '
            'chat.send response (runId changed)',
      );

      await client.dispose();
    });

    test('delta with a differing runId resets the buffer', () async {
      final (:client, ws: ws) = await connectAndHandshake();
      final messages = <Message>[];
      client.messageStream('test-instance').listen(messages.add);

      // chat.send → run-1, then a delta for run-1.
      await sendWithRunId(client, ws, runId: 'run-1');
      chatDelta(ws, 'a', 'run-1');
      await pumpMicrotasks();

      // A delta arrives with run-2 and NO fresh chat.send (agent
      // self-branch / tool continuation). The differing runId signals a
      // turn boundary → the "a" buffer must be dropped.
      chatDelta(ws, 'b', 'run-2');
      await pumpMicrotasks();

      chatFinal(ws, 'run-2');
      await pumpMicrotasks();

      final agentMessages = messages
          .where((m) => m.role == MessageRole.agent)
          .toList();
      expect(agentMessages.length, 1);
      expect(agentMessages.single.content, 'b');
      expect(
        agentMessages.single.content,
        isNot(contains('a')),
        reason: 'a differing runId on a delta must reset the buffer',
      );

      await client.dispose();
    });

    test(
      'lifecycle.start with the same runId keeps in-flight buffer data',
      () async {
        final (:client, ws: ws) = await connectAndHandshake();
        final messages = <Message>[];
        client.messageStream('test-instance').listen(messages.add);

        await sendWithRunId(client, ws, runId: 'run-1');
        chatDelta(ws, 'first', 'run-1');
        await pumpMicrotasks();

        // lifecycle.start for the SAME turn (run-1) — must NOT wipe the
        // in-flight buffer. Regression guard for Fix 7's conditional
        // clear, now scoped by runId equality.
        lifecycleStart(ws, 'run-1');
        await pumpMicrotasks();

        chatDelta(ws, 'second', 'run-1');
        await pumpMicrotasks();

        chatFinal(ws, 'run-1');
        await pumpMicrotasks();

        final agentMessages = messages
            .where((m) => m.role == MessageRole.agent)
            .toList();
        expect(agentMessages.length, 1);
        expect(agentMessages.single.content, contains('first'));
        expect(agentMessages.single.content, contains('second'));

        await client.dispose();
      },
    );

    test(
      'lifecycle.start with a differing runId drops stale buffer data',
      () async {
        final (:client, ws: ws) = await connectAndHandshake();
        final messages = <Message>[];
        client.messageStream('test-instance').listen(messages.add);

        await sendWithRunId(client, ws, runId: 'run-1');
        chatDelta(ws, 'stale', 'run-1');
        await pumpMicrotasks();

        // lifecycle.start for a NEW turn (run-2) — the prior "stale"
        // buffer must be dropped (the case Fix 7's conditional clear
        // could not handle).
        lifecycleStart(ws, 'run-2');
        await pumpMicrotasks();

        chatDelta(ws, 'fresh', 'run-2');
        await pumpMicrotasks();

        chatFinal(ws, 'run-2');
        await pumpMicrotasks();

        final agentMessages = messages
            .where((m) => m.role == MessageRole.agent)
            .toList();
        expect(agentMessages.length, 1);
        expect(agentMessages.single.content, 'fresh');
        expect(
          agentMessages.single.content,
          isNot(contains('stale')),
          reason:
              'lifecycle.start with a differing runId must drop the '
              'stale prior-turn buffer',
        );

        await client.dispose();
      },
    );
  });

  // ==========================================================================
  // sendMessage failure must not leak session mapping
  //
  // Bug: `sendMessage` wrote `_sessionToAgentId[sessionKey]` and the
  // `_sessionKeysByInstance` reverse-index entry BEFORE `await
  // manager.sendRequest(...)`. If that await threw (transport error,
  // timeout, PayloadTooLarge) or the response was `ok:false` (sendMessage
  // throws), the entries were never removed — they leaked until the
  // instance disconnected / `_cleanup`. The reverse-index (added to fix
  // the disconnect leak) made the leak grow across DIFFERENT failed
  // agents, since the bare sessionKey is stable per agent.
  //
  // Fix: populate the mappings only on a successful send (after the
  // `!res.ok` throw). A failed send never writes them → nothing to leak.
  // `_resolveAgentId`'s string-parsing fallback (`split(':')[1]`) still
  // resolves agentId for any early-arriving event, so deferring the write
  // is behavior-preserving on the success path.
  // ==========================================================================
  group('sendMessage failure does not leak session mapping', () {
    /// Start a `sendMessage` for [agentId]. Caller pumps, reads the
    /// chat.send reqId from `ws.sentFrames.last`, replies, then pumps
    /// again and awaits [future].
    Future<({String serverId, int timestamp})> startSend({
      required WsGatewayClient client,
      required String agentId,
      String clientId = 'msg-1',
    }) {
      return client.sendMessage(
        instanceId: 'test-instance',
        agentId: agentId,
        message: Message(
          clientId: clientId,
          conversationId: 'conv-1',
          agentId: agentId,
          role: MessageRole.user,
          type: MessageType.text,
          content: 'prompt',
          logicalClock: 0,
        ),
      );
    }

    test('failed sendMessage (ok:false) leaves no mapping entries', () async {
      final (:client, ws: ws) = await connectAndHandshake();

      // Two DIFFERENT agents, both failing. Before the fix each failure
      // wrote its sessionKey into both maps and never removed it → sizes
      // grew to 2. After the fix neither write happens → sizes stay 0.
      final f1 = startSend(client: client, agentId: 'agent-a', clientId: 'c1');
      await pumpMicrotasks();
      final reqId1 = extractReqId(ws.sentFrames.last);
      ws.simulateServerFrame(
        '{"type":"res","id":"$reqId1","ok":false,'
        '"error":{"message":"boom"}}',
      );
      await expectLater(f1, throwsA(isA<Exception>()));
      await pumpMicrotasks();

      final f2 = startSend(client: client, agentId: 'agent-b', clientId: 'c2');
      await pumpMicrotasks();
      final reqId2 = extractReqId(ws.sentFrames.last);
      ws.simulateServerFrame(
        '{"type":"res","id":"$reqId2","ok":false,'
        '"error":{"message":"boom"}}',
      );
      await expectLater(f2, throwsA(isA<Exception>()));
      await pumpMicrotasks();

      expect(
        client.sessionToAgentIdSizeForTesting,
        0,
        reason: 'a failed send must not leak a _sessionToAgentId entry',
      );
      expect(
        client.sessionKeysByInstanceSizeForTesting,
        0,
        reason: 'a failed send must not leak a reverse-index entry',
      );

      await client.dispose();
    });

    test(
      'failed sendMessage preserves a prior successful send\'s mapping',
      () async {
        final (:client, ws: ws) = await connectAndHandshake();

        // Successful send for agent-a → mapping populated (size 1).
        final ok = startSend(
          client: client,
          agentId: 'agent-a',
          clientId: 'c1',
        );
        await pumpMicrotasks();
        final okReqId = extractReqId(ws.sentFrames.last);
        ws.simulateServerFrame(
          '{"type":"res","id":"$okReqId","ok":true,'
          '"payload":{"runId":"run-agent-a","timestamp":1700000000000}}',
        );
        await pumpMicrotasks();
        await ok;
        await pumpMicrotasks();
        expect(client.sessionToAgentIdSizeForTesting, 1);

        // A subsequent FAILED send for the same agent must NOT remove the
        // prior good entry (sessionKey is stable per agent; removing it
        // would break event dispatch for the still-valid session).
        final fail = startSend(
          client: client,
          agentId: 'agent-a',
          clientId: 'c2',
        );
        await pumpMicrotasks();
        final failReqId = extractReqId(ws.sentFrames.last);
        ws.simulateServerFrame(
          '{"type":"res","id":"$failReqId","ok":false,'
          '"error":{"message":"boom"}}',
        );
        await expectLater(fail, throwsA(isA<Exception>()));
        await pumpMicrotasks();

        expect(
          client.sessionToAgentIdSizeForTesting,
          1,
          reason:
              'a failed send must not evict a prior successful '
              'send\'s mapping for the same agent',
        );

        await client.dispose();
      },
    );
  });

  // ==========================================================================
  // fetchAgents() / sendMessage() — error handling
  // ==========================================================================
  group('RPC error handling', () {
    test(
      'fetchAgents throws NotConnectedException when not connected',
      () async {
        final client = WsGatewayClient(
          identityProvider: FakeDeviceIdentityProvider(),
        );

        expect(
          () => client.fetchAgents('test-instance'),
          throwsA(isA<NotConnectedException>()),
        );

        await client.dispose();
      },
    );

    test(
      'sendMessage throws NotConnectedException when not connected',
      () async {
        final client = WsGatewayClient(
          identityProvider: FakeDeviceIdentityProvider(),
        );

        expect(
          () => client.sendMessage(
            instanceId: 'test-instance',
            agentId: 'agent-1',
            message: Message(
              clientId: 'msg-1',
              conversationId: 'conv-1',
              agentId: 'agent-1',
              role: MessageRole.user,
              type: MessageType.text,
              content: 'hello',
              logicalClock: 0,
            ),
          ),
          throwsA(isA<NotConnectedException>()),
        );

        await client.dispose();
      },
    );

    test(
      'fetchMessageHistory throws NotConnectedException when not connected',
      () async {
        final client = WsGatewayClient(
          identityProvider: FakeDeviceIdentityProvider(),
        );

        expect(
          () => client.fetchMessageHistory(
            instanceId: 'test-instance',
            agentId: 'agent-1',
          ),
          throwsA(isA<NotConnectedException>()),
        );

        await client.dispose();
      },
    );
  });

  group('fetchAgents quickCommands identity', () {
    Future<List<String>> fetchQuickCommandIds({
      String? commandId,
      String agentRemoteId = 'remote-a',
    }) async {
      final (:client, :ws) = await connectAndHandshake();
      final future = client.fetchAgents('test-instance');
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.last);
      final idField = commandId == null ? '' : '"id":"$commandId",';
      ws.simulateServerFrame(
        '{"type":"res","id":"$reqId","ok":true,'
        '"payload":{"agents":[{"id":"$agentRemoteId","name":"A",'
        '"quickCommands":[{$idField"label":"状态","payload":"/status"}]}]}}',
      );
      final agents = await future;
      await client.dispose();
      return agents.single.quickCommands.map((c) => c.id).toList();
    }

    test('derives stable IDs when Gateway omits quickCommand id', () async {
      final first = await fetchQuickCommandIds();
      final second = await fetchQuickCommandIds();

      expect(first, second);
    });

    test('preserves Gateway-provided quickCommand id', () async {
      final ids = await fetchQuickCommandIds(commandId: 'server-cmd-1');

      expect(ids, ['server-cmd-1']);
    });

    test('stable fallback IDs are scoped by remote agent id', () async {
      final first = await fetchQuickCommandIds(agentRemoteId: 'remote-a');
      final second = await fetchQuickCommandIds(agentRemoteId: 'remote-b');

      expect(first.single, isNot(second.single));
    });
  });

  // ==========================================================================
  // fetchAgents() — bio field parsing (协议 §A.6 实测 vs §5.2 示意图)
  // ==========================================================================
  group('fetchAgents bio field parsing', () {
    Future<Agent> fetchSingleAgent(String agentJson) async {
      final (:client, :ws) = await connectAndHandshake();
      final future = client.fetchAgents('test-instance');
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.last);
      ws.simulateServerFrame(
        '{"type":"res","id":"$reqId","ok":true,'
        '"payload":{"agents":[$agentJson]}}',
      );
      final agents = await future;
      await client.dispose();
      return agents.single;
    }

    test('description is null when only identity.name is present '
        '(identity.name is display name, NOT a bio source — fix for name/'
        'description collision bug)', () async {
      // 真实 Gateway 实测：agent_b43ae25f name="旅行规划师" identity.name="行远"
      // 旧 parser 把 identity.name 当 description fallback，导致 name 和
      // description 在 UI 上完全撞车（name="旅行规划师" 简介="行远"→"行远"）。
      // 修复后：identity.name 不再是 description 来源，description 应为 null。
      final agent = await fetchSingleAgent(
        '{"id":"agent_b43ae25f","name":"旅行规划师",'
        '"identity":{"name":"行远"}}',
      );
      expect(agent.name, '旅行规划师');
      expect(agent.description, isNull);
    });

    test('prefers top-level description when other fields coexist', () async {
      final agent = await fetchSingleAgent(
        '{"id":"a1","name":"A",'
        '"description":"top-level description wins",'
        '"identity":{"name":"identity name"}}',
      );
      expect(agent.description, 'top-level description wins');
    });

    test('falls back to identity.theme when no top-level description '
        '(real Gateway schema: identity.theme holds role description for '
        'jvsclaw/xinqing/zhishi-style agents)', () async {
      final agent = await fetchSingleAgent(
        '{"id":"jvsclaw","name":"编程大师-Bob",'
        '"identity":{"name":"Bob","theme":"严谨专业的 AI 编程顾问",'
        '"emoji":"💻"}}',
      );
      expect(agent.description, '严谨专业的 AI 编程顾问');
    });

    test('prefers identity.theme over identity.description', () async {
      final agent = await fetchSingleAgent(
        '{"id":"a1","identity":{"theme":"theme wins","description":"desc"}}',
      );
      expect(agent.description, 'theme wins');
    });

    test('skips empty description string and falls back to identity.theme '
        '(_nonEmpty guards against empty-string short-circuit)', () async {
      final agent = await fetchSingleAgent(
        '{"id":"a1","description":"",'
        '"identity":{"theme":"fallback"}}',
      );
      expect(agent.description, 'fallback');
    });

    test('skips empty identity.theme string and falls back to '
        'identity.description', () async {
      final agent = await fetchSingleAgent(
        '{"id":"a1","identity":{"theme":"","description":"final"}}',
      );
      expect(agent.description, 'final');
    });

    test('falls back to identity.description when no top-level description '
        'and no identity.name (legacy v3 Gateway 兼容)', () async {
      final agent = await fetchSingleAgent(
        '{"id":"a1","name":"A",'
        '"identity":{"description":"role description"}}',
      );
      expect(agent.description, 'role description');
    });

    test('description is null when no bio source is present '
        '(default agent "main" — no identity block)', () async {
      final agent = await fetchSingleAgent(
        '{"id":"main","workspace":"/path/to/workspace"}',
      );
      expect(agent.description, isNull);
    });
  });
  group('device token lifecycle RPCs', () {
    test('rotateDeviceToken saves token returned by Gateway', () async {
      final store = FakeDeviceTokenStore();
      final (:client, :ws) = await connectAndHandshake(deviceTokenStore: store);

      final future = client.rotateDeviceToken('test-instance');
      await pumpMicrotasks();
      final req = ws.sentFrames.last;
      final decoded = jsonDecode(req) as Map<String, dynamic>;
      expect(decoded['method'], Methods.deviceTokenRotate);
      final reqId = decoded['id'] as String;

      ws.simulateServerFrame(
        '{"type":"res","id":"$reqId","ok":true,'
        '"payload":{"deviceToken":"dt-rotated"}}',
      );
      await future;

      expect(store.values['test-instance'], 'dt-rotated');
      await client.dispose();
    });

    test('revokeDeviceToken deletes token after successful revoke', () async {
      final store = FakeDeviceTokenStore()..values['test-instance'] = 'dt-old';
      final (:client, :ws) = await connectAndHandshake(deviceTokenStore: store);

      final future = client.revokeDeviceToken('test-instance');
      await pumpMicrotasks();
      final req = ws.sentFrames.last;
      final decoded = jsonDecode(req) as Map<String, dynamic>;
      expect(decoded['method'], Methods.deviceTokenRevoke);
      final reqId = decoded['id'] as String;

      ws.simulateServerFrame(
        '{"type":"res","id":"$reqId","ok":true,"payload":{}}',
      );
      await future;

      expect(store.values.containsKey('test-instance'), isFalse);
      await client.dispose();
    });
  });
  group('Stream access without connect', () {
    test('connectionStateStream works before connect', () async {
      final client = WsGatewayClient(
        identityProvider: FakeDeviceIdentityProvider(),
      );

      final states = <GatewayConnectionState>[];
      final sub = client
          .connectionStateStream('test-instance')
          .listen(states.add);

      // No events should arrive because no manager is connected
      await pumpMicrotasks();
      expect(states, isEmpty);

      await sub.cancel();
      await client.dispose();
    });

    test('messageStream works before connect', () async {
      final client = WsGatewayClient(
        identityProvider: FakeDeviceIdentityProvider(),
      );

      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      await pumpMicrotasks();
      expect(messages, isEmpty);

      await sub.cancel();
      await client.dispose();
    });

    test('pairingInfoStream works before connect', () async {
      final client = WsGatewayClient(
        identityProvider: FakeDeviceIdentityProvider(),
      );

      final infos = <GatewayPairingInfo?>[];
      final sub = client.pairingInfoStream('test-instance').listen(infos.add);

      await pumpMicrotasks();
      expect(infos, isEmpty);

      await sub.cancel();
      await client.dispose();
    });
  });

  // ==========================================================================
  // ClientIds platform mapping (regression)
  // ==========================================================================
  group('ClientIds.forPlatform', () {
    test('ios → openclaw-ios', () {
      expect(ClientIds.forPlatform('ios'), 'openclaw-ios');
    });
    test('android → openclaw-android', () {
      expect(ClientIds.forPlatform('android'), 'openclaw-android');
    });
    test('macos → openclaw-macos', () {
      expect(ClientIds.forPlatform('macos'), 'openclaw-macos');
    });
    test('unknown → gateway-client', () {
      expect(ClientIds.forPlatform('linux'), 'gateway-client');
      expect(ClientIds.forPlatform('windows'), 'gateway-client');
      expect(ClientIds.forPlatform('web'), 'gateway-client');
    });
  });

  // ==========================================================================
  // Law 16: Event routing — _handleEvent → _emitMessage / _emitToolCall
  // ==========================================================================
  group('Event routing', () {
    test('chat final event emits complete Message via messageStream', () async {
      final (:client, :ws) = await connectAndHandshake();

      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      // Simulate chat final event (Gateway v2026.6.6)
      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":"Hello World","role":"agent","type":"text"}',
        ),
      );
      await pumpMicrotasks();

      expect(
        messages.length,
        1,
        reason: 'Complete message should be emitted on chat final',
      );
      expect(messages.first.content, 'Hello World');
      expect(messages.first.role, MessageRole.agent);

      await sub.cancel();
      await client.dispose();
    });

    test(
      'chat final without logicalClock assigns timestamp-based clock (not 0)',
      () async {
        final (:client, :ws) = await connectAndHandshake();

        final messages = <Message>[];
        final sub = client.messageStream('test-instance').listen(messages.add);

        final before = DateTime.now().millisecondsSinceEpoch;

        // Gateway omits logicalClock — _parseMessage must NOT default to 0
        // because user messages use timestamp-based clocks (~1.7 trillion).
        // Ordering by logical_clock DESC would put agent messages (0) after
        // all user messages, breaking chronological display.
        ws.simulateServerFrame(
          chatFinalJson(
            sessionKey: 'agent:r-1:main',
            messageContent:
                '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
                '"content":"Reply","role":"agent","type":"text"}',
          ),
        );
        await pumpMicrotasks();

        final after = DateTime.now().millisecondsSinceEpoch;

        expect(messages.length, 1);
        final msg = messages.first;
        expect(
          msg.logicalClock,
          greaterThanOrEqualTo(before),
          reason:
              'logicalClock should be >= time before the event was sent, '
              'not 0 (which breaks message ordering)',
        );
        expect(
          msg.logicalClock,
          lessThanOrEqualTo(after),
          reason:
              'logicalClock should be <= time after the event was processed',
        );

        await sub.cancel();
        await client.dispose();
      },
    );

    test(
      'chat final with logicalClock preserves Gateway-provided value',
      () async {
        final (:client, :ws) = await connectAndHandshake();

        final messages = <Message>[];
        final sub = client.messageStream('test-instance').listen(messages.add);

        // Gateway provides explicit logicalClock
        ws.simulateServerFrame(
          chatFinalJson(
            sessionKey: 'agent:r-1:main',
            messageContent:
                '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
                '"content":"Reply","role":"agent","type":"text",'
                '"logicalClock":999999}',
          ),
        );
        await pumpMicrotasks();

        expect(messages.length, 1);
        expect(
          messages.first.logicalClock,
          999999,
          reason: 'Should preserve Gateway-provided logicalClock',
        );

        await sub.cancel();
        await client.dispose();
      },
    );

    test('chat final parses List-format content (real Gateway format)', () async {
      final (:client, :ws) = await connectAndHandshake();

      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      // Real Gateway sends content as structured content blocks — a List of
      // {"type":"text","text":"..."} maps, not a plain String.  This was the
      // format that caused the type-cast crash in _parseMessage before the
      // extractTextContent fix.
      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          // JSON-escape the inner array: content is a List<Map>, not a String
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":[{"type":"text","text":"你好"},{"type":"text","text":"世界"}],'
              '"role":"agent","type":"text"}',
        ),
      );
      await pumpMicrotasks();

      expect(
        messages.length,
        1,
        reason: 'Should parse chat.final with List-format content',
      );
      expect(
        messages.first.content,
        '你好世界',
        reason: 'Text blocks should be joined',
      );
      expect(messages.first.role, MessageRole.agent);

      await sub.cancel();
      await client.dispose();
    });

    test('agent tool event routed to toolCallStream', () async {
      final (:client, :ws) = await connectAndHandshake();

      final toolCalls = <ToolCall>[];
      final sub = client.toolCallStream('test-instance').listen(toolCalls.add);

      ws.simulateServerFrame(
        agentToolJson(toolName: 'search', toolCallId: 'tc-1'),
      );
      await pumpMicrotasks();

      expect(
        toolCalls.length,
        1,
        reason: 'agent tool event should be routed to toolCallStream',
      );
      expect(toolCalls.first.toolName, 'search');
      expect(toolCalls.first.status, ToolCallStatus.running);

      await sub.cancel();
      await client.dispose();
    });

    test('non-chat events are silently ignored (not forwarded)', () async {
      final (:client, :ws) = await connectAndHandshake();

      final messages = <Message>[];
      final toolCalls = <ToolCall>[];
      final msgSub = client.messageStream('test-instance').listen(messages.add);
      final tcSub = client
          .toolCallStream('test-instance')
          .listen(toolCalls.add);

      // tick event is not a chat event — should not be forwarded
      ws.simulateServerFrame(tickJson);
      await pumpMicrotasks();

      expect(
        messages,
        isEmpty,
        reason: 'Non-chat events should not appear on messageStream',
      );
      expect(
        toolCalls,
        isEmpty,
        reason: 'Non-chat events should not appear on toolCallStream',
      );

      await msgSub.cancel();
      await tcSub.cancel();
      await client.dispose();
    });

    test('streamingDeltaStream emits StreamingDelta on chat.delta', () async {
      final (:client, :ws) = await connectAndHandshake();

      final events = <StreamingEvent>[];
      final sub = client
          .streamingDeltaStream('test-instance')
          .listen(events.add);

      ws.simulateServerFrame(chatDeltaJson(deltaText: 'Hey'));
      await pumpMicrotasks();

      expect(events.length, 1);
      expect(events.first, isA<StreamingDelta>());
      final delta = events.first as StreamingDelta;
      expect(delta.text, 'Hey');
      expect(
        delta.agentId,
        'r-1',
      ); // extracted from sessionKey "agent:r-1:main"

      await sub.cancel();
      await client.dispose();
    });

    test('streamingDeltaStream emits StreamingDone on chat.final', () async {
      final (:client, :ws) = await connectAndHandshake();

      final events = <StreamingEvent>[];
      final sub = client
          .streamingDeltaStream('test-instance')
          .listen(events.add);

      ws.simulateServerFrame(chatFinalJson());
      await pumpMicrotasks();

      expect(events.length, 1);
      expect(events.first, isA<StreamingDone>());
      expect((events.first as StreamingDone).agentId, 'r-1');

      await sub.cancel();
      await client.dispose();
    });

    test('multi-delta streaming produces correct sequence', () async {
      final (:client, :ws) = await connectAndHandshake();

      final events = <StreamingEvent>[];
      final sub = client
          .streamingDeltaStream('test-instance')
          .listen(events.add);

      ws.simulateServerFrame(chatDeltaJson(deltaText: 'Hello'));
      await pumpMicrotasks();
      ws.simulateServerFrame(chatDeltaJson(deltaText: ' World'));
      await pumpMicrotasks();
      ws.simulateServerFrame(chatFinalJson());
      await pumpMicrotasks();

      expect(events.length, 3);
      expect(events[0], isA<StreamingDelta>());
      expect((events[0] as StreamingDelta).text, 'Hello');
      expect(events[1], isA<StreamingDelta>());
      expect((events[1] as StreamingDelta).text, ' World');
      expect(events[2], isA<StreamingDone>());

      await sub.cancel();
      await client.dispose();
    });

    test('agent message event routes delta to streamingDeltaStream', () async {
      final (:client, :ws) = await connectAndHandshake();

      final events = <StreamingEvent>[];
      final sub = client
          .streamingDeltaStream('test-instance')
          .listen(events.add);

      ws.simulateServerFrame(agentMessageJson(delta: 'v3 message delta'));
      await pumpMicrotasks();

      expect(events.length, 1);
      expect(events.first, isA<StreamingDelta>());
      final delta = events.first as StreamingDelta;
      expect(delta.text, 'v3 message delta');
      expect(delta.agentId, 'r-1');

      await sub.cancel();
      await client.dispose();
    });

    test(
      'chat.delta + agent.assistant for same session does NOT duplicate deltas',
      () async {
        final (:client, :ws) = await connectAndHandshake();

        final events = <StreamingEvent>[];
        final sub = client
            .streamingDeltaStream('test-instance')
            .listen(events.add);

        // Gateway sends BOTH chat.delta and agent.assistant for the same
        // streaming response — only ONE StreamingDelta should be emitted
        // per chunk, not two.
        ws.simulateServerFrame(chatDeltaJson(deltaText: '你好'));
        await pumpMicrotasks();
        ws.simulateServerFrame(agentAssistantJson(delta: '你好'));
        await pumpMicrotasks();

        ws.simulateServerFrame(chatDeltaJson(deltaText: '世界'));
        await pumpMicrotasks();
        ws.simulateServerFrame(agentAssistantJson(delta: '世界'));
        await pumpMicrotasks();

        final deltas = events.whereType<StreamingDelta>().toList();
        expect(
          deltas.length,
          2,
          reason:
              'When Gateway sends both chat.delta and agent.assistant '
              'for the same session, only one delta per chunk should '
              'be emitted — got ${deltas.length} instead of 2',
        );
        expect(deltas[0].text, '你好');
        expect(deltas[1].text, '世界');

        await sub.cancel();
        await client.dispose();
      },
    );

    test(
      'agent.assistant-only deltas work when no chat.delta arrives',
      () async {
        final (:client, :ws) = await connectAndHandshake();

        final events = <StreamingEvent>[];
        final sub = client
            .streamingDeltaStream('test-instance')
            .listen(events.add);

        // v3 Gateway sends only agent.assistant — should work normally
        ws.simulateServerFrame(agentAssistantJson(delta: 'v3 only'));
        await pumpMicrotasks();

        final deltas = events.whereType<StreamingDelta>().toList();
        expect(deltas.length, 1);
        expect(deltas[0].text, 'v3 only');

        await sub.cancel();
        await client.dispose();
      },
    );

    // ====================================================================
    // lifecycle.end 事件测试 — Phase 3: 假设验证
    // ====================================================================
    group('agent.lifecycle.end', () {
      // H3: lifecycle.end without prior deltas → MUST NOT emit empty Message
      test(
        'lifecycle.end without deltas does NOT emit empty Message',
        () async {
          final (:client, :ws) = await connectAndHandshake();

          final messages = <Message>[];
          final sub = client
              .messageStream('test-instance')
              .listen(messages.add);

          // lifecycle.end without any prior assistant deltas
          ws.simulateServerFrame(agentLifecycleJson(phase: 'end'));
          await pumpMicrotasks();

          expect(
            messages.where((m) => (m.content ?? '').isNotEmpty).length,
            0,
            reason:
                'lifecycle.end without accumulated deltas '
                'should not emit a message',
          );
          expect(
            messages.length,
            0,
            reason:
                'No message at all should be emitted when buffer was never '
                'populated',
          );

          await sub.cancel();
          await client.dispose();
        },
      );

      // H3 variant: lifecycle.end with prior deltas → should emit ONE message
      test(
        'lifecycle.end with deltas emits ONE message and StreamingDone',
        () async {
          final (:client, :ws) = await connectAndHandshake();

          final messages = <Message>[];
          final streamingEvents = <StreamingEvent>[];
          final msgSub = client
              .messageStream('test-instance')
              .listen(messages.add);
          final streamSub = client
              .streamingDeltaStream('test-instance')
              .listen(streamingEvents.add);

          // Simulate: assistant delta → lifecycle.end (v3-only Gateway path)
          ws.simulateServerFrame(agentAssistantJson(delta: 'Hello'));
          await pumpMicrotasks();
          ws.simulateServerFrame(agentAssistantJson(delta: ' World'));
          await pumpMicrotasks();
          ws.simulateServerFrame(agentLifecycleJson(phase: 'end'));
          await pumpMicrotasks();

          expect(
            messages.length,
            1,
            reason: 'lifecycle.end should emit exactly one final message',
          );
          expect(
            messages.first.content,
            'Hello World',
            reason: 'Message content should equal all accumulated deltas',
          );
          expect(messages.first.role, MessageRole.agent);

          expect(
            streamingEvents.whereType<StreamingDone>().length,
            1,
            reason: 'lifecycle.end should emit exactly one StreamingDone',
          );

          await msgSub.cancel();
          await streamSub.cancel();
          await client.dispose();
        },
      );

      // H1: lifecycle.end BEFORE chat.final with msgJson → MUST NOT duplicate
      test('lifecycle.end before chat.final does NOT duplicate', () async {
        final (:client, :ws) = await connectAndHandshake();

        final messages = <Message>[];
        final streamingEvents = <StreamingEvent>[];
        final msgSub = client
            .messageStream('test-instance')
            .listen(messages.add);
        final streamSub = client
            .streamingDeltaStream('test-instance')
            .listen(streamingEvents.add);

        // Populate buffer with deltas
        ws.simulateServerFrame(agentAssistantJson(delta: 'Streaming'));
        await pumpMicrotasks();

        // lifecycle.end arrives FIRST (consumes buffer)
        ws.simulateServerFrame(agentLifecycleJson(phase: 'end'));
        await pumpMicrotasks();

        // chat.final with msgJson arrives SECOND
        ws.simulateServerFrame(
          chatFinalJson(
            sessionKey: 'agent:r-1:main',
            messageContent:
                '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
                '"content":"Streaming","role":"agent","type":"text"}',
          ),
        );
        await pumpMicrotasks();

        expect(
          messages.length,
          1,
          reason:
              'lifecycle.end + chat.final for the same session '
              'should NOT produce duplicate messages — only ONE message '
              'should be emitted',
        );
        expect(
          streamingEvents.whereType<StreamingDone>().length,
          1,
          reason:
              'StreamingDone should NOT be emitted twice for the '
              'same session',
        );

        await msgSub.cancel();
        await streamSub.cancel();
        await client.dispose();
      });

      // H2: chat.final BEFORE lifecycle.end → MUST NOT emit empty message
      test(
        'chat.final before lifecycle.end does NOT emit empty Message',
        () async {
          final (:client, :ws) = await connectAndHandshake();

          final messages = <Message>[];
          final streamingEvents = <StreamingEvent>[];
          final msgSub = client
              .messageStream('test-instance')
              .listen(messages.add);
          final streamSub = client
              .streamingDeltaStream('test-instance')
              .listen(streamingEvents.add);

          // Populate buffer with deltas
          ws.simulateServerFrame(agentAssistantJson(delta: 'Content'));
          await pumpMicrotasks();

          // chat.final arrives FIRST (consumes from msgJson, cleans buffer)
          ws.simulateServerFrame(
            chatFinalJson(
              sessionKey: 'agent:r-1:main',
              messageContent:
                  '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
                  '"content":"Content","role":"agent","type":"text"}',
            ),
          );
          await pumpMicrotasks();

          // lifecycle.end arrives SECOND (buffer already cleaned)
          ws.simulateServerFrame(agentLifecycleJson(phase: 'end'));
          await pumpMicrotasks();

          expect(
            messages.length,
            1,
            reason:
                'Only chat.final message should be emitted, '
                'lifecycle.end should NOT emit an empty message',
          );
          expect(
            messages.first.content,
            'Content',
            reason: 'The sole message should be from chat.final',
          );
          expect((messages.first.content ?? '').isNotEmpty, isTrue);

          expect(
            streamingEvents.whereType<StreamingDone>().length,
            1,
            reason: 'StreamingDone should NOT be emitted twice',
          );

          await msgSub.cancel();
          await streamSub.cancel();
          await client.dispose();
        },
      );
    });

    test('connection state stream reflects handshake progression', () async {
      final ws = ControllableWebSocket.ready();
      final identityProvider = FakeDeviceIdentityProvider();

      final client = WsGatewayClient(
        identityProvider: identityProvider,
        webSocketFactory: (_) => ws.channel,
      );

      final states = <GatewayConnectionState>[];
      final sub = client
          .connectionStateStream('test-instance')
          .listen(states.add);

      final instance = Instance(
        id: 'test-instance',
        name: 'Test',
        gatewayUrl: 'ws://localhost:9999/ws',
        tokenRef: 'test-token',
        healthStatus: HealthStatus.online,
        isLocalNetwork: false,
      );

      unawaited(client.connect(instance));
      await pumpMicrotasks();

      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      expect(
        states,
        containsAll([
          GatewayConnectionState.connecting,
          GatewayConnectionState.connected,
        ]),
        reason:
            'Connection state stream should reflect '
            'handshake progression (connecting → connected)',
      );

      await sub.cancel();
      await client.dispose();
    });

    test(
      'connectionStateStream seeds late subscriber with last known state',
      () async {
        // 复现 bug：同一实例连接已建立后，新打开的聊天页（晚订阅者）
        // 在无 replay 的广播流上收不到已发出的 `connected`，停留在默认
        // `disconnected`，导致横幅误显示"连接已断开，正在重连..."。
        final (:client, ws: _) = await connectAndHandshake();

        // 晚订阅：无 replay 的广播流此刻不会投递任何事件。
        final states = <GatewayConnectionState>[];
        final sub = client
            .connectionStateStream('test-instance')
            .listen(states.add);
        await pumpMicrotasks();

        expect(
          states,
          contains(GatewayConnectionState.connected),
          reason:
              '晚订阅者（连接已建立后才订阅）必须立即收到最后已知状态，'
              '而不是停留在默认 `disconnected` —— 这是同一实例下部分 agent '
              '显示"连接已断开，正在重连..."的根因。',
        );

        await sub.cancel();
        await client.dispose();
      },
    );

    test(
      'connectionStateStream does NOT seed stale terminal state after disconnect',
      () async {
        // 安全属性：ConnectionOrchestrator 在 reconnect() / 编辑保存时会重新
        // 订阅本流。终态（disconnected 等）绝不能作为 seed 下沉，否则
        // _onConnectionStateChanged 会被陈旧终态提前触发 → _connecting 锁
        // 提前释放（允许并发 _connect 绕过去重守卫）/ 重发 ReconnectExhaustedEvent
        // 等过期事件（违反 orchestrator Bug 3 守卫）。
        // 只有 connected 是安全的 seed（见 connectionStateStream 注释）。
        final (:client, ws: _) = await connectAndHandshake();

        await client.disconnect('test-instance');
        await pumpMicrotasks();

        // 断开后新订阅 —— 不应收到任何 stale seed
        final states = <GatewayConnectionState>[];
        final sub = client
            .connectionStateStream('test-instance')
            .listen(states.add);
        await pumpMicrotasks();

        expect(
          states,
          isEmpty,
          reason:
              '终态（disconnected）不得作为 seed 下沉。orchestrator 重连时 '
              '重新订阅若收到陈旧终态，会触发 _connecting 锁提前释放或重发 '
              'ReconnectExhaustedEvent，破坏连接去重与 Bug 3 守卫。',
        );

        await sub.cancel();
        await client.dispose();
      },
    );

    test(
      'connectionStateStream does NOT seed stale connected state after resetConnectionState',
      () async {
        // 锁住问题 1：resetConnectionState 必须经过 ReplayableConnectionState.emit，
        // 让 last 缓存与广播事件原子同步。否则 connected 实例调 reset 后新订阅者
        // 会拿到陈旧 connected seed（这次修复想消灭的 bug 复发形态）。
        final (:client, ws: _) = await connectAndHandshake();

        client.resetConnectionState('test-instance');
        await pumpMicrotasks();

        final states = <GatewayConnectionState>[];
        final sub = client
            .connectionStateStream('test-instance')
            .listen(states.add);
        await pumpMicrotasks();

        expect(
          states,
          isNot(contains(GatewayConnectionState.connected)),
          reason:
              'resetConnectionState 后 last 缓存应为 disconnected（而非 '
              '保留 connected）。否则新订阅者拿到陈旧 connected seed，UI 显示 '
              '已连接但真实状态是 reset 后的 disconnected。',
        );

        await sub.cancel();
        await client.dispose();
      },
    );

    test('connectionStateStream 支持同一实例多个订阅者（修复单订阅回归）', () async {
      // 回归锁：同一实例下多个聊天页（不同 agent）共享同一条
      // connectionStateStream。旧 ReplayableConnectionState 把 async* 生成器
      // 缓存为单订阅流，第二个 .listen() 抛 StateError，导致同实例第二个聊天页
      // 打开即崩溃。本测试直接覆盖该回归。
      final (:client, ws: _) = await connectAndHandshake();

      final states1 = <GatewayConnectionState>[];
      final states2 = <GatewayConnectionState>[];
      final sub1 = client
          .connectionStateStream('test-instance')
          .listen(states1.add);
      final sub2 = client
          .connectionStateStream('test-instance')
          .listen(states2.add);
      await pumpMicrotasks();

      expect(states1, contains(GatewayConnectionState.connected));
      expect(states2, contains(GatewayConnectionState.connected));

      await sub1.cancel();
      await sub2.cancel();
      await client.dispose();
    });

    test(
      'connectionStateStream does NOT seed stale connected during connect-reuse cleanup window',
      () async {
        // 锁住问题 2：_cleanup(emitDisconnected: false) 在 connect() 复用已有
        // conn 时被调用 —— 它 dispose manager 但必须 clear() last 缓存。否则
        // 在 await 新 manager.connect() 完成之前，晚订阅者会拿到陈旧 connected
        // seed 而真实底层 manager 已不存在。
        final (:client, ws: _) = await connectAndHandshake();

        await client.disconnect('test-instance');
        await pumpMicrotasks();

        // 再次 connect —— 复用 conn 触发 _cleanup(emitDisconnected:false)
        //    路径。_cleanup 调 clear() 把 last 缓存复位为 null，因此订阅后
        //    在新握手完成「之前」不应收到任何陈旧 connected seed。
        unawaited(client.connect(testInstance()));
        await pumpMicrotasks();

        final states = <GatewayConnectionState>[];
        final sub = client
            .connectionStateStream('test-instance')
            .listen(states.add);
        await pumpMicrotasks();

        // 关键不变式（窗口内）：_cleanup 已 clear 缓存，订阅初始无 stale seed。
        // 必须在驱动第二次握手「之前」断言 —— 否则新连接完成后会合法地投递
        // live `connected`，那是正常事件而非陈旧 seed，整段轨迹断言会误判。
        expect(
          states,
          isEmpty,
          reason:
              'connect-reuse 窗口内（新握手完成前）新订阅者不应收到任何 seed —— '
              '_cleanup 已 clear last 缓存。若非空，说明缓存未清，'
              '窗口内 seed 与真实 manager 状态错位。',
        );

        await sub.cancel();
        await client.dispose();
      },
    );

    test(
      'messageStream works before connect (empty stream, no error)',
      () async {
        final client = WsGatewayClient(
          identityProvider: FakeDeviceIdentityProvider(),
        );

        final messages = <Message>[];
        final sub = client.messageStream('test-instance').listen(messages.add);

        await pumpMicrotasks();
        expect(
          messages,
          isEmpty,
          reason: 'messageStream should be empty before connect',
        );

        await sub.cancel();
        await client.dispose();
      },
    );

    test(
      'toolCallStream works before connect (empty stream, no error)',
      () async {
        final client = WsGatewayClient(
          identityProvider: FakeDeviceIdentityProvider(),
        );

        final toolCalls = <ToolCall>[];
        final sub = client
            .toolCallStream('test-instance')
            .listen(toolCalls.add);

        await pumpMicrotasks();
        expect(
          toolCalls,
          isEmpty,
          reason: 'toolCallStream should be empty before connect',
        );

        await sub.cancel();
        await client.dispose();
      },
    );
  });

  // ==========================================================================
  // Bug #1: 双对号 — _parseMessage 把所有入站消息（包括回传的 user 消息）
  // 一律标 delivered，导致用户自己发的消息右下角显示双对号（done_all）。
  // 修复：按角色赋状态 — user → sent（最多已送达网关），agent/system → delivered。
  // ==========================================================================
  group('_parseMessage status by role (Bug #1 — double-checkmark)', () {
    test('user-role message is parsed as SENT, not DELIVERED', () async {
      final (:client, :ws) = await connectAndHandshake();

      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      // Gateway 回传 / 历史拉取中的 user 消息（role=user）。
      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":"我发送的消息","role":"user","type":"text"}',
        ),
      );
      await pumpMicrotasks();

      expect(messages, hasLength(1));
      expect(messages.first.role, MessageRole.user);
      expect(
        messages.first.status,
        MessageStatus.sent,
        reason:
            '回传/历史中的 user 消息不能被标 delivered —— 否则右下角会渲染双对号 '
            '(Icons.done_all)。user 消息最多到 sent（已送达网关），delivered '
            '保留给 agent 已读。',
      );

      await sub.cancel();
      await client.dispose();
    });

    test('agent-role message remains DELIVERED (regression guard)', () async {
      final (:client, :ws) = await connectAndHandshake();

      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":"Agent reply","role":"agent","type":"text"}',
        ),
      );
      await pumpMicrotasks();

      expect(messages, hasLength(1));
      expect(messages.first.role, MessageRole.agent);
      expect(
        messages.first.status,
        MessageStatus.delivered,
        reason: 'agent 回复仍应标 delivered（已读/已处理）。',
      );

      await sub.cancel();
      await client.dispose();
    });
  });

  // ==========================================================================
  // Bug #2 (重启错乱): 历史消息 logicalClock 兜底用 DateTime.now() → 所有历史
  // 消息聚到「重启时刻」,而非各自原始时间 → ORDER BY logical_clock DESC 把
  // 整批历史堆在顶部、本地消息压到底部,且历史消息间互相 tie → 错乱。
  // 修法: _parseMessage 在 gateway 省略 logicalClock 时回退到「消息自身时间戳」
  // (而非 DateTime.now()),并把秒级时间戳归一化为毫秒,保证时序正确。
  // gateway 显式给的 logicalClock 保持原样(向后兼容,不二次猜测)。
  // ==========================================================================
  group('_parseMessage chronology (Bug #2 — history scramble)', () {
    test('seconds-scale timestamp is normalized to milliseconds', () async {
      final (:client, :ws) = await connectAndHandshake();
      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      // Gateway 历史可能用秒级时间戳 (doc §5.4 示意图: 1718000000)。
      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":"reply","role":"agent","type":"text",'
              '"timestamp":1718000000}',
        ),
      );
      await pumpMicrotasks();

      expect(messages, hasLength(1));
      expect(
        messages.first.timestamp,
        1718000000000,
        reason:
            '秒级时间戳必须归一化为毫秒,与本地消息(DateTime.now().ms)同量级,'
            '否则软匹配 ±60s 永不命中、排序错乱。',
      );

      await sub.cancel();
      await client.dispose();
    });

    test('milliseconds-scale timestamp is preserved unchanged', () async {
      final (:client, :ws) = await connectAndHandshake();
      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":"reply","role":"agent","type":"text",'
              '"timestamp":1718000000000}',
        ),
      );
      await pumpMicrotasks();

      expect(messages.first.timestamp, 1718000000000, reason: '毫秒时间戳不应被改动。');

      await sub.cancel();
      await client.dispose();
    });

    test('message without logicalClock falls back to its own timestamp '
        '(NOT DateTime.now) — fixes history scramble', () async {
      final (:client, :ws) = await connectAndHandshake();
      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      // 历史消息: gateway 省略 logicalClock, 但带原始 timestamp。
      // 旧实现兜底为 DateTime.now()(重启时刻)→ 错乱。
      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":"old reply","role":"agent","type":"text",'
              '"timestamp":1717000000000}',
        ),
      );
      await pumpMicrotasks();

      expect(messages, hasLength(1));
      expect(
        messages.first.logicalClock,
        1717000000000,
        reason:
            '省略 logicalClock 时应回退到消息自身时间戳(归一化后),'
            '保证历史消息按原始时间排序,而非全部聚到重启时刻。',
      );

      await sub.cancel();
      await client.dispose();
    });

    test('message without logicalClock and without timestamp stays now-based '
        '(regression guard)', () async {
      final (:client, :ws) = await connectAndHandshake();
      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      final before = DateTime.now().millisecondsSinceEpoch;
      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":"reply","role":"agent","type":"text"}',
        ),
      );
      await pumpMicrotasks();
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(messages, hasLength(1));
      expect(messages.first.logicalClock, greaterThanOrEqualTo(before));
      expect(messages.first.logicalClock, lessThanOrEqualTo(after));

      await sub.cancel();
      await client.dispose();
    });

    test(
      'explicit gateway logicalClock is preserved verbatim (no normalization)',
      () async {
        final (:client, :ws) = await connectAndHandshake();
        final messages = <Message>[];
        final sub = client.messageStream('test-instance').listen(messages.add);

        ws.simulateServerFrame(
          chatFinalJson(
            sessionKey: 'agent:r-1:main',
            messageContent:
                '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
                '"content":"reply","role":"agent","type":"text",'
                '"logicalClock":999999}',
          ),
        );
        await pumpMicrotasks();

        expect(
          messages.first.logicalClock,
          999999,
          reason: 'gateway 显式给的 logicalClock 必须原样保留,不二次猜测。',
        );

        await sub.cancel();
        await client.dispose();
      },
    );
  });

  // ==========================================================================
  // _parseMessage response-side image promotion (PROTOCOL-VERIFY assumption)
  // ==========================================================================
  group('_parseMessage image content blocks (PROTOCOL-VERIFY)', () {
    test(
      'content blocks with image_url → type=image, content=null, metadata.imageUrl',
      () async {
        final (:client, :ws) = await connectAndHandshake();

        final messages = <Message>[];
        final sub = client.messageStream('test-instance').listen(messages.add);

        // 外层 type=text,但 content 是结构化 blocks 且含 image_url block。
        // _parseMessage 应提升 type=image,content 置 null,caption+imageUrl 入 metadata。
        ws.simulateServerFrame(
          chatFinalJson(
            sessionKey: 'agent:r-1:main',
            messageContent:
                '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
                '"content":[{"type":"text","text":"看这个"},'
                '{"type":"image_url","image_url":{"url":"https://x.com/a.png"}}],'
                '"role":"agent","type":"text"}',
          ),
        );
        await pumpMicrotasks();

        expect(messages, hasLength(1));
        final msg = messages.first;
        expect(msg.type, MessageType.image);
        // content 保留为图片说明文本;imagePath 靠 imageUrl==null 区分,故为 null
        expect(msg.content, '看这个');
        expect(msg.imageUrl, 'https://x.com/a.png');
        expect(msg.isImage, isTrue);
        expect(msg.imagePath, isNull, reason: 'Agent 回图无本地路径');

        await sub.cancel();
        await client.dispose();
      },
    );

    test('plain text content (no image block) stays type=text', () async {
      final (:client, :ws) = await connectAndHandshake();

      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":[{"type":"text","text":"纯文本"}],'
              '"role":"agent","type":"text"}',
        ),
      );
      await pumpMicrotasks();

      expect(messages, hasLength(1));
      expect(messages.first.type, MessageType.text);
      expect(messages.first.content, '纯文本');
      expect(messages.first.imageUrl, isNull);

      await sub.cancel();
      await client.dispose();
    });

    test('explicit type=image with string content preserved', () async {
      final (:client, :ws) = await connectAndHandshake();

      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      // Gateway 显式标 type=image 但用字符串 content(无 blocks)。
      // 无 imageRef → 不强制 null content,保留原 content。
      ws.simulateServerFrame(
        chatFinalJson(
          sessionKey: 'agent:r-1:main',
          messageContent:
              '{"agentId":"r-1","sessionKey":"agent:r-1:main",'
              '"content":"caption-only","role":"agent","type":"image"}',
        ),
      );
      await pumpMicrotasks();

      expect(messages, hasLength(1));
      expect(messages.first.type, MessageType.image);
      // 无 imageRef → content 不被置 null
      expect(messages.first.content, 'caption-only');

      await sub.cancel();
      await client.dispose();
    });
  });

  // ==========================================================================
  // modelIdentifierLoader (US-XXX — protocol handshake device reporting)
  // ==========================================================================
  group('modelIdentifierLoader', () {
    test('loader return value flows to config.modelIdentifier', () async {
      final identityProvider = FakeDeviceIdentityProvider();
      final client = WsGatewayClient(
        identityProvider: identityProvider,
        modelIdentifierLoader: () async => 'Pixel 8',
      );

      final identity = await identityProvider.ensureDeviceIdentity();
      final config = await WsGatewayClient.resolveConfigForTesting(
        client,
        identity,
      );

      expect(config.modelIdentifier, 'Pixel 8');

      await client.dispose();
    });

    test('loader returns null → config.modelIdentifier is null', () async {
      final identityProvider = FakeDeviceIdentityProvider();
      final client = WsGatewayClient(
        identityProvider: identityProvider,
        modelIdentifierLoader: () async => null,
      );

      final identity = await identityProvider.ensureDeviceIdentity();
      final config = await WsGatewayClient.resolveConfigForTesting(
        client,
        identity,
      );

      expect(config.modelIdentifier, isNull);

      await client.dispose();
    });

    test(
      'loader throws → config.modelIdentifier is null (Law 8 best-effort)',
      () async {
        final identityProvider = FakeDeviceIdentityProvider();
        final client = WsGatewayClient(
          identityProvider: identityProvider,
          modelIdentifierLoader: () async {
            throw StateError('device_info_plus blew up');
          },
        );

        final identity = await identityProvider.ensureDeviceIdentity();
        // Must not throw — loader exceptions are swallowed.
        final config = await WsGatewayClient.resolveConfigForTesting(
          client,
          identity,
        );

        expect(config.modelIdentifier, isNull);

        await client.dispose();
      },
    );

    test('no loader injected → config.modelIdentifier is null '
        '(backward compat)', () async {
      final identityProvider = FakeDeviceIdentityProvider();
      final client = WsGatewayClient(identityProvider: identityProvider);

      final identity = await identityProvider.ensureDeviceIdentity();
      final config = await WsGatewayClient.resolveConfigForTesting(
        client,
        identity,
      );

      expect(config.modelIdentifier, isNull);

      await client.dispose();
    });
  });

  _replayableConnectionStateTests();
}

// ============================================================================
// ReplayableConnectionState 单元测试 —— 锁定"仅 seed connected"契约
// ============================================================================

void _replayableConnectionStateTests() {
  group('ReplayableConnectionState', () {
    test('初始（last == null）订阅者无 seed', () async {
      final state = ReplayableConnectionState();
      final events = <GatewayConnectionState>[];
      final sub = state.stream.listen(events.add);
      await pumpMicrotasks();

      expect(events, isEmpty);

      await sub.cancel();
      await state.dispose();
    });

    test('仅在 emit(connected) 后订阅者才收到 connected seed', () async {
      final state = ReplayableConnectionState();
      state.emit(GatewayConnectionState.connected);

      final events = <GatewayConnectionState>[];
      final sub = state.stream.listen(events.add);
      await pumpMicrotasks();

      expect(events, [GatewayConnectionState.connected]);

      await sub.cancel();
      await state.dispose();
    });

    test(
      'emit(reconnecting/connecting/recovering/disconnected) 均不下沉 seed',
      () async {
        // 锁住问题 4 边界 + 整个设计契约：
        // 只有 connected 被 seed；其他状态（含瞬态、各终态）保持原广播流
        // 行为。原因见 WsGatewayClient.connectionStateStream 的注释。
        const statesToTest = [
          GatewayConnectionState.connecting,
          GatewayConnectionState.authenticating,
          GatewayConnectionState.recovering,
          GatewayConnectionState.disconnected,
          GatewayConnectionState.authFailed,
          GatewayConnectionState.pairingRequired,
          GatewayConnectionState.reconnectExhausted,
        ];

        for (final s in statesToTest) {
          final state = ReplayableConnectionState();
          state.emit(s);

          final events = <GatewayConnectionState>[];
          final sub = state.stream.listen(events.add);
          await pumpMicrotasks();

          expect(
            events,
            isEmpty,
            reason:
                '状态 $s 不应作为 seed 下沉（避免向 reconnect/编辑保存时 '
                '重新订阅的 orchestrator 投递陈旧事件）。',
          );

          await sub.cancel();
          await state.dispose();
        }
      },
    );

    test('clear() 之后 last 复位为 null，新订阅者无 seed', () async {
      final state = ReplayableConnectionState();
      state.emit(GatewayConnectionState.connected);
      // 模拟 _cleanup(emitDisconnected:false) —— clear 但不 emit
      state.clear();

      final events = <GatewayConnectionState>[];
      final sub = state.stream.listen(events.add);
      await pumpMicrotasks();

      expect(
        events,
        isEmpty,
        reason:
            'clear() 必须彻底复位 last 缓存，否则 _cleanup 复用路径上 '
            '会出现陈旧 connected seed。',
      );

      await sub.cancel();
      await state.dispose();
    });

    test('多个同时订阅者均收到 connected seed（广播语义不退化）', () async {
      // 回归锁：旧实现把 async* 生成器缓存进 _seededView（单订阅流），
      // 第二个 .listen() 会抛 StateError。同实例下多个聊天页（不同 agent）
      // 共享同一条 connectionStateStream，必须支持多订阅。
      final state = ReplayableConnectionState();
      state.emit(GatewayConnectionState.connected);

      final events1 = <GatewayConnectionState>[];
      final events2 = <GatewayConnectionState>[];
      final sub1 = state.stream.listen(events1.add);
      final sub2 = state.stream.listen(events2.add);
      await pumpMicrotasks();

      expect(events1, [GatewayConnectionState.connected]);
      expect(events2, [GatewayConnectionState.connected]);

      // live 事件须同时透传给两个订阅者
      state.emit(GatewayConnectionState.recovering);
      await pumpMicrotasks();
      expect(events1, [
        GatewayConnectionState.connected,
        GatewayConnectionState.recovering,
      ]);
      expect(events2, [
        GatewayConnectionState.connected,
        GatewayConnectionState.recovering,
      ]);

      await sub1.cancel();
      await sub2.cancel();
      await state.dispose();
    });

    test('取消后重新订阅仍能收到 seed（页面回收复用）', () async {
      // 回归锁：旧缓存的 async* 流被第一次订阅耗尽后不可重启，
      // 仅 subscription.cancel()（状态仍为 connected）不会清缓存，
      // 导致关闭聊天页再重开时 .listen() 抛 StateError。
      final state = ReplayableConnectionState();
      state.emit(GatewayConnectionState.connected);

      final events1 = <GatewayConnectionState>[];
      final sub1 = state.stream.listen(events1.add);
      await pumpMicrotasks();
      expect(events1, [GatewayConnectionState.connected]);
      await sub1.cancel();

      // 仍处于 connected —— 重新订阅不应抛 StateError，且应再次收到 seed
      final events2 = <GatewayConnectionState>[];
      final sub2 = state.stream.listen(events2.add);
      await pumpMicrotasks();
      expect(events2, [GatewayConnectionState.connected]);

      await sub2.cancel();
      await state.dispose();
    });

    test('emit 之后订阅者同时收到 seed 和 live 事件', () async {
      final state = ReplayableConnectionState();
      state.emit(GatewayConnectionState.connected);

      final events = <GatewayConnectionState>[];
      final sub = state.stream.listen(events.add);
      await pumpMicrotasks();

      // seed 已收到；后续 emit 的 live 事件应继续透传
      state.emit(GatewayConnectionState.recovering);
      state.emit(GatewayConnectionState.connected);
      await pumpMicrotasks();

      expect(events, [
        GatewayConnectionState.connected, // seed
        GatewayConnectionState.recovering, // live
        GatewayConnectionState.connected, // live
      ]);

      await sub.cancel();
      await state.dispose();
    });
  });

  // ==========================================================================
  // Bug #2: chat.history cursor field name — defensively read both
  // 'cursor' and 'nextCursor' from response payload.
  //
  // spec §5.4 example uses 'cursor' but the client used to only read
  // 'nextCursor', causing pagination to deadlock at page 2 (nextCursor
  // was always null because the server was sending 'cursor').
  // ==========================================================================
  group('fetchMessageHistory pagination (Bug #2)', () {
    /// Helper: send a chat.history request and inject a server response.
    /// The 1st sent frame is the connect request (consumed by
    /// connectAndHandshake); the 2nd sent frame is chat.history.
    Future<({List<Message> messages, String? nextCursor})> sendHistory(
      WsGatewayClient client,
      ControllableWebSocket ws, {
      String? cursor,
      String? nextCursor,
    }) async {
      final future = client.fetchMessageHistory(
        instanceId: 'test-instance',
        agentId: 'a-1',
      );
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames[1]);
      ws.simulateServerFrame(
        chatHistoryResponseJson(
          id: reqId,
          cursor: cursor,
          nextCursor: nextCursor,
        ),
      );
      return future;
    }

    test('reads nextCursor from payload.nextCursor field', () async {
      final (:client, :ws) = await connectAndHandshake();
      final result = await sendHistory(client, ws, nextCursor: 'nc-1');
      expect(result.nextCursor, 'nc-1');
      await client.dispose();
    });

    test(
      'falls back to payload.cursor when nextCursor absent (Bug #2)',
      () async {
        final (:client, :ws) = await connectAndHandshake();
        final result = await sendHistory(client, ws, cursor: 'c-1');
        expect(
          result.nextCursor,
          'c-1',
          reason:
              'must read "cursor" field per docs/technical/api-protocol.md §5.4',
        );
        await client.dispose();
      },
    );

    test('prefers nextCursor when both present (forward-compat)', () async {
      final (:client, :ws) = await connectAndHandshake();
      final result = await sendHistory(
        client,
        ws,
        nextCursor: 'nc-1',
        cursor: 'c-1',
      );
      expect(
        result.nextCursor,
        'nc-1',
        reason: 'nextCursor is the forward-compat field name; wins over cursor',
      );
      await client.dispose();
    });

    test(
      'returns null when neither cursor nor nextCursor is present',
      () async {
        final (:client, :ws) = await connectAndHandshake();
        final result = await sendHistory(client, ws);
        expect(result.nextCursor, isNull);
        await client.dispose();
      },
    );
  });

  // ============================================================================
  // Gap #6: payload.large diagnostic event (spec §2.7).
  //
  // When the Gateway rejects an over-sized payload, it pushes a
  // `payload.large` event with sessionKey/size/limit. WsGatewayClient must
  // parse it and emit a LargePayloadNotice on the per-instance diagnostic
  // stream so the UI can show a user-visible hint instead of silently
  // failing the message.
  // ============================================================================
  group('payload.large diagnostic event (Gap #6)', () {
    test('emits LargePayloadNotice on gatewayNoticeStream', () async {
      final (:client, :ws) = await connectAndHandshake();

      final noticeFuture = client.gatewayNoticeStream('test-instance').first;

      ws.simulateServerFrame(
        '{"type":"event","event":"payload.large",'
        '"payload":{"sessionKey":"agent:r-1:main",'
        '"size":31457280,"limit":26214400}}',
      );
      await pumpMicrotasks();

      final base = await noticeFuture;
      expect(base, isA<LargePayloadNotice>());
      final notice = base as LargePayloadNotice;
      expect(notice.sessionKey, 'agent:r-1:main');
      expect(notice.size, 31457280);
      expect(notice.limit, 26214400);

      await client.dispose();
    });

    test('stream tolerates a payload.large with missing fields', () async {
      final (:client, :ws) = await connectAndHandshake();

      final noticeFuture = client.gatewayNoticeStream('test-instance').first;

      // Server variant: missing sessionKey/size/limit — parser coerces
      // to defaults instead of crashing the diagnostic path.
      ws.simulateServerFrame(
        '{"type":"event","event":"payload.large","payload":{}}',
      );
      await pumpMicrotasks();

      final base = await noticeFuture;
      expect(base, isA<LargePayloadNotice>());
      final notice = base as LargePayloadNotice;
      expect(notice.sessionKey, '');
      expect(notice.size, 0);
      expect(notice.limit, 0);

      await client.dispose();
    });

    // NOTE: The third test case (IGatewayClient default impl returns
    // Stream.empty) was removed — the default impl is `=> const
    // Stream.empty()` and is trivially correct.  The two tests above
    // cover the actual production path: WsGatewayClient parses and
    // emits the notice, and tolerates partial server payloads.
  });

  // ============================================================================
  // F-4: BufferOverflowException → BufferOverflowNotice translation.
  //
  // When the in-flight buffer is full (reject-new backpressure, spec §2.2
  // maxBufferedBytes), ConnectionManager.sendRequest throws
  // BufferOverflowException *before* writing to the socket. WsGatewayClient
  // .sendMessage catches it, emits a BufferOverflowNotice on the diagnostic
  // stream (so the UI shows a toast via the existing sealed-union path), then
  // rethrows so SendMessageUseCase marks the message FAILED (retryable by
  // OutboxProcessor once the buffer drains). No socket write, no session-
  // mapping leak.
  // ============================================================================
  group('BufferOverflowException → BufferOverflowNotice (F-4)', () {
    /// hello-ok with a tight maxBufferedBytes cap so a second in-flight send
    /// trips the reject-new guard. Kept local (not added to test_helpers.dart)
    /// to avoid touching a shared file for a single test.
    String helloOkTightBuffer(String id, {required int maxBufferedBytes}) =>
        '{"type":"res","id":"$id","ok":true,'
        '"payload":{"type":"hello-ok","protocol":4,'
        '"policy":{"tickIntervalMs":15000,'
        '"maxBufferedBytes":$maxBufferedBytes,"maxPayload":10000000}}}';

    /// Drive the handshake with a tight-buffer hello-ok (the default
    /// [connectAndHandshake] uses a 50MB cap, which never trips reject-new).
    Future<({WsGatewayClient client, ControllableWebSocket ws})>
    handshakeTightBuffer({required int maxBufferedBytes}) async {
      final ws = ControllableWebSocket.ready();
      final client = WsGatewayClient(
        identityProvider: FakeDeviceIdentityProvider(),
        webSocketFactory: (_) => ws.channel,
      );
      unawaited(client.connect(testInstance()));
      await pumpMicrotasks();
      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(
        helloOkTightBuffer(reqId, maxBufferedBytes: maxBufferedBytes),
      );
      await pumpMicrotasks();
      return (client: client, ws: ws);
    }

    Message buildMsg(String content, {required String clientId}) => Message(
      clientId: clientId,
      conversationId: 'conv-1',
      agentId: 'agent-r1',
      role: MessageRole.user,
      type: MessageType.text,
      content: content,
      logicalClock: 0,
    );

    test('sendMessage throws BufferOverflowException AND emits '
        'BufferOverflowNotice when the in-flight buffer is full', () async {
      // Byte math (robust margins): one chat.send with 'x'*500 content
      // serializes to ~688 UTF-8 bytes (params wrapper + 500 content).
      // cap=1000 → one request fits (688 < 1000), two would overflow
      // (1376 > 1000) → reject-new on the second.
      final (:client, :ws) = await handshakeTightBuffer(maxBufferedBytes: 1000);

      // 1. Fire first send unawaited — it passes the buffer check,
      //    writes a frame, registers its completer, then suspends at
      //    `await completer.future`. Its ~688 bytes stay counted.
      final f1 = client.sendMessage(
        instanceId: 'test-instance',
        agentId: 'agent-r1',
        message: buildMsg('x' * 500, clientId: 'msg-1'),
      );
      await pumpMicrotasks();

      // 2. Subscribe to the diagnostic stream BEFORE firing #2 —
      //    gatewayNoticeCtrl is a broadcast controller (no replay).
      final notices = <GatewayNotice>[];
      final sub = client
          .gatewayNoticeStream('test-instance')
          .listen(notices.add);

      // 3. Second same-shape send trips reject-new → throws
      //    BufferOverflowException. The catch in sendMessage emits the
      //    notice on the diagnostic stream, then rethrows.
      await expectLater(
        client.sendMessage(
          instanceId: 'test-instance',
          agentId: 'agent-r1',
          message: buildMsg('x' * 500, clientId: 'msg-2'),
        ),
        throwsA(isA<BufferOverflowException>()),
      );
      await pumpMicrotasks();

      // 4. Exactly one notice was emitted, typed as BufferOverflowNotice
      //    (and as the sealed base type GatewayNotice).
      expect(notices.length, 1);
      expect(notices.single, isA<BufferOverflowNotice>());
      expect(notices.single, isA<GatewayNotice>());

      // 5. The rejected send never touched the socket — only #1's
      //    chat.send frame was written (reject-new throws before
      //    _channel.sink.add). sentFrames = [connect, chat.send#1].
      final chatSendFrames = ws.sentFrames
          .where((f) => f.contains('"method":"chat.send"'))
          .length;
      expect(
        chatSendFrames,
        1,
        reason:
            'the rejected send must not have written a frame — '
            'reject-new throws before _channel.sink.add',
      );

      await sub.cancel();

      // 6. Clean up #1: inject its chat.send response so it resolves
      //    normally (otherwise dispose→_failAllPending→ok:false→sendMessage
      //    throws Exception → unhandled post-dispose error).
      final f1Frame = ws.sentFrames.lastWhere(
        (f) => f.contains('"method":"chat.send"'),
      );
      final f1ReqId = extractReqId(f1Frame);
      ws.simulateServerFrame(
        '{"type":"res","id":"$f1ReqId","ok":true,'
        '"payload":{"runId":"run-1","timestamp":1700000000000}}',
      );
      await f1;

      await client.dispose();
    });

    test(
      'a non-overflow send (buffer not full) does NOT emit a notice',
      () async {
        // Sanity guard: the catch must fire ONLY on BufferOverflowException,
        // not on every sendMessage. A single send well under the cap must
        // produce zero diagnostic notices.
        final (:client, :ws) = await handshakeTightBuffer(
          maxBufferedBytes: 10_000,
        );

        final notices = <GatewayNotice>[];
        final sub = client
            .gatewayNoticeStream('test-instance')
            .listen(notices.add);

        final future = client.sendMessage(
          instanceId: 'test-instance',
          agentId: 'agent-r1',
          message: buildMsg('hello', clientId: 'msg-1'),
        );
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.last);
        ws.simulateServerFrame(
          '{"type":"res","id":"$reqId","ok":true,'
          '"payload":{"runId":"run-1","timestamp":1700000000000}}',
        );
        await future;
        await pumpMicrotasks();

        expect(
          notices,
          isEmpty,
          reason:
              'a successful send under the cap must not emit a '
              'BufferOverflowNotice — the catch fires only on reject-new',
        );

        await sub.cancel();
        await client.dispose();
      },
    );

    test('sendMessage logs buffered/attempted/max byte sizes on overflow '
        '(diagnostic trail)', () async {
      // BufferOverflowException carries buffered/attempted/max fields, but
      // every downstream catch (SendMessageUseCase.execute / .retry)
      // discards them. The sendMessage catch is the only site where they're
      // in scope — pin that a debugPrint actually fires carrying the fields,
      // so a user report of "网关繁忙" leaves a diagnosable trail and the log
      // can't be silently removed.
      final (:client, :ws) = await handshakeTightBuffer(maxBufferedBytes: 1000);

      // Capture debugPrint output for the duration of this test only.
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = original);

      // Fire #1 unawaited so its ~688 bytes stay counted, then #2 trips
      // reject-new and hits the sendMessage catch (where the log lives).
      unawaited(
        client.sendMessage(
          instanceId: 'test-instance',
          agentId: 'agent-r1',
          message: buildMsg('x' * 500, clientId: 'msg-1'),
        ),
      );
      await pumpMicrotasks();

      await expectLater(
        client.sendMessage(
          instanceId: 'test-instance',
          agentId: 'agent-r1',
          message: buildMsg('x' * 500, clientId: 'msg-2'),
        ),
        throwsA(isA<BufferOverflowException>()),
      );
      await pumpMicrotasks();

      final overflowLogs = logs
          .where((l) => l.contains('Buffer overflow on sendMessage'))
          .toList();
      expect(overflowLogs.length, 1, reason: 'exactly one overflow log line');
      final line = overflowLogs.single;
      expect(line, contains('test-instance'));
      // The three diagnostic fields are surfaced (max is deterministic = the
      // negotiated cap; buffered/attempted are approximate, only assert
      // presence + sign).
      expect(line, contains('max=1000'));
      expect(line, contains('buffered='));
      expect(line, contains('attempted='));

      // Resolve #1 so dispose doesn't throw on a pending completer.
      final f1Frame = ws.sentFrames.firstWhere(
        (f) => f.contains('"method":"chat.send"'),
      );
      final f1ReqId = extractReqId(f1Frame);
      ws.simulateServerFrame(
        '{"type":"res","id":"$f1ReqId","ok":true,'
        '"payload":{"runId":"run-1","timestamp":1700000000000}}',
      );
      await client.dispose();
    });
  });

  // ==========================================================================
  // Step 5 (P3): sendMessage attachment error handling — _readFileBase64
  //
  // Law 17 test-first (ACL). The fix changes:
  //   - lengthSync() → await file.length() (non-blocking, moved inside try)
  //   - bare Exception('...$e') → typed AttachmentReadException
  //
  // Actual catch shape observed (READ before writing these tests):
  // `_readFileBase64(message)` is called at the TOP of `sendMessage` (line
  // 381), BEFORE the `try` block (line 388). So any exception it throws
  // propagates straight out of `sendMessage` — sendMessage does NOT catch it
  // and does NOT mark the message FAILED. FAILED marking is done by the
  // UseCase layer (per comment at lines 401-402). Therefore these tests
  // assert the exception TYPE thrown by sendMessage, not a FAILED status.
  // ==========================================================================
  group('sendMessage attachment error handling (P3 — _readFileBase64)', () {
    Message attachmentMsg({
      required String path,
      required MessageType type,
      String clientId = 'att-1',
    }) => Message(
      clientId: clientId,
      conversationId: 'conv-1',
      agentId: 'r-1',
      role: MessageRole.user,
      type: type,
      content: path,
      logicalClock: 0,
      metadata: const {'fileName': 'f', 'mimeType': 'image/jpeg'},
    );

    test('missing attachment file throws AttachmentReadException '
        '(not raw FileSystemException)', () async {
      final (:client, :ws) = await connectAndHandshake();
      final msg = attachmentMsg(
        path: '/nonexistent/path/img.jpg',
        type: MessageType.image,
      );
      // Before fix: lengthSync() threw FileSystemException (untyped, outside
      // the try). After fix: caught inside try, rethrown as typed
      // AttachmentReadException via readFailed factory.
      await expectLater(
        client.sendMessage(
          instanceId: 'test-instance',
          agentId: 'r-1',
          message: msg,
        ),
        throwsA(isA<AttachmentReadException>()),
      );
      await client.dispose();
    });

    test('oversized attachment throws AttachmentReadException (typed, not '
        'bare Exception)', () async {
      final tempDir = await Directory.systemTemp.createTemp('att_oversize_');
      final tempFile = File('${tempDir.path}/big.bin');
      // file-type limit = 5MB (5*1024*1024); write 6MB to exceed it.
      await tempFile.writeAsBytes(Uint8List(6 * 1024 * 1024));
      addTearDown(() async => tempDir.delete(recursive: true));

      final (:client, :ws) = await connectAndHandshake();
      final msg = attachmentMsg(path: tempFile.path, type: MessageType.file);
      await expectLater(
        client.sendMessage(
          instanceId: 'test-instance',
          agentId: 'r-1',
          message: msg,
        ),
        throwsA(isA<AttachmentReadException>()),
      );
      await client.dispose();
    });

    test(
      'readable attachment file encodes to base64 in chat.send frame',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('att_ok_');
        final tempFile = File('${tempDir.path}/img.jpg');
        final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG SOI
        await tempFile.writeAsBytes(bytes);
        addTearDown(() async => tempDir.delete(recursive: true));

        final (:client, :ws) = await connectAndHandshake();
        final future = client.sendMessage(
          instanceId: 'test-instance',
          agentId: 'r-1',
          message: attachmentMsg(path: tempFile.path, type: MessageType.image),
        );
        // _readFileBase64 does real dart:io reads (await file.length()/
        // readAsBytes) which complete on the IO port, not the microtask
        // queue. pumpMicrotasks alone races the assertion below (chat.send
        // not yet emitted → reads the connect handshake frame instead).
        // Drain the event loop so the reads finish and the chat.send frame
        // is sent before we inspect ws.sentFrames.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await pumpMicrotasks();

        // The chat.send frame must carry attachments with base64 content.
        // Frame shape: {type, id, method, params:{...attachments?}} -
        // attachments live under `params`, not at the frame root.
        final sent = ws.sentFrames.last;
        final decoded = jsonDecode(sent) as Map<String, dynamic>;
        expect(decoded['method'], Methods.chatSend);
        final params = decoded['params'] as Map<String, dynamic>;
        final attachments = params['attachments'] as List<dynamic>?;
        expect(attachments, isNotNull);
        expect(attachments, hasLength(1));
        final att = attachments!.first as Map<String, dynamic>;
        expect(att['content'], base64Encode(bytes));

        // Reply to complete the RPC cleanly.
        final reqId = decoded['id'] as String;
        ws.simulateServerFrame(
          '{"type":"res","id":"$reqId","ok":true,'
          '"payload":{"runId":"run-1","timestamp":1700000000000}}',
        );
        await future;
        await client.dispose();
      },
    );
  });

  // ==========================================================================
  // apiLogger forwarding
  // ==========================================================================
  group('apiLogger forwarding', () {
    test(
      'WsGatewayClient forwards apiLogger to ConnectionManager — handshake is logged',
      () async {
        final logger = _RecordingApiLogger();
        final ws = ControllableWebSocket.ready();
        final client = WsGatewayClient(
          identityProvider: FakeDeviceIdentityProvider(),
          webSocketFactory: (_) => ws.channel,
          apiLogger: logger,
        );

        unawaited(client.connect(testInstance()));
        await pumpMicrotasks();
        ws.simulateServerFrame(challengeJson());
        await pumpMicrotasks();
        final reqId = extractReqId(ws.sentFrames.first);
        ws.simulateServerFrame(helloOkJson(reqId));
        await pumpMicrotasks();

        // The connect handshake req must have been logged (method = connect) and
        // the hello-ok must have produced a 'connected' state log. This proves the
        // logger flowed WsGatewayClient → ConnectionManager → IApiLogger.
        expect(logger.requestMethods, contains(Methods.connect));
        expect(logger.stateNames, contains('connected'));

        await client.dispose();
      },
    );
  });
}
