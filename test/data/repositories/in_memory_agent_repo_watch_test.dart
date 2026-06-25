import 'dart:async';

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
  });
}
