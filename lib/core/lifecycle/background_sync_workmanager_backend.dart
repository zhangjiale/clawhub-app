import 'package:workmanager/workmanager.dart';
import 'package:claw_hub/core/lifecycle/background_sync_scheduler.dart';

/// Production [WorkmanagerBackend] that delegates to the `workmanager` plugin.
///
/// Uses REPLACE policy so [ensureScheduled] is idempotent.
class WorkmanagerBackendImpl implements WorkmanagerBackend {
  const WorkmanagerBackendImpl();

  @override
  Future<void> enqueueUniquePeriodic() async {
    await Workmanager().registerPeriodicTask(
      BackgroundSyncScheduler.uniqueWorkName,
      BackgroundSyncScheduler.uniqueWorkName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  @override
  Future<void> cancelUniqueWork() async {
    await Workmanager().cancelByUniqueName(
      BackgroundSyncScheduler.uniqueWorkName,
    );
  }
}
