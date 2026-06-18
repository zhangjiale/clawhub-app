import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';

/// Tests for InMemoryMessageRepo outbox filtering by instanceId.
///
/// Before the fix, getOutboxByInstance / getOutboxCountByInstance were stubs
/// returning empty/zero regardless of stored messages.  After the fix, they
/// use an optional InMemoryConversationRepo to filter correctly.
void main() {
  group('InMemoryMessageRepo outbox by instance', () {
    late InMemoryConversationRepo conversationRepo;
    late InMemoryMessageRepo messageRepo;

    setUp(() {
      conversationRepo = InMemoryConversationRepo();
      messageRepo = InMemoryMessageRepo(conversationRepo: conversationRepo);
    });

    Message _msg({
      required String clientId,
      required String conversationId,
      String agentId = 'agent-1',
      MessageStatus status = MessageStatus.pending,
      int logicalClock = 0,
    }) {
      return Message(
        clientId: clientId,
        conversationId: conversationId,
        agentId: agentId,
        role: MessageRole.user,
        content: 'test $clientId',
        type: MessageType.text,
        status: status,
        logicalClock: logicalClock,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }

    test(
      'without conversation repo, returns empty (backward compat)',
      () async {
        final noConvRepo = InMemoryMessageRepo();

        await noConvRepo.insert(_msg(clientId: 'm1', conversationId: 'conv-a'));

        final result = await noConvRepo.getOutboxByInstance('inst-1');
        expect(result, isEmpty);

        final count = await noConvRepo.getOutboxCountByInstance('inst-1');
        expect(count, 0);
      },
    );

    test('returns empty when no conversations match instanceId', () async {
      // No conversations created for 'inst-1'
      await messageRepo.insert(_msg(clientId: 'm1', conversationId: 'conv-a'));

      final result = await messageRepo.getOutboxByInstance('inst-1');
      expect(result, isEmpty);
    });

    test('returns only messages belonging to the specified instance', () async {
      // Create conversations for two different instances
      final convA1 = await conversationRepo.getOrCreate('inst-a', 'agent-1');
      final convA2 = await conversationRepo.getOrCreate('inst-a', 'agent-2');
      final convB = await conversationRepo.getOrCreate('inst-b', 'agent-1');

      // Insert PENDING messages across instances
      final ma1 = _msg(
        clientId: 'ma1',
        conversationId: convA1.id,
        logicalClock: 1,
      );
      final ma2 = _msg(
        clientId: 'ma2',
        conversationId: convA1.id,
        logicalClock: 2,
      );
      final ma3 = _msg(
        clientId: 'ma3',
        conversationId: convA2.id,
        logicalClock: 3,
      );
      final mb1 = _msg(
        clientId: 'mb1',
        conversationId: convB.id,
        logicalClock: 4,
      );

      await messageRepo.insert(ma1);
      await messageRepo.insert(ma2);
      await messageRepo.insert(ma3);
      await messageRepo.insert(mb1);

      // Instance A: should see 3 messages
      final resultA = await messageRepo.getOutboxByInstance('inst-a');
      expect(
        resultA.map((m) => m.clientId),
        containsAll(['ma1', 'ma2', 'ma3']),
      );
      expect(resultA, hasLength(3));
      // Must be sorted by logicalClock ASC
      expect(resultA[0].logicalClock, lessThan(resultA[1].logicalClock));
      expect(resultA[1].logicalClock, lessThan(resultA[2].logicalClock));

      // Instance B: should see 1 message
      final resultB = await messageRepo.getOutboxByInstance('inst-b');
      expect(resultB.map((m) => m.clientId), ['mb1']);
      expect(resultB, hasLength(1));
    });

    test(
      'getOutboxByInstance filters out non-PENDING/FAILED messages',
      () async {
        final convA = await conversationRepo.getOrCreate('inst-a', 'agent-1');

        final pending = _msg(
          clientId: 'm-p',
          conversationId: convA.id,
          status: MessageStatus.pending,
          logicalClock: 1,
        );
        final failed = _msg(
          clientId: 'm-f',
          conversationId: convA.id,
          status: MessageStatus.failed,
          logicalClock: 2,
        );
        final sent = _msg(
          clientId: 'm-s',
          conversationId: convA.id,
          status: MessageStatus.sent,
          logicalClock: 3,
        );
        final sending = _msg(
          clientId: 'm-ing',
          conversationId: convA.id,
          status: MessageStatus.sending,
          logicalClock: 4,
        );

        await messageRepo.insert(pending);
        await messageRepo.insert(failed);
        await messageRepo.insert(sent);
        await messageRepo.insert(sending);

        final result = await messageRepo.getOutboxByInstance('inst-a');
        // Only PENDING and FAILED
        expect(result.map((m) => m.clientId), containsAll(['m-p', 'm-f']));
        expect(result, hasLength(2));
      },
    );

    test('getOutboxCountByInstance returns correct count', () async {
      final convA = await conversationRepo.getOrCreate('inst-a', 'agent-1');

      await messageRepo.insert(
        _msg(clientId: 'm1', conversationId: convA.id, logicalClock: 1),
      );
      await messageRepo.insert(
        _msg(
          clientId: 'm2',
          conversationId: convA.id,
          status: MessageStatus.failed,
          logicalClock: 2,
        ),
      );

      final count = await messageRepo.getOutboxCountByInstance('inst-a');
      expect(count, 2);
    });

    test(
      'getOutboxCountByInstance returns 0 for instances without outbox',
      () async {
        final convA = await conversationRepo.getOrCreate('inst-a', 'agent-1');

        // Only SENT messages — nothing countable
        await messageRepo.insert(
          _msg(
            clientId: 'm1',
            conversationId: convA.id,
            status: MessageStatus.sent,
            logicalClock: 1,
          ),
        );

        final count = await messageRepo.getOutboxCountByInstance('inst-a');
        expect(count, 0);
      },
    );
  });

  group('InMemoryMessageRepo.resetStaleSending (crash recovery)', () {
    late InMemoryConversationRepo conversationRepo;
    late InMemoryMessageRepo messageRepo;

    setUp(() {
      conversationRepo = InMemoryConversationRepo();
      messageRepo = InMemoryMessageRepo(conversationRepo: conversationRepo);
    });

    /// Constructs a SENDING message, optionally already ACK'd (serverId set).
    Message sendingMsg({
      required String clientId,
      required String conversationId,
      String? serverId,
    }) {
      return Message(
        clientId: clientId,
        serverId: serverId,
        conversationId: conversationId,
        agentId: 'agent-1',
        role: MessageRole.user,
        content: 'test $clientId',
        type: MessageType.text,
        status: MessageStatus.sending,
        logicalClock: 0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }

    test('resets SENDING without serverId back to PENDING', () async {
      final convA = await conversationRepo.getOrCreate('inst-a', 'agent-1');
      // SENDING, no serverId yet — app killed mid-send before ACK.
      await messageRepo.insert(
        sendingMsg(clientId: 'm1', conversationId: convA.id),
      );

      final count = await messageRepo.resetStaleSending('inst-a');

      expect(count, 1);
      final after = await messageRepo.getByClientId('m1');
      expect(after!.status, MessageStatus.pending);
    });

    test('does NOT reset SENDING messages that already have a serverId '
        '(prevents server-side duplicate on re-send)', () async {
      final convA = await conversationRepo.getOrCreate('inst-a', 'agent-1');
      // SENDING but already ACK'd by Gateway (bindServerId ran, status
      // machine didn't advance to SENT before app kill). Resetting this to
      // PENDING would cause the next flush to re-send an acknowledged
      // message → server-side duplicate. Must be skipped.
      await messageRepo.insert(
        sendingMsg(
          clientId: 'm-ack',
          conversationId: convA.id,
          serverId: 'srv-1',
        ),
      );

      final count = await messageRepo.resetStaleSending('inst-a');

      expect(count, 0);
      final after = await messageRepo.getByClientId('m-ack');
      expect(
        after!.status,
        MessageStatus.sending,
        reason: 'ACK\'d SENDING message must not be reset to PENDING',
      );
      expect(after.serverId, 'srv-1');
    });

    test(
      'resets only the target instance (cross-instance isolation)',
      () async {
        final convA = await conversationRepo.getOrCreate('inst-a', 'agent-1');
        final convB = await conversationRepo.getOrCreate('inst-b', 'agent-1');

        await messageRepo.insert(
          sendingMsg(clientId: 'a1', conversationId: convA.id),
        );
        await messageRepo.insert(
          sendingMsg(clientId: 'b1', conversationId: convB.id),
        );

        // Flush instance A only.
        final count = await messageRepo.resetStaleSending('inst-a');

        expect(count, 1);
        expect(
          (await messageRepo.getByClientId('a1'))!.status,
          MessageStatus.pending,
        );
        // Instance B's in-flight SENDING must be untouched.
        expect(
          (await messageRepo.getByClientId('b1'))!.status,
          MessageStatus.sending,
        );
      },
    );
  });
}
