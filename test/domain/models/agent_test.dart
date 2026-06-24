import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent.dart';

void main() {
  group('Agent', () {
    test('创建有效 Agent（复合键方案）', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'remote-001',
        instanceId: 'inst-001',
        name: '产品虾',
      );

      expect(agent.localId, 'local-a1');
      expect(agent.remoteId, 'remote-001');
      expect(agent.instanceId, 'inst-001');
      expect(agent.name, '产品虾');
      expect(agent.nickname, isNull); // 可选字段
      expect(agent.avatarUrl, isNull);
      expect(agent.themeColor, '#4F83FF'); // V2 sapphire 默认色
      expect(agent.isPinned, isFalse);
    });

    test('同一实例同一 remoteId 视为相同 Agent', () {
      final a1 = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      final a2 = Agent(
        localId: 'local-a2',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾（改名）',
      );

      // 同一 (instanceId, remoteId) 组合应视为同一 Agent
      expect(a1.isSameAgent(a2), isTrue);
    });

    test('不同实例同 remoteId 视为不同 Agent', () {
      final a1 = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      final a2 = Agent(
        localId: 'local-a2',
        remoteId: 'r1',
        instanceId: 'inst-002',
        name: '产品虾',
      );

      expect(a1.isSameAgent(a2), isFalse);
    });

    test('主题色格式校验', () {
      // 有效 Hex 颜色
      final validColors = ['#007AFF', '#6c5ce7', '#00b894', '#FF0000', '#abc'];
      for (final color in validColors) {
        final agent = Agent(
          localId: 'local-test',
          remoteId: 'r-test',
          instanceId: 'inst-001',
          name: '测试虾',
          themeColor: color,
        );
        expect(agent.themeColor, color);
      }
    });

    test('无效主题色应抛异常', () {
      expect(
        () => Agent(
          localId: 'local-test',
          remoteId: 'r-test',
          instanceId: 'inst-001',
          name: '测试虾',
          themeColor: 'blue', // 不是 Hex 格式
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('名称为空应抛异常', () {
      expect(
        () => Agent(
          localId: 'local-test',
          remoteId: 'r-test',
          instanceId: 'inst-001',
          name: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('昵称最大20字符', () {
      final validNick = Agent(
        localId: 'local-test',
        remoteId: 'r-test',
        instanceId: 'inst-001',
        name: '测试虾',
        nickname: '12345678901234567890', // 正好20字
      );
      expect(validNick.nickname!.length, 20);

      expect(
        () => Agent(
          localId: 'local-test2',
          remoteId: 'r-test2',
          instanceId: 'inst-001',
          name: '测试虾',
          nickname: '123456789012345678901', // 21字
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('description 可选字段默认为 null', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      expect(agent.description, isNull);
    });

    test('copyWith 保留 description 字段', () {
      final original = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        description: '产品规划、需求分析',
      );
      expect(original.description, '产品规划、需求分析');

      final updated = original.copyWith(name: '新名称');
      expect(updated.description, '产品规划、需求分析'); // 未被覆盖
    });

    test('copyWith 正确创建修改副本', () {
      final original = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );

      final updated = original.copyWith(
        nickname: '我的小虾',
        themeColor: '#FF0000',
        isPinned: true,
      );

      expect(updated.localId, original.localId);
      expect(updated.nickname, '我的小虾');
      expect(updated.themeColor, '#FF0000');
      expect(updated.isPinned, isTrue);
      expect(updated.name, original.name); // 未修改
    });
  });

  // US-021: Agent tombstone 状态。removed_at / hidden_at 由
  // DriftAgentRepo.syncFromGateway 通过 DB 独占写入（不经过 copyWith），
  // 此处只验证 domain 层的只读语义。
  group('Agent tombstone state (US-021)', () {
    Agent baseAgent() => Agent(
      localId: 'local-a1',
      remoteId: 'r1',
      instanceId: 'inst-001',
      name: '产品虾',
    );

    test('默认构造的 Agent 既未移除也未隐藏', () {
      final agent = baseAgent();
      expect(agent.removedAt, isNull);
      expect(agent.hiddenAt, isNull);
      expect(agent.isRemoved, isFalse);
      expect(agent.isHidden, isFalse);
    });

    test('removedAt 非空时 isRemoved 为 true', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
      );
      expect(agent.removedAt, 1719200000000);
      expect(agent.isRemoved, isTrue);
      expect(agent.isHidden, isFalse); // hiddenAt 仍 null
    });

    test('hiddenAt 非空时 isHidden 为 true', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        hiddenAt: 1719200000000,
      );
      expect(agent.hiddenAt, 1719200000000);
      expect(agent.isHidden, isTrue);
      expect(agent.isRemoved, isFalse); // removedAt 仍 null
    });

    test('removedAt 与 hiddenAt 可同时非空（正交状态）', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
        hiddenAt: 1719300000000,
      );
      expect(agent.isRemoved, isTrue);
      expect(agent.isHidden, isTrue);
    });

    test('copyWith 不暴露 removedAt/hiddenAt 参数，透传保留 tombstone 状态', () {
      // copyWith 故意不暴露 removedAt/hiddenAt（防 ?? old 清空坑，见 spec §3.3）。
      // 改其他字段时，tombstone 状态必须被透传保留。
      final tombstoned = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        removedAt: 1719200000000,
        hiddenAt: 1719300000000,
      );

      final updated = tombstoned.copyWith(name: '改名后的虾');

      expect(updated.name, '改名后的虾');
      // tombstone 状态被透传，未被清空
      expect(updated.removedAt, 1719200000000);
      expect(updated.hiddenAt, 1719300000000);
      expect(updated.isRemoved, isTrue);
      expect(updated.isHidden, isTrue);
    });
  });
}
