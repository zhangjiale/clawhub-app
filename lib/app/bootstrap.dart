import 'package:flutter/widgets.dart';

import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/data/local/database/database.dart';
import 'package:claw_hub/ui_kit/default_error_fallback.dart';

/// Signature of `Workmanager().initialize(...)` — extracted as a typedef so
/// [bootstrapApp] can be unit-tested without subclassing the final
/// `Workmanager` class (its constructor is `Workmanager._internal`).
typedef WorkmanagerInitializer = Future<void> Function();

/// `AppDatabase` constructor for [bootstrapApp]. Testable seam: production
/// passes `createAppDatabase`; tests can pass a fake that throws or returns
/// an in-memory `AppDatabase`.
typedef DatabaseFactory = Future<AppDatabase> Function();

/// Pre-`ProviderScope` logger — `const` to mirror the pattern used by
/// `lib/app/background_sync/callback_dispatcher.dart` for code that runs
/// outside a Riverpod scope.
const _logger = DebugPrintLogger();

/// Runs the pre-`runApp` startup chain with full error capture.
///
/// On success, [buildSuccess] is invoked with the opened database so the
/// caller can wrap it in a `ProviderScope` and call `runApp`.
///
/// On failure (any thrown error from [initializeWorkmanager] or
/// [createDatabase], or a synchronous error before any `await`), [showFatal]
/// is invoked with `(error, stackTrace)` so the caller can call
/// `runApp(StartupFatalScreen(...))`.
///
/// [buildSuccess] is responsible for calling `runApp` itself — this
/// function is `runApp`-free and therefore unit-testable under
/// `TestWidgetsFlutterBinding`.
Future<void> bootstrapApp({
  required WorkmanagerInitializer initializeWorkmanager,
  required DatabaseFactory createDatabase,
  required Widget Function(AppDatabase database) buildSuccess,
  required void Function(Object error, StackTrace stackTrace) showFatal,
}) async {
  try {
    await initializeWorkmanager();

    // Install the global error widget so any build-time error in the tree
    // (not just startup failures) is presented via the same UI.
    ErrorWidget.builder = (details) => DefaultErrorFallback(
      error: details.exception,
      stackTrace: details.stack,
    );

    final database = await createDatabase();
    runApp(buildSuccess(database));
  } catch (error, stackTrace) {
    _logger.error('[bootstrap] startup failed: $error', stackTrace);
    showFatal(error, stackTrace);
  }
}
