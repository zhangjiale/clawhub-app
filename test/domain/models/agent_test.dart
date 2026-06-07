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
      expect(agent.themeColor, '#007AFF'); // 默认蓝色
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
}
