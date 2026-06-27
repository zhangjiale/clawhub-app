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
        QuickCommand(
          id: '1',
          agentId: 'a1',
          label: 'C',
          payload: '/c',
          sortOrder: 2,
        ),
        QuickCommand(
          id: '2',
          agentId: 'a1',
          label: 'A',
          payload: '/a',
          sortOrder: 0,
        ),
        QuickCommand(
          id: '3',
          agentId: 'a1',
          label: 'B',
          payload: '/b',
          sortOrder: 1,
        ),
      ];

      cmds.sort(QuickCommand.sortByOrder);

      expect(cmds[0].label, 'A');
      expect(cmds[1].label, 'B');
      expect(cmds[2].label, 'C');
    });
  });

  // Bug 1 修复新增:contentEquals 必须检出同 id 不同内容字段的差异。
  // 原 Agent.contentEquals → _quickCommandsEqual → QuickCommand.== 链条
  // 只比 id，导致 QuickCommandBar 在 label/payload/sortOrder 变更后不 rebuild。
  group('QuickCommand.contentEquals', () {
    QuickCommand base() => QuickCommand(
      id: 'qc-1',
      agentId: 'agent-local-1',
      label: '查看状态',
      payload: '/status',
      sortOrder: 0,
    );

    test('同 id + 全字段相同 → contentEquals 返回 true', () {
      expect(base().contentEquals(base()), isTrue);
    });

    test('同 id + 不同 label → contentEquals 返回 false', () {
      final a = base();
      final b = QuickCommand(
        id: 'qc-1',
        agentId: 'agent-local-1',
        label: '健康检查', // 不同
        payload: '/status',
        sortOrder: 0,
      );
      expect(a.contentEquals(b), isFalse);
    });

    test('同 id + 不同 payload → contentEquals 返回 false', () {
      final a = base();
      final b = QuickCommand(
        id: 'qc-1',
        agentId: 'agent-local-1',
        label: '查看状态',
        payload: '/health', // 不同
        sortOrder: 0,
      );
      expect(a.contentEquals(b), isFalse);
    });

    test('同 id + 不同 sortOrder → contentEquals 返回 false', () {
      final a = base();
      final b = QuickCommand(
        id: 'qc-1',
        agentId: 'agent-local-1',
        label: '查看状态',
        payload: '/status',
        sortOrder: 5, // 不同
      );
      expect(a.contentEquals(b), isFalse);
    });

    test('不同 id → contentEquals 返回 false', () {
      final a = base();
      final b = QuickCommand(
        id: 'qc-2', // 不同 id
        agentId: 'agent-local-1',
        label: '查看状态',
        payload: '/status',
        sortOrder: 0,
      );
      expect(a.contentEquals(b), isFalse);
    });

    test('不变量: == 仍只比 id (contentEquals 与 == 是两层语义)', () {
      // 验证 == 没被改成 content-aware —— 否则 Set<QuickCommand> 会按内容
      // 去重而不是按 id 去重（参见 MEMORY model-equals-identity-blindspot）。
      final a = base();
      final b = QuickCommand(
        id: 'qc-1',
        agentId: 'agent-local-1',
        label: '完全不同的 label',
        payload: '/other',
        sortOrder: 99,
      );
      expect(a == b, isTrue, reason: '== 应保持 identity-only');
      expect(
        a.contentEquals(b),
        isFalse,
        reason: 'contentEquals 必须检出 label/payload/sortOrder 差异',
      );
    });
  });
}
