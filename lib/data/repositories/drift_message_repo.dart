import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:drift/drift.dart' show Variable;

import '../local/database/database.dart' as db;
import '../local/mapping/message_mapper.dart';

/// Drift/SQLite implementation of [IMessageRepo].
///
/// Handles FTS5 manual synchronization per the Zero-Trigger principle.
/// All multi-step operations are wrapped in transactions.
class DriftMessageRepo implements IMessageRepo {
  final db.AppDatabase _database;

  DriftMessageRepo(this._database);

  // ---------------------------------------------------------------------------
  // Write operations
  // ---------------------------------------------------------------------------

  @override
  Future<Message> insert(Message message) async {
    await _database.transaction(() async {
      await _database.insertMessage(
        message.clientId,
        message.serverId,
        message.conversationId,
        message.agentId,
        message.role.toInt(),
        message.content,
        message.type.toInt(),
        message.status.toInt(),
        message.logicalClock,
        message.timestamp,
        message.metadata != null ? jsonEncode(message.metadata) : null,
      );

      await _syncFtsForMessage(message.clientId, message.content);
    });

    return message;
  }

  /// Best-effort FTS5 index sync — failure is logged but never propagated.
  ///
  /// Uses [db.AppDatabase.getLastInsertRowid] + [db.AppDatabase.syncFtsInsert].
  /// Must be called inside a transaction, immediately after the INSERT that
  /// produced the rowid.
  ///
  /// 这是单条插入路径（[insert]）的 FTS 同步；批量路径
  /// [batchInsertByIndexedIds] 改用 [db.AppDatabase.batchSyncFtsInsert]
  /// 一次性多行同步。两条路径语义等价（INSERT + FTS），只是实现不同：
  /// 单条用 `last_insert_rowid()`（标准做法、更高效），批量用"先 INSERT 再
  /// SELECT rowid 映射"（batch API 不返回逐行 rowid）。不为一致性统一改造单条路径。
  Future<void> _syncFtsForMessage(String clientId, String? content) async {
    try {
      final rowid = await _database.getLastInsertRowid();
      await _database.syncFtsInsert(rowid, content);
    } catch (error, stackTrace) {
      debugPrint('FTS sync failed for message $clientId: $error\n$stackTrace');
    }
  }

