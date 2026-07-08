import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/notifications/notification_bootstrap.dart';
import 'package:claw_hub/app/notifications/notification_coordinator.dart';
import 'package:claw_hub/core/lifecycle/background_sync_scheduler.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ===========================================================================
// TDD-RED test for code-review finding F4:
//   notification_bootstrap.dart:111 — didChangeAppLifecycleState(resumed)
//   must re-warm the dispatcher's _notifiedKeys LRU from persisted pending
//   notifications, otherwise messages the background isolate enqueued
//   during pause are re-fired by the live messageStream on resume.
//
// This test FAILS on the current code (the bootstrap only calls
// scheduler.onAppResumed on resume, not coordinator.warmupDispatcherFromPending).
// The corresponding fix is to call coordinator.warmupDispatcherFromPending
// in the resumed branch of didChangeAppLifecycleState.
//
// Task 6 refactor: the bootstrap's constructor now takes a `ProviderReader`
// (a typedef for `T Function<T>(ProviderListenable<T>)`) instead of a full
// `WidgetRef`. This decouples it from the Widget/Provider ref-type mismatch
// (Riverpod 2.6.x: `WidgetRef` and `Ref` are sibling abstract classes, not
// related by inheritance). The mock below targets the reader function shape.
// ===========================================================================

/// `ProviderReader` is a generic function typedef — Mocktail can't mock a
/// function type directly. We wrap it in a callable interface so `Mocktail`
/// can stub its `call` method. Dart treats any class with a `call` method
/// as callable using `instance(args)` syntax, which is what the bootstrap
/// uses internally.
class _MockProviderReader extends Mock implements _ProviderReaderCallable {}

abstract class _ProviderReaderCallable {
  T call<T>(ProviderListenable<T> provider);
}

class _MockCoordinator extends Mock implements NotificationCoordinator {}

class _MockScheduler extends Mock implements BackgroundSyncScheduler {}

void main() {
  setUpAll(() {
    // Fallback for any() matchers.
    registerFallbackValue(UserPreferences.defaults());
  });

  late _MockProviderReader read;
  late _MockCoordinator coordinator;
  late _MockScheduler scheduler;

  setUp(() {
    read = _MockProviderReader();
    coordinator = _MockCoordinator();
    scheduler = _MockScheduler();

    // Set up return values for each provider the bootstrap reads. Note:
    // we only stub the providers that didChangeAppLifecycleState touches
    // (backgroundSyncSchedulerProvider) plus the new dependency
    // (notificationCoordinatorProvider) that the fix adds.
    when(() => scheduler.onAppResumed()).thenAnswer((_) async {});
    when(() => scheduler.onAppPaused()).thenAnswer((_) async {});
    when(() => read(backgroundSyncSchedulerProvider)).thenReturn(scheduler);
    when(() => read(notificationCoordinatorProvider)).thenReturn(coordinator);
    // Default: warmup is a no-op (current code never calls it on resume;
    // after the fix, the call is added).
    when(
      () => coordinator.warmupDispatcherFromPending(),
    ).thenAnswer((_) async {});
  });

  test(
    'F4_didChangeAppLifecycleState_resumed_callsWarmupDispatcherFromPending',
    () {
      final bootstrap = NotificationBootstrap(read.call);

      // Act: fire the resume lifecycle event.
      bootstrap.didChangeAppLifecycleState(AppLifecycleState.resumed);

      // Assert: after the fix, the resume path must trigger
      // warmupDispatcherFromPending so the dispatcher's _notifiedKeys
      // LRU is re-seeded with serverIds the background isolate enqueued
      // during pause. Without the fix, this is never called and
      // duplicate notifications fire on resume.
      verify(() => coordinator.warmupDispatcherFromPending()).called(1);
    },
  );

  test(
    'F4_didChangeAppLifecycleState_paused_doesNotCallWarmupDispatcherFromPending',
    () {
      // Symmetric guard: warmup is expensive (reads the entire pending
      // notifications table). It should fire on resume (re-seed after
      // background writes) but NOT on pause (no writes happened yet).
      final bootstrap = NotificationBootstrap(read.call);

      bootstrap.didChangeAppLifecycleState(AppLifecycleState.paused);

      verifyNever(() => coordinator.warmupDispatcherFromPending());
    },
  );
}
