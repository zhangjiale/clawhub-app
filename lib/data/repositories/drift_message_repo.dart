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

      // Sync FTS5 index (best-effort — message persistence is primary).
      // FTS sync failure must not prevent the message from being saved.
      try {
        final rowid = await _database.getLastInsertRowid();
        await _database.syncFtsInsert(rowid, message.content);
      } catch (error, stackTrace) {
        debugPrint(
          'FTS sync failed for message ${message.clientId}: $error\n$stackTrace',
        );
      }
    });

    return message;
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
    // Load all messages in this conversation (sorted ASC)
    final all = await _database
        .getAllMessagesByConversationAsc(conversationId)
        .get();
    if (all.isEmpty) return [];

    final messages = all.map(MessageMapper.toDomain).toList();

    // Find the target
    final idx = messages.indexWhere((m) => m.clientId == targetClientId);
    if (idx < 0) return [];

    final start = (idx - before).clamp(0, messages.length);
    final end = (idx + after + 1).clamp(0, messages.length);
    return messages.sublist(start, end);
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
