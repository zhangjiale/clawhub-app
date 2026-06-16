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
}
