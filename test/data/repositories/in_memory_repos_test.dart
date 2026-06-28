import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
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

    Message msg({
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

        await noConvRepo.insert(msg(clientId: 'm1', conversationId: 'conv-a'));

        final result = await noConvRepo.getOutboxByInstance('inst-1');
        expect(result, isEmpty);

        final count = await noConvRepo.getOutboxCountByInstance('inst-1');
        expect(count, 0);
      },
    );

    test('returns empty when no conversations match instanceId', () async {
      // No conversations created for 'inst-1'
      await messageRepo.insert(msg(clientId: 'm1', conversationId: 'conv-a'));

      final result = await messageRepo.getOutboxByInstance('inst-1');
      expect(result, isEmpty);
    });

    test('returns only messages belonging to the specified instance', () async {
      // Create conversations for two different instances
      final convA1 = await conversationRepo.getOrCreate('inst-a', 'agent-1');
      final convA2 = await conversationRepo.getOrCreate('inst-a', 'agent-2');
      final convB = await conversationRepo.getOrCreate('inst-b', 'agent-1');

      // Insert PENDING messages across instances
      final ma1 = msg(
        clientId: 'ma1',
        conversationId: convA1.id,
        logicalClock: 1,
      );
      final ma2 = msg(
        clientId: 'ma2',
        conversationId: convA1.id,
        logicalClock: 2,
      );
      final ma3 = msg(
        clientId: 'ma3',
        conversationId: convA2.id,
        logicalClock: 3,
      );
      final mb1 = msg(
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

        final pending = msg(
          clientId: 'm-p',
          conversationId: convA.id,
          status: MessageStatus.pending,
          logicalClock: 1,
        );
        final failed = msg(
          clientId: 'm-f',
          conversationId: convA.id,
          status: MessageStatus.failed,
          logicalClock: 2,
        );
        final sent = msg(
          clientId: 'm-s',
          conversationId: convA.id,
          status: MessageStatus.sent,
          logicalClock: 3,
        );
        final sending = msg(
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
        msg(clientId: 'm1', conversationId: convA.id, logicalClock: 1),
      );
      await messageRepo.insert(
        msg(
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
          msg(
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

  group('InMemoryMessageRepo.getAnchorWindow (bounded)', () {
    late InMemoryMessageRepo messageRepo;

    /// Inserts N messages into one conversation with logicalClock 1..N and
    /// clientId 'm{i}'. Returns the shared conversationId.
    Future<String> seedConversation(int count) async {
      final conv = 'conv-anchor';
      for (var i = 1; i <= count; i++) {
        await messageRepo.insert(
          Message(
            clientId: 'm$i',
            conversationId: conv,
            agentId: 'agent-1',
            role: MessageRole.user,
            content: 'msg $i',
            type: MessageType.text,
            status: MessageStatus.sent,
            logicalClock: i,
            timestamp: i,
          ),
        );
      }
      return conv;
    }

    setUp(() {
      messageRepo = InMemoryMessageRepo();
    });

    test('returns before + target + after, chronologically ordered', () async {
      final conv = await seedConversation(20);
      // Target = m10. before=3 -> m7,m8,m9 ; after=4 -> m11,m12,m13,m14.
      final window = await messageRepo.getAnchorWindow(
        conv,
        targetClientId: 'm10',
        before: 3,
        after: 4,
      );

      expect(window.map((m) => m.clientId).toList(), [
        'm7',
        'm8',
        'm9',
        'm10',
        'm11',
        'm12',
        'm13',
        'm14',
      ]);
    });

    test('never exceeds before + 1 + after rows', () async {
      final conv = await seedConversation(1000);
      final window = await messageRepo.getAnchorWindow(
        conv,
        targetClientId: 'm500',
        before: 5,
        after: 10,
      );
      // Bounded: at most 5 + 1 + 10 = 16, regardless of conversation size.
      expect(window.length, lessThanOrEqualTo(5 + 1 + 10));
      expect(window.length, 16);
    });

    test('clamps before at the head of the conversation', () async {
      final conv = await seedConversation(20);
      // Target near the start — fewer than `before` older messages exist.
      final window = await messageRepo.getAnchorWindow(
        conv,
        targetClientId: 'm2',
        before: 5,
        after: 3,
      );
      expect(window.map((m) => m.clientId).toList(), [
        'm1',
        'm2',
        'm3',
        'm4',
        'm5',
      ]);
    });

    test('clamps after at the tail of the conversation', () async {
      final conv = await seedConversation(20);
      // Target near the end — fewer than `after` newer messages exist.
      final window = await messageRepo.getAnchorWindow(
        conv,
        targetClientId: 'm19',
        before: 3,
        after: 5,
      );
      expect(window.map((m) => m.clientId).toList(), [
        'm16',
        'm17',
        'm18',
        'm19',
        'm20',
      ]);
    });

    test('returns empty when target does not exist', () async {
      final conv = await seedConversation(10);
      final window = await messageRepo.getAnchorWindow(
        conv,
        targetClientId: 'nonexistent',
        before: 5,
        after: 5,
      );
      expect(window, isEmpty);
    });

    // Bug 5: Messages with same logicalClock as target must be included.
    test('includes messages with same logicalClock as target', () async {
      final conv = 'conv-tied-clock';
      // Insert messages with logicalClock ties around target m3.
      await messageRepo.insert(_msg('m1', conv, clock: 5));
      await messageRepo.insert(_msg('m2', conv, clock: 5)); // tied with m3
      await messageRepo.insert(_msg('m3', conv, clock: 5)); // target
      await messageRepo.insert(_msg('m4', conv, clock: 6));
      await messageRepo.insert(_msg('m5', conv, clock: 7));

      final window = await messageRepo.getAnchorWindow(
        conv,
        targetClientId: 'm3',
        before: 5,
        after: 5,
      );

      final ids = window.map((m) => m.clientId).toList();

      // Target must appear exactly once in the middle
      expect(
        ids.where((id) => id == 'm3').length,
        1,
        reason: 'Target must appear exactly once',
      );
      // Tied-clock m1,m2 must appear before target
      final targetIdx = ids.indexOf('m3');
      expect(
        ids.sublist(0, targetIdx).toSet(),
        {'m1', 'm2'},
        reason: 'Same-clock messages must appear before target',
      );
      // Strictly newer m4,m5 must appear after target
      expect(ids.sublist(targetIdx + 1), ['m4', 'm5']);
      // All 5 messages present
      expect(ids.toSet(), {'m1', 'm2', 'm3', 'm4', 'm5'});
    });

    // Bug 5: Target itself must not appear twice.
    test('target appears exactly once even with tied clocks', () async {
      final conv = 'conv-no-dup-target';
      await messageRepo.insert(_msg('t1', conv, clock: 10));
      await messageRepo.insert(_msg('t2', conv, clock: 10)); // target
      await messageRepo.insert(_msg('t3', conv, clock: 10));

      final window = await messageRepo.getAnchorWindow(
        conv,
        targetClientId: 't2',
        before: 5,
        after: 5,
      );

      final ids = window.map((m) => m.clientId).toList();
      expect(
        ids.where((id) => id == 't2').length,
        1,
        reason: 'Target must appear exactly once',
      );
      expect(ids, contains('t1'));
      expect(ids, contains('t3'));
    });

    // Bug 6: Target from different conversation → empty result.
    test(
      'returns empty when target clientId belongs to other conversation',
      () async {
        final convA = 'conv-a';
        final convB = 'conv-b';
        await messageRepo.insert(_msg('m1', convA, clock: 1));
        await messageRepo.insert(_msg('m2', convB, clock: 1));

        final window = await messageRepo.getAnchorWindow(
          convA,
          targetClientId: 'm2', // m2 belongs to convB, not convA
          before: 5,
          after: 5,
        );
        expect(window, isEmpty);
      },
    );

    // Bug 6: Normal case with correct conversation still works.
    test(
      'returns correct window when target is in correct conversation',
      () async {
        final convA = 'conv-a';
        final convB = 'conv-b';
        await messageRepo.insert(_msg('a1', convA, clock: 1));
        await messageRepo.insert(_msg('a2', convA, clock: 2)); // target
        await messageRepo.insert(_msg('a3', convA, clock: 3));
        await messageRepo.insert(_msg('b1', convB, clock: 1));

        final window = await messageRepo.getAnchorWindow(
          convA,
          targetClientId: 'a2',
          before: 5,
          after: 5,
        );
        expect(window.map((m) => m.clientId).toList(), ['a1', 'a2', 'a3']);
      },
    );
  });
}

Message _msg(String clientId, String conversationId, {int clock = 0}) {
  return Message(
    clientId: clientId,
    conversationId: conversationId,
    agentId: 'agent-1',
    role: MessageRole.user,
    content: 'msg $clientId',
    type: MessageType.text,
    status: MessageStatus.sent,
    logicalClock: clock,
    timestamp: clock,
  );
}
