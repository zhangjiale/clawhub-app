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
}
