import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:drift/drift.dart' show Value, Variable;

import '../../core/i_avatar_storage_service.dart';
import '../local/database/database.dart' as db;
import '../local/mapping/agent_mapper.dart';
import '../local/mapping/quick_command_codec.dart';

/// Drift/SQLite implementation of [IAgentRepo].
class DriftAgentRepo implements IAgentRepo {
  final db.AppDatabase _database;
  final IAvatarStorageService? _avatarStorage;

  DriftAgentRepo(this._database, {IAvatarStorageService? avatarStorage})
    : _avatarStorage = avatarStorage;

  @override
  Future<List<Agent>> getByInstanceId(String instanceId) async {
    final rows = await _database.getAgentsByInstance(instanceId).get();
    return rows.map(AgentMapper.toDomain).toList();
  }

  @override
  Future<List<Agent>> getAll() async {
    final rows = await _database.getAllAgents().get();
    return rows.map(AgentMapper.toDomain).toList();
  }

  @override
  Future<Agent?> getById(String localId) async {
    final row = await _database.getAgentByLocalId(localId).getSingleOrNull();
    return row != null ? AgentMapper.toDomain(row) : null;
  }

  @override
  Future<Map<String, Agent>> getByIds(List<String> localIds) async {
    if (localIds.isEmpty) return {};
    final placeholders = localIds.map((_) => '?').join(', ');
    final rows = await _database
        .customSelect(
          'SELECT * FROM agents WHERE local_id IN ($placeholders)',
          variables: [for (final id in localIds) Variable.withString(id)],
          readsFrom: {_database.agents},
        )
        .get();
    final result = <String, Agent>{};
    for (final row in rows) {
      final agent = AgentMapper.toDomain(db.Agent.fromJson(row.data));
      result[agent.localId] = agent;
    }
    return result;
  }

  @override
  Future<Agent?> findByCompositeKey(String instanceId, String remoteId) async {
    final row = await _database
        .findAgentByCompositeKey(instanceId, remoteId)
        .getSingleOrNull();
    return row != null ? AgentMapper.toDomain(row) : null;
  }

  @override
  Future<List<Agent>> syncFromGateway(
    String instanceId,
    List<Agent> remoteAgents,
  ) async {
    final results = <Agent>[];

    await _database.transaction(() async {
      for (final remote in remoteAgents) {
        final existingRow = await _database
            .findAgentByCompositeKey(instanceId, remote.remoteId)
            .getSingleOrNull();

        if (existingRow != null) {
          // Update name/description from remote, preserve local customizations
          await _database.updateAgentFromGateway(
            remote.name,
            remote.description,
            existingRow.localId,
          );
          // Re-read to get the updated row with preserved local fields
          final updatedRow = await _database
              .getAgentByLocalId(existingRow.localId!)
              .getSingle();
          results.add(AgentMapper.toDomain(updatedRow));
        } else {
          // New agent — insert with fresh localId
          await _database.insertAgent(
            remote.localId,
            remote.remoteId,
            remote.instanceId,
            remote.name,
            remote.nickname,
            remote.avatarUrl,
            remote.themeColor,
            null, // quickCommandsJson
            remote.description,
            remote.isPinned ? 1 : 0,
            remote.createdAt,
          );
          final insertedRow = await _database
              .getAgentByLocalId(remote.localId)
              .getSingle();
          results.add(AgentMapper.toDomain(insertedRow));
        }
      }
    });

    return results;
  }

  @override
  Future<Agent> updateLocalProfile(
    String localId, {
    String? nickname,
    String? avatarUrl,
    String? themeColor,
  }) async {
    // Existence check + write in a single transaction to prevent TOCTOU race.
    await _database.transaction(() async {
      final row = await _database.getAgentByLocalId(localId).getSingleOrNull();
      if (row == null) throw StateError('Agent 不存在: $localId');

      // Use Drift's typed update (not customStatement) so that table-watching
      // streams are invalidated and UI widgets observing agent queries
      // receive the update without manual refresh.
      //
      // Value.absent() means "skip this column" — equivalent to COALESCE(?, col).
      await (_database.update(
        _database.agents,
      )..where((tbl) => tbl.localId.equals(localId))).write(
        db.AgentsCompanion(
          nickname: nickname != null
              ? Value<String?>(nickname)
              : const Value<String?>.absent(),
          avatarUrl: avatarUrl != null
              ? Value<String?>(avatarUrl)
              : const Value<String?>.absent(),
          themeColor: themeColor != null
              ? Value<String?>(themeColor)
              : const Value<String?>.absent(),
        ),
      );
    });

    return (await getById(localId))!;
  }

  @override
  Future<void> updateFullProfile(
    String localId, {
    String? nickname,
    String? avatarUrl,
    String? themeColor,
    List<QuickCommand>? quickCommands,
  }) async {
    // Existence check + write in a single transaction to prevent TOCTOU race.
    await _database.transaction(() async {
      final row = await _database.getAgentByLocalId(localId).getSingleOrNull();
      if (row == null) throw StateError('Agent 不存在: $localId');

      // 1) Profile fields (nickname / avatarUrl / themeColor)
      final hasProfileUpdate =
          nickname != null || avatarUrl != null || themeColor != null;
      if (hasProfileUpdate) {
        await (_database.update(
          _database.agents,
        )..where((tbl) => tbl.localId.equals(localId))).write(
          db.AgentsCompanion(
            nickname: nickname != null
                ? Value<String?>(nickname)
                : const Value<String?>.absent(),
            avatarUrl: avatarUrl != null
                ? Value<String?>(avatarUrl)
                : const Value<String?>.absent(),
            themeColor: themeColor != null
                ? Value<String?>(themeColor)
                : const Value<String?>.absent(),
          ),
        );
      }

      // 2) Quick commands
      if (quickCommands != null) {
        await _database.updateAgentQuickCommands(
          QuickCommandCodec.serialize(quickCommands),
          localId,
        );
      }
    });
  }

  @override
  Future<void> clearAvatar(String localId) async {
    // 使用 Value(null) 而非 Value.absent()：显式将列设为 NULL。
    // Value.absent() 意为"跳过此列"，无法清除已有值。
    await (_database.update(_database.agents)
          ..where((tbl) => tbl.localId.equals(localId)))
        .write(const db.AgentsCompanion(avatarUrl: Value<String?>(null)));
  }

  @override
  Future<Agent> togglePin(String localId) async {
    await _database.toggleAgentPin(localId);
    final updated = await getById(localId);
    if (updated == null) throw StateError('Agent 不存在: $localId');
    return updated;
  }

  @override
  Future<void> deleteByInstanceId(String instanceId) async {
    // Purge FTS5 entries BEFORE the FK CASCADE wipes messages — otherwise
    // the messages_fts virtual table retains orphaned rows that show up
    // as phantom search results.
    await _database.transaction(() async {
      // First, find all agents belonging to this instance so we can
      // purge each agent's messages from the FTS5 index individually.
      final agents = await _database.getAgentsByInstance(instanceId).get();
      for (final agent in agents) {
        // localId is the PRIMARY KEY — guaranteed non-null when read from DB.
        await _database.purgeMessagesFtsForAgent(agent.localId!);
        // iron-law-allow: Law8 -- 清理沙箱文件失败不影响主流程
        if (_avatarStorage != null) {
          try {
            await _avatarStorage!.deleteAvatar(agent.localId!);
          } catch (_) {
            // Best-effort: avatar file deletion must not block instance
            // deletion. The file may already be gone or on an unmounted
            // volume — both are acceptable outcomes.
          }
        }
      }
      await _database.deleteAgentsByInstanceId(instanceId);
    });
  }
}
