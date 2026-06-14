import 'package:drift/drift.dart';

part 'database.g.dart';

/// Application database for ClawHub.
///
/// Tables and named queries are defined in [schema.drift].
/// Complex queries that can't be expressed as named queries
/// (e.g., dynamic IN clauses) are implemented as Dart methods below.
@DriftDatabase(include: {'schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

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
      },
      onUpgrade: (migrator, from, to) async {
        // Schema v1: no prior versions to migrate from.
        // When schemaVersion is bumped, add migration steps here for each
        // version increment (e.g. if (from < 2) { ... }).
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
  Future<void> purgeMessagesFtsForInstance(String instanceId) async {
    final rows = await customSelect(
      'SELECT m.rowid, m.content FROM messages m '
      'JOIN conversations c ON m.conversation_id = c.id '
      'WHERE c.instance_id = ?',
      variables: [Variable.withString(instanceId)],
      readsFrom: {messages},
    ).get();
    for (final row in rows) {
      await syncFtsDelete(row.read<int>('rowid'), row.read<String?>('content'));
    }
  }

  /// Purge FTS5 entries for all messages belonging to a given agent.
  Future<void> purgeMessagesFtsForAgent(String agentId) async {
    final rows = await customSelect(
      'SELECT rowid, content FROM messages WHERE agent_id = ?',
      variables: [Variable.withString(agentId)],
      readsFrom: {messages},
    ).get();
    for (final row in rows) {
      await syncFtsDelete(row.read<int>('rowid'), row.read<String?>('content'));
    }
  }

  /// Purge FTS5 entries for all messages in a given conversation.
  Future<void> purgeMessagesFtsForConversation(String conversationId) async {
    final rows = await customSelect(
      'SELECT rowid, content FROM messages WHERE conversation_id = ?',
      variables: [Variable.withString(conversationId)],
      readsFrom: {messages},
    ).get();
    for (final row in rows) {
      await syncFtsDelete(row.read<int>('rowid'), row.read<String?>('content'));
    }
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