  @override
  Future<void> deleteByClientId(String clientId) async {
    await _database.transaction(() async {
      // Fetch rowid and content in a single query for FTS5 cleanup
      final info = await _database.getMessageRowidAndContent(clientId);

      await _database.deleteMessageByClientId(clientId);

      // Sync FTS5 index
      if (info != null) {
        await _database.syncFtsDelete(info.rowid, info.content);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Read operations
  // ---------------------------------------------------------------------------

  @override
  Future<Message?> getByClientId(String clientId) async {
    final row = await _database
        .getMessageByClientId(clientId)
        .getSingleOrNull();
    return row != null ? MessageMapper.toDomain(row) : null;
  }

  @override
  Future<Message?> getByServerId(String serverId) async {
    final row = await _database
        .getMessageByServerId(serverId)
        .getSingleOrNull();
    return row != null ? MessageMapper.toDomain(row) : null;
  }

  @override
  Future<List<Message>> getByConversation(
    String conversationId, {
    String? before,
    int limit = 50,
  }) async {
    final rows = before != null
        ? await _database
              .getMessagesByConversationBefore(conversationId, before, limit)
              .get()
        : await _database
              .getMessagesByConversationFirst(conversationId, limit)
              .get();
    return rows.map(MessageMapper.toDomain).toList();
  }

  @override
  Future<List<Message>> getAnchorWindow(
    String conversationId, {
    required String targetClientId,
    int before = 5,
    int after = 10,
  }) async {
    // Bounded anchor window: load at most `before + 1 + after` rows instead
    // of the whole conversation. Three indexed queries:
    //   1. the target row itself (also serves as the "target not found" check)
    //   2. `before` rows older than the target (DESC, reversed to ASC)
    //   3. `after` rows newer than the target (ASC)
    // Each query filters by conversation_id + logical_clock, so it never
    // deserializes the entire history for a long conversation.
    final target = await _database
        .getMessageByClientId(targetClientId)
        .getSingleOrNull();
    if (target == null) return [];

    // Bug 6: Target must belong to the requested conversation.
    // getMessageByClientId is a global query (no conversation filter on
    // the client_id UNIQUE index), so a target from a different conversation
    // would produce a wrong anchor window.
    if (target.conversationId != conversationId) return [];

    final olderRows = await _database
        .getMessagesByConversationBeforeAnchor(
          conversationId,
          targetClientId,
          before,
        )
        .get();
    final newerRows = await _database
        .getMessagesByConversationAfterAnchor(
          conversationId,
          targetClientId,
          after,
        )
        .get();

    // olderRows came back DESC (nearest-older first); reverse to ASC so the
    // merged window is chronologically ordered: [older...], target, [newer...].
    final older = olderRows.reversed.map(MessageMapper.toDomain).toList();
    final targetMsg = MessageMapper.toDomain(target);
    final newer = newerRows.map(MessageMapper.toDomain).toList();

    return [...older, targetMsg, ...newer];
  }

  @override
  Future<List<Message>> getOutbox(String agentId) async {
    final rows = await _database.getOutboxMessages(agentId).get();
    return rows.map(MessageMapper.toDomain).toList();
  }

  @override
  Future<List<Message>> getOutboxByInstance(String instanceId) async {
    final rows = await _database.getOutboxMessagesByInstance(instanceId).get();
    return rows.map(MessageMapper.toDomain).toList();
  }

  @override
  Future<int> getOutboxCountByInstance(String instanceId) async {
    final count = await _database
        .getOutboxCountByInstance(instanceId)
        .getSingle();
    return count;
  }

  @override
  Stream<int> watchOutboxCount(String instanceId) {
    // drift 的 stream query：首次订阅发射当前值，之后 messages/conversations
    // 表任何变更自动重查并发射新值。写操作无需任何改动 —— 这是本方案的核心红利。
    // 单值 int 查询，开销低；按 instanceId 过滤，跨实例不互相干扰。
    return _database.getOutboxCountByInstance(instanceId).watchSingle();
  }

  @override
  Future<bool> tryTransitionToSending(
    String clientId,
    MessageStatus expectedStatus,
  ) async {
    final affected = await _database.tryTransitionToSending(
      clientId,
      expectedStatus.toInt(),
    );
    return affected == 1;
  }

  @override
  Future<int> resetStaleSending(String instanceId) async {
    return _database.resetStaleSending(instanceId);
  }

  @override
  Future<List<Message>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await _database.searchMessagesSanitized(
      query,
      limit: limit,
      offset: offset,
    );
    return rows.map(MessageMapper.toDomain).toList();
  }

  // ---------------------------------------------------------------------------
  // Status transitions
  // ---------------------------------------------------------------------------

  @override
  Future<Message> updateStatus(String clientId, MessageStatus status) async {
    final existing = await getByClientId(clientId);
    if (existing == null) throw StateError('消息不存在: $clientId');

    // Validate state transition via domain model — returns updated entity
    final updated = existing.transitionTo(status);

    await _database.updateMessageStatusById(status.toInt(), clientId);
    return updated;
  }

  @override
  Future<Message> bindServerId(String clientId, String serverId) async {
    final existing = await getByClientId(clientId);
    if (existing == null) throw StateError('消息不存在: $clientId');

    // Validate via domain model (must be in SENDING state) — returns updated entity
    final updated = existing.bindServerId(serverId);

    await _database.bindMessageServerId(
      serverId,
      MessageStatus.sent.toInt(),
      clientId,
    );
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Maintenance & batch
  // ---------------------------------------------------------------------------

  @override
  Future<List<Message>> batchInsertByIndexedIds(List<Message> messages) async {
    if (messages.isEmpty) return <Message>[];

    // 1. Collect non-null / non-empty indexed IDs
    final serverIds = messages
        .where((m) => m.serverId != null && m.serverId!.isNotEmpty)
        .map((m) => m.serverId!)
        .toList();
    final clientIds = messages
        .where((m) => m.clientId.isNotEmpty)
        .map((m) => m.clientId)
        .toList();
    if (serverIds.isEmpty && clientIds.isEmpty) return <Message>[];

    // 2. Build IN-clause placeholders for the dedup SELECT.
    //    SQLite default max variable number is 999; _pageSize (50) × 2 IDs = 100,
    //    well within the limit.  batchInsertMessages 自带 900 变量守卫（11 列/行）。
    final serverPlaceholders = serverIds.isNotEmpty
        ? serverIds.map((_) => '?').join(', ')
        : 'NULL';
    final clientPlaceholders = clientIds.isNotEmpty
        ? clientIds.map((_) => '?').join(', ')
        : 'NULL';
    final allIds = [...serverIds, ...clientIds];

    // 3. SELECT existing IDs + 批量 INSERT + 批量 FTS 同步，全在单事务内。
    //    dedup SELECT 必须在事务内（见下注释）；批量 INSERT/FTS 用单条多行
    //    VALUES 语句，消除逐条 await 的 N+1（Iron Law 6）。
    final inserted = <Message>[];
    await _database.transaction(() async {
      final existingServerIds = <String>{};
      final existingClientIds = <String>{};

      if (allIds.isNotEmpty) {
        final rows = await _database
            .customSelect(
              'SELECT server_id, client_id FROM messages '
              'WHERE server_id IN ($serverPlaceholders) '
              'OR client_id IN ($clientPlaceholders)',
              variables: allIds.map((id) => Variable.withString(id)).toList(),
              readsFrom: {_database.messages},
            )
            .get();

        for (final row in rows) {
          final sid = row.readNullable<String>('server_id');
          final cid = row.read<String>('client_id');
          if (sid != null && sid.isNotEmpty) existingServerIds.add(sid);
          if (cid.isNotEmpty) existingClientIds.add(cid);
        }
      }

      // 收集真正新增的消息（serverId 与 clientId 均不存在）。
      // 注意：同一批内可能有重复 clientId（catch-up 翻页边界偶发），
      // 用 seenClientIds 去重，避免 UNIQUE 冲突击穿整批 INSERT。
      final newMessages = <Message>[];
      final seenClientIds = <String>{};
      for (final msg in messages) {
        if (msg.serverId != null && existingServerIds.contains(msg.serverId)) {
          continue;
        }
        if (existingClientIds.contains(msg.clientId)) continue;
        if (!seenClientIds.add(msg.clientId)) continue;

        newMessages.add(msg);
      }
      if (newMessages.isEmpty) return;

      // 单条多行 INSERT — 替代 N 次 insertMessage 循环。
      final rowidMap = await _database.batchInsertMessages([
        for (final m in newMessages)
          (
            clientId: m.clientId,
            serverId: m.serverId,
            conversationId: m.conversationId,
            agentId: m.agentId,
            role: m.role.toInt(),
            content: m.content,
            type: m.type.toInt(),
            status: m.status.toInt(),
            logicalClock: m.logicalClock,
            timestamp: m.timestamp,
            metadata: m.metadata != null ? jsonEncode(m.metadata) : null,
          ),
      ]);

      // 单条多行 FTS 同步 — best-effort，失败不阻断（与 _syncFtsForMessage 一致）。
      final rowidToContent = <int, String?>{};
      for (final m in newMessages) {
        final rowid = rowidMap[m.clientId];
        if (rowid != null) rowidToContent[rowid] = m.content;
      }
      try {
        await _database.batchSyncFtsInsert(rowidToContent);
      } catch (error, stackTrace) {
        debugPrint(
          'Batch FTS sync failed for ${rowidToContent.length} messages: '
          '$error\n$stackTrace',
        );
      }

      inserted.addAll(newMessages);
    });

    return inserted;
  }

  @override
  Future<int> cleanupOldMessages(String agentId, {int keep = 1000}) async {
    // Identify rows that the bulk delete will remove, so we can purge
    // them from the FTS5 index incrementally instead of triggering an
    // expensive full-table rebuild.
    final doomedRows = await _database
        .customSelect(
          'SELECT rowid, content FROM messages '
          'WHERE agent_id = ? AND rowid NOT IN ('
          '  SELECT rowid FROM messages '
          '  WHERE agent_id = ? ORDER BY timestamp DESC LIMIT ?'
          ')',
          variables: [
            Variable.withString(agentId),
            Variable.withString(agentId),
            Variable.withInt(keep),
          ],
          readsFrom: {_database.messages},
        )
        .get();

    if (doomedRows.isEmpty) return 0;

    await _database.transaction(() async {
      for (final row in doomedRows) {
        await _database.syncFtsDelete(
          row.read<int>('rowid'),
          row.read<String?>('content'),
        );
      }
      await _database.deleteOldMessagesByAgent(agentId, keep);
    });

    return doomedRows.length;
  }

  @override
  Future<int> getMessageCount(String agentId) async {
    final row = await _database.getMessageCountByAgent(agentId).getSingle();
    return row;
  }

  @override
  Future<Map<String, int>> getMessageCountsByAgent(
    List<String> agentIds,
  ) async {
    if (agentIds.isEmpty) return {};

    // Batch query via custom SQL with dynamic IN clause (Iron Law 6)
    final dbCounts = await _database.getMessageCountsByAgent(agentIds);

    // Initialize all requested agentIds to 0, then fill in actual counts
    final result = <String, int>{};
    for (final id in agentIds) {
      result[id] = dbCounts[id] ?? 0;
    }
    return result;
  }
}
