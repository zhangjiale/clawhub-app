import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';

/// Minimal backend so the scheduler is unit-testable without the real
/// workmanager plugin (which throws outside an app context).
abstract class WorkmanagerBackend {
  Future<void> enqueueUniquePeriodic();
  Future<void> cancelUniqueWork();
}

/// Schedules / cancels the periodic background-sync work and flips the
/// [BackgroundSyncGate] on app lifecycle changes.
///
/// The real production backend (Task 7) wraps `Workmanager().registerPeriodicTask`
/// / `cancelUniqueWork`. REPLACE uniqueness makes [ensureScheduled] idempotent.
class BackgroundSyncScheduler {
  static const uniqueWorkName = 'clawhub.background-sync';

  final BackgroundSyncGate gate;
  final WorkmanagerBackend backend;

  BackgroundSyncScheduler({required this.gate, required this.backend});

  /// Called on app start and on toggle-on. Idempotent (REPLACE policy).
  Future<void> ensureScheduled() => backend.enqueueUniquePeriodic();

  Future<void> cancel() => backend.cancelUniqueWork();

  /// Instances changed (saved/deleted) — reschedule so the next tick sees the
  /// new instance set. (The runner re-reads instances each tick, so this is
  /// belt-and-suspenders; mainly ensures work is scheduled if it was cancelled.)
  Future<void> notifyInstancesChanged() => backend.enqueueUniquePeriodic();

  /// App went to background → mark main inactive + enqueue a tick soon.
  Future<void> onAppPaused() async {
    await gate.setMainActive(false);
    await backend.enqueueUniquePeriodic();
  }

  /// App returned to foreground → mark main active + cancel pending tick
  /// (the live messageStream takes over).
  Future<void> onAppResumed() async {
    await gate.setMainActive(true);
    await backend.cancelUniqueWork();
  }
}
