/// Cross-isolate persistence of the "main isolate is active" flag.
///
/// Production impl (Task 9) wraps `SharedPreferences`; tests inject a fake.
/// workmanager runs same-process by default (enableSeparateBackgroundProcess=false),
/// so SharedPreferences is shared between main and background isolates.
abstract class IBackgroundSyncPrefs {
  /// Whether the main (UI) isolate is currently active/foreground.
  Future<bool> get mainActive;

  /// Persist the main-isolate-active flag.
  Future<void> setMainActive(bool active);

  /// Reset the flag to inactive (used on dispose / test teardown).
  Future<void> clear();
}
