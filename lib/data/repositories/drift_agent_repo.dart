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
    // US-021: 默认过滤 tombstoned (removed_at) 和 hidden (hidden_at) agent。
    // 原未过滤的 getAgentsByInstance 命名查询保留供 deleteByInstanceId 清理
    // 逻辑及未来"显示已移除"开关使用。
    final rows = await _database.getActiveAgentsByInstance(instanceId).get();
    return rows.map(AgentMapper.toDomain).toList();
  }

  @override
  Future<List<Agent>> getAllByInstanceId(String instanceId) async {
    // US-021: 不过滤，返回实例下全部 agent（含 tombstoned/hidden）。
    // SaveInstanceUseCase 的 host 切换警告需要统计所有本地 agent，避免只含
    // tombstoned agent 的实例被误判为空。
    final rows = await _database.getAgentsByInstance(instanceId).get();
    return rows.map(AgentMapper.toDomain).toList();
  }

  @override
  Future<List<Agent>> getAll() async {
    // US-021: 默认过滤 tombstoned + hidden agent（见 getByInstanceId 注释）。
    final rows = await _database.getAllActiveAgents().get();
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
    // INTENTIONALLY UNFILTERED — 不过滤 tombstoned/hidden agent。syncFromGateway
    // 的复活逻辑（US-021）依赖此查询找回 tombstoned agent 以清空 removed_at。
    // 误加 WHERE removed_at IS NULL 过滤会让复活路径永远找不到对象，被迫降级
    // 为新插入 → 失去全部历史 messages。getById 同理不过滤。
    final row = await _database
        .findAgentByCompositeKey(instanceId, remoteId)
        .getSingleOrNull();
    return row != null ? AgentMapper.toDomain(row) : null;
  }

  @override
  Stream<Agent?> watchById(String localId) {
    // Drift .watchSingleOrNull()：订阅时立即 emit 当前行（如果存在），后续每次
    // 该行 commit 触发 emit。不存在的 localId 立即 emit null 并保持 open。
    return _database
        .getAgentByLocalId(localId)
        .watchSingleOrNull()
        .map((row) => row == null ? null : AgentMapper.toDomain(row));
  }

  @override
  Future<List<Agent>> syncFromGateway(
    String instanceId,
    List<Agent> remoteAgents,
  ) async {
    // Collect the local IDs that correspond to the synced remote agents.
    // We intentionally do NOT build the returned Agent objects here — the
    // subsequent tombstone/revive UPDATEs can change removed_at, so reading
    // rows before those UPDATEs would leak stale tombstone state to callers.
    final syncedLocalIds = <String>[];

    await _database.transaction(() async {
      // *** 顺序不可换 ***：upsert 必须在 diff 之前。diff 的 `NOT IN (remoteIds)`
      // 依赖 remoteIds 是完整的远端列表（含本次刚 upsert 的新 agent）。若把 diff
      // 提前，新 upsert 的 agent 会因不在旧 remoteIds 里被误 tombstone。

      // Law 6: 一次 batch SELECT 取出本实例下所有可能的现有 row,避免
      // per-remote-agent N+1。建 Map<remoteId, row> 后,循环内仅做
      // 内存查找,不再 round-trip SQLite。remoteAgents 为空时无需查
      // (差集分支会直接 tombstone 全部 active agent)。
      final existingByRemoteId = <String, db.Agent>{};
      if (remoteAgents.isNotEmpty) {
        final remoteIds = remoteAgents.map((a) => a.remoteId).toList();
        final placeholders = remoteIds.map((_) => '?').join(', ');
        final rows = await _database
            .customSelect(
              'SELECT * FROM agents '
              'WHERE instance_id = ? AND remote_id IN ($placeholders)',
              variables: [
                Variable.withString(instanceId),
                for (final id in remoteIds) Variable.withString(id),
              ],
              readsFrom: {_database.agents},
            )
            .get();
        for (final row in rows) {
          final agent = db.Agent.fromJson(row.data);
          existingByRemoteId[agent.remoteId] = agent;
        }
      }

      for (final remote in remoteAgents) {
        final existingRow = existingByRemoteId[remote.remoteId];

        if (existingRow != null) {
          // Update name/description from remote, preserve local customizations
          await _database.updateAgentFromGateway(
            remote.name,
            remote.description,
            existingRow.localId,
          );
          syncedLocalIds.add(existingRow.localId!);
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
            null, // removedAt — 新插入的 agent 未被 tombstone
            null, // hiddenAt — v1 不写入
          );
          syncedLocalIds.add(remote.localId);
        }
      }

      // US-021: 差集 → tombstone / 复活。两条 batch UPDATE 替代 N 行
      // 逐行写入（Law 6）。`agents: []` 协议下唯一含义为"Gateway 真无
      // agent",必须正常走 tombstone —— 否则清空 Gateway 后本地残留幽灵虾。
      // SQL 的 `WHERE removed_at IS [NOT] NULL` guard 保证 do-while 重入幂等。
      // removed_at 存毫秒（created_at 是秒）。
      final remoteIds = remoteAgents.map((a) => a.remoteId).toList();
      final now = DateTime.now().millisecondsSinceEpoch;

      if (remoteIds.isEmpty) {
        // 远端一个都没有 → 本实例所有 active agent 全部 tombstone
        await _database.customStatement(
          'UPDATE agents SET removed_at = ? '
          'WHERE instance_id = ? AND removed_at IS NULL',
          [now, instanceId],
        );
      } else {
        final placeholders = remoteIds.map((_) => '?').join(', ');
        // tombstone：本地存在、远端缺失、且尚未 tombstoned 的 agent
        await _database.customStatement(
          'UPDATE agents SET removed_at = ? '
          'WHERE instance_id = ? AND removed_at IS NULL '
          'AND remote_id NOT IN ($placeholders)',
          [now, instanceId, ...remoteIds],
        );
        // 复活：远端又出现、且当前 tombstoned 的 agent
        await _database.customStatement(
          'UPDATE agents SET removed_at = NULL '
          'WHERE instance_id = ? AND removed_at IS NOT NULL '
          'AND remote_id IN ($placeholders)',
          [instanceId, ...remoteIds],
        );
      }
    });

    if (syncedLocalIds.isEmpty) return [];

    // Re-read the synced rows AFTER the transaction commits so the returned
    // Agents reflect the final tombstone/revive state.
    final placeholders = syncedLocalIds.map((_) => '?').join(', ');
    final rows = await _database
        .customSelect(
          'SELECT * FROM agents WHERE local_id IN ($placeholders)',
          variables: [for (final id in syncedLocalIds) Variable.withString(id)],
          readsFrom: {_database.agents},
        )
        .get();

    final byLocalId = <String, Agent>{};
    for (final row in rows) {
      final agent = AgentMapper.toDomain(db.Agent.fromJson(row.data));
      byLocalId[agent.localId] = agent;
    }

    // Preserve the order of remoteAgents in the returned list.
    return syncedLocalIds
        .where((id) => byLocalId.containsKey(id))
        .map((id) => byLocalId[id]!)
        .toList();
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
