import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/domain/repositories/i_achievement_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';

class MockAchievementRepo extends Mock implements IAchievementRepo {}

void main() {
  setUpAll(() {
    registerFallbackValue(AgentStats(agentId: 'fallback'));
    registerFallbackValue(<String>{''});
  });

  group('EvaluateAchievementsUseCase', () {
    late MockAchievementRepo repo;
    late EvaluateAchievementsUseCase useCase;

    setUp(() {
      repo = MockAchievementRepo();
      useCase = EvaluateAchievementsUseCase(repo);

      // Default stubs — individual tests override as needed.
      // batchUnlock is only called when new achievements are detected;
      // return a conservative default so tests that don't expect unlocks
      // still pass without explicitly stubbing it.
      when(
        () => repo.getUnlocks(any()),
      ).thenAnswer((_) async => buildAchievementList({}, {}));
      when(
        () => repo.batchUnlock(any(), any()),
      ).thenAnswer((_) async => buildAchievementList({}, {}));
    });

    test('always calls computeStats (3B: no cache layer)', () async {
      final computedStats = AgentStats(agentId: 'a1', totalDialogs: 3);
      when(
        () => repo.computeStats('a1'),
      ).thenAnswer((_) async => computedStats);
      when(
        () => repo.getUnlocks('a1'),
      ).thenAnswer((_) async => buildAchievementList({}, {}));

      final result = await useCase.execute('a1');

      expect(result.stats, computedStats);
      verify(() => repo.computeStats('a1')).called(1);
    });

    // F13 (review-findings.json): regression guard against re-introducing a
    // `getStats`/`saveStats` cache layer. The interface contract
    // (i_achievement_repo.dart:11-24) explicitly forbids cache methods; this
    // test pins the BEHAVIORAL corollary — every execute() must hit
    // computeStats (no in-memory or repo-side shortcut).
    //
    // If someone re-adds cache methods, this test fails because the new
    // code path skips computeStats. Mocktail `verifyNever` can't enforce
    // absent methods, so we use a positive-multiplicity check instead.
    test('computeStats is called on every execute — no cache bypass '
        '(F13 no-cache regression guard)', () async {
      when(
        () => repo.computeStats('a1'),
      ).thenAnswer((_) async => AgentStats(agentId: 'a1'));
      when(
        () => repo.getUnlocks('a1'),
      ).thenAnswer((_) async => buildAchievementList({}, {}));

      await useCase.execute('a1');
      await useCase.execute('a1');
      await useCase.execute('a1');

      // Three executes → three computeStats invocations. If a future
      // `getStats`/`saveStats` cache layer is introduced and bypasses
      // computeStats on subsequent calls, this assertion fails.
      verify(() => repo.computeStats('a1')).called(3);
    });

    test('returns all achievements with correct unlock status', () async {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1,
        totalMessages: 5,
      );
      when(() => repo.computeStats('a1')).thenAnswer((_) async => stats);
      // first_dialog is already unlocked in DB
      when(() => repo.getUnlocks('a1')).thenAnswer(
        (_) async =>
            buildAchievementList({'first_dialog'}, {'first_dialog': 100}),
      );

      final result = await useCase.execute('a1');

      expect(result.achievements.length, 8);
      final fd = result.achievements.firstWhere((a) => a.id == 'first_dialog');
      expect(fd.unlocked, isTrue);
      expect(fd.unlockedAt, 100);
    });

    test('detects and unlocks new achievements', () async {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1,
        totalMessages: 50,
        currentStreak: 7,
      );
      when(() => repo.computeStats('a1')).thenAnswer((_) async => stats);
      // Nothing unlocked yet
      when(
        () => repo.getUnlocks('a1'),
      ).thenAnswer((_) async => buildAchievementList({}, {}));
      // batchUnlock should be called and return updated list
      when(() => repo.batchUnlock('a1', any())).thenAnswer(
        (_) async => buildAchievementList(
          {'first_dialog', 'streak_7'},
          {'first_dialog': 200, 'streak_7': 200},
        ),
      );

      final result = await useCase.execute('a1');

      expect(result.freshUnlocks.length, 2);
      expect(result.freshUnlocks.any((a) => a.id == 'first_dialog'), isTrue);
      expect(result.freshUnlocks.any((a) => a.id == 'streak_7'), isTrue);
    });

    test('does not unlock already-unlocked achievements', () async {
      final stats = AgentStats(agentId: 'a1', totalDialogs: 1);
      when(() => repo.computeStats('a1')).thenAnswer((_) async => stats);
      // first_dialog already unlocked
      when(() => repo.getUnlocks('a1')).thenAnswer(
        (_) async =>
            buildAchievementList({'first_dialog'}, {'first_dialog': 100}),
      );

      final result = await useCase.execute('a1');

      // first_dialog should NOT be in freshUnlocks
      expect(result.freshUnlocks, isEmpty);
      // batchUnlock should NOT be called
      verifyNever(() => repo.batchUnlock(any(), any()));
    });

    test('freshUnlocks empty when no new achievements', () async {
      final stats = AgentStats(agentId: 'a1');
      when(() => repo.computeStats('a1')).thenAnswer((_) async => stats);
      when(
        () => repo.getUnlocks('a1'),
      ).thenAnswer((_) async => buildAchievementList({}, {}));

      final result = await useCase.execute('a1');

      expect(result.freshUnlocks, isEmpty);
    });

    test('propagates repo errors to caller', () async {
      when(() => repo.computeStats('a1')).thenThrow(Exception('DB error'));

      expect(() => useCase.execute('a1'), throwsException);
    });

    // T-CONCURRENT-DEDUP: F4 (review-findings.json) — when two concurrent
    // execute() calls race for the same agentId (chat message checker +
    // profile-page listener both fire simultaneously), the achievement
    // must only appear in freshUnlocks ONCE across both calls. Currently
    // the use case lets both calls read existingUnlocks=[] before either
    // commits batchUnlock, so both return freshUnlocks=[first_dialog],
    // and the UI celebration animation fires twice for one unlock.
    //
    // Fix contract: per-agentId in-flight serialization at the use case.
    // Call A starts first → returns freshUnlocks=[first_dialog]. Call B
    // awaits Call A's future, then makes a FRESH call (sees updated
    // existingUnlocks), returns freshUnlocks=[].
    test('two concurrent execute(agentId) calls dedup freshUnlocks '
        '(F4: UI celebration fires once)', () async {
      final stats = AgentStats(agentId: 'a1', totalDialogs: 1);
      // Both calls start with no unlocks; first call unlocks first_dialog
      // and returns the updated list (DB-level INSERT OR IGNORE ensures
      // the row exists); second call sees existingUnlocks includes
      // first_dialog → freshUnlocks=[].
      when(() => repo.computeStats('a1')).thenAnswer((_) async => stats);
      // First call: no unlocks yet
      when(
        () => repo.getUnlocks('a1'),
      ).thenAnswer((_) async => buildAchievementList({}, {}));
      // After batchUnlock runs, subsequent getUnlocks sees first_dialog.
      // We can't easily change the stub mid-test; use thenAnswer with a
      // mutable backing field to flip behavior after the first batchUnlock.
      var batchUnlockCount = 0;
      when(() => repo.batchUnlock('a1', any())).thenAnswer((invocation) async {
        batchUnlockCount++;
        // First batchUnlock returns first_dialog unlocked; subsequent
        // calls return same (DB-level dedup is the contract).
        return buildAchievementList({'first_dialog'}, {'first_dialog': 200});
      });
      // After first batchUnlock, getUnlocks should reflect the new state.
      // Override the stub so subsequent calls return the unlocked list.
      when(() => repo.getUnlocks('a1')).thenAnswer((invocation) async {
        if (batchUnlockCount == 0) {
          return buildAchievementList({}, {});
        }
        return buildAchievementList({'first_dialog'}, {'first_dialog': 200});
      });

      // Fire two concurrent execute() calls. Use unawaited to actually
      // start both before awaiting.
      final futureA = useCase.execute('a1');
      final futureB = useCase.execute('a1');

      final results = await Future.wait([futureA, futureB]);

      // Combined freshUnlocks must contain 'first_dialog' exactly once.
      final allFresh = [...results[0].freshUnlocks, ...results[1].freshUnlocks];
      final firstDialogCount = allFresh
          .where((a) => a.id == 'first_dialog')
          .length;
      expect(
        firstDialogCount,
        equals(1),
        reason:
            'F4: two concurrent execute() calls must NOT both report '
            'first_dialog as a fresh unlock. Current bug: both return '
            'freshUnlocks=[first_dialog], causing UI celebration twice. '
            'Fix contract: second call awaits first, then sees updated '
            'existingUnlocks → freshUnlocks=empty.',
      );
    });

    // T-LAW17-CONCURRENT: Domain Law 17 contract — computeStats and
    // getUnlocks must run concurrently (line 46 `(computeStats, getUnlocks)
    // .wait`), not sequentially. A regression to sequential awaits would
    // pass every other test in this file. Pin the concurrency invariant
    // directly: hang both repo calls on Completers and assert both have
    // been invoked before either is released.
    //
    // Why this matters: the use case is on the chat-message hot path
    // (AchievementChecker fires it on every chat event). Sequential
    // await of two SELECTs would double the latency of every chat
    // message that happens to coincide with a Profile page open.
    test(
      'computeStats and getUnlocks are awaited concurrently (Law 17)',
      () async {
        final statsCompleter = Completer<AgentStats>();
        final unlocksCompleter = Completer<List<Achievement>>();

        when(
          () => repo.computeStats('a1'),
        ).thenAnswer((_) => statsCompleter.future);
        when(
          () => repo.getUnlocks('a1'),
        ).thenAnswer((_) => unlocksCompleter.future);

        final future = useCase.execute('a1');

        // Yield so both awaits in the `.wait` record start. flushMicrotasks
        // alone is insufficient — the futures are async (event-loop), not
        // microtasks.
        await Future<void>.delayed(Duration.zero);

        // Both repo calls must have been invoked before either resolves.
        // If computeStats awaited getUnlocks (sequential regression), the
        // getUnlocks stub would not have been called yet.
        verify(() => repo.computeStats('a1')).called(1);
        verify(() => repo.getUnlocks('a1')).called(1);

        // Release in reverse order to prove order doesn't matter.
        unlocksCompleter.complete(buildAchievementList({}, {}));
        await Future<void>.delayed(Duration.zero);
        statsCompleter.complete(AgentStats(agentId: 'a1'));
        await future;
      },
    );
  });
}
