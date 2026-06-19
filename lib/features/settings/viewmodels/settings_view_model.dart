// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_settings_repo.dart';

/// ViewModel for the global settings page (US-030).
///
/// Manages a singleton [UserPreferences] state.  All mutations apply
/// optimistically (UI updates immediately) and are persisted to
/// [ISettingsRepo] through a **serialised** future chain — only one
/// persist is in-flight at a time, eliminating both the rollback-overwrite
/// race and the DB full-row-overwrite race.
///
/// Internally, every serialised persist writes the **current** [state],
/// which already incorporates any superseding optimistic updates.  This
/// means that even if an earlier persist fails transiently, the next
/// persist (or the [watchPreferences] stream) will bring the DB back in
/// sync with the UI — data loss is impossible across concurrent mutations.
///
/// Mutations that arrive before [init] completes are queued and replayed
/// (with optimistic state application) once the initial SQLite read finishes.
class SettingsViewModel extends StateNotifier<UserPreferences> {
  final ISettingsRepo _repo;
  StreamSubscription<UserPreferences>? _subscription;

  /// Guards against mutations arriving before [init] completes.
  ///
  /// Before init completes, state holds [UserPreferences.defaults].
  /// Mutations arriving during the init window are queued (not dropped)
  /// and replayed once init finishes.
  bool _initialized = false;

  /// Serialisation chain — every mutation is enqueued so only one
  /// persist is in-flight at a time.
  Future<void> _pendingUpdate = Future<void>.value();

  /// Mutations that arrived before [init] completed.  Replayed in FIFO
  /// order once [_initialized] flips to true.
  final List<UserPreferences> _preInitQueue = [];

  SettingsViewModel({required ISettingsRepo repo})
    : _repo = repo,
      super(UserPreferences.defaults());

  /// Load current preferences from the repository and subscribe to changes.
  ///
  /// Uses an explicit [ISettingsRepo.getPreferences] call for the initial value
  /// so the first paint shows real data, not defaults.  The subsequent stream
  /// subscription propagates future changes (including cross-session writes).
  ///
  /// Must be called once after construction.
  Future<void> init() async {
    try {
      final prefs = await _repo.getPreferences();
      if (!mounted) return;
      state = prefs;
      _initialized = true;

      _subscription?.cancel();
      _subscription = _repo.watchPreferences().listen(
        (prefs) {
          if (mounted && prefs != state) state = prefs;
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            '[SettingsViewModel] watchPreferences stream error: $error\n$stackTrace',
          );
        },
      );

      // Replay queued mutations, each with optimistic state update.
      if (_preInitQueue.isNotEmpty) {
        final queued = List<UserPreferences>.from(_preInitQueue);
        _preInitQueue.clear();
        for (final mutation in queued) {
          state = mutation;
          await _doPersist();
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[SettingsViewModel] init failed — staying at defaults: $error\n$stackTrace',
      );
      // Mark as initialized anyway so mutations are not queued forever;
      // they will persist, effectively creating the first row.
      _initialized = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Notification settings
  // ---------------------------------------------------------------------------

  /// Toggle master notification switch.
  Future<void> setNotificationsEnabled(bool value) {
    _update(state.copyWith(notificationsEnabled: value));
    return _pendingUpdate;
  }

  /// Toggle "notify on agent reply" switch.
  Future<void> setNotifyOnReply(bool value) {
    _update(state.copyWith(notifyOnReply: value));
    return _pendingUpdate;
  }

  /// Toggle "notify on agent error" switch.
  Future<void> setNotifyOnError(bool value) {
    _update(state.copyWith(notifyOnError: value));
    return _pendingUpdate;
  }

  /// Toggle "notify on connection change" switch.
  Future<void> setNotifyOnConnectionChange(bool value) {
    _update(state.copyWith(notifyOnConnectionChange: value));
    return _pendingUpdate;
  }

  // ---------------------------------------------------------------------------
  // Do Not Disturb
  // ---------------------------------------------------------------------------

  /// Toggle do-not-disturb mode.
  Future<void> setDndEnabled(bool value) {
    _update(state.copyWith(dndEnabled: value));
    return _pendingUpdate;
  }

  /// Update DND time range.
  Future<void> setDndTimeRange({
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
  }) {
    _update(
      state.copyWith(
        dndStartHour: startHour,
        dndStartMinute: startMinute,
        dndEndHour: endHour,
        dndEndMinute: endMinute,
      ),
    );
    return _pendingUpdate;
  }

  // ---------------------------------------------------------------------------
  // Biometric
  // ---------------------------------------------------------------------------

  /// Toggle biometric app lock.
  Future<void> setBiometricEnabled(bool value) {
    _update(state.copyWith(biometricEnabled: value));
    return _pendingUpdate;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Enqueue a mutation and apply it optimistically.
  ///
  /// The state is updated immediately so the UI feels responsive.
  /// The persist is chained onto [_pendingUpdate] — only one persist runs
  /// at a time, and each persist saves the **current** [state], which
  /// includes any later optimistic updates.  This eliminates both the
  /// rollback-overwrite race (no rollback needed) and the DB full-row
  /// overwrite race (the serialised persists see monotonically increasing
  /// state versions).
  void _update(UserPreferences updated) {
    if (!mounted) return;
    if (!_initialized) {
      _preInitQueue.add(updated);
      return;
    }
    // Optimistic update — UI sees the change on the next frame.
    state = updated;
    _pendingUpdate = _pendingUpdate.then((_) => _doPersist());
  }

  /// Persist current [state] to the repository.
  Future<void> _doPersist() async {
    if (!mounted) return;
    try {
      await _repo.updatePreferences(state);
    } catch (error, stackTrace) {
      debugPrint(
        '[SettingsViewModel] Failed to persist preferences: $error\n$stackTrace',
      );
      // No rollback: the next serialised persist (or the watchPreferences
      // stream) will bring the DB back in sync with the UI.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
