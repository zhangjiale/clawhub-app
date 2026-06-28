import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

Agent _agent({
  String localId = 'local-1',
  String remoteId = 'r-1',
  String instanceId = 'inst-1',
  String name = '产品虾',
  List<QuickCommand>? quickCommands,
}) => Agent(
  localId: localId,
  remoteId: remoteId,
  instanceId: instanceId,
  name: name,
  themeColor: '#6c5ce7',
  quickCommands: quickCommands ?? const [],
);

QuickCommand _cmd(
  String id,
  String label,
  String payload, [
  int sortOrder = 0,
]) => QuickCommand(
  id: id,
  agentId: 'local-1',
  label: label,
  payload: payload,
  sortOrder: sortOrder,
);

void main() {
  group('InMemoryAgentRepo.watchById', () {
    late InMemoryAgentRepo repo;

    setUp(() {
      repo = InMemoryAgentRepo();
    });

    tearDown(() async {
      await repo.dispose();
    });

    test('subscribe emits current agent as seed event', () async {
      await repo.syncFromGateway('inst-1', [_agent()]);

      final stream = repo.watchById('local-1');
      final emitted = await stream.first;

      expect(emitted, isNotNull);
      expect(emitted!.localId, 'local-1');
      expect(emitted.name, '产品虾');
    });

    test('subscribe to nonexistent localId emits null', () async {
      final stream = repo.watchById('nonexistent');
      final emitted = await stream.first;

      expect(emitted, isNull);
    });

    test(
      'updateFullProfile with new quickCommands emits updated agent',
      () async {
        await repo.syncFromGateway('inst-1', [_agent()]);

        final emitted = <Agent>[];
        final sub = repo.watchById('local-1').skip(1).listen((a) {
          if (a != null) emitted.add(a);
        });
        // 等 async* generator 完成 seed yield 并订阅 _agentsChanged.stream
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await repo.updateFullProfile(
          'local-1',
          quickCommands: [_cmd('c1', '状态', '/status', 0)],
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));
        await sub.cancel();

        expect(emitted.length, greaterThanOrEqualTo(1));
        final last = emitted.last;
        expect(last.quickCommands.length, 1);
        expect(last.quickCommands.first.payload, '/status');
      },
    );

    test('clearAvatar emits agent with avatarUrl=null', () async {
      await repo.syncFromGateway('inst-1', [
        _agent().copyWith(avatarUrl: '/path/to/avatar.png'),
      ]);

      final emitted = <Agent>[];
      final sub = repo.watchById('local-1').skip(1).listen((a) {
        if (a != null) emitted.add(a);
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await repo.clearAvatar('local-1');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last.avatarUrl, isNull);
    });

    test('togglePin emits agent with flipped isPinned', () async {
      await repo.syncFromGateway('inst-1', [_agent()]);

      final emitted = <Agent>[];
      final sub = repo.watchById('local-1').skip(1).listen((a) {
        if (a != null) emitted.add(a);
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await repo.togglePin('local-1');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last.isPinned, isTrue);
    });

    test('syncFromGateway emits upserted agents', () async {
      final emitted = <Agent?>[];
      final sub = repo.watchById('local-1').listen(emitted.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await repo.syncFromGateway('inst-1', [_agent()]);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      // seed (null) + upsert (agent) = 2 emits
      expect(
        emitted.length,
        greaterThanOrEqualTo(2),
        reason: 'syncFromGateway 应 emit seed + upsert',
      );
      expect(emitted.first, isNull, reason: 'seed 在 sync 之前订阅,应为 null');
      final last = emitted.last;
      expect(last, isNotNull);
      expect(last!.localId, 'local-1');
    });

    test('updateLocalProfile emits agent with new nickname', () async {
      await repo.syncFromGateway('inst-1', [_agent()]);

      final emitted = <Agent>[];
      final sub = repo.watchById('local-1').skip(1).listen((a) {
        if (a != null) emitted.add(a);
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await repo.updateLocalProfile('local-1', nickname: '小虾');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last.nickname, '小虾');
    });

    test('multiple subscribers all receive emits (broadcast)', () async {
      await repo.syncFromGateway('inst-1', [_agent()]);

      final sub1 = <Agent>[];
      final sub2 = <Agent>[];
      final s1 = repo.watchById('local-1').skip(1).listen((a) {
        if (a != null) sub1.add(a);
      });
      final s2 = repo.watchById('local-1').skip(1).listen((a) {
        if (a != null) sub2.add(a);
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await repo.updateLocalProfile('local-1', nickname: 'test');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await s1.cancel();
      await s2.cancel();

      expect(sub1.length, greaterThanOrEqualTo(1));
      expect(sub2.length, greaterThanOrEqualTo(1));
      expect(sub1.last.nickname, 'test');
      expect(sub2.last.nickname, 'test');
    });

    // ========================================================================
    // Bug #5 regression — bulk delete triggers watchById null emission
    // ========================================================================
    //
    // The Drift implementation gets deletion notifications automatically
    // (the SQL DELETE statement changes the watched row).  In-memory
    // implementations must synthesize a change event per removed localId
    // so watchById subscribers observe the deletion (post-delete lookup
    // of _store[localId] yields null).
    //
    // Without this fix, dev / test paths silently leak "ghost" agents in
    // subscribers until the next syncFromGateway.

    test(
      'deleteByInstanceId triggers watchById null emission for each removed agent',
      () async {
        // Seed two agents on the same instance.
        await repo.syncFromGateway('inst-1', [
          _agent(localId: 'local-1'),
          _agent(localId: 'local-2', remoteId: 'r-2'),
        ]);

        final emittedLocal1 = <Agent?>[];
        final emittedLocal2 = <Agent?>[];
        final sub1 = repo.watchById('local-1').listen(emittedLocal1.add);
        final sub2 = repo.watchById('local-2').listen(emittedLocal2.add);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await repo.deleteByInstanceId('inst-1');

        await Future<void>.delayed(const Duration(milliseconds: 10));
        await sub1.cancel();
        await sub2.cancel();

        // Each subscriber must observe the deletion: seed yields the
        // current agent, the post-delete marker re-fires the stream and
        // .map(_ => _store[localId]) yields null.
        expect(
          emittedLocal1.last,
          isNull,
          reason:
              'watchById must emit null after deleteByInstanceId — '
              'the contract guarantees nonexistent localIds emit null.',
        );
        expect(
          emittedLocal2.last,
          isNull,
          reason:
              'Bulk delete must notify every removed agent\'s subscriber, '
              'not just the first one.',
        );
        // Sanity: each subscriber saw at least one non-null seed before
        // the null (rules out a test that only sees the seed null).
        expect(
          emittedLocal1.contains(null),
          isTrue,
          reason: 'at least one null emission expected',
        );
        expect(
          emittedLocal1.where((a) => a != null).length,
          greaterThanOrEqualTo(1),
        );
        expect(
          emittedLocal2.where((a) => a != null).length,
          greaterThanOrEqualTo(1),
        );
      },
    );

    test(
      'deleteByInstanceId on unrelated instance does NOT trigger watchById emit',
      () async {
        // Negative case: deleting other instances' agents must not falsely
        // fire null for unrelated subscribers. Guards against a
        // well-meaning "emit on any delete" overcorrection.
        await repo.syncFromGateway('inst-1', [_agent(localId: 'local-1')]);
        await repo.syncFromGateway('inst-2', [
          _agent(localId: 'local-2', remoteId: 'r-2', instanceId: 'inst-2'),
        ]);

        final emitted = <Agent?>[];
        final sub = repo.watchById('local-1').listen(emitted.add);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await repo.deleteByInstanceId('inst-2');

        await Future<void>.delayed(const Duration(milliseconds: 10));
        await sub.cancel();

        // local-1 should still be the last emit (post-seed) — no null
        // arrived from the unrelated inst-2 delete.
        expect(emitted.last, isNotNull);
        expect(emitted.last!.localId, 'local-1');
      },
    );

    test(
      'syncFromGateway tombstones local agents missing from remote list',
      () async {
        await repo.syncFromGateway('inst-1', [
          _agent(localId: 'local-1', remoteId: 'r-1'),
          _agent(localId: 'local-2', remoteId: 'r-2'),
        ]);

        await repo.syncFromGateway('inst-1', [
          _agent(localId: 'local-1', remoteId: 'r-1', name: '产品虾 v2'),
        ]);

        final removed = await repo.getById('local-2');
        expect(removed, isNotNull);
        expect(removed!.isRemoved, isTrue);
        expect(
          (await repo.getByInstanceId('inst-1')).map((a) => a.localId),
          ['local-1'],
          reason: '默认列表应过滤 tombstoned agent',
        );
        expect(
          (await repo.getAllByInstanceId('inst-1')).map((a) => a.localId),
          contains('local-2'),
          reason: 'getAllByInstanceId 按契约不过滤 tombstoned agent',
        );
      },
    );

    test(
      'syncFromGateway revives tombstoned agent when remote reappears',
      () async {
        await repo.syncFromGateway('inst-1', [
          _agent(localId: 'local-1', remoteId: 'r-1'),
          _agent(localId: 'local-2', remoteId: 'r-2'),
        ]);
        await repo.syncFromGateway('inst-1', [
          _agent(localId: 'local-1', remoteId: 'r-1'),
        ]);
        expect((await repo.getById('local-2'))!.isRemoved, isTrue);

        await repo.syncFromGateway('inst-1', [
          _agent(localId: 'local-1', remoteId: 'r-1'),
          _agent(localId: 'remote-local-ignored', remoteId: 'r-2', name: '复活虾'),
        ]);

        final revived = await repo.findByCompositeKey('inst-1', 'r-2');
        expect(revived, isNotNull);
        expect(revived!.localId, 'local-2', reason: '复活必须保留本地 localId 与历史消息关联');
        expect(revived.isRemoved, isFalse);
        expect(revived.name, '复活虾');
      },
    );

    test(
      'syncFromGateway with empty remote list tombstones all active agents',
      () async {
        await repo.syncFromGateway('inst-1', [
          _agent(localId: 'local-1', remoteId: 'r-1'),
          _agent(localId: 'local-2', remoteId: 'r-2'),
        ]);

        await repo.syncFromGateway('inst-1', const []);

        expect(await repo.getByInstanceId('inst-1'), isEmpty);
        final all = await repo.getAllByInstanceId('inst-1');
        expect(all, hasLength(2));
        expect(all.every((a) => a.isRemoved), isTrue);
      },
    );

    test(
      'syncFromGateway tombstone and revive emits watchById updates',
      () async {
        await repo.syncFromGateway('inst-1', [
          _agent(localId: 'local-1', remoteId: 'r-1'),
        ]);
        final emitted = <Agent?>[];
        final sub = repo.watchById('local-1').skip(1).listen(emitted.add);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await repo.syncFromGateway('inst-1', const []);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await repo.syncFromGateway('inst-1', [
          _agent(localId: 'ignored', remoteId: 'r-1'),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await sub.cancel();

        expect(emitted.length, greaterThanOrEqualTo(2));
        expect(emitted.any((a) => a != null && a.isRemoved), isTrue);
        expect(emitted.last, isNotNull);
        expect(emitted.last!.isRemoved, isFalse);
        expect(emitted.last!.localId, 'local-1');
      },
    );
  });
}
