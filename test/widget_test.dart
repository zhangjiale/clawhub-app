import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/main.dart';

/// Helper: create an in-memory database ProviderScope for widget tests.
ProviderScope _testProviderScope({required Widget child}) {
  final memDb = db.AppDatabase(NativeDatabase.memory());
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) {
        ref.onDispose(() => memDb.close());
        return memDb;
      }),
    ],
    child: child,
  );
}

void main() {
  testWidgets('App renders 3-tab navigation', (WidgetTester tester) async {
    await tester.pumpWidget(_testProviderScope(child: const ClawHubApp()));
    await tester.pumpAndSettle();

    // The app should render with the 3-tab navigation bar
    // (Text may appear in both AppBar title and NavBar label)
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('🦐 ClawHub'), findsAtLeast(1));
    expect(find.text('虾列表'), findsAtLeast(1));
    expect(find.text('消息'), findsAtLeast(1));
    expect(find.text('实例'), findsAtLeast(1));
  });

  testWidgets(
    '_ConnectionInitializer sets init state to success after '
    'orchestrator initialization completes',
    (WidgetTester tester) async {
      // Read state from a container that mirrors the widget tree's overrides.
      // We pump the same ProviderScope setup so the widget and our read
      // share the same provider instances.
      final memDb = db.AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.onDispose(() => memDb.close());
            return memDb;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ClawHubApp(),
        ),
      );
      await tester.pumpAndSettle();

      // After pumpAndSettle, _ConnectionInitializer should have completed
      // initialization and set the provider to AsyncValue.data.
      final state = container.read(connectionInitStateProvider);
      expect(state, isA<AsyncValue<void>>());
      expect(state!.hasError, isFalse,
          reason: 'Expected successful init, got error: ${state.error}');
    },
  );

  testWidgets(
    '_ConnectionInitializer passes child through unchanged',
    (WidgetTester tester) async {
      // Verify that the child widget (the MaterialApp.router) is rendered
      // after _ConnectionInitializer wraps it.
      await tester.pumpWidget(_testProviderScope(child: const ClawHubApp()));
      await tester.pumpAndSettle();

      // If _ConnectionInitializer swallowed the child, NavigationBar wouldn't
      // be in the widget tree.
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );
}
