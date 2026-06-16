import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/local/mapping/quick_command_codec.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

void main() {
  group('QuickCommandCodec', () {
    test('serialize then deserialize is idempotent', () {
      final commands = [
        QuickCommand(
          id: 'b',
          agentId: 'agent-1',
          label: '记忆',
          payload: '/memory',
          sortOrder: 1,
        ),
        QuickCommand(
          id: 'a',
          agentId: 'agent-1',
          label: '状态',
          payload: '/status',
          sortOrder: 0,
        ),
      ];

      final encoded = QuickCommandCodec.serialize(commands);
      final decoded = QuickCommandCodec.deserialize(encoded);

      expect(decoded.map((c) => c.id), ['a', 'b']);
      expect(decoded.map((c) => c.sortOrder), [0, 1]);
      expect(decoded[0].label, '状态');
      expect(decoded[1].payload, '/memory');
    });

    test('empty list round-trips', () {
      final encoded = QuickCommandCodec.serialize([]);
      expect(QuickCommandCodec.deserialize(encoded), isEmpty);
      expect(QuickCommandCodec.deserialize(null), isEmpty);
      expect(QuickCommandCodec.deserialize(''), isEmpty);
    });

    test('payload with special characters round-trips unchanged', () {
      final commands = [
        QuickCommand(
          id: 'cmd-1',
          agentId: 'agent-1',
          label: '复杂',
          payload: '/ask "hello" && echo \${世界}\nnext',
          sortOrder: 0,
        ),
      ];

      final decoded = QuickCommandCodec.deserialize(
        QuickCommandCodec.serialize(commands),
      );
      expect(decoded.single.payload, commands.single.payload);
    });

    test('serialize normalizes sortOrder by sorted command order', () {
      final commands = [
        QuickCommand(
          id: 'later',
          agentId: 'agent-1',
          label: '后',
          payload: '/later',
          sortOrder: 99,
        ),
        QuickCommand(
          id: 'first',
          agentId: 'agent-1',
          label: '先',
          payload: '/first',
          sortOrder: -1,
        ),
      ];

      final decoded = QuickCommandCodec.deserialize(
        QuickCommandCodec.serialize(commands),
      );
      expect(decoded.map((c) => c.id), ['first', 'later']);
      expect(decoded.map((c) => c.sortOrder), [0, 1]);
    });

    test('deserialize throws FormatException for malformed JSON', () {
      expect(
        () => QuickCommandCodec.deserialize('not valid json{'),
        throwsFormatException,
      );
    });

    test('deserialize throws FormatException for non-list JSON', () {
      expect(
        () => QuickCommandCodec.deserialize('"a string"'),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
