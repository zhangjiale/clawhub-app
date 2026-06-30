import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_settings_repo.dart';
import 'package:claw_hub/features/settings/viewmodels/settings_view_model.dart';

class MockSettingsRepo extends Mock implements ISettingsRepo {}

void main() {
  setUpAll(() {
    registerFallbackValue(UserPreferences.defaults());
  });

  late MockSettingsRepo repo;
  late StreamController<UserPreferences> prefsController;

  setUp(() {
    repo = MockSettingsRepo();
    prefsController = StreamController<UserPreferences>.broadcast();

    when(
      () => repo.getPreferences(),
    ).thenAnswer((_) async => UserPreferences.defaults());
    when(
      () => repo.watchPreferences(),
    ).thenAnswer((_) => prefsController.stream);
    when(() => repo.updatePreferences(any())).thenAnswer((_) async {});
  });

  tearDown(() {
    prefsController.close();
  });

  group('SettingsViewModel.init', () {
    test('should load preferences and emit state on init', () async {
      const expected = UserPreferences(notificationsEnabled: false);
      when(() => repo.getPreferences()).thenAnswer((_) async => expected);

      final vm = SettingsViewModel(repo: repo);
      expect(
        vm.state,
        equals(UserPreferences.defaults()),
        reason: 'initial state before init',
      );

      await vm.init();

      expect(vm.state, equals(expected), reason: 'state after init');
    });

    test('should emit stream values after init', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      expect(vm.state, equals(UserPreferences.defaults()));

      final updated = UserPreferences.defaults().copyWith(dndEnabled: true);
      prefsController.add(updated);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(vm.state.dndEnabled, isTrue, reason: 'stream update reflected');
    });

    test('should replay pre-init mutations after init completes', () async {
      final vm = SettingsViewModel(repo: repo);

      // Fire a mutation before init — should be queued, not dropped
      await vm.setDndEnabled(true);
      // State is still defaults (optimistic update, but _initialized is false,
      // so it's queued) — wait, with the new code, the optimistic update still
      // applies immediately? Let me check...
      //
      // Actually, _update() checks !_initialized and queues to _preInitQueue.
      // The state is STILL updated optimistically (because _update doesn't change
      // state before the guard). Wait, no — _update used to check _initialized
      // BEFORE setting state. The new _update checks !_initialized and queues,
      // WITHOUT updating state. So pre-init mutations don't update state until
      // init completes and replays them.
      //
      // But actually I designed the new code so _update sets state optimistically
      // even for pre-init mutations? Let me check...
      //
      // New _update:
      // void _update(UserPreferences updated) {
      //   if (!mounted) return;
      //   if (!_initialized) {
      //     _preInitQueue.add(updated);
      //     return;  // <-- returns BEFORE setting state!
      //   }
      //   _pendingUpdate = _pendingUpdate.then((_) => _doUpdate(updated));
      // }
      //
      // So pre-init mutations are queued but state is NOT updated. This means
      // the UI won't show the optimistic update for pre-init toggles. This is
      // a minor UX issue but avoids the flicker of showing defaults → mutation
      // → real data.
      //
      // After init, the queued mutations are replayed with await _doUpdate,
      // which sets state.

      await vm.init();

      // After init + replay, dndEnabled should be true
      expect(vm.state.dndEnabled, isTrue);
      verify(() => repo.updatePreferences(any())).called(1);
    });
  });

  group('Notification mutators', () {
    test('setNotificationsEnabled should update state and persist', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      await vm.setNotificationsEnabled(false);
      expect(vm.state.notificationsEnabled, isFalse);

      verify(() => repo.updatePreferences(any())).called(1);
    });

    test('setNotifyOnReply should update state and persist', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      await vm.setNotifyOnReply(false);
      expect(vm.state.notifyOnReply, isFalse);

      verify(() => repo.updatePreferences(any())).called(1);
    });

    test('setNotifyOnError should update state and persist', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      await vm.setNotifyOnError(false);
      expect(vm.state.notifyOnError, isFalse);

      verify(() => repo.updatePreferences(any())).called(1);
    });

    test(
      'setNotifyOnConnectionChange should update state and persist',
      () async {
        final vm = SettingsViewModel(repo: repo);
        await vm.init();

        await vm.setNotifyOnConnectionChange(false);
        expect(vm.state.notifyOnConnectionChange, isFalse);

        verify(() => repo.updatePreferences(any())).called(1);
      },
    );
  });

  group('Do Not Disturb mutators', () {
    test('setDndEnabled should update state and persist', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      await vm.setDndEnabled(true);
      expect(vm.state.dndEnabled, isTrue);

      verify(() => repo.updatePreferences(any())).called(1);
    });

    test('setDndTimeRange should update all four time fields', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      await vm.setDndTimeRange(
        startHour: 23,
        startMinute: 30,
        endHour: 7,
        endMinute: 15,
      );

      expect(vm.state.dndStartHour, 23);
      expect(vm.state.dndStartMinute, 30);
      expect(vm.state.dndEndHour, 7);
      expect(vm.state.dndEndMinute, 15);

      verify(() => repo.updatePreferences(any())).called(1);
    });
  });

  group('Biometric mutator', () {
    test('setBiometricEnabled should update state and persist', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      await vm.setBiometricEnabled(true);
      expect(vm.state.biometricEnabled, isTrue);

      verify(() => repo.updatePreferences(any())).called(1);
    });
  });

  group('Background Sync mutator', () {
    test('setBackgroundSyncEnabled should update state and persist', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      expect(vm.state.backgroundSyncEnabled, isTrue); // default

      await vm.setBackgroundSyncEnabled(false);
      expect(vm.state.backgroundSyncEnabled, isFalse);
      verify(() => repo.updatePreferences(any())).called(1);

      await vm.setBackgroundSyncEnabled(true);
      expect(vm.state.backgroundSyncEnabled, isTrue);
    });
  });

  group('Serialised mutations', () {
    test('concurrent mutations should all be persisted', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      // Fire two mutations concurrently — both should persist
      final future1 = vm.setNotificationsEnabled(false);
      final future2 = vm.setDndEnabled(true);

      await Future.wait([future1, future2]);

      // Both mutations applied (optimistic + serialised persist writes latest state)
      expect(vm.state.notificationsEnabled, isFalse);
      expect(vm.state.dndEnabled, isTrue);
      verify(() => repo.updatePreferences(any())).called(2);
    });
  });

  group('Error handling', () {
    test('should keep optimistic state even when persistence fails', () async {
      final failingRepo = MockSettingsRepo();
      when(
        () => failingRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(
        () => failingRepo.watchPreferences(),
      ).thenAnswer((_) => const Stream.empty());
      when(() => failingRepo.updatePreferences(any())).thenAnswer((_) async {
        throw Exception('DB write failed');
      });

      final vm = SettingsViewModel(repo: failingRepo);
      await vm.init();

      // Mutation should not throw — optimistic state sticks
      await vm.setNotificationsEnabled(false);

      // State reflects the user's intent even though persist failed
      expect(
        vm.state.notificationsEnabled,
        isFalse,
        reason: 'optimistic state persists in memory',
      );
      verify(() => failingRepo.updatePreferences(any())).called(1);

      // The DB is out of sync, but the next successful persist
      // (or watchPreferences stream) will correct it.
    });
  });

  group('Dispose', () {
    test('should cancel stream subscription on dispose', () async {
      final vm = SettingsViewModel(repo: repo);
      await vm.init();

      // Capture stream subscription before dispose
      expect(vm.mounted, isTrue);
      vm.dispose();
      expect(vm.mounted, isFalse);

      // After dispose, stream updates should not crash
      final updated = UserPreferences.defaults().copyWith(dndEnabled: true);
      prefsController.add(updated);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // No assertion needed on state (it throws after dispose) —
      // the test passes if no exception is thrown.
    });
  });
}
