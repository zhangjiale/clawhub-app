/// 最短展示时间计时器。
///
/// `Future.wait([init, MinDisplayTimer.wait(800ms)])` 模式：
/// 让"初始化完成"和"最短展示时间已到"两个条件都满足才切到 app 阶段。
///
/// 抽成纯函数是为了让 widget test 用 `fake_async` 推进虚拟时钟，
/// 避免真实 `Future.delayed` 拖慢 CI。
class MinDisplayTimer {
  /// Wait at least [duration] before completing.
  static Future<void> wait(Duration duration) => Future<void>.delayed(duration);
}
