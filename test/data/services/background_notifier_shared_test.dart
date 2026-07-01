import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/data/services/background_notifier_shared.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/notification_event.dart';
import 'package:claw_hub/domain/models/pending_notification.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_notification_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockNotificationRepo extends Mock implements INotificationRepo {}

class _FakeLogger implements ILogger {
  @override
  void info(String message) {}
  @override
  void error(String message, [StackTrace? stackTrace]) {}
}

Message _msg({
  required String serverId,
  String clientId = 'c',
  String agentId = 'a',
  String content = 'reply',
}) {
  return Message(
    clientId: clientId,
    serverId: serverId,
    conversationId: 'conv-abc',
    agentId: agentId,
    role: MessageRole.agent,
    content: content,
    type: MessageType.text,
    logicalClock: 1,
  );
}

Agent _agent({String remoteId = 'a', String instanceId = 'i'}) {
  return Agent(
    localId: 'l-$remoteId',
    remoteId: remoteId,
    instanceId: instanceId,
    name: 'Claw',
  );
}

UserPreferences _prefs() {
  return UserPreferences(
    notificationsEnabled: true,
    notifyOnReply: true,
    notifyOnError: true,
    notifyOnConnectionChange: true,
    dndEnabled: false,
  );
}

void main() {
  late _MockNotificationRepo repo;
  late _FakeLogger logger;

  setUpAll(() {
    registerFallbackValue(
      const PendingNotification(
        id: 0,
        agentId: 'fb',
        instanceId: 'fb',
        agentName: 'fb',
        summary: 'fb',
        createdAt: 0,
        messageServerId: 'fb',
      ),
    );
  });

  setUp(() {
    repo = _MockNotificationRepo();
    logger = _FakeLogger();
  });

  // ===========================================================================
  // TDD-RED test for code-review finding F8:
  //   background_notifier_shared.dart:55 — the for-loop in enqueuePulled
  //   awaits repo.enqueue(PendingNotification) once per message. With
  //   maxMessagesPerPull=100 pulled per agent and N agents per instance,
  //   a single background-sync tick can produce hundreds of individually
  //   awaited round-trips to SQLite — measurable delay vs the
  //   WorkManager 10-minute budget on slow flash storage.
  //
  //   The fix is to batch the inserts (e.g. add a new
  //   `Future<List<int>> enqueueBatch(List<PendingNotification>)` method
  //   on INotificationRepo and call it once). This test pins the
  //   behavior contract: N messages must NOT result in N individual
  //   `repo.enqueue` invocations — at most one (batch) call.
  //
  //   This test FAILS on the current code (count = N = 5).
  // ===========================================================================
  test(
    'F8_enqueuePulled_batchesInsertsAcrossMessages_singleInsertCallPerBatch',
    () async {
      // Given: 5 agent messages with unique serverIds, all of which
      // pass the notification decision (notifyOnReply, no DND).
      final messages = List.generate(
        5,
        (i) => _msg(serverId: 's$i', clientId: 'c$i'),
      );
      final agent = _agent();

      when(() => repo.enqueue(any())).thenAnswer((_) async => 1);

      await BackgroundNotifierShared.enqueuePulled(
        messages: messages,
        resolveAgent: (_) => agent,
        prefs: _prefs(),
        evaluator: const EvaluateNotificationUseCase(),
        repo: repo,
        logger: logger,
      );

      // Contract (Law 6 — single SQL for a batch): the per-message
      // for-loop must collapse to a single batch insert (the new
      // `repo.enqueueBatch` method). Today the loop calls
      // `repo.enqueue` 5 times; the fix must reduce it to 0 — all
      // enqueues go through `repo.enqueueBatch` exactly once.
      //
      // N+1 enqueue per pull tick blocks the WorkManager 10-minute
      // budget on slow flash storage. Background sync pulls up to
      // 100 messages × N agents — must batch.
      verifyNever(() => repo.enqueue(any()));

      // And the batch call happens exactly once with all 5 rows.
      verify(
        () => repo.enqueueBatch(captureAny<List<PendingNotification>>()),
      ).captured.single;
    },
  );

  // -----------------------------------------------------------------------
  // Regression guard: messages that DROP the notification decision
  // (DroppedDecision) must not enqueue at all. Pin the boundary so the
  // batching fix doesn't accidentally widen the decision filter.
  // -----------------------------------------------------------------------
  test('regression_guard_droppedDecision_doesNotEnqueue_atAll', () async {
    final agent = _agent();
    final droppedPrefs = UserPreferences(
      notificationsEnabled: true,
      notifyOnReply: false, // reply filter off → DroppedDecision
      notifyOnError: true,
      notifyOnConnectionChange: true,
      dndEnabled: false,
    );

    final messages = List.generate(
      3,
      (i) => _msg(serverId: 'drop$i', clientId: 'dc$i'),
    );
    when(() => repo.enqueue(any())).thenAnswer((_) async => 1);

    await BackgroundNotifierShared.enqueuePulled(
      messages: messages,
      resolveAgent: (_) => agent,
      prefs: droppedPrefs,
      evaluator: const EvaluateNotificationUseCase(),
      repo: repo,
      logger: logger,
    );

    // All 3 messages were Dropped → repo.enqueue must not be called.
    verifyNever(() => repo.enqueue(any()));
  });

  // Reference-compile sanity: ReplyEvent has fields BackgroundNotifierShared
  // closes over; this test isn't a finding but pin that the public surface
  // we depend on stays intact.
  test('regression_guard_ReplyEvent_construction_succeeds', () {
    final e = ReplyEvent(
      agentId: 'a',
      instanceId: 'i',
      agentName: '小明虾',
      contentPreview: '你好',
      messageServerId: 's',
      messageClientId: 'c',
    );
    expect(e.agentId, 'a');
    expect(e.messageServerId, 's');
  });
}
