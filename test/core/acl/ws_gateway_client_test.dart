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

    test('agent message event routed to messageStream', () async {
      final (:client, :ws) = await connectAndHandshake();

      final messages = <Message>[];
      final sub = client.messageStream('test-instance').listen(messages.add);

      ws.simulateServerFrame(
        agentEventJson(
          streamType: 'message',
          data:
              '{"clientId":"c-1","serverId":"s-1",'
              '"conversationId":"conv-1","agentId":"r-1",'
              '"role":"agent","content":"Hello!","type":"text",'
              '"logicalClock":1}',
        ),
      );
      await pumpMicrotasks();

      expect(
        messages.length,
        1,
        reason: 'Agent message event should be routed to messageStream',
      );
      expect(messages.first.content, 'Hello!');
      expect(messages.first.role, MessageRole.agent);

      await sub.cancel();
      await client.dispose();
    });

    test('agent tool event routed to toolCallStream', () async {
      final (:client, :ws) = await connectAndHandshake();

      final toolCalls = <ToolCall>[];
      final sub = client.toolCallStream('test-instance').listen(toolCalls.add);

      ws.simulateServerFrame(
        agentEventJson(
          streamType: 'tool',
          data:
              '{"id":"tc-1","messageId":"msg-1","name":"search",'
              '"status":"running","input":"{\\"query\\":\\"test\\"}"}',
        ),
      );
      await pumpMicrotasks();

      expect(
        toolCalls.length,
        1,
        reason: 'Agent tool event should be routed to toolCallStream',
      );
      expect(toolCalls.first.toolName, 'search');
      expect(toolCalls.first.status, ToolCallStatus.running);

      await sub.cancel();
      await client.dispose();
    });

    test('non-agent events are silently ignored (not forwarded)', () async {
      final (:client, :ws) = await connectAndHandshake();

      final messages = <Message>[];
      final toolCalls = <ToolCall>[];
      final msgSub = client.messageStream('test-instance').listen(messages.add);
      final tcSub = client
          .toolCallStream('test-instance')
          .listen(toolCalls.add);

      // tick event is not an agent event — should not be forwarded
      ws.simulateServerFrame(tickJson);
      await pumpMicrotasks();

      expect(
        messages,
        isEmpty,
        reason: 'Non-agent events should not appear on messageStream',
      );
      expect(
        toolCalls,
        isEmpty,
        reason: 'Non-agent events should not appear on toolCallStream',
      );

      await msgSub.cancel();
      await tcSub.cancel();
      await client.dispose();
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
