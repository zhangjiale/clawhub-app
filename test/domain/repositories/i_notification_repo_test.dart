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
  Future<List<int>> enqueueBatch(
    List<PendingNotification> notifications,
  ) async {
    // Empty → no-op (matches DriftNotificationRepo contract).
    if (notifications.isEmpty) return const <int>[];
    // Iterate calling per-row enqueue — fakes don't share transaction
    // semantics with Drift; behavioral contract is the rowid list
    // shape and dedup (out of scope for this minimal fake).
    final ids = <int>[];
    for (final n in notifications) {
      ids.add(await enqueue(n));
    }
    return ids;
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

  // ===========================================================================
  // enqueueBatch — Law 6 batch contract (US-018 F8 fix).
  //
  // BackgroundNotifierShared.enqueuePulled processes one tick's worth of
  // pulled messages. With maxMessagesPerPull=100 across N agents, the
  // legacy per-row enqueue produced N+1 round-trips that visibly stalled
  // the WorkManager 10-minute budget on slow flash storage. The repo
  // now exposes a single-call batch entry point. This file is the LAW 17
  // contract test that pins the surface.
  // ===========================================================================

  test('enqueueBatch assigns ids and persists all rows', () async {
    final ids = await repo.enqueueBatch([
      _n('a', serverId: 's1'),
      _n('b', serverId: 's2'),
      _n('c', serverId: 's3'),
    ]);
    expect(ids.length, 3);
    expect(ids.every((id) => id > 0), isTrue);
    // All ids unique — order matches input order.
    expect(ids.toSet().length, 3);
    expect(await repo.countPending(), 3);
  });

  test(
    'enqueueBatch empty list returns empty list and does not change state',
    () async {
      // Pre-load a row so we can assert "no-op, not even a delete".
      await repo.enqueue(_n('a'));
      final beforePending = await repo.countPending();

      final ids = await repo.enqueueBatch(const []);
      expect(ids, isEmpty);
      expect(await repo.countPending(), beforePending);
    },
  );

  test('enqueueBatch single row behaves like enqueue', () async {
    final ids = await repo.enqueueBatch([_n('solo', serverId: 's1')]);
    expect(ids.length, 1);
    expect(await repo.countPending(), 1);
  });
}
