import 'dart:async';

/// 成就检查服务抽象接口。
///
/// 使 features 层可以不依赖 data/services/ 的具体实现。
/// 生产环境用 [AchievementChecker]，测试环境可注入 fake。
abstract interface class IAchievementChecker {
  /// 触发 fire-and-forget 成就重新评估。不阻塞调用方。
  void check(String agentId);

  /// 当 [check] 触发的重新评估成功完成后，发出的 agentId 广播流。
  ///
  /// 订阅者（例如 [AgentProfileViewModel]）可以在该 agent 的 stats/成就
  /// 被异步刷新后，自己重新加载页面快照——否则 profile 页只在 init() 时
  /// 取一次数据，新消息到达后用户看到陈旧的全 0 状态。
  ///
  /// 失败时**不**发事件（让下一条消息自然触发另一次 [check] 重试）。
  /// 失败重试由 [check] 的防抖 + 下一条消息保证，不需要在这里堆积失败事件。
  Stream<String> get updates;
}
