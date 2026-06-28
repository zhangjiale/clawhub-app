import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/domain/usecases/message_cluster_deduper.dart';
import 'package:drift/drift.dart' show UpdateKind, Variable;

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

  @override
  Future<void> clearAgentContent(String agentId) {
    // 委托给 AppDatabase.clearAgentContent —— 该方法封装了事务边界与
    // FTS5/messages/stats/achievements/pending_notifications 的删除顺序约束。
    return _database.clearAgentContent(agentId);
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
  Future<List<Message>> updateStatuses(
    List<String> clientIds,
    MessageStatus status,
  ) async {
    if (clientIds.isEmpty) return <Message>[];

    return _database.transaction(() async {
      // 1. 读取快照。同一事务内 SELECT 与 UPDATE 一致(SQLite deferred
      //    transaction: BEGIN 后第一次读/写时获取 SHARED 锁,后续写升级
      //    RESERVED,其他写事务必须等本事务 COMMIT/ROLLBACK)。
      //    ORDER BY logical_clock ASC 仅作确定性遍历,无业务意义。
      final placeholders = clientIds.map((_) => '?').join(', ');
      final rows = await _database
          .customSelect(
            'SELECT * FROM messages WHERE client_id IN ($placeholders) '
            'ORDER BY logical_clock ASC',
            variables: [for (final id in clientIds) Variable.withString(id)],
            readsFrom: {_database.messages},
          )
          .get();

      // 2. FSM 过滤:只接受合法转换的行,并记录每行的 (clientId, currentStatus)
      //    tuple 供第 3 步做 CAS guard。
      //
      //    BUG G 修复背景:本事务内 SELECT 与 UPDATE 原子,但显式 status
      //    guard 是 defense in depth —— 防止未来重构去掉 transaction wrapper
      //    时引入 race。语义与 [tryTransitionToSending] 的 `AND status = ?`
      //    单行 CAS 一致,只是 [updateStatuses] 走批量路径。
      final expectedTuples = <(String, int)>[]; // (clientId, oldStatus)
      final updatedMessages = <Message>[];
      for (final row in rows) {
        final message = MessageMapper.toDomain(db.Message.fromJson(row.data));
        if (!message.status.canTransitionTo(status)) continue;
        expectedTuples.add((message.clientId, message.status.toInt()));
        updatedMessages.add(message.transitionTo(status));
      }

      if (expectedTuples.isEmpty) return <Message>[];

      // 3. BUG J 修复:用 [customUpdate] + `updates: {messages}` 替代
      //    [customStatement] —— customStatement 不触发 messages 表的 stream
      //    watcher invalidate,导致 watchOutboxCount / watchByConversation 等
      //    stream 不会发射新值,OutboxWarningBanner 等 UI 显示陈旧计数。
      //
      //    BUG G 修复:WHERE 子句用 tuple IN
      //    `(client_id, status) IN ((?, ?), (?, ?), ...)` 做 CAS guard。
      //    若某行的 status 在 SELECT 之后被并发路径修改,该 tuple 不再匹配,
      //    UPDATE 跳过该行,不会用 stale snapshot 覆盖新状态。
      final tuplePlaceholders = expectedTuples.map((_) => '(?, ?)').join(', ');
      final args = <Object>[status.toInt()];
      for (final (clientId, oldStatus) in expectedTuples) {
        args.add(clientId);
        args.add(oldStatus);
      }
      await _database.customUpdate(
        'UPDATE messages SET status = ? '
        'WHERE (client_id, status) IN ($tuplePlaceholders)',
        variables: [for (final arg in args) Variable<Object>(arg)],
        updateKind: UpdateKind.update,
        updates: {_database.messages},
      );

      return updatedMessages;
    });
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
  Future<int> dedupeConversation(String conversationId) async {
    // 加载该会话全部消息(大 limit 等价于全量),交给 MessageClusterDeduper 规划
    // 哪些 clientId 应删除(空 content text + (role, content) 聚簇去重)。
    final all = await getByConversation(conversationId, limit: 1 << 20);
    final toDelete = MessageClusterDeduper.plan(all);
    if (toDelete.isEmpty) return 0;

    // Bug #5 修复: SQLite SQLITE_MAX_VARIABLE_NUMBER 限制 (现代默认值 32766,
    // 历史默认值 999). 老 install 累积大量 legacy CatchUp 重复时,单条
    // `WHERE client_id IN (?, ?, ...)` 会超出变量上限触发
    // "too many SQL variables" → 整个 dedupe 失败。
    //
    // 与 batchInsertMessages (database.dart:325) 共用 900 变量守卫 —— 留余量
    // 给后续 FTS/SELECT 语句,也保持项目风格统一。
    const _chunkSize = 900;
    final deleteList = toDelete.toList();

    // 单事务批量删除 + FTS5 同步(分块):
    //   1) FTS5 'delete' 每块一次性把所有 doomed 行的 rowid+content 拉出来 purge
    //      (必须在 messages 删除之前,否则 rowid 找不到)
    //   2) messages 单条 IN-clause DELETE
    // 替代旧的 N × (SELECT rowid + DELETE + FTS5 sync) 循环。
    await _database.transaction(() async {
      for (var i = 0; i < deleteList.length; i += _chunkSize) {
        final chunk = deleteList.sublist(
          i,
          i + _chunkSize > deleteList.length
              ? deleteList.length
              : i + _chunkSize,
        );
        final placeholders = List.filled(chunk.length, '?').join(', ');
        await _database.customStatement(
          "INSERT INTO messages_fts(messages_fts, rowid, content) "
          "SELECT 'delete', rowid, content FROM messages "
          "WHERE client_id IN ($placeholders)",
          chunk,
        );
        await _database.customStatement(
          'DELETE FROM messages WHERE client_id IN ($placeholders)',
          chunk,
        );
      }
    });
    return toDelete.length;
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
