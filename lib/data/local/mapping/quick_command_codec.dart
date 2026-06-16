import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

/// JSON codec for the agents.quick_commands_json column.
///
/// This is the single source of truth for QuickCommand persistence so Drift
/// and in-memory repositories cannot drift apart.
class QuickCommandCodec {
  const QuickCommandCodec._();

  static String serialize(List<QuickCommand> commands) {
    final sorted = [...commands]..sort(QuickCommand.sortByOrder);
    final normalized = [
      for (var i = 0; i < sorted.length; i++)
        {
          'id': sorted[i].id,
          'agentId': sorted[i].agentId,
          'label': sorted[i].label,
          'payload': sorted[i].payload,
          'sortOrder': i,
        },
    ];
    return jsonEncode(normalized);
  }

  /// Deserialize a JSON string into a sorted list of [QuickCommand]s.
  ///
  /// Returns an empty list for null/empty input. Throws [FormatException]
  /// if the top-level JSON is not a valid JSON string, or [TypeError] if the
  /// decoded value is not a JSON array — callers should catch broadly
  /// (e.g. `catch (error, stackTrace)`) to handle both cases.
  ///
  /// Individual corrupted entries are skipped gracefully — a single bad
  /// entry does not cause the entire list to be lost. Skipped entries are
  /// logged via [debugPrint] for diagnostics.
  static List<QuickCommand> deserialize(String? json) {
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    final commands = <QuickCommand>[];
    for (var i = 0; i < list.length; i++) {
      try {
        final e = list[i] as Map<String, dynamic>;
        commands.add(
          QuickCommand(
            id: e['id'] as String? ?? '',
            agentId: e['agentId'] as String? ?? '',
            label: e['label'] as String? ?? '',
            payload: e['payload'] as String? ?? '',
            sortOrder: e['sortOrder'] as int? ?? i,
          ),
        );
      } catch (e, st) {
        debugPrint(
          'Skipping corrupted quick_command entry at index $i: $e\n$st',
        );
      }
    }
    commands.sort(QuickCommand.sortByOrder);
    return commands;
  }
}
