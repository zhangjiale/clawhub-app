import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/errors.dart';

void main() {
  group('AgentNotFoundError', () {
    test('stores agentId', () {
      const error = AgentNotFoundError('test-id');
      expect(error.agentId, 'test-id');
    });

    test('toString includes agentId', () {
      const error = AgentNotFoundError('abc-123');
      expect(error.toString(), contains('abc-123'));
    });

    test('is Exception', () {
      const error = AgentNotFoundError('id');
      expect(error, isA<Exception>());
    });
  });
}
