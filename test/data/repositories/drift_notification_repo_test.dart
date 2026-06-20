import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/local/mapping/notification_mapping.dart';
import 'package:claw_hub/data/repositories/drift_notification_repo.dart';
import 'package:claw_hub/domain/models/pending_notification.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

db.AppDatabase _memDb() => db.AppDatabase(NativeDatabase.memory());

PendingNotification _domain({
  int id = 0,
  String agentId = 'a',
  String instanceId = 'i',
  String agentName = '虾',
  String summary = 'msg',
  int createdAt = 100,
  String? serverId = 's1',
}) {
  return PendingNotification(
    id: id,
    agentId: agentId,
    instanceId: instanceId,
    agentName: agentName,
    summary: summary,
    createdAt: createdAt,
    messageServerId: serverId,
  );
}

void main() {
  late db.AppDatabase database;
  late DriftNotificationRepo repo;

  setUp(() {
    database = _memDb();
    repo = DriftNotificationRepo(database);
  });

  tearDown(() async => database.close());

  test('enqueue persists and returns id > 0', () async {
    final id = await repo.enqueue(_domain());
    expect(id, greaterThan(0));
    expect(await repo.countPending(), 1);
  });

  test('getPending returns undelivered ordered by createdAt asc', () async {
    await repo.enqueue(_domain(createdAt: 300, serverId: 's3'));
    await repo.enqueue(_domain(createdAt: 100, serverId: 's1'));
    await repo.enqueue(_domain(createdAt: 200, serverId: 's2'));
    final pending = await repo.getPending();
    expect(pending.map((n) => n.createdAt).toList(), [100, 200, 300]);
  });

  test(
    'duplicate (instanceId, serverId) is ignored by partial unique index',
    () async {
      final first = await repo.enqueue(_domain(serverId: 'dup'));
      expect(first, greaterThan(0));
      await repo.enqueue(_domain(serverId: 'dup'));
      // second insert ignored (ON CONFLICT DO NOTHING) → count stays 1.
      // (customInsert's return value is last_insert_rowid(), which is NOT
      //  reset on a no-op conflict, so we rely on countPending, not the
      //  returned id, to verify dedup.)
      expect(await repo.countPending(), 1);
    },
  );

  test('null serverId rows coexist (no constraint)', () async {
    await repo.enqueue(_domain(serverId: null));
    await repo.enqueue(_domain(serverId: null));
    expect(await repo.countPending(), 2);
  });

  test('markDelivered moves item out of pending', () async {
    final id = await repo.enqueue(_domain());
    await repo.markDelivered(id);
    expect(await repo.countPending(), 0);
    expect((await repo.getPending()), isEmpty);
  });

  test('markDeliveredBatch marks all given ids in one statement', () async {
    final id1 = await repo.enqueue(_domain(serverId: 's1'));
    final id2 = await repo.enqueue(_domain(serverId: 's2', createdAt: 200));
    final id3 = await repo.enqueue(_domain(serverId: 's3', createdAt: 300));
    expect(await repo.countPending(), 3);

    final affected = await repo.markDeliveredBatch([id1, id2, id3]);
    expect(affected, 3);
    expect(await repo.countPending(), 0);
    expect(await repo.getPending(), isEmpty);
  });

  test('markDeliveredBatch with empty list is a no-op', () async {
    await repo.enqueue(_domain());
    final affected = await repo.markDeliveredBatch(const []);
    expect(affected, 0);
    expect(await repo.countPending(), 1);
  });

  test('clearDelivered removes delivered and returns count', () async {
    final id1 = await repo.enqueue(_domain(serverId: 's1'));
    await repo.enqueue(_domain(serverId: 's2'));
    await repo.markDelivered(id1);
    final removed = await repo.clearDelivered();
    expect(removed, 1);
    expect(await repo.countPending(), 1);
  });

  test('mapping round-trips domain ↔ drift row', () {
    final row = db.PendingNotification(
      id: 7,
      agentId: 'a',
      instanceId: 'i',
      agentName: '虾',
      summary: 'msg',
      createdAt: 999,
      messageServerId: 's',
      delivered: 0,
    );
    final domain = PendingNotificationMapper.toDomain(row);
    expect(domain.id, 7);
    expect(domain.agentId, 'a');
    expect(domain.messageServerId, 's');
    expect(domain.delivered, isFalse);
  });
}
