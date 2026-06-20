import 'package:claw_hub/domain/models/pending_notification.dart';
import 'package:claw_hub/domain/repositories/i_notification_repo.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个最小内存 fake，用于验证 [INotificationRepo] 契约。
class _FakeNotificationRepo implements INotificationRepo {
  final List<PendingNotification> _store = [];
  int _nextId = 1;

  @override
  Future<int> enqueue(PendingNotification n) async {
    final withId = n.copyWith(id: _nextId++);
    _store.add(withId);
    return withId.id;
  }

  @override
  Future<List<PendingNotification>> getPending() async {
    return _store.where((n) => !n.delivered).toList();
  }

  @override
  Future<void> markDelivered(int id) async {
    final i = _store.indexWhere((n) => n.id == id);
    if (i >= 0) _store[i] = _store[i].copyWith(delivered: true);
  }

  @override
  Future<int> markDeliveredBatch(List<int> ids) async {
    var affected = 0;
    for (final id in ids) {
      final i = _store.indexWhere((n) => n.id == id);
      if (i >= 0 && !_store[i].delivered) {
        _store[i] = _store[i].copyWith(delivered: true);
        affected++;
      }
    }
    return affected;
  }

  @override
  Future<int> clearDelivered() async {
    final before = _store.length;
    _store.removeWhere((n) => n.delivered);
    return before - _store.length;
  }

  @override
  Future<int> countPending() async {
    return _store.where((n) => !n.delivered).length;
  }
}

PendingNotification _n(String agent, {String? serverId}) => PendingNotification(
  id: 0,
  agentId: agent,
  instanceId: 'i',
  agentName: '虾$agent',
  summary: 'msg',
  createdAt: 1,
  messageServerId: serverId,
);

void main() {
  late _FakeNotificationRepo repo;

  setUp(() => repo = _FakeNotificationRepo());

  test('enqueue assigns id and persists', () async {
    final id = await repo.enqueue(_n('a'));
    expect(id, greaterThan(0));
    expect(await repo.countPending(), 1);
  });

  test('getPending returns only undelivered', () async {
    final id1 = await repo.enqueue(_n('a'));
    await repo.enqueue(_n('b'));
    await repo.markDelivered(id1);
    final pending = await repo.getPending();
    expect(pending.length, 1);
    expect(pending.first.agentId, 'b');
  });

  test('markDelivered moves item out of pending', () async {
    final id = await repo.enqueue(_n('a'));
    await repo.markDelivered(id);
    expect(await repo.countPending(), 0);
  });

  test(
    'markDeliveredBatch marks all ids in one call, empty list no-op',
    () async {
      final id1 = await repo.enqueue(_n('a'));
      final id2 = await repo.enqueue(_n('b'));
      final affected = await repo.markDeliveredBatch([id1, id2]);
      expect(affected, 2);
      expect(await repo.countPending(), 0);
      expect(await repo.markDeliveredBatch(const []), 0);
    },
  );

  test('clearDelivered removes delivered and returns count', () async {
    final id1 = await repo.enqueue(_n('a'));
    await repo.enqueue(_n('b'));
    await repo.markDelivered(id1);
    final removed = await repo.clearDelivered();
    expect(removed, 1);
    expect(await repo.countPending(), 1);
  });

  test('countPending counts undelivered', () async {
    await repo.enqueue(_n('a'));
    await repo.enqueue(_n('b'));
    await repo.enqueue(_n('c'));
    expect(await repo.countPending(), 3);
  });
}
