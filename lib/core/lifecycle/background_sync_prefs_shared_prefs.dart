import 'package:shared_preferences/shared_preferences.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_prefs.dart';

/// Production [IBackgroundSyncPrefs] backed by [SharedPreferences].
///
/// The `mainActive` flag is the cross-isolate gate: the main isolate sets it to
/// `true` while in the foreground; the background isolate reads it and skips
/// when the main isolate is active (avoiding redundant work).
class SharedPreferencesBackgroundSyncPrefs implements IBackgroundSyncPrefs {
  static const _key = 'background_gate_main_active';

  const SharedPreferencesBackgroundSyncPrefs();

  Future<SharedPreferences> _sp() => SharedPreferences.getInstance();

  @override
  Future<bool> get mainActive async => (await _sp()).getBool(_key) ?? false;

  @override
  Future<void> setMainActive(bool active) async =>
      (await _sp()).setBool(_key, active);

  @override
  Future<void> clear() async => (await _sp()).remove(_key);
}
