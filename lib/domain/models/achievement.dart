// 成就系统领域模型
// 对齐: 架构文档 5.2 (成就模型), PRD 3.9 (虾成长面板)

import 'agent_stats.dart';

/// 成就等级
enum AchievementTier {
  /// 金 — 高难度里程碑
  gold,

  /// 银 — 中等难度里程碑
  silver,

  /// 铜 — 入门/基础里程碑
  bronze,
}

/// Display ordering for [AchievementTier] (gold first, bronze last).
extension AchievementTierOrder on AchievementTier {
  int get order => switch (this) {
    AchievementTier.gold => 2,
    AchievementTier.silver => 1,
    AchievementTier.bronze => 0,
  };
}

/// 成就定义（不可变，预设在代码中，不可序列化）
///
/// [condition] 是纯函数，接收 [AgentStats] 返回是否满足解锁条件。
/// 注意：此字段为函数闭包，不可序列化 — 定义硬编码为常量列表。
class AchievementDefinition {
  final String id;
  final String icon;
  final String name;
  final String description;
  final AchievementTier tier;
  final bool Function(AgentStats) condition; // NOT serializable

  const AchievementDefinition({
    required this.id,
    required this.icon,
    required this.name,
    required this.description,
    required this.tier,
    required this.condition,
  });
}

/// 成就实例 — 包含解锁状态
///
/// 由 [AchievementDefinition] + 解锁记录合并而成。
class Achievement {
  final String id;
  final String icon;
  final String name;
  final String description;
  final AchievementTier tier;
  final bool unlocked;
  final int? unlockedAt; // Unix 秒，未解锁时为 null

  const Achievement({
    required this.id,
    required this.icon,
    required this.name,
    required this.description,
    required this.tier,
    required this.unlocked,
    this.unlockedAt,
  });

  Achievement copyWith({
    String? id,
    String? icon,
    String? name,
    String? description,
    AchievementTier? tier,
    bool? unlocked,
    int? unlockedAt,
  }) {
    return Achievement(
      id: id ?? this.id,
      icon: icon ?? this.icon,
      name: name ?? this.name,
      description: description ?? this.description,
      tier: tier ?? this.tier,
      unlocked: unlocked ?? this.unlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Achievement &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          unlocked == other.unlocked &&
          unlockedAt == other.unlockedAt;

  @override
  int get hashCode => Object.hash(id, unlocked, unlockedAt);

  @override
  String toString() =>
      'Achievement(id: $id, name: $name, tier: $tier, unlocked: $unlocked)';
}

// ============================================================================
// 预设成就定义
// ============================================================================

/// 8 个预设成就定义。
///
/// 条件函数为纯函数，从 [AgentStats] 判定是否满足。
/// 定义顺序按大致解锁难度排列。
const presetAchievementDefinitions = [
  AchievementDefinition(
    id: 'first_dialog',
    icon: '🏆',
    name: '初次对话',
    description: '与虾完成第一次对话',
    tier: AchievementTier.gold,
    condition: _condFirstDialog,
  ),
  AchievementDefinition(
    id: 'hundred_dialogs',
    icon: '💬',
    name: '百次对话',
    description: '累计完成100次对话',
    tier: AchievementTier.gold,
    condition: _condHundredDialogs,
  ),
  AchievementDefinition(
    id: 'thousand_dialogs',
    icon: '👑',
    name: '千次对话',
    description: '累计完成1000次对话',
    tier: AchievementTier.gold,
    condition: _condThousandDialogs,
  ),
  AchievementDefinition(
    id: 'streak_7',
    icon: '🔥',
    name: '连续活跃7天',
    description: '连续7天与虾对话',
    tier: AchievementTier.silver,
    condition: _condStreak7,
  ),
  AchievementDefinition(
    id: 'streak_30',
    icon: '🌟',
    name: '月度伙伴',
    description: '连续30天与虾对话',
    tier: AchievementTier.gold,
    condition: _condStreak30,
  ),
  AchievementDefinition(
    id: 'tool_50',
    icon: '🛠️',
    name: '工具达人',
    description: '虾累计使用工具50次',
    tier: AchievementTier.silver,
    condition: _condTool50,
  ),
  AchievementDefinition(
    id: 'tool_200',
    icon: '⚙️',
    name: '工具大师',
    description: '虾累计使用工具200次',
    tier: AchievementTier.gold,
    condition: _condTool200,
  ),
  AchievementDefinition(
    id: 'msg_1000',
    icon: '💎',
    name: '千条消息',
    description: '累计发送和接收1000条消息',
    tier: AchievementTier.silver,
    condition: _condMsg1000,
  ),
];

// -- condition functions (pure, no side effects) --

bool _condFirstDialog(AgentStats s) => s.totalDialogs >= 1;
bool _condHundredDialogs(AgentStats s) => s.totalDialogs >= 100;
bool _condThousandDialogs(AgentStats s) => s.totalDialogs >= 1000;
bool _condStreak7(AgentStats s) => s.currentStreak >= 7;
bool _condStreak30(AgentStats s) => s.currentStreak >= 30;
bool _condTool50(AgentStats s) => s.totalToolCalls >= 50;
bool _condTool200(AgentStats s) => s.totalToolCalls >= 200;
bool _condMsg1000(AgentStats s) => s.totalMessages >= 1000;

// ============================================================================
// 纯函数 — 成就评估
// ============================================================================

/// 评估哪些新成就应被解锁。
///
/// 对每个预设定义执行 [condition]，过滤出：
/// 1. [stats] 满足条件
/// 2. 尚未在 [alreadyUnlockedIds] 中
///
/// 返回新解锁的 [AchievementDefinition] 列表（可能为空）。
List<AchievementDefinition> evaluateNewAchievements(
  AgentStats stats,
  Set<String> alreadyUnlockedIds,
) {
  final newDefs = <AchievementDefinition>[];
  for (final def in presetAchievementDefinitions) {
    if (!alreadyUnlockedIds.contains(def.id) && def.condition(stats)) {
      newDefs.add(def);
    }
  }
  return newDefs;
}

/// 从定义列表 + 已解锁 ID 集合 + 解锁时间映射构建 [Achievement] 列表。
///
/// 所有 8 个成就均返回（locked + unlocked），按 tier 降序排列（gold 在前），
/// 同 tier 内 unlocked 的在前。
List<Achievement> buildAchievementList(
  Set<String> unlockedIds,
  Map<String, int> unlockedAtMap,
) {
  final achievements = <Achievement>[];
  for (final def in presetAchievementDefinitions) {
    final isUnlocked = unlockedIds.contains(def.id);
    achievements.add(
      Achievement(
        id: def.id,
        icon: def.icon,
        name: def.name,
        description: def.description,
        tier: def.tier,
        unlocked: isUnlocked,
        unlockedAt: unlockedAtMap[def.id],
      ),
    );
  }
  // Sort: gold > silver > bronze, then unlocked first within same tier
  achievements.sort((a, b) {
    final tierCmp = b.tier.order.compareTo(a.tier.order);
    if (tierCmp != 0) return tierCmp;
    if (a.unlocked != b.unlocked) return a.unlocked ? -1 : 1;
    return 0;
  });
  return achievements;
}
