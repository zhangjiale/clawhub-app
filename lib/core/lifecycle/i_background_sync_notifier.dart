import '../../domain/models/agent.dart';
import '../../domain/models/message.dart';

/// Interface for receiving pulled messages from [BackgroundSyncRunner].
///
/// Implementations handle incoming messages (e.g., dispatch local
/// notifications, update badge counts, etc.).
abstract class IBackgroundSyncNotifier {
  /// Called with messages that were actually inserted by the runner.
  ///
  /// [resolveAgent] is a callback that looks up an agent by
  /// (instanceId, agentRemoteId). The first argument (instanceId) may be
  /// empty — implementations should close over the real instanceId.
  Future<void> handlePulledMessages({
    required List<Message> messages,
    required Agent? Function(String instanceId, String agentRemoteId)
    resolveAgent,
  });
}
