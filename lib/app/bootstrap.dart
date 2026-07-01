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
/// On success, calls `runApp([buildSuccess](database))`: [buildSuccess]
/// returns the root widget (e.g. a `ProviderScope`) and THIS function
/// mounts it via `runApp`. On failure (any thrown error from
/// [initializeWorkmanager], [createDatabase], [buildSuccess], or a
/// synchronous error before the first `await`), [showFatal] is invoked
/// with `(error, stackTrace)` so the caller can render a fatal screen.
///
/// Testability: because this function calls `runApp` on the success path,
/// success-path tests assert via the [buildSuccess] callback's side-effect
/// (e.g. capture the database it received) rather than by observing
/// `runApp`. The failure path is tested by passing a throwing
/// [initializeWorkmanager] / [createDatabase] and asserting [showFatal] was
/// invoked.
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
