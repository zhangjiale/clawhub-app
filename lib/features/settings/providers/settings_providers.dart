import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/iconnectivity.dart';
import 'package:claw_hub/domain/models/storage_info.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/features/settings/viewmodels/settings_view_model.dart';

/// Global settings ViewModel provider (US-030).
///
/// Since settings are app-wide (not per-agent or per-instance), this is a
/// simple [StateNotifierProvider], not a `.family`.
///
/// [SettingsViewModel.init] reads real prefs from SQLite asynchronously.
/// The first frame shows [UserPreferences.defaults] for 1–2 frames until
/// init completes.  Mutations that arrive during the init window are queued
/// and replayed by the ViewModel — no user action is silently dropped.
///
/// The provider's [ref.onDispose] is intentionally omitted:
/// [StateNotifierProvider] already calls [dispose] on the notifier
/// automatically when the provider is disposed.
final settingsViewModelProvider =
    StateNotifierProvider<SettingsViewModel, UserPreferences>((ref) {
      final vm = SettingsViewModel(repo: ref.watch(settingsRepoProvider));
      vm.init().catchError((Object error, StackTrace stackTrace) {
        debugPrint('[SettingsProvider] init() failed: $error\n$stackTrace');
      });
      return vm;
    });

/// Storage info provider (US-030).
///
/// Fetches database size and message count lazily via [ISettingsRepo.getStorageInfo].
/// The [FutureProvider] pattern keeps storage data reactive and handles
/// loading / error states automatically via [AsyncValue].
final storageInfoProvider = FutureProvider<StorageInfo>((ref) {
  return ref.watch(settingsRepoProvider).getStorageInfo();
});

/// Real-time network connectivity state provider (US-030).
///
/// Wraps [IConnectivity.onConnectivityChanged] in a [StreamProvider] so the
/// network settings page can display live connection status (WiFi / Mobile /
/// Ethernet / None) instead of only a static platform hint.
///
/// The stream starts with [ConnectivityResult.none] until the first real
/// platform event arrives, ensuring the provider never hangs in loading state.
final connectivityStateProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) {
  return ref.watch(connectivityProvider).onConnectivityChanged;
});

/// Format a [ConnectivityResult] list into a human-readable label.
///
/// Example: [WiFi] → "WiFi", [WiFi, Mobile] → "WiFi + 移动网络",
/// [Ethernet] → "以太网", [None] → "无网络连接".
String connectivityResultLabel(List<ConnectivityResult> results) {
  if (results.isEmpty) return '无网络连接';

  // Filter out 'none' — if a real interface is active alongside it,
  // we should show the real interface, not claim offline.
  final active = results.where((r) => r != ConnectivityResult.none).toList();
  if (active.isEmpty) return '无网络连接';

  final parts = <String>[];
  for (final r in active) {
    switch (r) {
      case ConnectivityResult.wifi:
        parts.add('WiFi');
      case ConnectivityResult.mobile:
        parts.add('移动网络');
      case ConnectivityResult.ethernet:
        parts.add('以太网');
      case ConnectivityResult.bluetooth:
        parts.add('蓝牙');
      case ConnectivityResult.vpn:
        parts.add('VPN');
      case ConnectivityResult.other:
        parts.add('其他');
      case ConnectivityResult.satellite:
        parts.add('卫星网络');
      case ConnectivityResult.none:
        break; // Already filtered above
    }
  }
  if (parts.isEmpty) return '无网络连接';
  return parts.join(' + ');
}
