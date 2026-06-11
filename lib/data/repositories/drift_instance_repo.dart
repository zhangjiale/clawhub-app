import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';

import '../local/database/database.dart' as db;
import '../local/mapping/instance_mapper.dart';

/// Drift/SQLite implementation of [IInstanceRepo].
class DriftInstanceRepo implements IInstanceRepo {
  final db.AppDatabase _database;

  DriftInstanceRepo(this._database);

  @override
  Future<List<Instance>> getAll() async {
    final rows = await _database.getAllInstances().get();
    return rows.map(InstanceMapper.toDomain).toList();
  }

  @override
  Future<Instance?> getById(String id) async {
    final row = await _database.getInstanceById(id).getSingleOrNull();
    return row != null ? InstanceMapper.toDomain(row) : null;
  }

  @override
  Future<Instance> save(Instance instance) async {
    await _database.upsertInstance(
      instance.id,
      instance.name,
      instance.gatewayUrl,
      instance.tokenRef,
      instance.healthStatus.toInt(),
      instance.isLocalNetwork ? 1 : 0,
      instance.lastConnectedAt,
      instance.createdAt,
    );
    return instance;
  }

  @override
  Future<void> delete(String id) async {
    // Purge FTS5 entries BEFORE the FK CASCADE wipes messages, otherwise
    // the messages_fts virtual table keeps orphaned (rowid, content) pairs
    // that surface as phantom search results.
    await _database.transaction(() async {
      await _database.purgeMessagesFtsForInstance(id);
      await _database.deleteInstanceById(id);
    });
  }

  @override
  Future<bool> nameExists(String name, {String? excludeId}) async {
    final row = await _database.checkNameExists(name, excludeId).getSingle();
    return row > 0;
  }

  @override
  Future<Instance> updateHealthStatus(String id, HealthStatus status) async {
    await _database.updateInstanceHealthStatus(status.toInt(), id);
    final updated = await getById(id);
    if (updated == null) throw StateError('实例不存在: $id');
    return updated;
  }

  @override
  Future<void> updateLastConnectedAt(String id, int timestamp) async {
    await _database.updateInstanceLastConnectedAt(timestamp, id);
  }

  @override
  Future<void> batchUpdateStatusByNetwork({
    required bool isLocalNetwork,
    required HealthStatus status,
  }) async {
    await _database.batchUpdateStatusByNetwork(
      status.toInt(),
      isLocalNetwork ? 1 : 0,
    );
  }
}
