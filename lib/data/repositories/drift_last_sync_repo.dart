import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/domain/repositories/i_last_sync_repo.dart';

class DriftLastSyncRepo implements ILastSyncRepo {
  final db.AppDatabase _database;
  DriftLastSyncRepo(this._database);

  @override
  Future<int?> get(String instanceId, String agentRemoteId) async {
    final rows = await _database.getLastSyncAt(instanceId, agentRemoteId).get();
    if (rows.isEmpty) return null;
    return rows.first;
  }

  @override
  Future<void> upsert(
    String instanceId,
    String agentRemoteId,
    int msEpoch,
  ) async {
    await _database.upsertLastSyncAt(instanceId, agentRemoteId, msEpoch);
  }
}
