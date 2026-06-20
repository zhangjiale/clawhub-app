/// 全局统计快照值对象 — 从实例、Agent、消息仓库聚合。
///
/// 被 [statsProvider] (app/di/providers.dart) 使用，
/// 同时被 agent_list 和 chat_room 两个 feature 消费。
/// 放在 domain/models/ 而非 app/di/ 以遵循 Clean Architecture 层级分离。
class StatsData {
  final int activeInstances;
  final int totalInstances;
  final int onlineAgents;
  final int totalAgents;
  final int totalMessages;

  const StatsData({
    required this.activeInstances,
    required this.totalInstances,
    required this.onlineAgents,
    required this.totalAgents,
    required this.totalMessages,
  });

  static const empty = StatsData(
    activeInstances: 0,
    totalInstances: 0,
    onlineAgents: 0,
    totalAgents: 0,
    totalMessages: 0,
  );
}
