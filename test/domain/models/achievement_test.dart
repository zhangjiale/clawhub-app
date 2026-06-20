import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/achievement.dart';

void main() {
  group('Achievement', () {
    test('创建已解锁成就', () {
      final achievement = Achievement(
        id: 'first_dialog',
        icon: '🏆',
        name: '初次对话',
        description: '与虾完成第一次对话',
        tier: AchievementTier.gold,
        unlocked: true,
        unlockedAt: 1715000000,
      );

      expect(achievement.id, 'first_dialog');
      expect(achievement.icon, '🏆');
      expect(achievement.name, '初次对话');
      expect(achievement.tier, AchievementTier.gold);
      expect(achievement.unlocked, isTrue);
      expect(achievement.unlockedAt, 1715000000);
    });

    test('创建未解锁成就', () {
      final achievement = Achievement(
        id: 'streak_30',
        icon: '🌟',
        name: '月度伙伴',
        description: '连续30天与虾对话',
        tier: AchievementTier.gold,
        unlocked: false,
      );

      expect(achievement.unlocked, isFalse);
      expect(achievement.unlockedAt, isNull);
    });

    test('相同 id + unlocked + unlockedAt 相等', () {
      final a = Achievement(
        id: 'first_dialog',
        icon: '🏆',
        name: '初次对话',
        description: 'desc',
        tier: AchievementTier.gold,
        unlocked: true,
        unlockedAt: 100,
      );
      final b = Achievement(
        id: 'first_dialog',
        icon: '🏆',
        name: '初次对话',
        description: 'desc',
        tier: AchievementTier.gold,
        unlocked: true,
        unlockedAt: 100,
      );

      expect(a, equals(b));
    });

    test('不同解锁状态不相等', () {
      final locked = Achievement(
        id: 'first_dialog',
        icon: '🏆',
        name: '初次对话',
        description: 'desc',
        tier: AchievementTier.gold,
        unlocked: false,
      );
      final unlocked = Achievement(
        id: 'first_dialog',
        icon: '🏆',
        name: '初次对话',
        description: 'desc',
        tier: AchievementTier.gold,
        unlocked: true,
        unlockedAt: 100,
      );

      expect(locked, isNot(equals(unlocked)));
    });

    test('copyWith 更新解锁状态', () {
      final original = Achievement(
        id: 'first_dialog',
        icon: '🏆',
        name: '初次对话',
        description: 'desc',
        tier: AchievementTier.gold,
        unlocked: false,
      );

      final unlocked = original.copyWith(
        unlocked: true,
        unlockedAt: 1715000000,
      );

      expect(unlocked.unlocked, isTrue);
      expect(unlocked.unlockedAt, 1715000000);
      expect(unlocked.id, original.id); // unchanged
      expect(unlocked.name, original.name); // unchanged
    });

    test('toString 包含关键信息', () {
      final achievement = Achievement(
        id: 'first_dialog',
        icon: '🏆',
        name: '初次对话',
        description: 'desc',
        tier: AchievementTier.gold,
        unlocked: false,
      );

      final str = achievement.toString();
      expect(str, contains('first_dialog'));
      expect(str, contains('初次对话'));
      expect(str, contains('false'));
    });
  });

  group('AchievementTier', () {
    test('三个等级', () {
      expect(AchievementTier.values.length, 3);
      expect(AchievementTier.values, contains(AchievementTier.gold));
      expect(AchievementTier.values, contains(AchievementTier.silver));
      expect(AchievementTier.values, contains(AchievementTier.bronze));
    });
  });

  group('evaluateNewAchievements', () {
    test('初次对话返回 first_dialog', () {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1,
        totalMessages: 1,
      );
      final result = evaluateNewAchievements(stats, {});

      expect(result.length, 1);
      expect(result.first.id, 'first_dialog');
    });

    test('无消息时不返回任何成就', () {
      final stats = AgentStats(agentId: 'a1');
      final result = evaluateNewAchievements(stats, {});

      expect(result, isEmpty);
    });

    test('多条消息触发 first_dialog + msg 相关', () {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1,
        totalMessages: 5,
      );
      final result = evaluateNewAchievements(stats, {});

      expect(result.any((d) => d.id == 'first_dialog'), isTrue);
      // 5 messages don't hit msg_1000
      expect(result.any((d) => d.id == 'msg_1000'), isFalse);
    });

    test('1000 条消息触发 msg_1000', () {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 50,
        totalMessages: 1000,
      );
      final result = evaluateNewAchievements(stats, {});

      expect(result.any((d) => d.id == 'msg_1000'), isTrue);
      expect(result.any((d) => d.id == 'first_dialog'), isTrue);
    });

    test('连续 7 天触发 streak_7', () {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1,
        currentStreak: 7,
      );
      final result = evaluateNewAchievements(stats, {});

      expect(result.any((d) => d.id == 'streak_7'), isTrue);
      expect(result.any((d) => d.id == 'first_dialog'), isTrue);
    });

    test('连续 30 天同时触发 streak_7 和 streak_30', () {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1,
        currentStreak: 30,
      );
      final result = evaluateNewAchievements(stats, {});

      expect(result.any((d) => d.id == 'streak_7'), isTrue);
      expect(result.any((d) => d.id == 'streak_30'), isTrue);
    });

    test('50 次工具调用触发 tool_50', () {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1,
        totalToolCalls: 50,
      );
      final result = evaluateNewAchievements(stats, {});

      expect(result.any((d) => d.id == 'tool_50'), isTrue);
      expect(result.any((d) => d.id == 'tool_200'), isFalse);
    });

    test('200 次工具调用同时触发 tool_50 和 tool_200', () {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1,
        totalToolCalls: 200,
      );
      final result = evaluateNewAchievements(stats, {});

      expect(result.any((d) => d.id == 'tool_50'), isTrue);
      expect(result.any((d) => d.id == 'tool_200'), isTrue);
    });

    test('已解锁的不再返回', () {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1,
        currentStreak: 7,
      );
      final result = evaluateNewAchievements(stats, {'first_dialog'});

      // first_dialog already unlocked, should not appear
      expect(result.any((d) => d.id == 'first_dialog'), isFalse);
      // streak_7 still new
      expect(result.any((d) => d.id == 'streak_7'), isTrue);
    });

    test('所有成就都已解锁时返回空列表', () {
      final stats = AgentStats(
        agentId: 'a1',
        totalDialogs: 1000,
        totalMessages: 1000,
        totalToolCalls: 200,
        currentStreak: 30,
      );
      final allIds = presetAchievementDefinitions.map((d) => d.id).toSet();
      final result = evaluateNewAchievements(stats, allIds);

      expect(result, isEmpty);
    });
  });

  group('buildAchievementList', () {
    test('返回全部 8 个成就', () {
      final list = buildAchievementList({}, {});

      expect(list.length, 8);
    });

    test('已解锁的标记为 unlocked=true', () {
      final list = buildAchievementList(
        {'first_dialog'},
        {'first_dialog': 100},
      );

      final fd = list.firstWhere((a) => a.id == 'first_dialog');
      expect(fd.unlocked, isTrue);
      expect(fd.unlockedAt, 100);

      final others = list.where((a) => a.id != 'first_dialog');
      for (final a in others) {
        expect(a.unlocked, isFalse);
      }
    });

    test('gold 排在 silver 前面', () {
      final list = buildAchievementList({'first_dialog', 'streak_7'}, {});

      final goldIndices = <int>[];
      final silverIndices = <int>[];
      for (var i = 0; i < list.length; i++) {
        if (list[i].tier == AchievementTier.gold) goldIndices.add(i);
        if (list[i].tier == AchievementTier.silver) silverIndices.add(i);
      }

      // All gold indices should be less than all silver indices
      if (goldIndices.isNotEmpty && silverIndices.isNotEmpty) {
        expect(goldIndices.last, lessThan(silverIndices.first));
      }
    });
  });
}
