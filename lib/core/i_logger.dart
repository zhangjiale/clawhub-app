/// 日志接口 — 面向接口编程，使 domain 层可以不依赖 Flutter 而输出日志。
///
/// [print] 和 [debugPrint] 在 domain 层不可用（违反 Iron Law 1），
/// 但 use case 需要输出错误信息。此接口提供一个抽象层。
///
/// 生产环境使用 [DebugPrintLogger]，测试环境可注入 fake。
abstract class ILogger {
  /// 输出信息级别日志。
  void info(String message);

  /// 输出错误级别日志（含堆栈）。
  void error(String message, [StackTrace? stackTrace]);
}
