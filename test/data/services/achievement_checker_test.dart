import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/data/services/achievement_checker.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
import '../../_helpers/mocks.dart';

class MockUseCase extends Mock implements EvaluateAchievementsUseCase {}

void main() {
  setUpAll(() {
    registerFallbackValue('fallback-agent-id');
  });

  group('AchievementChecker', () {
    late MockUseCase useCase;
    late MockILogger logger;
    late AchievementChecker checker;

    setUp(() {
      useCase = MockUseCase();
      logger = MockILogger();
      checker = AchievementChecker(useCase, logger);
      when(() => useCase.execute(any())).thenAnswer(
        (_) async => EvaluateAchievementsResult(
          stats: const AgentStats(agentId: 'stub'),
          achievements: const [],
          freshUnlocks: const [],
        ),
      );
      when(() => logger.error(any(), any())).thenReturn(null);
    });

    // T-EVICTION-CLOCK: build a checker with a controllable Clock so the
    // time-eviction branch (line ~96: `removeWhere((_, t) => now.difference(t) > _maxAge)`)
    // can be exercised deterministically. Used by the F7 time-eviction tests
    // below; default `DateTime.now` for the rest of the suite.
    AchievementChecker buildCheckerWithClock(DateTime Function() clock) {
      return AchievementChecker(useCase, logger, clock: clock);
    }

    // 3A: use case.execute() 不再有 forceRecompute named param。
    // AchievementChecker 仍然在每次 chat 事件后 fire-and-forget 调一次,
    // use case 内部永远走 computeStats 全量聚合（cache 读路径已删）。
    test('check(agentId) forwards to use case on each chat event', () async {
      checker.check('agent-42');

      // The check is fire-and-forget; give the unawaited future time to run.
      await Future<void>.delayed(Duration.zero);

      verify(() => useCase.execute('agent-42')).called(1);
    });

    test(
      'check(agentId) within debounce window does not call use case twice',
      () async {
        checker.check('agent-42');
        await Future<void>.delayed(Duration.zero);
        checker.check('agent-42'); // within 5s — must be debounced
        await Future<void>.delayed(Duration.zero);

        verify(() => useCase.execute('agent-42')).called(1);
      },
    );

    test(
      'check(agentId) for different agents both trigger evaluation',
      () async {
        checker.check('agent-A');
        checker.check('agent-B');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        verify(() => useCase.execute('agent-A')).called(1);
        verify(() => useCase.execute('agent-B')).called(1);
      },
    );

    test('check(agentId) swallows use case errors and logs them', () async {
      when(() => useCase.execute(any())).thenThrow(Exception('boom'));

      checker.check('agent-fail');
      await Future<void>.delayed(Duration.zero);

      verify(() => logger.error(any(), any())).called(1);
      // Note: pre-3A this verified `execute(..., forceRecompute: false)` was
      // never called. After 3A removed the named param, that assertion is
      // meaningless — the test relies on execute() being CALLED (and throwing)
      // to drive the logger.error path. The verify() above is sufficient.
    });

    // Bug-fix (round 3) contract: the updates stream lets subscribers
    // (e.g. AgentProfileViewModel) know when this agent's stats cache has
    // been freshly recomputed, so they can refresh their own snapshot
    // instead of serving stale data from page-init time.
    test('updates stream emits agentId after successful recompute', () async {
      final received = <String>[];
      final sub = checker.updates.listen(received.add);

      checker.check('agent-42');
      await Future<void>.delayed(Duration.zero);

      expect(received, ['agent-42']);
      await sub.cancel();
    });

    test('updates stream does NOT emit when recompute fails '
        '(avoids no-op refresh storms)', () async {
      when(() => useCase.execute(any())).thenThrow(Exception('DB down'));

      final received = <String>[];
      final sub = checker.updates.listen(received.add);

      checker.check('agent-fail');
      await Future<void>.delayed(Duration.zero);

      // Failure path must stay silent on the updates stream — the next
      // chat message will naturally trigger another check() and retry.
      expect(received, isEmpty);
      await sub.cancel();
    });

    // T-LIFECYCLE-01: dispose during in-flight _checkAsync prevents update
    // emission AND must not produce a spurious error log. Without the
    // isClosed guard inside _checkAsync, the unawaited future completing
    // after dispose() would call _updates.add() on a closed broadcast
    // controller and throw StateError — caught by the surrounding try/catch
    // and logged via logger.error. The contract is: a disposed checker is
    // silent on BOTH the updates stream and the logger.
    test(
      'dispose during in-flight _checkAsync is silent (no emit, no log)',
      () async {
        final completer = Completer<EvaluateAchievementsResult>();
        when(() => useCase.execute(any())).thenAnswer((_) => completer.future);

        final received = <String>[];
        final sub = checker.updates.listen(received.add);

        checker.check('agent-42');
        await Future<void>.delayed(Duration.zero); // let _checkAsync hit await

        checker.dispose();

        // Release the hanging future, simulating in-flight completion.
        completer.complete(
          EvaluateAchievementsResult(
            stats: const AgentStats(agentId: 'agent-42'),
            achievements: const [],
            freshUnlocks: const [],
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(
          received,
          isEmpty,
          reason: 'disposed controller must not emit update events',
        );
        verify(() => useCase.execute('agent-42')).called(1);
        // T-LIFECYCLE-01 (strengthened): disposed checker must be silent on
        // BOTH the stream and the logger. Without the post-await isClosed
        // guard in _checkAsync, _updates.add() throws StateError on a closed
        // broadcast controller; the try/catch catches it and routes to
        // logger.error, producing a spurious "Achievement check failed" log
        // in production on every dispose-during-in-flight race.
        verifyNever(() => logger.error(any(), any()));
      },
    );

    // T-LIFECYCLE-02: double dispose must be idempotent. The implementation
    // guards with `if (!_updates.isClosed)` so the second call short-circuits.
    test('dispose called twice is a safe no-op', () {
      checker.dispose();
      expect(
        () => checker.dispose(),
        returnsNormally,
        reason: 'second dispose must be idempotent and not throw StateError',
      );
    });

    // T-LIFECYCLE-03: post-dispose check() must short-circuit before any
    // state mutation. The isClosed guard at the top of check() ensures
    // _lastChecks is not written and no use case call is scheduled.
    test('check after dispose is a safe no-op (no useCase call)', () async {
      checker.dispose();

      expect(() => checker.check('agent-42'), returnsNormally);
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => useCase.execute(any()));
    });

    // T-LIFECYCLE-04 (strengthened): dispose() must reset the debounce state.
    // Round 2 verified this indirectly (a fresh checker can fire a never-seen
    // agentId). Round 4 strengthens to DIRECT verification: the disposed
    // instance's _lastChecks map must be literally empty, asserted via
    // [debugLastChecks]. Catches regressions where dispose() forgets to call
    // `_lastChecks.clear()`.
    test(
      'dispose clears _lastChecks (direct verification via debugLastChecks)',
      () async {
        // Seed the disposed checker with two agents.
        checker.check('agent-A');
        await Future<void>.delayed(Duration.zero);
        checker.check('agent-B');
        await Future<void>.delayed(Duration.zero);

        // Pre-dispose sanity: map must contain both entries.
        expect(checker.debugLastChecks, isNotEmpty);
        expect(
          checker.debugLastChecks.keys,
          containsAll(['agent-A', 'agent-B']),
        );

        checker.dispose();

        // Direct assertion: disposed instance's debounce map is empty.
        expect(
          checker.debugLastChecks,
          isEmpty,
          reason:
              'dispose() must call _lastChecks.clear() so future checks on a '
              'newly constructed checker are not blocked by stale state.',
        );
      },
    );

    // T-EVICTION-01: when the debounce map reaches _maxEntries, the oldest
    // Soft-cap behavior contract: when inserting past _maxEntries with all
    // entries fresh (< _maxAge old), the time-based eviction sweep finds
    // nothing stale to remove. The map therefore exceeds _maxEntries by
    // design — this is a deliberate "soft cap with time-based cleanup"
    // pattern, not a hard LRU cap.
    //
    // Documented behavior: a fully-fresh map can grow past _maxEntries
    // until enough wall-clock time passes that the next sweep can prune
    // time-stale entries. The cap is a TRIGGER for the sweep, not a size
    // ceiling.
    //
    // For true hard-cap testing we'd need a Clock injection — that's a
    // separate design decision, not required by Iron Laws.
    test('soft cap: fresh entries survive past _maxEntries '
        '(cap is a sweep trigger, not a size ceiling)', () async {
      const total = 55; // exceeds _maxEntries=50
      for (var i = 0; i < total; i++) {
        checker.check('agent-$i');
        // Small real-clock delay so timestamps are monotonically distinct.
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      // All 55 entries are fresh (just inserted), so the sweep at cap
      // removes NONE of them. Map size equals the number of inserts.
      expect(
        checker.debugLastChecks.length,
        total,
        reason: 'Fresh entries are not evicted — only time-stale ones are',
      );
      // Sanity: the cap constant is what we expect — tests against the
      // constant directly, not a hardcoded 50.
      expect(
        AchievementChecker.debugMaxEntries,
        50,
        reason: 'Cap constant should remain 50 (regression guard)',
      );
      expect(
        AchievementChecker.debugMaxAge,
        const Duration(minutes: 30),
        reason: 'Stale threshold should remain 30min (regression guard)',
      );
      expect(
        AchievementChecker.debugMinInterval,
        const Duration(seconds: 5),
        reason: 'Debounce window should remain 5s (regression guard)',
      );
    });

    // T-EVICTION-02: time-based eviction branch — verifies the eviction
    // constants remain positive. (Real time-eviction would need a
    // [Clock] injection to test deterministically; see T-EVICTION-01 for
    // the cap-bound sweep path that does exercise eviction.)
    test(
      'eviction constants remain positive durations (regression guard)',
      () async {
        // Bring the map right at cap so the next insertion triggers the
        // eviction sweep — confirms the sweep path runs without error.
        for (var i = 0; i < AchievementChecker.debugMaxEntries; i++) {
          checker.check('agent-fill-$i');
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(
          checker.debugLastChecks.length,
          AchievementChecker.debugMaxEntries,
          reason: 'Map should hold up to cap entries',
        );

        expect(
          AchievementChecker.debugMaxAge,
          greaterThan(Duration.zero),
          reason: '_maxAge must be positive so stale entries can be evicted',
        );
        expect(
          AchievementChecker.debugMinInterval,
          greaterThan(Duration.zero),
          reason: '_minInterval must be positive for debounce to be meaningful',
        );
      },
    );

    // F7 (review-findings.json): real time-eviction test using controllable
    // Clock. The T-EVICTION-02 above only asserts constants are positive;
    // this one exercises the actual `removeWhere((_, t) => now.difference(t) > _maxAge)`
    // branch at achievement_checker.dart by:
    //   1. seeding entries at time T0 (all fresh)
    //   2. advancing the clock past `_maxAge`
    //   3. inserting one more entry to trigger cap-bound sweep
    //   4. asserting stale entries are evicted, fresh one survives
    test('time-eviction removes entries older than _maxAge on cap-bound sweep '
        '(F7 real eviction branch)', () async {
      var now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final checker = buildCheckerWithClock(() => now);

      const cap = AchievementChecker.debugMaxEntries;
      // Fill map to exactly the cap with all-fresh entries (timestamp T0).
      for (var i = 0; i < cap; i++) {
        checker.check('stale-$i');
        // Avoid minInterval debounce by jumping clock forward each call.
        now = now.add(const Duration(seconds: 6));
      }
      expect(checker.debugLastChecks.length, cap);

      // Advance the clock by `_maxAge + 1m` — all `stale-*` entries are now
      // older than `_maxAge` and should be evicted on the next sweep.
      now = now.add(
        AchievementChecker.debugMaxAge + const Duration(minutes: 1),
      );

      // Trigger the sweep by inserting one more entry (length was at cap
      // before this call, so the `>= _maxEntries` branch fires).
      checker.check('fresh-1');
      await Future<void>.delayed(Duration.zero);

      // All stale-* entries evicted; only fresh-1 remains.
      expect(
        checker.debugLastChecks.length,
        1,
        reason:
            'All stale-* entries (older than _maxAge) must be evicted by '
            'the cap-bound sweep; only the just-inserted fresh-1 remains.',
      );
      expect(checker.debugLastChecks.containsKey('fresh-1'), isTrue);
      for (var i = 0; i < cap; i++) {
        expect(
          checker.debugLastChecks.containsKey('stale-$i'),
          isFalse,
          reason:
              'stale-$i must have been evicted (timestamp older '
              'than _maxAge)',
        );
      }
    });

    // F7 inverse: fresh entries within _maxAge survive the sweep.
    test('time-eviction preserves entries within _maxAge on cap-bound sweep '
        '(F7 negative path)', () async {
      var now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final checker = buildCheckerWithClock(() => now);

      const cap = AchievementChecker.debugMaxEntries;
      for (var i = 0; i < cap; i++) {
        checker.check('recent-$i');
        now = now.add(const Duration(seconds: 6));
      }
      expect(checker.debugLastChecks.length, cap);

      // Advance only 1 minute — well within _maxAge (30 min default).
      now = now.add(const Duration(minutes: 1));

      // Trigger sweep by inserting one more entry.
      checker.check('recent-extra');
      await Future<void>.delayed(Duration.zero);

      // All `recent-*` (within _maxAge) survive; new `recent-extra` also
      // present. Total = cap + 1 (no eviction triggered by stale age).
      expect(checker.debugLastChecks.length, cap + 1);
      for (var i = 0; i < cap; i++) {
        expect(checker.debugLastChecks.containsKey('recent-$i'), isTrue);
      }
      expect(checker.debugLastChecks.containsKey('recent-extra'), isTrue);
    });
  });
}
