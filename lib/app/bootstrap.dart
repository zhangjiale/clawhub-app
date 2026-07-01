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
  // Install the global error widget before the first await. The builder
  // is harmless before runApp (no widget tree exists yet, so the
  // framework can't invoke it during the pre-runApp awaits). Installing
  // it up-front matters because it persists for the lifetime of the
  // isolate and covers two real cases:
  //   1. A synchronous build error inside buildSuccess(database) after
  //      runApp — without an early install, the builder would still be
  //      set, but only because this function runs every time; on a Retry
  //      re-entry, the previous successful install is what catches it.
  //   2. A build error inside the post-runApp widget tree (any frame)
  //      — ErrorWidget.builder is global state; setting it once here
  //      means we don't need to re-install it on every Retry re-entry
  //      or worry about order-of-operations between buildSuccess and
  //      the error widget.
  ErrorWidget.builder = (details) =>
      DefaultErrorFallback(error: details.exception, stackTrace: details.stack);

  try {
    await initializeWorkmanager();
    final database = await createDatabase();
    runApp(buildSuccess(database));
  } catch (error, stackTrace) {
    _logger.error('[bootstrap] startup failed: $error', stackTrace);
    showFatal(error, stackTrace);
  }
}
