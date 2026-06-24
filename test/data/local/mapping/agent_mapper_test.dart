// US-021: AgentMapper 双向映射测试 —— 验证 removed_at / hidden_at 列
// 正确映射到 domain Agent.removedAt / hiddenAt（含 null 与非 null 两种）。
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/local/mapping/agent_mapper.dart';

void main() {
  group('AgentMapper.toDomain tombstone columns (US-021)', () {
    // 构造一个最小可用的 drift row。removed_at / hidden_at 由各用例单独指定。
    db.Agent row({int? removedAt, int? hiddenAt}) => db.Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      nickname: null,
      avatarUrl: null,
      themeColor: '#4F83FF',
      quickCommandsJson: null,
      description: null,
      isPinned: 0,
      createdAt: 1719200000,
      removedAt: removedAt,
      hiddenAt: hiddenAt,
    );

    test('removed_at / hidden_at 均为 NULL 时映射为 null', () {
      final agent = AgentMapper.toDomain(row());
      expect(agent.removedAt, isNull);
      expect(agent.hiddenAt, isNull);
      expect(agent.isRemoved, isFalse);
      expect(agent.isHidden, isFalse);
    });

    test('removed_at 非空时映射到 removedAt，isRemoved 为 true', () {
      final agent = AgentMapper.toDomain(row(removedAt: 1719200000000));
      expect(agent.removedAt, 1719200000000);
      expect(agent.isRemoved, isTrue);
      expect(agent.hiddenAt, isNull);
    });

    test('hidden_at 非空时映射到 hiddenAt，isHidden 为 true', () {
      final agent = AgentMapper.toDomain(row(hiddenAt: 1719300000000));
      expect(agent.hiddenAt, 1719300000000);
      expect(agent.isHidden, isTrue);
      expect(agent.removedAt, isNull);
    });

    test('removed_at 与 hidden_at 同时非空时正交映射', () {
      final agent = AgentMapper.toDomain(
        row(removedAt: 1719200000000, hiddenAt: 1719300000000),
      );
      expect(agent.removedAt, 1719200000000);
      expect(agent.hiddenAt, 1719300000000);
      expect(agent.isRemoved, isTrue);
      expect(agent.isHidden, isTrue);
    });

    test('其他字段不受 tombstone 列影响', () {
      final agent = AgentMapper.toDomain(row(removedAt: 1719200000000));
      expect(agent.localId, 'local-1');
      expect(agent.name, '产品虾');
      expect(agent.themeColor, '#4F83FF');
      expect(agent.isPinned, isFalse);
    });
  });
}
