/// Agent 统计数据（实时聚合值对象）
/// 对齐: 架构文档 5.2 (虾成长面板统计表), PRD 3.9 (虾成长面板)
///
/// 所有字段从原始消息/工具调用数据实时聚合计算，无缓存层。
class AgentStats {
  final String agentId;

  /// 总对话次数 = COUNT(DISTINCT conversation_id) FROM messages WHERE agent_id = ?
  final int totalDialogs;

  /// 总消息数 = COUNT(*) FROM messages WHERE agent_id = ?
  final int totalMessages;

  /// 工具调用总次数 = COUNT(*) FROM tool_calls JOIN messages
  final int totalToolCalls;

  /// 活跃天数 = COUNT(DISTINCT DATE(timestamp)) FROM messages WHERE agent_id = ?
  final int activeDays;

  /// 连续活跃天数（从最新消息日期向前连续计数）
  final int currentStreak;

  /// 首次对话日期（Unix 秒），null 表示尚无消息
  final int? firstDialogDate;

  /// 最近对话日期（Unix 秒），null 表示尚无消息
  final int? lastDialogDate;

  const AgentStats({
    required this.agentId,
    this.totalDialogs = 0,
    this.totalMessages = 0,
    this.totalToolCalls = 0,
    this.activeDays = 0,
    this.currentStreak = 0,
    this.firstDialogDate,
    this.lastDialogDate,
  });

  /// 当 agent 没有任何消息时的零统计快照
  factory AgentStats.empty(String agentId) => AgentStats(agentId: agentId);

  /// Create a copy with the given fields replaced.
  ///
  /// For [int] and [int?] fields: passing `null` means "keep the current
  /// value" (NOT "clear to null"). This is the same sentinel-less pattern
  /// used by [Achievement.copyWith] — null in = no change, not null in =
  /// replacement. If a sentinel-based clear-to-null is needed in the future,
  /// switch to [CopyWithSentinel].
  AgentStats copyWith({
    String? agentId,
    int? totalDialogs,
    int? totalMessages,
    int? totalToolCalls,
    int? activeDays,
    int? currentStreak,
    int? firstDialogDate,
    int? lastDialogDate,
  }) {
    return AgentStats(
      agentId: agentId ?? this.agentId,
      totalDialogs: totalDialogs ?? this.totalDialogs,
      totalMessages: totalMessages ?? this.totalMessages,
      totalToolCalls: totalToolCalls ?? this.totalToolCalls,
      activeDays: activeDays ?? this.activeDays,
      currentStreak: currentStreak ?? this.currentStreak,
      firstDialogDate: firstDialogDate ?? this.firstDialogDate,
      lastDialogDate: lastDialogDate ?? this.lastDialogDate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentStats &&
          runtimeType == other.runtimeType &&
          agentId == other.agentId &&
          totalDialogs == other.totalDialogs &&
          totalMessages == other.totalMessages &&
          totalToolCalls == other.totalToolCalls &&
          activeDays == other.activeDays &&
          currentStreak == other.currentStreak &&
          firstDialogDate == other.firstDialogDate &&
          lastDialogDate == other.lastDialogDate;

  @override
  int get hashCode => Object.hash(
    agentId,
    totalDialogs,
    totalMessages,
    totalToolCalls,
    activeDays,
    currentStreak,
    firstDialogDate,
    lastDialogDate,
  );

  @override
  String toString() =>
      'AgentStats(agentId: $agentId, totalDialogs: $totalDialogs, '
      'totalMessages: $totalMessages, totalToolCalls: $totalToolCalls, '
      'activeDays: $activeDays, currentStreak: $currentStreak)';
}
