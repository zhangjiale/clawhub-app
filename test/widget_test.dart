import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/notifications/notification_bootstrap.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/main.dart';

import '_helpers/mocks.dart' show noOpBackgroundSyncSchedulerOverride;

/// Headless fake — real [NotificationBootstrap] opens a Drift prefs stream
/// whose cancel-on-dispose (provider onDispose) schedules a 0-duration timer
/// that trips flutter_test's "Timer is still pending" at teardown. These
/// widget tests exercise the app shell, not the notification subsystem, so a
/// no-op init fake is the right seam.
class _FakeNotificationBootstrap implements NotificationBootstrap {
  @override
  Future<void> init() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_FakeNotificationBootstrap.${invocation.memberName}',
  );
}

/// Helper: create an in-memory database ProviderScope for widget tests.
ProviderScope _testProviderScope({required Widget child}) {
  final memDb = db.AppDatabase(NativeDatabase.memory());
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) {
        ref.onDispose(() => memDb.close());
        return memDb;
      }),
      noOpBackgroundSyncSchedulerOverride,
      notificationBootstrapProvider.overrideWith(
        (ref) => _FakeNotificationBootstrap(),
      ),
    ],
    child: child,
  );
}

/// StartupGate 在 splash 阶段挂 800ms MinDisplayTimer；`pumpAndSettle` 在
/// 800ms 之前因「无调度帧」提前停止，app 阶段永不 mount。本 helper 先 pump
/// 一帧让 initState/_runStartup 跑起来，再推进 800ms 越过
/// MinDisplayTimer，最后 pumpAndSettle 收尾 app 自身的动画/路由过渡。
Future<void> _settlePastSplashGate(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('App renders 3-tab navigation', (WidgetTester tester) async {
    await tester.pumpWidget(_testProviderScope(child: const ClawHubApp()));
    await _settlePastSplashGate(tester);

    // The app should render the 3-tab navigation (now custom glassmorphism)
    // Text may appear in both AppBar title and NavBar label
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.text('虾列表'), findsAtLeast(1));
    expect(find.text('消息'), findsAtLeast(1));
    expect(find.text('实例'), findsAtLeast(1));
  });

  testWidgets('StartupGate sets init state to success after '
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
        noOpBackgroundSyncSchedulerOverride,
        notificationBootstrapProvider.overrideWith(
          (ref) => _FakeNotificationBootstrap(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClawHubApp(),
      ),
    );
    await _settlePastSplashGate(tester);

    // After settling past the splash gate, StartupGate should have completed
    // initialization (Tier 2 success path) and set the provider to
    // AsyncValue.data.
    final state = container.read(connectionInitStateProvider);
    expect(state, isA<AsyncValue<void>>());
    expect(
      state!.hasError,
      isFalse,
      reason: 'Expected successful init, got error: ${state.error}',
    );
  });

  testWidgets('StartupGate passes child through unchanged', (
    WidgetTester tester,
  ) async {
    // Verify that the child widget (the MaterialApp.router) is rendered
    // after StartupGate wraps it.
    await tester.pumpWidget(_testProviderScope(child: const ClawHubApp()));
    await _settlePastSplashGate(tester);

    // If StartupGate swallowed the child, BackdropFilter (bottom nav)
    // wouldn't be in the widget tree.
    expect(find.byType(BackdropFilter), findsWidgets);
  });
}
