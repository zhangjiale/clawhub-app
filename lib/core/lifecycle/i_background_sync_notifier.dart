import '../../domain/models/agent.dart';
import '../../domain/models/message.dart';

/// Interface for receiving pulled messages from [BackgroundSyncRunner].
///
/// Implementations handle incoming messages (e.g., dispatch local
/// notifications, update badge counts, etc.).
abstract class IBackgroundSyncNotifier {
  /// Called with messages that were actually inserted by the runner.
  ///
  /// [resolveAgent] looks up an agent by its remote id. The caller
  /// ([BackgroundSyncRunner]) closes over the real instanceId when building
  /// the callback, so the instance is already in scope here — the lookup only
  /// needs the agentRemoteId carried on each [Message].
  Future<void> handlePulledMessages({
    required List<Message> messages,
    required Agent? Function(String agentRemoteId) resolveAgent,
  });
}
