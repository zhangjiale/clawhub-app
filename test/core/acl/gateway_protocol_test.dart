import 'dart:convert';

import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildAgentRequest', () {
    test('should include idempotencyKey in the request params', () {
      const id = 'req-001';
      const agentId = 'agent-1';
      const message = 'Hello, world!';
      const idempotencyKey = '550e8400-e29b-41d4-a716-446655440000';

      final json = buildAgentRequest(
        id: id,
        agentId: agentId,
        message: message,
        idempotencyKey: idempotencyKey,
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['type'], 'req');
      expect(decoded['id'], id);
      expect(decoded['method'], Methods.agent);

      final params = decoded['params'] as Map<String, dynamic>;
      expect(params['agentId'], agentId);
      expect(params['message'], message);
      expect(
        params['idempotencyKey'],
        idempotencyKey,
        reason:
            'idempotencyKey is required by the Gateway (§3.6) '
            'to prevent duplicate message execution on retry',
      );
    });

    test('should include optional sessionId when provided', () {
      const sessionId = 'session-abc';
      final json = buildAgentRequest(
        id: 'req-1',
        agentId: 'agent-1',
        message: 'test',
        idempotencyKey: 'key-1',
        sessionId: sessionId,
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final params = decoded['params'] as Map<String, dynamic>;
      expect(params['sessionId'], sessionId);
    });

    test('should not include sessionId when omitted', () {
      final json = buildAgentRequest(
        id: 'req-1',
        agentId: 'agent-1',
        message: 'test',
        idempotencyKey: 'key-1',
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final params = decoded['params'] as Map<String, dynamic>;
      expect(params.containsKey('sessionId'), isFalse);
    });

    test('should include overrides when provided', () {
      final overrides = {'model': 'gpt-5', 'temperature': 0.7};
      final json = buildAgentRequest(
        id: 'req-1',
        agentId: 'agent-1',
        message: 'test',
        idempotencyKey: 'key-1',
        overrides: overrides,
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final params = decoded['params'] as Map<String, dynamic>;
      expect(params['overrides'], overrides);
    });
  });
}
