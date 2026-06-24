import 'package:drift/drift.dart';

part 'database.g.dart';

/// 单条消息的原始字段，用于批量插入（与 [AppDatabase.insertMessage] 的参数一一对应）。
///
/// database 层保持 drift-pure，不引入 domain Message 依赖，故用 record 传参。
typedef MessageRow = ({
  String clientId,
  String? serverId,
  String conversationId,
  String agentId,
  int role,
  String? content,
  int type,
  int status,
  int logicalClock,
  int timestamp,
  String? metadata,
});

/// Application database for ClawHub.
///
/// Tables and named queries are defined in [schema.drift].
/// Complex queries that can't be expressed as named queries
/// (e.g., dynamic IN clauses) are implemented as Dart methods below.
@DriftDatabase(include: {'schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
      beforeOpen: (details) async {
        // FTS5 virtual table MUST be created AFTER Drift manages its tables,
        // because content='messages' requires the messages table to exist.
        //
        // NativeDatabase.setup fires BEFORE Drift creates tables — too early.
        // MigrationStrategy.beforeOpen fires AFTER schema validation/creation,
        // which is the correct lifecycle hook for FTS5 setup.
        await customStatement('''
          CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            content,
            content='messages',
            content_rowid='rowid',
            tokenize='unicode61'
          )
        ''');

        // Backfill FTS5 index for pre-existing messages (e.g. databases
        // created before FTS5 was introduced, or databases where the old
        // setup()-based creation silently failed because messages didn't
        // exist yet at that point).
        //
        // Guard avoids full messages table scan on every open: once the
        // initial backfill completes, per-message FTS sync in
        // DriftMessageRepo keeps the index current.
        await customStatement('''
          INSERT INTO messages_fts(rowid, content)
          SELECT m.rowid, m.content FROM messages m
          WHERE (SELECT COUNT(*) FROM messages_fts) = 0
            AND NOT EXISTS (
              SELECT 1 FROM messages_fts f WHERE f.rowid = m.rowid
            )
        ''');

        // US-018: partial unique index for pending_notifications dedup.
        // Only rows with a non-null message_server_id participate in the
        // (instance_id, message_server_id) uniqueness constraint. Rows with
        // NULL serverId always insert (dedup falls back to in-memory LRU in
        // NotificationDispatcher). IF NOT EXISTS makes this idempotent across
        // fresh installs (onCreate) and upgrades alike.
        await customStatement('''
          CREATE UNIQUE INDEX IF NOT EXISTS pending_notifications_by_server
          ON pending_notifications(instance_id, message_server_id)
          WHERE message_server_id IS NOT NULL
        ''');
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.createTable(userPreferences);
        }
        if (from < 3) {
          await migrator.createTable(agentStats);
          await migrator.createTable(achievementUnlocks);
        }
        if (from < 4) {
          await migrator.createTable(pendingNotifications);
        }
        if (from < 5) {
          // V1 → V2 default theme_color migration (issue #1).
          //
          // Pre-V2 installs used '#007AFF' as the default for the agents
          // table. The schema default was changed to '#4F83FF' (V2 sapphire)
          // but existing rows still carry the old color value, causing a
          // visible color mismatch between old and new agents. Rewrite those
          // rows in place so all agents display the V2 color.
          //
          // Only '#007AFF' is touched — agents with user-chosen colors are
          // preserved (they never had the V1 default).
          await customStatement(
            "UPDATE agents SET theme_color = '#4F83FF' "
            "WHERE theme_color = '#007AFF'",
          );
        }
        if (from < 6) {
          // US-021: Agent tombstone 列。nullable add column 是 SQLite O(1)
          // 操作（只改 schema 不重写行），无需 backfill。removed_at 由
          // DriftAgentRepo.syncFromGateway 独占写入；hidden_at v1 不写入。
          await migrator.addColumn(agents, agents.removedAt);
          await migrator.addColumn(agents, agents.hiddenAt);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // FTS5 helpers — manual sync (Zero-Trigger principle)
  // ---------------------------------------------------------------------------

  /// Insert a row into the FTS5 index after inserting a message.
  ///
  /// FTS5 backfill for pre-existing messages is handled once at database
  /// open in [createAppDatabase]'s setup callback — no lazy guard needed here.
  Future<void> syncFtsInsert(int rowid, String? content) {
    return customStatement(
      'INSERT INTO messages_fts(rowid, content) VALUES (?, ?)',
      [rowid, content],
    );
  }

  /// Remove a row from the FTS5 index when a message is deleted.
  Future<void> syncFtsDelete(int rowid, String? content) {
    return customStatement(
      "INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', ?, ?)",
      [rowid, content],
    );
  }

  /// Purge FTS5 entries for all messages belonging to a given instance,
  /// so that a subsequent `ON DELETE CASCADE` on `instances` does not
  /// leave orphaned search-index rows.
  ///
  /// Must be called inside the same transaction that performs the cascade
  /// delete (callers wrap both in `_database.transaction(...)`).
  ///
  /// Implemented as a single FTS5 `'delete'` command with a `SELECT`
  /// subquery over the messages table — replaces an N+1 per-row loop
  /// (1 round-trip per message) with one round-trip total.
  Future<void> purgeMessagesFtsForInstance(String instanceId) {
    return customStatement(
      "INSERT INTO messages_fts(messages_fts, rowid, content) "
      "SELECT 'delete', m.rowid, m.content "
      'FROM messages m '
      'JOIN conversations c ON m.conversation_id = c.id '
      'WHERE c.instance_id = ?',
      [instanceId],
    );
  }

  /// Purge ALL FTS5 entries at once (US-030 清除缓存路径).
  ///
  /// FTS5 is a separate virtual table — `DELETE FROM messages` does NOT
  /// cascade into `messages_fts`. We must explicitly clear it before
  /// the bulk agent delete that triggers the message cascade, or search
  /// results will be left pointing at non-existent rowids.
  ///
  /// Uses FTS5's `'delete-all'` special command (vs. plain `DELETE FROM
  /// messages_fts`). The special command is required for **contentless**
  /// FTS5 tables (`content='messages'` in our schema) — plain `DELETE`
  /// would trigger FTS5's integrity check and raise "database disk image
  /// is malformed" when the content table is empty.
  ///
  /// Single-statement is also ~100× faster than row-by-row `syncFtsDelete`
  /// loops for large datasets (10k+ messages).
  Future<void> purgeAllMessagesFts() {
    return customStatement(
      "INSERT INTO messages_fts(messages_fts) VALUES('delete-all')",
    );
  }

  /// 清空所有聊天内容,但**保留 agents/conversations 骨架**(US-030 清除缓存路径)。
  ///
  /// 删除:messages / tool_calls / agent_stats / achievement_unlocks /
  ///      pending_notifications
  /// 保留:agents / conversations / instances / user_preferences
  ///
  /// **为什么不删 agents(改自旧 `deleteAllAgents`)**:旧实现 `DELETE FROM
  /// agents` 触发 CASCADE 删掉 conversations,会导致**进行中的流式会话**在
  /// `StreamingDone` 到达时,最终消息 INSERT 因 `conversation_id` 外键不存在
  /// 而抛 `FOREIGN KEY constraint failed`,Agent 回复永久丢失。
  ///
  /// 保留骨架后,clearAll 期间仍在流式的会话能正常落库;Agent 列表页也仍
  /// 显示这些 agent(仅无消息历史),对用户更友好。
  ///
  /// **为什么清 pending_notifications**:该表用 `message_server_id` 做跨重启
  /// 去重。消息删后若残留旧条目,dispatcher 会把同一 serverId 的新通知误判
  /// 为「已通知」而跳过(去重误杀),DND 汇总通知也会引用已清空对话。该表是
  /// 派生缓存(可由新消息重建),一并清理以保持 clearAll 语义完整。
  ///
  /// **顺序约束**:本方法内部的 `DELETE FROM messages` 必须在
  /// `purgeAllMessagesFts`(由 [DriftSettingsRepo.clearAll] 在本方法之前、
  /// 同一事务内调用)之后执行——contentless FTS5 表要求 content 表非空时
  /// 才能执行 'delete-all'。本方法不调用 purge,顺序由调用方保证。
  Future<void> clearAllContent() async {
    await customStatement('DELETE FROM tool_calls');
    await customStatement('DELETE FROM agent_stats');
    await customStatement('DELETE FROM achievement_unlocks');
    await customStatement('DELETE FROM messages');
    await customStatement('DELETE FROM pending_notifications');
    // 不删 agents / conversations —— 保留骨架,保证流式会话的最终消息
    // 落库时 conversation_id 外键仍存在(见方法文档)。
  }

  /// Purge FTS5 entries for all messages belonging to a given agent.
  ///
  /// Single round-trip FTS5 `'delete'` over a subquery — replaces the
  /// prior per-row SELECT + DELETE loop.
  Future<void> purgeMessagesFtsForAgent(String agentId) {
    return customStatement(
      "INSERT INTO messages_fts(messages_fts, rowid, content) "
      "SELECT 'delete', rowid, content FROM messages WHERE agent_id = ?",
      [agentId],
    );
  }

  /// Purge FTS5 entries for all messages in a given conversation.
  ///
  /// Single round-trip FTS5 `'delete'` over a subquery.
  Future<void> purgeMessagesFtsForConversation(String conversationId) {
    return customStatement(
      "INSERT INTO messages_fts(messages_fts, rowid, content) "
      "SELECT 'delete', rowid, content FROM messages "
      'WHERE conversation_id = ?',
      [conversationId],
    );
  }

  /// Update FTS5 index when message content changes.
  /// Performs delete + insert since FTS5 has no UPDATE.
  Future<void> syncFtsUpdate(
    int rowid,
    String? oldContent,
    String? newContent,
  ) async {
    await syncFtsDelete(rowid, oldContent);
    await syncFtsInsert(rowid, newContent);
  }

  // ---------------------------------------------------------------------------
  // Batch queries — dynamic IN clauses that can't be named queries
  // ---------------------------------------------------------------------------

  /// Batch query: get message counts for multiple agents.
  /// Uses a single SELECT with GROUP BY (Iron Law 6 compliance).
  ///
  /// Returns a map of agentId → count. Agents with zero messages
  /// are not included in the result (caller defaults them to 0).
  Future<Map<String, int>> getMessageCountsByAgent(
    List<String> agentIds,
  ) async {
    if (agentIds.isEmpty) return {};

    // Build parameterized IN clause
    final placeholders = agentIds.map((_) => '?').join(', ');
    final rows = await customSelect(
      'SELECT agent_id, COUNT(*) AS cnt FROM messages '
      'WHERE agent_id IN ($placeholders) GROUP BY agent_id',
      variables: [for (final id in agentIds) Variable.withString(id)],
    ).get();

    final result = <String, int>{};
    for (final row in rows) {
      result[row.read<String>('agent_id')] = row.read<int>('cnt');
    }
    return result;
  }

  /// 批量插入消息 — 单条多行 VALUES INSERT，替代 N 次 [insertMessage] 循环。
  ///
  /// 返回 clientId → rowid 映射，供调用方随后批量同步 FTS5 索引。
  /// **必须在事务内调用**（与 dedup SELECT 同事务，保证原子性与并发安全）。
  ///
  /// SQLite 默认单语句最多 999 个绑定变量；每行 11 列，故上限约 81 行/语句。
  /// 超出时抛 [StateError] —— 调用方应分块。当前 catch-up 单页 50 条安全。
  Future<Map<String, int>> batchInsertMessages(List<MessageRow> rows) async {
    if (rows.isEmpty) return {};

    const columnsPerRow = 11;
    // 留余量给后续 FTS/SELECT 语句，用 900 而非 999。
    final maxRows = 900 ~/ columnsPerRow;
    if (rows.length > maxRows) {
      throw StateError(
        'batchInsertMessages: ${rows.length} rows exceed SQLite variable '
        'limit (max $maxRows rows × $columnsPerRow cols). Chunk the input.',
      );
    }

    // 构建 `VALUES (?,?,?,?,?,?,?,?,?,?,?), (?,?,?,?,?,?,?,?,?,?,?), ...`
    final rowPlaceholder = '(${List.filled(columnsPerRow, '?').join(', ')})';
    final valuesClause = List.filled(rows.length, rowPlaceholder).join(', ');

    // 用 customStatement + 裸值列表（与 syncFtsInsert 一致），避免可空列的
    // Variable 构造问题；null 直接传 null，SQLite 绑定为 NULL。
    final args = <Object?>[];
    for (final m in rows) {
      args
        ..add(m.clientId)
        ..add(m.serverId)
        ..add(m.conversationId)
        ..add(m.agentId)
        ..add(m.role)
        ..add(m.content)
        ..add(m.type)
        ..add(m.status)
        ..add(m.logicalClock)
        ..add(m.timestamp)
        ..add(m.metadata);
    }

    await customStatement(
      'INSERT INTO messages '
      '(client_id, server_id, conversation_id, agent_id, role, content, '
      'type, status, logical_clock, timestamp, metadata) '
      'VALUES $valuesClause',
      args,
    );

    // 一次性查出所有插入行的 clientId → rowid 映射。client_id 有 UNIQUE 索引，
    // 50 条查询开销可忽略。用 IN 子句匹配刚插入的 clientId。
    final clientIds = rows.map((m) => m.clientId).toList();
    final placeholders = clientIds.map((_) => '?').join(', ');
    final selectRows = await customSelect(
      'SELECT rowid, client_id FROM messages WHERE client_id IN ($placeholders)',
      variables: [for (final id in clientIds) Variable.withString(id)],
      readsFrom: {messages},
    ).get();

    final result = <String, int>{};
    for (final row in selectRows) {
      result[row.read<String>('client_id')] = row.read<int>('rowid');
    }
    return result;
  }

  /// 批量同步 FTS5 索引 — 单条多行 VALUES INSERT，替代 N 次 [syncFtsInsert] 循环。
  ///
  /// 与 [syncFtsInsert] 一致：抛出异常由调用方做 best-effort 捕获
  /// （FTS 失败不得阻断消息持久化）。**必须在事务内调用**，紧接
  /// [batchInsertMessages] 之后。
  Future<void> batchSyncFtsInsert(Map<int, String?> rowidToContent) async {
    if (rowidToContent.isEmpty) return;

    // 每行 2 个变量，上限约 450 行。
    final maxRows = 900 ~/ 2;
    if (rowidToContent.length > maxRows) {
      throw StateError(
        'batchSyncFtsInsert: ${rowidToContent.length} entries exceed SQLite '
        'variable limit (max $maxRows rows × 2 cols). Chunk the input.',
      );
    }

    final entries = rowidToContent.entries.toList();
    final valuesClause = List.filled(entries.length, '(?, ?)').join(', ');
    await customStatement(
      'INSERT INTO messages_fts(rowid, content) VALUES $valuesClause',
      [
        for (final e in entries) ...[e.key, e.value],
      ],
    );
  }

  /// Get the rowid and content for a message by its client_id.
  /// Used before FTS5 delete operations — fetches both in a single query.
  Future<({int rowid, String? content})?> getMessageRowidAndContent(
    String clientId,
  ) {
    return customSelect(
          'SELECT rowid, content FROM messages WHERE client_id = ?',
          variables: [Variable.withString(clientId)],
        )
        .map(
          (row) => (
            rowid: row.read<int>('rowid'),
            content: row.read<String?>('content'),
          ),
        )
        .getSingleOrNull();
  }

  /// Get the rowid for a message by its client_id.
  /// Used before FTS5 delete operations.
  Future<int?> getMessageRowid(String clientId) {
    return customSelect(
      'SELECT rowid FROM messages WHERE client_id = ?',
      variables: [Variable.withString(clientId)],
    ).map((row) => row.read<int>('rowid')).getSingleOrNull();
  }

  /// Get the last inserted rowid.
  /// Used after INSERT to sync FTS5.
  Future<int> getLastInsertRowid() {
    return customSelect(
      'SELECT last_insert_rowid() AS rowid',
    ).map((row) => row.read<int>('rowid')).getSingle();
  }

  // ---------------------------------------------------------------------------
  // Agent Stats aggregation — single-query aggregates per agent (Iron Law 6)
  // ---------------------------------------------------------------------------

  /// Count distinct conversations for an agent.
  Future<int> countDialogsForAgent(String agentId) {
    return customSelect(
      'SELECT COUNT(DISTINCT conversation_id) AS cnt FROM messages '
      'WHERE agent_id = ?',
      variables: [Variable.withString(agentId)],
    ).map((row) => row.read<int>('cnt')).getSingle();
  }

  /// Count tool calls for an agent (via messages join).
  Future<int> countToolCallsForAgent(String agentId) {
    return customSelect(
      'SELECT COUNT(*) AS cnt FROM tool_calls '
      'WHERE message_id IN (SELECT client_id FROM messages WHERE agent_id = ?)',
      variables: [Variable.withString(agentId)],
    ).map((row) => row.read<int>('cnt')).getSingle();
  }

  /// Get sorted unique day buckets for an agent's messages.
  ///
  /// Returns Unix timestamps in ascending order, each representing
  /// a unique calendar day on which at least one message was sent/received.
  /// Caller computes activeDays (count) and currentStreak (consecutive-day
  /// walk from today/lastActive backward) in Dart.
  ///
  /// `timestamp` is stored in milliseconds; dividing by 86400000 maps each
  /// row to a UTC calendar day index (seconds since epoch ÷ 86400).
  Future<List<int>> getActiveDayBucketsForAgent(String agentId) {
    return customSelect(
      'SELECT DISTINCT (timestamp / 86400000) AS day_bucket '
      'FROM messages WHERE agent_id = ? '
      'ORDER BY day_bucket ASC',
      variables: [Variable.withString(agentId)],
    ).map((row) => row.read<int>('day_bucket')).get();
  }

  /// Get min and max message timestamps for an agent.
  ///
  /// Returns (firstDialogDate, lastDialogDate) as Unix seconds, or null
  /// if no messages exist.
  Future<({int? firstMsg, int? lastMsg})?> getMessageTimestampRange(
    String agentId,
  ) async {
    final row = await customSelect(
      'SELECT MIN(timestamp) AS first_msg, MAX(timestamp) AS last_msg '
      'FROM messages WHERE agent_id = ?',
      variables: [Variable.withString(agentId)],
    ).getSingleOrNull();
    if (row == null) return null;
    return (
      firstMsg: row.read<int?>('first_msg'),
      lastMsg: row.read<int?>('last_msg'),
    );
  }

  /// Combined messages-stats query — one scan replaces [countDialogsForAgent],
  /// [getMessageCountByAgent], and [getMessageTimestampRange].
  ///
  /// COUNT(*) always returns 0 when no rows match, so null means the
  /// messages table has zero rows for this agent.
  Future<({int dialogs, int messages, int? firstMsg, int? lastMsg})?>
  getMessageStatsForAgent(String agentId) async {
    final row = await customSelect(
      'SELECT '
      'COUNT(DISTINCT conversation_id) AS dialogs, '
      'COUNT(*) AS messages, '
      'MIN(timestamp) AS first_msg, '
      'MAX(timestamp) AS last_msg '
      'FROM messages WHERE agent_id = ?',
      variables: [Variable.withString(agentId)],
    ).getSingleOrNull();
    if (row == null) return null;
    return (
      dialogs: row.read<int>('dialogs'),
      messages: row.read<int>('messages'),
      firstMsg: row.read<int?>('first_msg'),
      lastMsg: row.read<int?>('last_msg'),
    );
  }

  // ---------------------------------------------------------------------------
  // FTS5 search — owns sanitization so callers don't need to know FTS5 syntax
  // ---------------------------------------------------------------------------

  /// Search messages via FTS5 with automatic query sanitization.
  ///
  /// Callers pass a raw user query string; this method handles
  /// FTS5-specific escaping (term quoting) internally.
  Future<List<Message>> searchMessagesSanitized(
    String rawQuery, {
    int limit = 20,
    int offset = 0,
  }) async {
    final sanitized = _sanitizeFtsQuery(rawQuery);
    if (sanitized.isEmpty) return [];
    return searchMessages(sanitized, limit, offset).get();
  }

  /// Escape special characters for FTS5 MATCH queries.
  /// Wraps each term in double quotes to treat it as a literal term.
  /// Doubled double-quotes inside a term are the FTS5 escape for a
  /// literal quote character.
  static String _sanitizeFtsQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return '';

    final terms = trimmed.split(RegExp(r'\s+'));
    return terms.map((t) => '"${t.replaceAll('"', '""')}"').join(' ');
  }
}
