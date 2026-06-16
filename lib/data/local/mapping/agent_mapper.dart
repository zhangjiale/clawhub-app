import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:flutter/foundation.dart';

import '../database/database.dart' as db;
import 'quick_command_codec.dart';

/// Maps between Drift-generated [db.Agent] rows and the domain [Agent] model.
class AgentMapper {
  const AgentMapper._();

  /// Convert a Drift row to a domain [Agent].
  static Agent toDomain(db.Agent row) {
    final localId = row.localId;
    if (localId == null) throw StateError('Agent row has null primary key');
    return Agent(
      localId: localId,
      remoteId: row.remoteId,
      instanceId: row.instanceId,
      name: row.name,
      nickname: row.nickname,
      avatarUrl: row.avatarUrl,
      themeColor: row.themeColor ?? '#007AFF',
      description: row.description,
      isPinned: row.isPinned == 1,
      quickCommands: _safeDeserializeQuickCommands(row.quickCommandsJson),
      createdAt: row.createdAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Deserialize quick_commands_json with graceful fallback.
  /// Corrupted JSON is logged and returns an empty list so the app doesn't
  /// crash — the user can still re-add their commands.
  static List<QuickCommand> _safeDeserializeQuickCommands(String? json) {
    try {
      return QuickCommandCodec.deserialize(json);
    } catch (error, stackTrace) {
      debugPrint('Failed to parse quick_commands JSON: $error\n$stackTrace');
      return [];
    }
  }
}
