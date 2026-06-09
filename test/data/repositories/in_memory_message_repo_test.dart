import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message_status.dart';

Message _msg(String clientId, String agentId) => Message(
      clientId: clientId,
      conversationId: 'conv-1',
      agentId: agentId,
      role: MessageRole.user,
      content: 'hello',
      type: MessageType.text,
      status: MessageStatus.delivered,
      logicalClock: 0,
      timestamp: 0,
    );

void main() {
  group('InMemoryMessageRepo.getMessageCountsByAgent', () {
    late InMemoryMessageRepo repo;

    setUp(() {
      repo = InMemoryMessageRepo();
    });

    test('empty agentIds returns empty map', () async {
      final counts = await repo.getMessageCountsByAgent([]);
      expect(counts, isEmpty);
    });

    test('agents with no messages return zero counts', () async {
      final counts = await repo.getMessageCountsByAgent(['a1', 'a2']);
      expect(counts, {'a1': 0, 'a2': 0});
    });

    test('unknown agentIds are included with zero', () async {
      await repo.insert(_msg('m1', 'a1'));
      final counts = await repo.getMessageCountsByAgent(['a1', 'unknown']);
      expect(counts, {'a1': 1, 'unknown': 0});
    });

    test('counts messages correctly across multiple agents', () async {
      await repo.insert(_msg('m1', 'a1'));
      await repo.insert(_msg('m2', 'a1'));
      await repo.insert(_msg('m3', 'a1'));
      await repo.insert(_msg('m4', 'a2'));
      await repo.insert(_msg('m5', 'a3'));
      await repo.insert(_msg('m6', 'a3'));

      final counts = await repo.getMessageCountsByAgent(['a1', 'a2', 'a3']);
      expect(counts, {'a1': 3, 'a2': 1, 'a3': 2});
    });

    test('ignores messages from agents not in the list', () async {
      await repo.insert(_msg('m1', 'a1'));
      await repo.insert(_msg('m2', 'a2'));
      await repo.insert(_msg('m3', 'a3'));

      final counts = await repo.getMessageCountsByAgent(['a1']);
      expect(counts, {'a1': 1});
      expect(counts.containsKey('a2'), isFalse);
    });
  });
}
