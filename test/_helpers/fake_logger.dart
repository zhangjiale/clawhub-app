// No-op ILogger for tests that only need to *inject* a logger and never
// assert on its calls. Cheaper than a mocktail Mock — no allocation, no
// stub setup, no `verify()` calls needed.
//
// Use this when your test code only does `logger.error(...)` as a side
// effect and you want it to silently succeed. For tests that DO assert
// on logger behavior (e.g., that an error was logged), use a mocktail
// Mock<ILogger> instead so `verify(() => logger.error(...))` works.
//
// Pattern adopted from existing _FakeLogger in:
//   - test/data/services/notification_dispatcher_test.dart:13
//   - test/app/notifications/notification_coordinator_test.dart:21
//   - test/domain/usecases/message_catch_up_service_test.dart:19
//   - test/domain/usecases/outbox_processor_test.dart:22
//
// Hoisted to a shared file so the four agent_profile tests can reuse it
// without each declaring its own 8-line no-op.

import 'package:claw_hub/core/i_logger.dart';

class FakeLogger implements ILogger {
  const FakeLogger();

  @override
  void info(String message) {}

  @override
  void error(String message, [StackTrace? stackTrace]) {}
}
