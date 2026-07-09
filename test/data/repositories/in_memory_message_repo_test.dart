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

  group('InMemoryMessageRepo.updateContentTypeAndMetadata', () {
    late InMemoryMessageRepo repo;

    setUp(() {
      repo = InMemoryMessageRepo();
    });

    test('updates content/type/metadata by serverId', () async {
      await repo.insert(
        Message(
          clientId: 'm1',
          serverId: 'srv-1',
          conversationId: 'conv-1',
          agentId: 'a1',
          role: MessageRole.agent,
          content: null,
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 0,
          timestamp: 0,
        ),
      );

      final updated = await repo.updateContentTypeAndMetadata(
        'srv-1',
        content: 'caption',
        type: MessageType.image,
        metadata: const {'imageUrl': '/img.png'},
      );

      expect(updated, isNotNull);
      expect(updated!.type, MessageType.image);
      expect(updated.content, 'caption');
      expect(updated.metadata?['imageUrl'], '/img.png');

      final stored = await repo.getByServerId('srv-1');
      expect(stored!.type, MessageType.image);
    });

    test('returns null for unknown serverId', () async {
      final updated = await repo.updateContentTypeAndMetadata(
        'missing',
        content: 'x',
        type: MessageType.text,
        metadata: null,
      );
      expect(updated, isNull);
    });
  });

  group('InMemoryMessageRepo.bindServerIdAndUpdateContent', () {
    late InMemoryMessageRepo repo;

    setUp(() {
      repo = InMemoryMessageRepo();
    });

    test(
      'binds serverId and updates content/type/metadata by clientId',
      () async {
        await repo.insert(
          Message(
            clientId: 'm2',
            serverId: null,
            conversationId: 'conv-1',
            agentId: 'a1',
            role: MessageRole.agent,
            content: 'placeholder',
            type: MessageType.text,
            status: MessageStatus.delivered,
            logicalClock: 0,
            timestamp: 0,
          ),
        );

        final updated = await repo.bindServerIdAndUpdateContent(
          'm2',
          serverId: 'srv-real',
          content: 'caption',
          type: MessageType.image,
          metadata: const {'imageUrl': '/img.png'},
        );

        expect(updated, isNotNull);
        expect(updated!.serverId, 'srv-real');
        expect(updated.type, MessageType.image);
        expect(updated.content, 'caption');

        final byServer = await repo.getByServerId('srv-real');
        expect(byServer, isNotNull);
        final byClient = await repo.getByClientId('m2');
        expect(byClient?.serverId, 'srv-real');
      },
    );

    test('returns null for unknown clientId', () async {
      final updated = await repo.bindServerIdAndUpdateContent(
        'missing',
        serverId: 'srv-real',
        content: 'x',
        type: MessageType.text,
        metadata: null,
      );
      expect(updated, isNull);
    });
  });
}
