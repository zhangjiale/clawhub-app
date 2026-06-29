import 'i_background_sync_prefs.dart';

/// Lets background sync skip itself when the main isolate is already running.
///
/// Semantics: when the main isolate is active, the live `messageStream`
/// already drives notifications — a background pull would only duplicate
/// work. The flag is best-effort: `onPaused` writes asynchronously; if a
/// background tick reads `true` before the write flushes, it skips
/// conservatively (wastes one 15-min window, no correctness impact).
class BackgroundSyncGate {
  final IBackgroundSyncPrefs prefs;
  BackgroundSyncGate({required this.prefs});

  /// True → background sync should skip this tick.
  Future<bool> shouldSkip() => prefs.mainActive;

  Future<void> setMainActive(bool active) => prefs.setMainActive(active);

  Future<void> clear() => prefs.clear();
}
