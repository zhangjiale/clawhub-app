import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/repositories/i_conversation_repo.dart';
import 'package:drift/drift.dart' show Variable;

import '../local/database/database.dart' as db;
import '../local/mapping/conversation_mapper.dart';

/// Drift/SQLite implementation of [IConversationRepo].
class DriftConversationRepo implements IConversationRepo {
  final db.AppDatabase _database;

  DriftConversationRepo(this._database);

  @override
  Future<Conversation> getOrCreate(String instanceId, String agentId) async {
    final id = Conversation.generateId(instanceId, agentId);

    // INSERT OR IGNORE — if it already exists, nothing happens.
    // Pass explicit defaults (0 / 0 / 0) instead of relying on schema
    // DEFAULTs so repo behavior does not silently drift if the schema
    // changes later.
    await _database.insertConversation(
      id,
      agentId,
      instanceId,
      null, // lastMessageId
      null, // lastMessagePreview
      0, // lastMessageTime
      null, // lastMessageRole
      0, // unreadCount
      0, // isMuted
    );

    final row = await _database.getConversationById(id).getSingle();
    return ConversationMapper.toDomain(row);
  }

  @override
  Future<List<Conversation>> getAllWithMessages() async {
    final rows = await _database.getAllConversationsWithMessages().get();
    return rows.map(ConversationMapper.toDomain).toList();
  }

  @override
  Future<Conversation?> getById(String id) async {
    final row = await _database.getConversationById(id).getSingleOrNull();
    return row != null ? ConversationMapper.toDomain(row) : null;
  }

  @override
  Future<Map<String, Conversation>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final placeholders = ids.map((_) => '?').join(', ');
    final rows = await _database
        .customSelect(
          'SELECT * FROM conversations WHERE id IN ($placeholders)',
          variables: [for (final id in ids) Variable.withString(id)],
          readsFrom: {_database.conversations},
        )
        .get();
    final result = <String, Conversation>{};
    for (final row in rows) {
      final conv = ConversationMapper.toDomain(
        db.Conversation.fromJson(row.data),
      );
      result[conv.id] = conv;
    }
    return result;
  }

  @override
  Future<Conversation> updateLastMessage({
    required String conversationId,
    required String messageId,
    required String preview,
    required int timestamp,
    required MessageRole role,
  }) async {
    await _database.updateConversationLastMessage(
      messageId,
      preview,
      timestamp,
      role.toInt(),
      conversationId,
    );
    final updated = await getById(conversationId);
    if (updated == null) throw StateError('会话不存在: $conversationId');
    return updated;
  }

  @override
  Future<Conversation> incrementUnread(
    String conversationId, {
    int count = 1,
  }) async {
    final current = await getById(conversationId);
    if (current == null) throw StateError('会话不存在: $conversationId');
    await _database.incrementConversationUnread(
      count.toDouble(),
      conversationId,
    );
    return current.copyWith(unreadCount: current.unreadCount + count);
  }

  @override
  Future<Conversation> clearUnread(String conversationId) async {
    final current = await getById(conversationId);
    if (current == null) throw StateError('会话不存在: $conversationId');
    await _database.clearConversationUnread(conversationId);
    return current.clearUnread();
  }

  @override
  Future<Conversation> toggleMute(String conversationId) async {
    final current = await getById(conversationId);
    if (current == null) throw StateError('会话不存在: $conversationId');
    await _database.toggleConversationMute(conversationId);
    return current.copyWith(isMuted: !current.isMuted);
  }

  @override
  Future<void> deleteByInstanceId(String instanceId) async {
    // Purge FTS5 entries for every conversation in this instance BEFORE
    // the FK CASCADE wipes messages — otherwise the messages_fts virtual
    // table retains orphaned rows that surface as phantom search results.
    await _database.transaction(() async {
      final convRows = await _database
          .customSelect(
            'SELECT id FROM conversations WHERE instance_id = ?',
            variables: [Variable.withString(instanceId)],
          )
          .get();
      for (final row in convRows) {
        await _database.purgeMessagesFtsForConversation(row.read<String>('id'));
      }
      await _database.deleteConversationsByInstanceId(instanceId);
    });
  }
}
