import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';

import '../database/database.dart' as db;

/// Maps between Drift-generated [db.Conversation] rows and the domain [Conversation] model.
class ConversationMapper {
  const ConversationMapper._();

  /// Convert a Drift row to a domain [Conversation].
  static Conversation toDomain(db.Conversation row) {
    final id = row.id;
    if (id == null) throw StateError('Conversation row has null primary key');
    return Conversation(
      id: id,
      agentId: row.agentId,
      instanceId: row.instanceId,
      lastMessageId: row.lastMessageId,
      lastMessagePreview: row.lastMessagePreview,
      lastMessageRole: row.lastMessageRole != null
          ? MessageRole.fromInt(row.lastMessageRole!)
          : null,
      lastMessageTime: row.lastMessageTime ?? 0,
      unreadCount: row.unreadCount ?? 0,
      isMuted: row.isMuted == 1,
    );
  }

}
