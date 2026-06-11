import 'dart:convert';

import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message_status.dart';

import '../database/database.dart' as db;

/// Maps between Drift-generated [db.Message] rows and the domain [Message] model.
class MessageMapper {
  const MessageMapper._();

  /// Convert a Drift row to a domain [Message].
  static Message toDomain(db.Message row) {
    return Message(
      clientId: row.clientId,
      serverId: row.serverId,
      conversationId: row.conversationId,
      agentId: row.agentId,
      role: MessageRole.fromInt(row.role),
      content: row.content,
      type: MessageType.fromInt(row.type),
      status: MessageStatus.fromInt(row.status),
      logicalClock: row.logicalClock,
      timestamp: row.timestamp,
      metadata: _parseMetadata(row.metadata),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Map<String, dynamic>? _parseMetadata(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (error, stackTrace) {
      print('Failed to parse message metadata JSON: $error\n$stackTrace');
      return null;
    }
  }
}
