import 'dart:convert';

import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildChatSendRequest', () {
    test('should include idempotencyKey in the request params', () {
      const id = 'req-001';
      const sessionKey = 'agent:main:main';
      const message = 'Hello, world!';
      const idempotencyKey = '550e8400-e29b-41d4-a716-446655440000';

      final json = buildChatSendRequest(
        id: id,
        sessionKey: sessionKey,
        message: message,
        idempotencyKey: idempotencyKey,
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['type'], 'req');
      expect(decoded['id'], id);
      expect(decoded['method'], Methods.chatSend);

      final params = decoded['params'] as Map<String, dynamic>;
      expect(params['sessionKey'], sessionKey);
      expect(params['message'], message);
      expect(
        params['idempotencyKey'],
        idempotencyKey,
        reason:
            'idempotencyKey is required by the Gateway (§3.6) '
            'to prevent duplicate message execution on retry',
      );
    });

    test('should include overrides when provided', () {
      final overrides = {'model': 'gpt-5', 'temperature': 0.7};
      final json = buildChatSendRequest(
        id: 'req-1',
        sessionKey: 'agent:main:main',
        message: 'test',
        idempotencyKey: 'key-1',
        overrides: overrides,
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final params = decoded['params'] as Map<String, dynamic>;
      expect(params['overrides'], overrides);
    });
  });

  group('parseChatEvent', () {
    test('should parse delta state', () {
      final payload = {
        'runId': 'run-1',
        'sessionKey': 'agent:main:main',
        'state': 'delta',
        'deltaText': 'Hello',
        'seq': 6,
      };
      final event = parseChatEvent(payload);
      expect(event.runId, 'run-1');
      expect(event.sessionKey, 'agent:main:main');
      expect(event.state, ChatState.delta);
      expect(event.deltaText, 'Hello');
      expect(event.seq, 6);
      expect(event.message, isNull);
    });

    test('should parse final state with message', () {
      final msgJson = {
        'agentId': 'r-1',
        'sessionKey': 'agent:r-1:main',
        'content': 'Hello World',
        'role': 'agent',
      };
      final payload = {
        'sessionKey': 'agent:main:main',
        'state': 'final',
        'message': msgJson,
      };
      final event = parseChatEvent(payload);
      expect(event.state, ChatState.final_);
      expect(event.deltaText, isNull);
      expect(event.message, isNotNull);
      expect(event.message!['content'], 'Hello World');
    });

    test('should default to unknown state for unrecognized', () {
      final event = parseChatEvent({'state': 'bogus'});
      expect(event.state, ChatState.unknown);
    });
  });

  group('parseAgentEvent', () {
    test('should parse tool stream', () {
      final payload = {
        'runId': 'run-1',
        'sessionKey': 'agent:main:main',
        'stream': 'tool',
        'data': {'phase': 'start', 'name': 'search', 'toolCallId': 'tc-1'},
      };
      final event = parseAgentEvent(payload);
      expect(event.stream, AgentStreamType.tool);
      expect(event.data['name'], 'search');
    });

    test('should parse assistant stream', () {
      final payload = {
        'sessionKey': 'agent:main:main',
        'stream': 'assistant',
        'data': {'text': 'Hello', 'delta': 'Hel'},
      };
      final event = parseAgentEvent(payload);
      expect(event.stream, AgentStreamType.assistant);
      expect(event.data['delta'], 'Hel');
    });

    test('should parse lifecycle stream', () {
      final payload = {
        'stream': 'lifecycle',
        'data': {'phase': 'end', 'stopReason': 'stop'},
      };
      final event = parseAgentEvent(payload);
      expect(event.stream, AgentStreamType.lifecycle);
    });

    test('should parse item stream', () {
      final payload = {
        'stream': 'item',
        'data': {'itemId': 'tool:call_00', 'phase': 'start'},
      };
      final event = parseAgentEvent(payload);
      expect(event.stream, AgentStreamType.item);
    });
  });

  group('StreamingBuffer', () {
    test('should be empty on creation', () {
      final buffer = StreamingBuffer(sessionKey: 'agent:main:main');
      expect(buffer.isEmpty, isTrue);
      expect(buffer.text, isEmpty);
    });

    test('should accumulate delta text', () {
      final buffer = StreamingBuffer(sessionKey: 'agent:main:main');
      buffer.append('Hello');
      expect(buffer.text, 'Hello');
      expect(buffer.isEmpty, isFalse);

      buffer.append(' World');
      expect(buffer.text, 'Hello World');
    });

    test('should reset to empty state', () {
      final buffer = StreamingBuffer(sessionKey: 'agent:main:main');
      buffer.append('some text');
      buffer.reset();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.text, isEmpty);
    });
  });

  // ============================================================================
  // Bug #1: deviceFamily alignment between signature payload and connect wire
  // spec §2.5 requires 11 pipe-separated segments, ending with deviceFamily.
  // Signature path always includes `|phone|` (default); wire path used to skip
  // the field when config.deviceFamily was null, causing the server-side
  // signature reconstruction to mismatch and reject with
  // DEVICE_AUTH_SIGNATURE_INVALID.
  // ============================================================================
  group('buildConnectParams deviceFamily alignment', () {
    test('wire client.deviceFamily mirrors explicit config.deviceFamily', () {
      final params = buildConnectParams(
        token: 't',
        deviceId: 'd',
        config: ConnectionConfig(deviceFamily: 'phone'),
      );
      final client = params['client'] as Map<String, dynamic>;
      expect(
        client['deviceFamily'],
        'phone',
        reason: 'wire field must mirror the configured deviceFamily',
      );
    });

    test(
      'wire client.deviceFamily is always present (defaults to phone) — Bug #1',
      () {
        final params = buildConnectParams(
          token: 't',
          deviceId: 'd',
          config: ConnectionConfig(),
        );
        final client = params['client'] as Map<String, dynamic>;
        expect(
          client.containsKey('deviceFamily'),
          isTrue,
          reason:
              'wire must always include deviceFamily so the server-side '
              'signature payload reconstruction matches the client payload',
        );
        expect(
          client['deviceFamily'],
          'phone',
          reason: 'default deviceFamily must align with signing path default',
        );
      },
    );

    test('buildV3SignaturePayload includes default deviceFamily segment', () {
      // Wire default must equal the signed-payload default. If the wire
      // omits the field but the signature includes it, the server
      // reconstructs a different payload and rejects the signature.
      final payload = buildV3SignaturePayload(
        deviceId: 'd',
        clientId: 'openclaw-ios',
        clientMode: 'ui',
        role: 'operator',
        scopes: const ['operator.read'],
        signedAtMs: 1700000000000,
        token: 't',
        nonce: 'n',
        platform: 'ios',
        deviceFamily: 'phone',
      );
      // Format: "v3|...|{platform}|{deviceFamily}" — 11 segments,
      // last one is 'phone' (the default).
      final segments = payload.split('|');
      expect(
        segments.length,
        11,
        reason: 'spec §2.5 mandates 11 pipe-separated segments',
      );
      expect(
        segments.last,
        'phone',
        reason: 'last segment is deviceFamily; must be present',
      );
    });
  });

  // ============================================================================
  // Bug #3: ConnectionConfig default platform must be a valid OpenClaw spec
  // platform (§2.3). The previous default `'flutter'` is a Flutter framework
  // name, not a platform name. Production is unaffected (DI overrides with
  // platformOS()), but mock/test paths benefit from a legal value so future
  // server-side enum validation cannot reject the default.
  // ============================================================================
  group('ConnectionConfig defaults', () {
    test('default platform is a valid OpenClaw spec §2.3 value — Bug #3', () {
      // Spec §2.3 client.id enum + platformOS() values (DI production path).
      // 'flutter' is intentionally NOT in this set — it's a framework name,
      // not a platform.
      const spec = {
        // spec §2.3 client.id values
        'webchat-ui',
        'openclaw-control-ui',
        'openclaw-tui',
        'webchat',
        'cli',
        'gateway-client',
        'openclaw-macos',
        'openclaw-ios',
        'openclaw-android',
        'node-host',
        'test',
        'fingerprint',
        'openclaw-probe',
        // platformOS() values used by lib/app/di/providers.dart
        'ios',
        'android',
        'macos',
        'linux',
        'windows',
        'web',
      };
      expect(
        ConnectionConfig().platform,
        isIn(spec),
        reason:
            'default platform must be a valid OpenClaw spec value, '
            'not a framework name like "flutter"',
      );
    });

    test('ClientIds.forPlatform accepts the default platform', () {
      final defaultPlatform = ConnectionConfig().platform;
      expect(
        () => ClientIds.forPlatform(defaultPlatform),
        returnsNormally,
        reason:
            'ClientIds.forPlatform must handle any default platform value '
            'via its switch default case',
      );
    });
  });
}
