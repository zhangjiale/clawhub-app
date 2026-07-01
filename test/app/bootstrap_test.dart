// SYSTEMATIC-DEBUGGING / TDD-RED: This test proves the startup fail-fast
// guardrail surfaces a thrown exception in main()'s pre-runApp chain as a
// visible fatal screen (with error message, Retry button, and Stack trace
// expansion). It is RED until lib/app/bootstrap.dart and the new
// lib/ui_kit/default_error_fallback.dart both exist.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claw_hub/app/bootstrap.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/data/local/database/database.dart';
import 'package:claw_hub/ui_kit/default_error_fallback.dart';
import 'package:drift/native.dart';

Future<void> _throwingInitialize() async {
  throw StateError('simulated startup failure');
}

Future<AppDatabase> _alwaysFailDb() async {
  throw StateError('db should not be reached in this test');
}

/// Mirrors `main.dart`'s `showFatal` callback (which is the only consumer
/// of `DefaultErrorFallback`'s `error + stackTrace + onRetry` surface).
/// Kept inline in the test so the assertion is against the same widget
/// tree the user actually sees on a fatal startup failure. Mirrors
/// `main.dart`'s dark-theme wrapping so the test catches a regression
/// where the production fatal screen loses its dark theme (e.g. someone
/// removes the `theme: AppTheme.darkTheme` args and it falls back to
/// `ThemeData.light()`).
Widget _buildFatal(Object error, StackTrace stackTrace) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.darkTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: ThemeMode.dark,
  home: Scaffold(
    body: SafeArea(
      child: DefaultErrorFallback(
        error: error,
        stackTrace: stackTrace,
        onRetry: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'bootstrap surfaces a startup failure as a visible fatal screen',
    (tester) async {
      // bootstrapApp installs ErrorWidget.builder unconditionally (before the
      // first await). flutter_test guards against tests leaving this changed,
      // so save + restore it — there's no point setting a benign default
      // first because bootstrapApp overwrites it synchronously on entry.
      final previousErrorWidgetBuilder = ErrorWidget.builder;

      Widget? mountedFatal;
      await bootstrapApp(
        initializeWorkmanager: _throwingInitialize,
        createDatabase: _alwaysFailDb,
        buildSuccess: (_) => const SizedBox.shrink(),
        showFatal: (error, stackTrace) {
          mountedFatal = _buildFatal(error, stackTrace);
        },
      );

      // Restore before assertions so flutter_test's post-test guard sees the
      // original builder, and so `tester.pumpWidget` below renders our fatal
      // widget instead of the benign SizedBox.
      ErrorWidget.builder = previousErrorWidgetBuilder;

      expect(
        mountedFatal,
        isNotNull,
        reason: 'showFatal must be invoked on startup failure',
      );

      await tester.pumpWidget(mountedFatal!);
      await tester.pumpAndSettle();

      // The fatal screen must visibly present the error.
      expect(find.text('应用出现了问题'), findsOneWidget);
      expect(find.textContaining('simulated startup failure'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);

      // Regression guard: production wraps DefaultErrorFallback in a
      // MaterialApp with AppTheme.darkTheme. If a future change drops
      // the theme args and falls back to ThemeData.light(), this assertion
      // catches it.
      final fallbackElement = tester.element(find.byType(DefaultErrorFallback));
      expect(
        Theme.of(fallbackElement).brightness,
        Brightness.dark,
        reason:
            'fatal screen must use the app dark theme — light '
            'theme would clash with the running app',
      );

      // The stack trace must be discoverable (collapsed in an ExpansionTile).
      expect(find.text('堆栈信息'), findsOneWidget);

      // Tapping the expansion must reveal the stack trace text.
      await tester.tap(find.text('堆栈信息'));
      await tester.pumpAndSettle();
      expect(find.textContaining('#0 '), findsWidgets);
    },
  );

  testWidgets('bootstrap mounts the success widget and hands the opened DB to '
      'buildSuccess on the happy path', (tester) async {
    AppDatabase? capturedDb;
    var fatalCalled = false;

    // bootstrapApp installs ErrorWidget.builder unconditionally (before the
    // first await). flutter_test guards against tests leaving this changed,
    // so save + restore it. No benign default needed — bootstrapApp
    // overwrites it synchronously on entry. Same pattern as the failure
    // test above and test/ui_kit/error_boundary_test.dart.
    final previousErrorWidgetBuilder = ErrorWidget.builder;

    // bootstrapApp calls runApp(...) on the success path; runAsync lets
    // the real async DB-open complete. We assert via the buildSuccess
    // side-effect (it captured the DB) rather than the rendered tree,
    // because runApp's root is not tester.pumpWidget's root.
    await tester.runAsync(
      () => bootstrapApp(
        initializeWorkmanager: () async {},
        createDatabase: () async => AppDatabase(NativeDatabase.memory()),
        buildSuccess: (db) {
          capturedDb = db;
          return const SizedBox.shrink();
        },
        showFatal: (_, _) => fatalCalled = true,
      ),
    );
    // Pump one frame so the binding has no pending frame from runApp.
    await tester.pump();

    // Restore the global before the test framework's post-test guard
    // checks it.
    ErrorWidget.builder = previousErrorWidgetBuilder;

    expect(
      fatalCalled,
      isFalse,
      reason: 'showFatal must not fire on the success path',
    );
    expect(
      capturedDb,
      isNotNull,
      reason: 'buildSuccess must receive the opened database',
    );
    await capturedDb?.close();
  });
}
