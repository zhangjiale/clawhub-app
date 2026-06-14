import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

import '../database/database.dart' as db;

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
      quickCommands: _parseQuickCommands(row.quickCommandsJson),
      createdAt: row.createdAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static List<QuickCommand> _parseQuickCommands(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map(
            (e) => QuickCommand(
              id: e['id'] as String? ?? '',
              agentId: e['agentId'] as String? ?? '',
              label: e['label'] as String? ?? '',
              payload: e['payload'] as String? ?? '',
              sortOrder: e['sortOrder'] as int? ?? 0,
            ),
          )
          .toList();
    } catch (error, stackTrace) {
      debugPrint('Failed to parse quick_commands JSON: $error\n$stackTrace');
      return [];
    }
  }
}
