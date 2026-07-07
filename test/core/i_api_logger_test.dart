import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/i_api_logger.dart';

void main() {
  group('ApiLogEntry', () {
    test('constructs with required fields; nullables default to null', () {
      final entry = ApiLogEntry(
        id: 'e1',
        timestampMs: 1000,
        instanceId: 'inst-1',
        direction: ApiLogDirection.outgoing,
        kind: ApiLogKind.req,
        methodOrEvent: 'chat.send',
        requestId: 'r1',
        byteSize: 42,
      );
      expect(entry.id, 'e1');
      expect(entry.direction, ApiLogDirection.outgoing);
      expect(entry.kind, ApiLogKind.req);
      expect(entry.byteSize, 42);
      expect(entry.ok, isNull);
      expect(entry.durationMs, isNull);
      expect(entry.payloadPreview, isNull);
      expect(entry.state, isNull);
      expect(entry.message, isNull);
    });

    test('state entry has null direction and payload', () {
      final entry = ApiLogEntry(
        id: 'e2',
        timestampMs: 2000,
        instanceId: 'inst-1',
        kind: ApiLogKind.state,
        state: 'authFailed',
        message: 'Auth failed: bad token',
      );
      expect(entry.direction, isNull);
      expect(entry.kind, ApiLogKind.state);
      expect(entry.state, 'authFailed');
      expect(entry.payloadPreview, isNull);
    });
  });
}
