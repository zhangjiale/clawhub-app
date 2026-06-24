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
  Future<List<Agent>> syncFromGateway(
    String instanceId,
    List<Agent> remoteAgents,
  ) async {
    final results = <Agent>[];

    await _database.transaction(() async {
      // *** 顺序不可换 ***：upsert 必须在 diff 之前。diff 的 `NOT IN (remoteIds)`
      // 依赖 remoteIds 是完整的远端列表（含本次刚 upsert 的新 agent）。若把 diff
      // 提前，新 upsert 的 agent 会因不在旧 remoteIds 里被误 tombstone。
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
            null, // removedAt — 新插入的 agent 未被 tombstone
            null, // hiddenAt — v1 不写入
          );
          final insertedRow = await _database
              .getAgentByLocalId(remote.localId)
              .getSingle();
          results.add(AgentMapper.toDomain(insertedRow));
        }
      }

      // US-021: 差集 → tombstone / 复活（batch SQL，Law 6 合规）。
      //
      // 协议契约：scope 不足时 fetchAgents 抛错被上层接住，`agents: []` 在
      // 协议下唯一含义为"Gateway 真无 agent"，必须正常走 tombstone（而非
      // "空列表跳过"），否则用户清空 Gateway 后本地仍残留幽灵虾——这正是
      // US-021 要修的原 BUG。
      //
      // 用两条 UPDATE 替代 N 行逐行写入：Law 6 禁止 for...await repo/DB 的
      // N+1 模式，pre-commit hook 的正则会拦下逐行写法。
      //
      // customStatement 选择：本项目 agents 表当前无 .watch() stream 查询，
      // UI 全走 agentSyncTickerProvider 脚踏式刷新，故 customStatement 的
      // "不触发 stream 失效"特性对本改动无影响。未来若给 agents 加 watch，
      // 需改用 Drift typed update。
      //
      // do-while 重入安全：ConnectionOrchestrator._syncAgentsForInstance 的
      // pending-retry 循环可能对同一实例多次 sync。SQL 的
      // `WHERE removed_at IS [NOT] NULL` guard 保证同一 agent 不会重复打标/
      // 复活——天然幂等。
      //
      // removed_at 存毫秒（与 created_at 的秒精度不同，跨列计算注意换算）。
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
