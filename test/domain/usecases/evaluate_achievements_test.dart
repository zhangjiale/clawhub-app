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
  });
}
