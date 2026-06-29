/// Per-instance "last background sync" cursor (ms epoch).
///
/// Background sync writes; main isolate reads (settings page "last synced").
/// Null = never synced -> BackgroundSyncRunner uses now()-1h as start point.
abstract class ILastSyncRepo {
  Future<int?> get(String instanceId);
  Future<void> upsert(String instanceId, int msEpoch);
}
