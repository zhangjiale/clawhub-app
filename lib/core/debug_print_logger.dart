import 'package:flutter/foundation.dart';

import 'i_logger.dart';

/// [ILogger] 的生产环境实现 — 使用 [debugPrint] 输出。
///
/// [debugPrint] 在 release 模式中会被 Flutter 截断长消息并限流。
class DebugPrintLogger implements ILogger {
  const DebugPrintLogger();

  @override
  void info(String message) {
    debugPrint(message);
  }

  @override
  void error(String message, [StackTrace? stackTrace]) {
    debugPrint(message);
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
}
