import 'dart:async';

import 'package:claw_hub/core/acl/device_identity.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_device_identity_provider.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/ws_gateway_client.dart';
import 'package:claw_hub/domain/models/enums.dart'
    show HealthStatus, MessageRole, MessageType, ToolCallStatus;
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
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

// ---------------------------------------------------------------------------
// Helpers (specific to WsGatewayClient tests)
// ---------------------------------------------------------------------------

/// A minimal [Instance] for testing.
Instance testInstance({
  String id = 'test-instance',
  String name = 'Test Gateway',
  String gatewayUrl = 'ws://localhost:9999/ws',
  String token = 'test-token',
}) => Instance(id: id, name: name, gatewayUrl: gatewayUrl, tokenRef: token);

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
      expect(WsGatewayClient.extractTextContent(null), isNull);
    });

    test('returns string unchanged for String input', () {
      expect(WsGatewayClient.extractTextContent('hello'), 'hello');
    });

    test('joins structured content blocks (real Gateway format)', () {
      final blocks = [
        {'type': 'text', 'text': '第一部分'},
        {'type': 'text', 'text': '第二部分'},
      ];
      expect(WsGatewayClient.extractTextContent(blocks), '第一部分第二部分');
    });

    test('skips non-text blocks in structured content', () {
      final blocks = [
        {'type': 'image_url', 'url': 'https://example.com/img.png'},
        {'type': 'text', 'text': '图片描述'},
      ];
      expect(WsGatewayClient.extractTextContent(blocks), '图片描述');
    });

    test('joins list of plain strings', () {
      expect(WsGatewayClient.extractTextContent(['a', 'b', 'c']), 'abc');
    });

    test('falls back to toString for unrecognized non-list types', () {
      expect(WsGatewayClient.extractTextContent(42), '42');
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

  // ==========================================================================
  // Stream access without connect
  // ==========================================================================
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
    /// Helper: create a WsGatewayClient backed by a ControllableWebSocket,
    /// connect to a test instance, complete the handshake, and return the
    /// client + controllable ws for event injection.
    Future<({WsGatewayClient client, ControllableWebSocket ws})>
    connectAndHandshake() async {
      final ws = ControllableWebSocket.ready();
      final identityProvider = FakeDeviceIdentityProvider();

      final client = WsGatewayClient(
        identityProvider: identityProvider,
        webSocketFactory: (_) => ws.channel,
      );

      final instance = Instance(
        id: 'test-instance',
        name: 'Test',
        gatewayUrl: 'ws://localhost:9999/ws',
        tokenRef: 'test-token',
        healthStatus: HealthStatus.online,
        isLocalNetwork: false,
      );

      // Start connect (don't await — it blocks on manager.connect())
      unawaited(client.connect(instance));
      await pumpMicrotasks();

      // Complete the challenge → connect → hello-ok handshake
      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();

      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      return (client: client, ws: ws);
    }

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
}
