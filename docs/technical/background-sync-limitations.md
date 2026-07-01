# US-018 Background Sync — Known Limitations & Verification Status

**Date**: 2026-06-30
**Spec**: `docs/superpowers/specs/2026-06-29-us-018-background-sync-design.md`
**Plan**: `docs/superpowers/plans/2026-06-29-us-018-background-sync.md`

This document records the limitations of the US-018 background-sync implementation
and the verification status of each. Background sync is **best-effort by design** —
it is not a real-time push channel.

## Verification Status (automated)

| Check | Status |
|---|---|
| `flutter analyze` | ✅ No issues |
| `flutter test` (full suite) | ✅ 1552/1552 pass |
| Domain/unit tests (Gate, LastSyncRepo, Runner 22 cases, Scheduler, Dispatcher) | ✅ Pass |
| Widget tests (toggle UI, Law 14) | ✅ Pass |

## Verification Status (manual / not executable in dev environment)

The following were NOT executed during implementation because they require a
real device/emulator or Xcode (the dev environment is Windows, no iOS toolchain,
no connected device). They are deferred to manual verification per the spec's
Task 11 checklist.

| Check | Status | Notes |
|---|---|---|
| **MVP performance pre-check** (3-agent instance, 1h replay, ≤25s/instance) | ⏳ Deferred | Load-bearing assumption. Must be measured on a real device/emulator before release. If it fails, switch iOS to `BGProcessingTask` and/or split Android pull. |
| **Android real-device** (kill process 30min → reopen → notifications arrive) | ⏳ Deferred | Manual checklist item. |
| **iOS real-device** (Simulate Background Fetch / kill+lock 30min) | ⏳ Deferred | Manual checklist item. |
| **iOS native build** (AppDelegate.swift BG task registration compiles + runs) | ⏳ Deferred | `WorkmanagerPlugin.registerTask(withIdentifier:)` API was written against the installed `workmanager` version but could NOT be compiled/verified without Xcode. **Must be confirmed at first iOS build.** |
| Cross-restart scheduling (reboot phone → still scheduled) | ⏳ Deferred | Manual. |
| DND时段 / DND结束 / Tombstoned agent / 多 instance matrix | ⏳ Deferred | Manual checklist. |

## Known Limitations (by design, documented in spec)

### Notification latency is best-effort, not real-time
- AC-16's implicit "real-time push" semantics is now a **known limitation**:
  notifications for messages arriving while the app is cold-started / killed
  arrive on a **15 min – several hours** best-effort cadence, driven by the OS
  scheduler. Foreground + short-background scenarios remain real-time (the live
  WebSocket `messageStream` drives those).
