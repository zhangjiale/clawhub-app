import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

void main() {
  group('InMemoryAgentRepo.updateFullProfile quickCommands', () {
    late InMemoryAgentRepo repo;
    late Agent agent;

    setUp(() async {
      repo = InMemoryAgentRepo();
      agent = Agent(
        localId: 'local-1',
        remoteId: 'remote-1',
        instanceId: 'inst-1',
        name: '产品虾',
        nickname: '小产品',
        avatarUrl: '/tmp/avatar.jpg',
        themeColor: '#6C8AAF',
      );
      await repo.syncFromGateway('inst-1', [agent]);
    });

    test('writes and reads quick commands with normalized sortOrder', () async {
      await repo.updateFullProfile(
        'local-1',
        quickCommands: [
          QuickCommand(
            id: '2',
            agentId: 'local-1',
            label: '记忆',
            payload: '/memory',
            sortOrder: 1,
          ),
          QuickCommand(
            id: '1',
            agentId: 'local-1',
            label: '状态',
            payload: '/status',
            sortOrder: 0,
          ),
        ],
      );

      final updated = await repo.getById('local-1');
      expect(updated!.quickCommands.map((c) => c.id), ['1', '2']);
      expect(updated.quickCommands.map((c) => c.sortOrder), [0, 1]);
    });

    test('empty list clears quick commands', () async {
      await repo.updateFullProfile(
        'local-1',
        quickCommands: [
          QuickCommand(
            id: '1',
            agentId: 'local-1',
            label: '状态',
            payload: '/status',
          ),
        ],
      );
      await repo.updateFullProfile('local-1', quickCommands: []);

      final updated = await repo.getById('local-1');
      expect(updated!.quickCommands, isEmpty);
    });

    test('preserves other local profile fields', () async {
      await repo.updateFullProfile(
        'local-1',
        quickCommands: [
          QuickCommand(
            id: '1',
            agentId: 'local-1',
            label: '状态',
            payload: '/status',
          ),
        ],
      );

      final updated = await repo.getById('local-1');
      expect(updated!.name, '产品虾');
      expect(updated.nickname, '小产品');
      expect(updated.avatarUrl, '/tmp/avatar.jpg');
      expect(updated.themeColor, '#6C8AAF');
    });
  });

  // US-021: InMemory 实现必须与 Drift 实现的过滤契约一致
  // (DriftAgentRepo.getByInstanceId 已过滤 tombstoned/hidden,
  //  InMemoryAgentRepo.getByInstanceId 必须同样过滤,
  //  否则测试套件与生产行为脱节)。
  group('InMemoryAgentRepo tombstone filter parity with Drift (US-021)', () {
    // 注：syncFromGateway 第一次插入时 _putAgent(remote) 直接使用 remote 对象的
    // 全部字段（含 removedAt）。后续 sync 走 copyWith 路径不会改 removedAt
    // （这是 US-021 spec §3.3 的"防 ?? 坑"语义）。所以最直接的 tombstone
    // 注入方式是首次 sync 就传带 removedAt 的 Agent。
    test(
      'getByInstanceId excludes tombstoned agents (parity with Drift)',
      () async {
        final repo = InMemoryAgentRepo();
        final tombstonedAt = DateTime.now().millisecondsSinceEpoch;
        await repo.syncFromGateway('inst-1', [
          Agent(
            localId: 'local-a',
            remoteId: 'r-a',
            instanceId: 'inst-1',
            name: 'A',
            removedAt: tombstonedAt,
          ),
          Agent(
            localId: 'local-c',
            remoteId: 'r-c',
            instanceId: 'inst-1',
            name: 'C',
          ),
        ]);

        final byInst = await repo.getByInstanceId('inst-1');
        final ids = byInst.map((a) => a.localId).toSet();
        expect(
          ids,
          {'local-c'},
          reason:
              'tombstoned agent (A) 必须在 getByInstanceId 结果中被过滤'
              ' (对齐 DriftAgentRepo.getActiveAgentsByInstance 语义)',
        );
        expect(byInst.every((a) => !a.isRemoved), isTrue);
      },
    );

    test('getAll excludes tombstoned agents (parity with Drift)', () async {
      final repo = InMemoryAgentRepo();
      await repo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-a',
          remoteId: 'r-a',
          instanceId: 'inst-1',
          name: 'A',
        ),
        Agent(
          localId: 'local-b',
          remoteId: 'r-b',
          instanceId: 'inst-1',
          name: 'B',
          removedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

      final all = await repo.getAll();
      final ids = all.map((a) => a.localId).toSet();
      expect(ids, {'local-a'}, reason: 'tombstoned B 必须从 getAll 过滤');
      expect(all.every((a) => !a.isRemoved), isTrue);
    });

    test('getAllByInstanceId returns ALL agents including tombstoned '
        '(unfiltered variant for host-change warning)', () async {
      final repo = InMemoryAgentRepo();
      await repo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-a',
          remoteId: 'r-a',
          instanceId: 'inst-1',
          name: 'A',
        ),
        Agent(
          localId: 'local-b',
          remoteId: 'r-b',
          instanceId: 'inst-1',
          name: 'B',
          removedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

      final all = await repo.getAllByInstanceId('inst-1');
      final ids = all.map((a) => a.localId).toSet();
      expect(
        ids,
        {'local-a', 'local-b'},
        reason:
            'getAllByInstanceId 不过滤 tombstoned,'
            '用于 SaveInstanceUseCase host 切换警告',
      );
    });

    test(
      'getById returns tombstoned agent (unfiltered — OutboxProcessor contract)',
      () async {
        final repo = InMemoryAgentRepo();
        await repo.syncFromGateway('inst-1', [
          Agent(
            localId: 'local-b',
            remoteId: 'r-b',
            instanceId: 'inst-1',
            name: 'B',
            removedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ]);

        final b = await repo.getById('local-b');
        expect(b, isNotNull);
        expect(b!.isRemoved, isTrue);
      },
    );
  });
}
