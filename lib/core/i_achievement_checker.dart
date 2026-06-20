/// 成就检查服务抽象接口。
///
/// 使 features 层可以不依赖 data/services/ 的具体实现。
/// 生产环境用 [AchievementChecker]，测试环境可注入 fake。
abstract interface class IAchievementChecker {
  /// 触发 fire-and-forget 成就重新评估。不阻塞调用方。
  void check(String agentId);
}