- iOS `BGAppRefreshTask` real frequency is often **far below 15 min** for
  low-usage apps (iOS learns the user's pattern). Fallback: switch to
  `BGProcessingTask` (10-min window) if observed too low.

### OS / OEM scheduling limits (not fixable in this Story)
- **Android OEM power-management** (华为/小米/OPPO aggressive battery modes)
  may kill the process entirely → no background sync. Requires the user to
  add the app to the OEM's battery whitelist. Out of scope (another Story).
- **Android Doze mode** delays WorkManager jobs (Doze does not delay in-job
  network, but defers the job start).
- **iOS 30-second wake window**: a single slow instance could exhaust it.
  Mitigated by `perInstanceBudget = 60s` (configurable) + graceful skip;
  skipped instances are recorded and the next tick retries the same window
  (Message dedup makes this safe).

### Cross-isolate dedup
- The background isolate has an empty in-memory dedup LRU, so background-pulled
  messages route through the **persistent** `pending_notifications` unique index
  (not the LRU). The main isolate cold-starts with `warmupFromPending()` to
  reseed its LRU from undelivered pending rows. See
  `BackgroundNotifierShared.enqueuePulled` (single shared evaluate→enqueue impl)
  and `NotificationDispatcher.warmupFromPending`.

### Lifecycle flag is best-effort async
- `WidgetsBindingObserver.didChangeAppLifecycleState` → `onAppPaused` writes
  the `main_isolate_active=false` flag to SharedPreferences asynchronously.
  If a background tick fires before the write flushes, it reads `true` and
  **conservatively skips** (wastes one 15-min window; no correctness impact —
  the next tick sees the flushed value).

### First-sync start point
- A user with no prior `last_background_sync_at` starts from `now() - 1h`
  (not 24h) to avoid a reply avalanche. Capped by `maxMessagesPerPull = 100`.

## Workmanager Plugin Upgrade Trap (2026-07-01 incident)

**Do NOT add a `tools:node="remove"` block on
`androidx.work.WorkManagerInitializer` in `android/app/src/main/AndroidManifest.xml`.**

The US-018 manifest currently has the default AndroidX Work initializer
intact (it was briefly removed in commit `c6f6d94` and restored after a
splash-hang incident — see commit `fix(android): restore default
WorkManagerInitializer` and the root-cause analysis below).

### Why this matters

- workmanager **0.5.2** (monolithic plugin) self-initialized AndroidX Work
  inside `WorkmanagerPlugin.onAttachedToEngine`, so removing the default
  `androidx.work.WorkManagerInitializer` from the merged manifest was
  harmless.
- workmanager **0.9.0+3** (federated: `workmanager` facade +
  `workmanager_android` impl) does **NOT** self-initialize. It calls
  `WorkManager.getInstance(context)` and assumes the `androidx.startup`
  default initializer has already run.

If the default initializer is removed:

1. `WorkManager.getInstance(context)` inside
   `WorkmanagerPlugin.onAttachedToEngine` throws
   `IllegalStateException` (or returns uninitialized) **before**
   `WorkmanagerHostApi.setUp(binding.binaryMessenger, this)` runs.
2. `setUp` never executes, so the Pigeon handler for
   `dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi.initialize`
   is never registered.
3. Dart-side `await Workmanager().initialize(...)` receives a `null`
   reply and throws
   `PlatformException(channel-error, Unable to establish connection on
   channel: "...", null, null)`.
4. `runApp()` is never called.
5. The Flutter engine never produces a first frame.
6. Android's `FlutterActivityAndFragmentDelegate` splash-hold
   `OnPreDrawListener` (`FlutterActivityAndFragmentDelegate$2`) loops
   forever, generating the log spam
   `W/VRI[MainActivity]: performTraversals: cancelAndRedraw,
   mLastPerformTraversalsSkipDrawReasonpredraw_...`.

The user sees a frozen splash. There is no visible UI to diagnose from —
the splash IS the entire visible surface when `runApp` never runs.

### Why the bug did not surface in `flutter build apk --debug`

`flutter build apk` only verifies that the build succeeds. The
`flutter run` debug pipeline (JIT, hot reload) can produce a
functionally-complete APK that crashes on first launch. Build success
does NOT guarantee a working startup.

### Detection and recovery

Symptom: Android splash + infinite VRI `cancelAndRedraw` log spam.
Recovery: `flutter clean && flutter pub get && flutter run` after
verifying the manifest is correct. If the problem persists, add
boundary `debugPrint` markers in `main()` (the
`[BOOT] workmanager.initialize START/DONE` pattern) to localize the
thrown exception. The error message names the missing Pigeon channel.

### Mitigations already in place

- The current `main.dart` is wrapped in `runZonedGuarded(bootstrapApp(...), <inline zone error handler>)`
  (see `lib/app/bootstrap.dart`). Any pre-`runApp` exception surfaces as
  a fatal screen (`MaterialApp` + `DefaultErrorFallback` with the error
  message + collapsible stack trace + a Retry button that re-enters
  `main()`). This is the developer-facing fail-fast
  guardrail added 2026-07-01 to prevent a future similar bug from
  silently stranding the user on a blank splash.
- `defaultErrorFallback` now actually renders the `error` field
  (previously a latent bug — the parameter was accepted but ignored).

## Startup Fail-Fast Guardrail (2026-07-01)

The pre-`runApp` startup chain (`Workmanager().initialize(...)` +
`createAppDatabase()` + `runApp(ProviderScope(...))`) is guarded by
`runZonedGuarded(bootstrapApp(...), <inline zone error handler>)` in
`lib/main.dart`. The `bootstrapApp` function in `lib/app/bootstrap.dart`
is the single composition point for pre-`ProviderScope` initialization;
any thrown exception from those awaits surfaces as a fatal screen
(`MaterialApp` + `DefaultErrorFallback`) with the error message,
collapsible stack trace, and a Retry button.

The guardrail is **developer-facing** more than user-facing — the bug
is reliably diagnosable from `error + stackTrace` alone. We do NOT
localize this screen.

If you need to add a new pre-`runApp` initialization step
(e.g. another plugin, secure-storage pre-warm, locale load), add it
inside `bootstrapApp` so it is covered by the guardrail. **Do not add
new pre-`runApp` awaits directly inside `main()`** — they will be
unguarded.

## Out of Scope (per spec)
- Foreground Service (user rejected).
- APNs / FCM remote push (requires Gateway protocol changes).
- Persistent WebSocket keepalive of any form (user rejected).
- Configurable schedule interval (15-min cross-platform default is sufficient).
- Background-pull-failure notifications (failure is常态; notifying would spam).
- Android OEM whitelist guidance (separate Story).
- Offline cache cleanup (separate Story).

## Configuration Constants
Defined in `BackgroundSyncBudget` (`lib/core/lifecycle/background_sync_runner.dart`):
- `maxMessagesPerPull` = 100
- `maxPagesPerAgent` = 5
- `perInstanceBudget` = 60s
- `connectTimeout` = 10s
- `pageFetchTimeout` = 30s
- Schedule interval = 15 min (`WorkmanagerBackendImpl`)
