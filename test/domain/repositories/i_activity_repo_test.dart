import 'package:claw_hub/domain/models/daily_activity.dart';
import 'package:claw_hub/domain/repositories/i_activity_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // This test file is a compile-time-only assertion: it verifies the
  // [IActivityRepo] interface exists and has the expected method
  // signature. Runtime semantics are covered by
  // `test/data/repositories/drift_activity_repo_test.dart`.
  group('IActivityRepo contract', () {
    test('can be implemented by a class with the expected method', () {
      final fake = _FakeActivityRepo();
      expect(fake, isA<IActivityRepo>());
    });

    test('getDailyActivity signature returns List<DailyActivity>', () async {
      final fake = _FakeActivityRepo();
      final result = await fake.getDailyActivity(
        'agent-1',
        days: 7,
        now: DateTime.utc(2024, 1, 10),
      );
      expect(result, isA<List<DailyActivity>>());
      expect(result.length, 7);
    });
  });
}

class _FakeActivityRepo implements IActivityRepo {
  @override
  Future<List<DailyActivity>> getDailyActivity(
    String agentId, {
    int days = 30,
    DateTime? now,
  }) async {
    final anchor = now ?? DateTime.now().toUtc();
    final todayBucket = anchor.millisecondsSinceEpoch ~/ 86400000;
    return List.generate(days, (i) {
      return DailyActivity(
        agentId: agentId,
        dayBucket: todayBucket - (days - 1 - i),
        messageCount: 0,
      );
    });
  }
}
