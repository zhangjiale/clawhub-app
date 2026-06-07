import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

void main() {
  group('QuickCommand', () {
    test('创建有效快捷指令', () {
      final cmd = QuickCommand(
        id: 'qc-001',
        agentId: 'agent-local-1',
        label: '查看状态',
        payload: '/status',
        sortOrder: 0,
      );

      expect(cmd.id, 'qc-001');
      expect(cmd.agentId, 'agent-local-1');
      expect(cmd.label, '查看状态');
      expect(cmd.payload, '/status');
      expect(cmd.sortOrder, 0);
    });

    test('label 不能为空', () {
      expect(
        () => QuickCommand(
          id: 'qc-002',
          agentId: 'agent-local-1',
          label: '',
          payload: '/status',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('payload 不能为空', () {
      expect(
        () => QuickCommand(
          id: 'qc-003',
          agentId: 'agent-local-1',
          label: '查看状态',
          payload: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('label 最大 20 字符', () {
      final ok = QuickCommand(
        id: 'qc-004',
        agentId: 'agent-local-1',
        label: '12345678901234567890', // 20
        payload: '/cmd',
      );
      expect(ok.label.length, 20);

      expect(
        () => QuickCommand(
          id: 'qc-005',
          agentId: 'agent-local-1',
          label: '123456789012345678901', // 21
          payload: '/cmd',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('按 sortOrder 排序', () {
      final cmds = [
        QuickCommand(id: '1', agentId: 'a1', label: 'C', payload: '/c', sortOrder: 2),
        QuickCommand(id: '2', agentId: 'a1', label: 'A', payload: '/a', sortOrder: 0),
        QuickCommand(id: '3', agentId: 'a1', label: 'B', payload: '/b', sortOrder: 1),
      ];

      cmds.sort(QuickCommand.sortByOrder);

      expect(cmds[0].label, 'A');
      expect(cmds[1].label, 'B');
      expect(cmds[2].label, 'C');
    });
  });
}
