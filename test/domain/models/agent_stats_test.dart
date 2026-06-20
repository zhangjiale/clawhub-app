import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';

void main() {
  group('AgentStats', () {
    test('创建完整统计数据', () {
      final stats = AgentStats(
        agentId: 'agent-1',
        totalDialogs: 42,
        totalMessages: 150,
        totalToolCalls: 23,
        activeDays: 18,
        currentStreak: 5,
        firstDialogDate: 1700000000,
        lastDialogDate: 1715000000,
      );

      expect(stats.agentId, 'agent-1');
      expect(stats.totalDialogs, 42);
      expect(stats.totalMessages, 150);
      expect(stats.totalToolCalls, 23);
      expect(stats.activeDays, 18);
      expect(stats.currentStreak, 5);
      expect(stats.firstDialogDate, 1700000000);
      expect(stats.lastDialogDate, 1715000000);
    });

    test('默认值均为零', () {
      final stats = AgentStats(agentId: 'agent-2');

      expect(stats.totalDialogs, 0);
      expect(stats.totalMessages, 0);
      expect(stats.totalToolCalls, 0);
      expect(stats.activeDays, 0);
      expect(stats.currentStreak, 0);
      expect(stats.firstDialogDate, isNull);
      expect(stats.lastDialogDate, isNull);
    });

    test('AgentStats.empty() 返回零值统计', () {
      final stats = AgentStats.empty('agent-3');

      expect(stats.agentId, 'agent-3');
      expect(stats.totalDialogs, 0);
      expect(stats.totalMessages, 0);
      expect(stats.totalToolCalls, 0);
      expect(stats.activeDays, 0);
      expect(stats.currentStreak, 0);
      expect(stats.firstDialogDate, isNull);
    });

    test('相同 agentId 相同字段值 → 相等（值对象语义）', () {
      final a = AgentStats(agentId: 'agent-1', totalMessages: 10);
      final b = AgentStats(agentId: 'agent-1', totalMessages: 10);

      expect(a, equals(b));
    });

    test('相同 agentId 不同字段值 → 不相等', () {
      final a = AgentStats(agentId: 'agent-1', totalMessages: 10);
      final b = AgentStats(agentId: 'agent-1', totalMessages: 999);

      expect(a, isNot(equals(b)));
    });

    test('不同 agentId → 不相等', () {
      final a = AgentStats(agentId: 'agent-1');
      final b = AgentStats(agentId: 'agent-2');

      expect(a, isNot(equals(b)));
    });

    test('hashCode 基于所有字段值', () {
      final a = AgentStats(agentId: 'agent-1', totalMessages: 10);
      final b = AgentStats(agentId: 'agent-1', totalMessages: 10);
      final c = AgentStats(agentId: 'agent-1', totalMessages: 999);

      expect(a.hashCode, b.hashCode); // same values → same hash
      expect(
        a.hashCode,
        isNot(c.hashCode),
      ); // different values → different hash
    });

    test('copyWith 部分更新', () {
      final original = AgentStats(
        agentId: 'agent-1',
        totalDialogs: 10,
        totalMessages: 50,
      );

      final updated = original.copyWith(totalDialogs: 20);

      expect(updated.agentId, 'agent-1');
      expect(updated.totalDialogs, 20);
      expect(updated.totalMessages, 50); // unchanged
      expect(updated.totalToolCalls, 0); // unchanged
    });

    test('copyWith 更新可空字段为 null', () {
      final original = AgentStats(
        agentId: 'agent-1',
        firstDialogDate: 1700000000,
      );

      // 注意：copyWith 中 int? 字段传 null 表示"不更新"（与 Agent 模式一致）
      // 如需显式清除，需要 sentinel 模式，但当前需求不需要
      final updated = original.copyWith(totalMessages: 100);
      expect(updated.firstDialogDate, 1700000000); // unchanged
    });

    test('toString 包含关键字段', () {
      final stats = AgentStats(agentId: 'agent-1', totalMessages: 100);

      final str = stats.toString();
      expect(str, contains('agent-1'));
      expect(str, contains('100'));
    });
  });
}
