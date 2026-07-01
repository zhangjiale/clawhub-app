// SYSTEMATIC-DEBUGGING / TDD-RED: This test proves the startup fail-fast
// guardrail surfaces a thrown exception in main()'s pre-runApp chain as a
// visible fatal screen (with error message, Retry button, and Stack trace
// expansion). It is RED until lib/app/bootstrap.dart,
// lib/ui_kit/startup_fatal_screen.dart, and the new
// lib/ui_kit/default_error_fallback.dart all exist.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claw_hub/app/bootstrap.dart';
import 'package:claw_hub/data/local/database/database.dart';
import 'package:claw_hub/ui_kit/startup_fatal_screen.dart';

Future<void> _throwingInitialize() async {
  throw StateError('simulated startup failure');
}

Future<AppDatabase> _alwaysFailDb() async {
  throw StateError('db should not be reached in this test');
}

void main() {
  testWidgets(
    'bootstrap surfaces a startup failure as a visible fatal screen',
    (tester) async {
      Widget? mountedFatal;
      await bootstrapApp(
        initializeWorkmanager: _throwingInitialize,
        createDatabase: _alwaysFailDb,
        buildSuccess: (_) => const SizedBox.shrink(),
        showFatal: (error, stackTrace) {
          mountedFatal = StartupFatalScreen(
            error: error,
            stackTrace: stackTrace,
            onRetry: () {},
          );
        },
      );

      expect(
        mountedFatal,
        isNotNull,
        reason: 'showFatal must be invoked on startup failure',
      );

      await tester.pumpWidget(mountedFatal!);
      await tester.pumpAndSettle();

      // The fatal screen must visibly present the error.
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.textContaining('simulated startup failure'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

      // The stack trace must be discoverable (collapsed in an ExpansionTile).
      expect(find.text('Stack trace'), findsOneWidget);

      // Tapping the expansion must reveal the stack trace text.
      await tester.tap(find.text('Stack trace'));
      await tester.pumpAndSettle();
      expect(find.textContaining('#0 '), findsWidgets);
    },
  );
}
