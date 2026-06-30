import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/background_sync_scheduler.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_prefs.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/main.dart';

class _NoOpWorkmanagerBackend implements WorkmanagerBackend {
  @override
  Future<void> enqueueUniquePeriodic() async {}

  @override
  Future<void> cancelUniqueWork() async {}
}

class _NoOpSyncPrefs implements IBackgroundSyncPrefs {
  @override
  Future<bool> get mainActive async => false;

  @override
  Future<void> setMainActive(bool active) async {}

  @override
  Future<void> clear() async {}
}

/// Scheduler override — prevents real workmanager calls in tests.
final _schedulerOverride = backgroundSyncSchedulerProvider.overrideWith(
  (ref) => BackgroundSyncScheduler(
    gate: BackgroundSyncGate(prefs: _NoOpSyncPrefs()),
    backend: _NoOpWorkmanagerBackend(),
  ),
);

/// Helper: create an in-memory database ProviderScope for widget tests.
ProviderScope _testProviderScope({required Widget child}) {
  final memDb = db.AppDatabase(NativeDatabase.memory());
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) {
        ref.onDispose(() => memDb.close());
        return memDb;
      }),
      _schedulerOverride,
    ],
    child: child,
  );
}

void main() {
  testWidgets('App renders 3-tab navigation', (WidgetTester tester) async {
    await tester.pumpWidget(_testProviderScope(child: const ClawHubApp()));
    await tester.pumpAndSettle();

    // The app should render the 3-tab navigation (now custom glassmorphism)
    // Text may appear in both AppBar title and NavBar label
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.text('虾列表'), findsAtLeast(1));
    expect(find.text('消息'), findsAtLeast(1));
    expect(find.text('实例'), findsAtLeast(1));
  });

  testWidgets('_ConnectionInitializer sets init state to success after '
      'orchestrator initialization completes', (WidgetTester tester) async {
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
        _schedulerOverride,
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
    expect(
      state!.hasError,
      isFalse,
      reason: 'Expected successful init, got error: ${state.error}',
    );
  });

  testWidgets('_ConnectionInitializer passes child through unchanged', (
    WidgetTester tester,
  ) async {
    // Verify that the child widget (the MaterialApp.router) is rendered
    // after _ConnectionInitializer wraps it.
    await tester.pumpWidget(_testProviderScope(child: const ClawHubApp()));
    await tester.pumpAndSettle();

    // If _ConnectionInitializer swallowed the child, BackdropFilter (bottom nav)
    // wouldn't be in the widget tree.
    expect(find.byType(BackdropFilter), findsWidgets);
  });
}
