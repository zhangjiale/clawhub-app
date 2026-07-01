/// Per-(instance, agent) "last background sync" cursor (ms epoch).
///
/// Background sync is the only writer; the first tick (cursor null) re-walks
/// from 0, and merge dedup idempotently skips already-inserted rows by
/// clientId/serverId. An instance-level "last synced" time, if ever needed
/// for UI display, is trivially recomputed as
/// `SELECT MAX(last_sync_at) FROM sync_state_agent WHERE instance_id = ?`
/// — no instance-level method is kept on this interface.
abstract class ILastSyncRepo {
  Future<int?> get(String instanceId, String agentRemoteId);
  Future<void> upsert(String instanceId, String agentRemoteId, int msEpoch);
}
