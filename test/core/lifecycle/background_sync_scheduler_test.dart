import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/background_sync_scheduler.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_prefs.dart';

class _RecordingPrefs implements IBackgroundSyncPrefs {
  bool value = true; // start: main active
  @override
  Future<bool> get mainActive => Future.value(value);
  @override
  Future<void> setMainActive(bool a) async {
    value = a;
  }

  @override
  Future<void> clear() async {
    value = false;
  }
}

class _RecordingBackend implements WorkmanagerBackend {
  int scheduleCalls = 0;
  int cancelCalls = 0;
  @override
  Future<void> enqueueUniquePeriodic() async {
    scheduleCalls++;
  }

  @override
  Future<void> cancelUniqueWork() async {
    cancelCalls++;
  }
}

void main() {
  test('onAppPaused_setsMainInactive_andEnqueues', () async {
    final prefs = _RecordingPrefs();
    final backend = _RecordingBackend();
    final scheduler = BackgroundSyncScheduler(
      gate: BackgroundSyncGate(prefs: prefs),
      backend: backend,
    );
    await scheduler.onAppPaused();
    expect(prefs.value, isFalse); // gate flipped
    expect(backend.scheduleCalls, 1); // work enqueued
  });

  test('onAppResumed_setsMainActive_andCancels', () async {
    final prefs = _RecordingPrefs()..value = false;
    final backend = _RecordingBackend();
    final scheduler = BackgroundSyncScheduler(
      gate: BackgroundSyncGate(prefs: prefs),
      backend: backend,
    );
    await scheduler.onAppResumed();
    expect(prefs.value, isTrue);
    expect(backend.cancelCalls, 1);
  });

  test('ensureScheduled_isIdempotent', () async {
    final backend = _RecordingBackend();
    final scheduler = BackgroundSyncScheduler(
      gate: BackgroundSyncGate(prefs: _RecordingPrefs()),
      backend: backend,
    );
    await scheduler.ensureScheduled();
    await scheduler.ensureScheduled();
    expect(
      backend.scheduleCalls,
      2,
    ); // REPLACE policy — re-enqueue is safe/idempotent
  });

  test('cancel_callsBackend', () async {
    final backend = _RecordingBackend();
    final scheduler = BackgroundSyncScheduler(
      gate: BackgroundSyncGate(prefs: _RecordingPrefs()),
      backend: backend,
    );
    await scheduler.cancel();
    expect(backend.cancelCalls, 1);
  });
}
