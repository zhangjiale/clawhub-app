import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/local/database/database.dart';
import 'drift_last_sync_repo_test_helper.dart' as helper;

void main() {
  late AppDatabase db;
  late helper.RepoHarness harness;

  setUp(() async {
    harness = await helper.openInMemory();
    db = harness.db;
  });
  tearDown(() => db.close());

  test('get_returnsNullWhenAbsent', () async {
    final repo = helper.makeRepo(db);
    expect(await repo.get('inst-a', 'agent-x'), isNull);
  });

  test('upsert_thenGet_returnsMsEpoch', () async {
    final repo = helper.makeRepo(db);
    await repo.upsert('inst-a', 'agent-x', 1700000000000);
    expect(await repo.get('inst-a', 'agent-x'), 1700000000000);
  });

  test('upsert_overwritesExisting', () async {
    final repo = helper.makeRepo(db);
    await repo.upsert('inst-a', 'agent-x', 1000);
    await repo.upsert('inst-a', 'agent-x', 2000);
    expect(await repo.get('inst-a', 'agent-x'), 2000);
  });

  test('upsert_isPerInstanceIndependent', () async {
    final repo = helper.makeRepo(db);
    await repo.upsert('inst-a', 'agent-x', 1000);
    await repo.upsert('inst-b', 'agent-x', 2000);
    expect(await repo.get('inst-a', 'agent-x'), 1000);
    expect(await repo.get('inst-b', 'agent-x'), 2000);
  });

  test('upsert_isPerAgentIndependent', () async {
    final repo = helper.makeRepo(db);
    await repo.upsert('inst-a', 'agent-1', 1000);
    await repo.upsert('inst-a', 'agent-2', 2000);
    expect(await repo.get('inst-a', 'agent-1'), 1000);
    expect(await repo.get('inst-a', 'agent-2'), 2000);
  });
}
