import 'package:drift/drift.dart' as drift;
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
  Future<Map<String, Instance>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    // Law 6: 单次 IN 查询替代 N 次 getById（message_hub N+1 修复）。
    // 对齐 DriftAgentRepo.getByIds 的 customSelect 模式。readsFrom 指定
    // instances 表以保证 Drift table-level invalidation 正确。
    final placeholders = ids.map((_) => '?').join(', ');
    final rows = await _database
        .customSelect(
          'SELECT * FROM instances WHERE id IN ($placeholders)',
          variables: [for (final id in ids) drift.Variable.withString(id)],
          readsFrom: {_database.instances},
        )
        .get();
    final result = <String, Instance>{};
    for (final row in rows) {
      final instance = InstanceMapper.toDomain(db.Instance.fromJson(row.data));
      result[instance.id] = instance;
    }
    return result;
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
  Future<List<String>> batchUpdateStatusByNetwork({
    required bool isLocalNetwork,
    required HealthStatus status,
  }) async {
    return _database.transaction(() async {
      // 1. 查询匹配的实例 ID
      final rows = await _database
          .customSelect(
            'SELECT id FROM instances WHERE is_local_network = ?1',
            variables: [drift.Variable<int>(isLocalNetwork ? 1 : 0)],
            readsFrom: {_database.instances},
          )
          .get();
      final ids = rows.map((r) => r.read<String>('id')).toList();

      // 2. 批量更新状态
      if (ids.isNotEmpty) {
        await _database.batchUpdateStatusByNetwork(
          status.toInt(),
          isLocalNetwork ? 1 : 0,
        );
      }

      return ids;
    });
  }
}
