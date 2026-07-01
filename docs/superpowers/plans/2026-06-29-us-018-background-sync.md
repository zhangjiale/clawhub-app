# US-018 Background Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let ClawHub fetch missed agent messages from Gateways while the app is suspended, so notifications still arrive after a cold-start / process-kill (best-effort, 15 min).

**Architecture:** Platform-periodic background work (Android WorkManager / iOS BGTaskScheduler) wakes a background Dart isolate. The isolate rebuilds Drift + secure-storage + notification service, then for each enabled instance does a per-agent cursor walk over `fetchMessageHistory`, dedups via the `batchInsertByIndexedIds` unique-index path, and routes decisions through `NotificationDispatcher.handlePulledMessages` → `pending_notifications` (persistent dedup, never `show()` directly). A `BackgroundSyncGate` (SharedPreferences atomic flag) lets the background work skip itself when the main isolate is active. Per-instance `last_background_sync_at` lives in a new `sync_state` table.

**Tech Stack:** Flutter, drift (SQLite), workmanager (`^0.5.2` to be added), shared_preferences (`^2.3.3` to be added), flutter_secure_storage `^9.2.4`, flutter_local_notifications `^18.0.1`, Riverpod.

## Global Constraints

(Verbatim from spec `2026-06-29-us-018-background-sync-design.md`. Every task implicitly inherits these.)

- **No Foreground Service.** No persistent notification-bar icon. (spec Design Constraints #1)
- Use **WorkManager (Android) + BGTaskScheduler (iOS) periodic pull**, no persistent notification. (#2)
- **Incremental pull** since last sync, per-instance `last_sync_at`. (#3)
- **15 min** cross-platform-aligned schedule interval. (#4)
- Provide a **"后台同步" toggle**, default enabled. (#5)
- **Detect main isolate still running → skip** background pull. (#6)
- `workmanager.enableSeparateBackgroundProcess = false` (default same-process) — otherwise secure-storage keychain cross-process access fails silently.
- First-ever sync start point = `now() - 1h` (**not** 24h) — avoid reply avalanche. Capped by `maxMessagesPerPull=100`.
- Background dedup path goes through the **persistent unique index** on `pending_notifications(instance_id, message_server_id)`, **never** the in-memory LRU and **never** `LocalNotificationService.show()` directly. `handlePulledMessages` only calls `pendingRepo.enqueue`.
- Law 17 (TDD) is mandatory and per-file for `lib/domain/`: test file FIRST, run it RED, then source file GREEN.
- Conventional Commits: `feat(scope):`, `fix(scope):`, `docs:`, `test:`.
- Never auto-commit unless the user explicitly asks (user memory: no-auto-commit). This plan includes `git add`/`git commit` steps as the canonical checkpoints; the executing engineer runs them.

## Key Resolved Signatures (verified against codebase)

These are the real signatures the plan builds on. Do not re-derive them.

```dart
// lib/core/acl/i_gateway_client.dart:30
Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
  required String instanceId,
  required String agentId,
  String? cursor,
  int limit = 50,
});
Future<List<Agent>> fetchAgents(String instanceId);          // :26
Future<void> connect(Instance instance);                      // :12
Future<void> disconnect(String instanceId);                   // :15

// lib/data/repositories/drift_message_repo.dart:339 (IMessageRepo:138)
Future<List<Message>> batchInsertByIndexedIds(List<Message> messages);
// returns the actually-inserted messages (empty if all dupes)

// lib/domain/models/message.dart
// fields: clientId:String, serverId:String?, conversationId:String, agentId:String,
//   role, content:String?, type, status, logicalClock:int, timestamp:int (ms)

// lib/domain/models/instance.dart
// fields: id:String, name:String, gatewayUrl:String, tokenRef:String (secure-storage KEY, not raw token),
//   healthStatus, isLocalNetwork:bool, lastConnectedAt:int?, createdAt:int

// lib/domain/models/agent.dart
// fields: localId, remoteId:String (Gateway id), instanceId, name, ..., removedAt:int? (tombstone), hiddenAt:int?
// bool get isRemoved => removedAt != null;   extension AgentTombstonedExt on Agent? { bool get isTombstoned => ... }

// lib/domain/models/user_preferences.dart  — needs new field: backgroundSyncEnabled (default true)

// lib/domain/usecases/evaluate_notification.dart:62
class EvaluateNotificationUseCase {
  const EvaluateNotificationUseCase();
  NotificationDecision evaluate(NotificationEvent event, UserPreferences prefs, DateTime now);
}
// sealed NotificationDecision: ShowDecision(title, body, event) / DndSuppressedDecision(event) / DroppedDecision()

// lib/domain/models/notification_event.dart
// sealed NotificationEvent; ReplyEvent has: agentId, instanceId, agentName, contentPreview, messageServerId:String?, messageClientId:String

// lib/domain/repositories/i_notification_repo.dart
abstract class INotificationRepo {
  Future<int> enqueue(PendingNotification notification);
  Future<List<PendingNotification>> getPending();
  Future<void> markDelivered(int id);
  Future<int> markDeliveredBatch(List<int> ids);
  Future<int> clearDelivered();
  Future<int> countPending();
}
// pending_notifications partial unique index (database.dart:79-83):
//   UNIQUE(instance_id, message_server_id) WHERE message_server_id IS NOT NULL
//   → enqueue uses ON CONFLICT DO NOTHING; duplicate serverId silently no-ops.

// lib/core/acl/i_device_token_store.dart
abstract class IDeviceTokenStore {
  Future<void> save(String instanceId, String deviceToken);
  Future<String?> load(String instanceId);   // raw token; null if never paired/revoked
  Future<void> delete(String instanceId);
}

// lib/domain/repositories/i_agent_repo.dart
Future<List<Agent>> getAllByInstanceId(String instanceId);
Future<Agent?> findByCompositeKey(String instanceId, String remoteId);

// AppDatabase: schemaVersion 7 (lib/data/local/database/database.dart:32). Migration via onUpgrade block.
// user_preferences singleton row (schema.drift:377). DriftSettingsRepo maps it (lib/data/repositories/drift_settings_repo.dart).
// SettingsViewModel: StateNotifier<UserPreferences>; setters do _update(copyWith(...)); return _pendingUpdate.
// NotificationBootstrap.init() — app bootstrap (lib/app/notifications/notification_bootstrap.dart). Called from main.dart _ConnectionInitializer before orchestrator.initialize().
// ConnectionOrchestrator.onInstanceSaved(Instance) — lib/app/connection/connection_orchestrator.dart:167
```

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `lib/core/lifecycle/background_sync_gate.dart` | Cross-isolate "main active" flag via SharedPreferences atomic bool. `shouldSkip()` / `setMainActive(bool)`. Pure Dart (wraps injected prefs interface → testable). |
| `lib/core/lifecycle/i_background_sync_prefs.dart` | Tiny interface abstracting `SharedPreferences` bool get/set, so the gate is unit-testable without the platform plugin. |
| `lib/core/lifecycle/background_sync_runner.dart` | One full pull: gate check → load settings+instances → per-instance per-agent cursor walk → `batchInsertByIndexedIds` → `NotificationDispatcher.handlePulledMessages` → update `last_sync_at`. Orchestrates injected repos/clients (pure logic, all deps injected). |
| `lib/core/lifecycle/background_sync_scheduler.dart` | Platform abstraction: `ensureScheduled()` / `cancel()` over `workmanager` + `WidgetsBindingObserver` didChangeAppLifecycleState hook. No logic — only platform wiring. |
| `lib/core/lifecycle/background_sync_runner_factory.dart` | Top-level `@pragma('vm:entry-point')` `callbackDispatcher` that rebuilds Drift/secure-storage/notification deps in the background isolate and invokes `BackgroundSyncRunner.executeOnce`. Must be top-level (workmanager requirement). |
| `lib/data/repositories/drift_last_sync_repo.dart` | `LastSyncAtRepository` over new `sync_state` table: `get(instanceId)` / `upsert(instanceId, ms)`. |
| `lib/domain/repositories/i_last_sync_repo.dart` | Domain interface (Law 1 purity). |
| `lib/features/settings/providers/background_sync_providers.dart` | Riverpod wiring for gate/runner/scheduler + a notifier that watches the toggle and schedules/cancels. |
| Tests (all test-first per Law 17 where domain): see per-task. |

### Modified files

| File | Change |
|---|---|
| `lib/domain/models/user_preferences.dart` | Add `backgroundSyncEnabled` field (default true) + copyWith/==/hash/toString. |
| `lib/data/local/database/schema.drift` | Add `sync_state` table + named queries; add `background_sync_enabled` column to `user_preferences` + update `upsertUserPreferences`. |
| `lib/data/local/database/database.dart` | `schemaVersion 7 → 8`; `onUpgrade` add `if (from < 8)` block (create `sync_state`, add column with default 1). |
| `lib/data/repositories/drift_settings_repo.dart` | Map `backgroundSyncEnabled` in `_rowToDomain` + `updatePreferences` (+ `upsertUserPreferences` arg count). |
| `lib/data/services/notification_dispatcher.dart` | Add `handlePulledMessages(List<Message>)` + `warmupFromPending()`. Internal-only; routes through `repo.enqueue`, never `show`. |
| `lib/features/settings/viewmodels/settings_view_model.dart` | Add `setBackgroundSyncEnabled(bool)`. |
| `lib/features/settings/notification_settings_page.dart` (or settings_page.dart) | Add "后台同步" toggle row. |
| `lib/app/notifications/notification_bootstrap.dart` | After coordinator.start(): `dispatcher.warmupFromPending()` + `BackgroundSyncScheduler.ensureScheduled()` + attach `WidgetsBindingObserver`. |
| `lib/app/connection/connection_orchestrator.dart` | `onInstanceSaved`/`onInstanceDeleted` tail → notify scheduler of instance-set change. |
| `lib/app/di/providers.dart` | Providers for gate, last-sync repo, runner, scheduler; rebuild helpers used by `callbackDispatcher`. |
| `lib/main.dart` | `Workmanager().initialize(callbackDispatcher, ...)` before `runApp`. |
| `android/app/src/main/AndroidManifest.xml` | `RECEIVE_BOOT_COMPLETED` perm + remove default WorkManagerInitializer. |
| `ios/Runner/Info.plist` | `UIBackgroundModes` + `BGTaskSchedulerPermittedIdentifiers`. |
| `ios/Runner/AppDelegate.swift` | New — register BG task. |
| `pubspec.yaml` | Add `workmanager`, `shared_preferences`. |

---

## Task 1: `BackgroundSyncGate` — cross-isolate "main active" flag

Pure-Dart gate backed by an injected bool-storage interface (so unit tests don't touch `SharedPreferences`). Law 17 → test first.

**Files:**
- Create: `lib/core/lifecycle/i_background_sync_prefs.dart`
- Create: `lib/core/lifecycle/background_sync_gate.dart`
- Test: `test/core/lifecycle/background_sync_gate_test.dart`

**Interfaces:**
- Produces: `IBackgroundSyncPrefs` (interface) and `BackgroundSyncGate` with `Future<bool> shouldSkip()`, `Future<void> setMainActive(bool)`, `Future<void> clear()`.

**Why an interface instead of `SharedPreferences` directly:** the background isolate and the main isolate both read this flag. Wrapping it behind `IBackgroundSyncPrefs` keeps the gate unit-testable (Law 1-ish purity for the logic) and lets the production impl be a thin `SharedPreferences` adapter added in Task 9.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/lifecycle/background_sync_gate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_prefs.dart';

class _FakePrefs implements IBackgroundSyncPrefs {
  bool value = false;
  Map<String, int> writes = {};
  @override
  Future<bool> get mainActive => Future.value(value);
  @override
  Future<void> setMainActive(bool active) async {
    value = active;
    writes['mainActive'] = active ? 1 : 0;
  }
  @override
  Future<void> clear() async {
    value = false;
  }
}

void main() {
  late _FakePrefs prefs;
  late BackgroundSyncGate gate;

  setUp(() {
    prefs = _FakePrefs();
    gate = BackgroundSyncGate(prefs: prefs);
  });

  test('shouldSkip_returnsTrueWhenMainActive', () async {
    prefs.value = true;
    expect(await gate.shouldSkip(), isTrue);
  });

  test('shouldSkip_returnsFalseWhenMainInactive', () async {
    prefs.value = false;
    expect(await gate.shouldSkip(), isFalse);
  });

  test('setMainActive_persistsAcrossReads', () async {
    await gate.setMainActive(true);
    expect(await gate.shouldSkip(), isTrue); // same process re-read
    await gate.setMainActive(false);
    expect(await gate.shouldSkip(), isFalse);
  });

  test('setMainActive_writesAndReadsAtomically', () async {
    await gate.setMainActive(true);
    expect(prefs.writes['mainActive'], 1);
    expect(prefs.value, isTrue);
    await gate.setMainActive(false);
    expect(prefs.writes['mainActive'], 0);
    expect(prefs.value, isFalse);
  });

  test('clear_resetsToInactive', () async {
    await gate.setMainActive(true);
    await gate.clear();
    expect(await gate.shouldSkip(), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/lifecycle/background_sync_gate_test.dart`
Expected: FAIL — `background_sync_gate.dart` / `i_background_sync_prefs.dart` do not exist (compile error = acceptable RED).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/lifecycle/i_background_sync_prefs.dart
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
```

```dart
// lib/core/lifecycle/background_sync_gate.dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/lifecycle/background_sync_gate_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/core/lifecycle/`
Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/lifecycle/i_background_sync_prefs.dart \
        lib/core/lifecycle/background_sync_gate.dart \
        test/core/lifecycle/background_sync_gate_test.dart
git commit -m "feat(background-sync): BackgroundSyncGate cross-isolate active flag"
```

---

## Task 2: `sync_state` schema + `LastSyncAtRepository` (TDD)

New Drift table + domain interface + drift impl. Law 17 → domain interface test first is not strictly required (it's an interface), but the **repo impl** test is the deliverable here. Per the codebase pattern (drift repos tested directly), we test the drift impl.

**Files:**
- Modify: `lib/data/local/database/schema.drift` (add `sync_state` table + queries)
- Modify: `lib/data/local/database/database.dart` (schemaVersion 7 → 8, onUpgrade)
- Create: `lib/domain/repositories/i_last_sync_repo.dart`
- Create: `lib/data/repositories/drift_last_sync_repo.dart`
- Test: `test/data/repositories/drift_last_sync_repo_test.dart`
- Regenerate: `dart run build_runner build --delete-conflicting-outputs`

**Interfaces:**
- Produces: `ILastSyncRepo` with `Future<int?> get(String instanceId)` (returns ms epoch or null), `Future<void> upsert(String instanceId, int msEpoch)`.
- `DriftLastSyncRepo(AppDatabase)` implements it.

- [ ] **Step 1: Add `sync_state` table to schema.drift**

Append after the `pending_notifications` block (before the named-queries section for pending, or in a new section). Exact SQL:

```sql
-- ============================================================
-- 9. Background Sync State — per-instance last sync cursor
-- ============================================================
CREATE TABLE sync_state (
    instance_id TEXT PRIMARY KEY,
    last_sync_at INTEGER NOT NULL
);

getLastSyncAt:
SELECT last_sync_at FROM sync_state WHERE instance_id = :instanceId;

upsertLastSyncAt:
INSERT INTO sync_state (instance_id, last_sync_at)
VALUES (:instanceId, :lastSyncAt)
ON CONFLICT(instance_id) DO UPDATE SET last_sync_at = :lastSyncAt;
```

- [ ] **Step 2: Bump schemaVersion + migration**

In `lib/data/local/database/database.dart`:

Change line 32:
```dart
int get schemaVersion => 8;
```

Add inside `onUpgrade:` (after the `if (from < 7)` block, before the closing `},`):

```dart
        if (from < 8) {
          // US-018 background sync: per-instance last_background_sync_at cursor.
          // New table only — no backfill. First background tick uses
          // now()-1h as the start point (handled in BackgroundSyncRunner).
          await migrator.createTable(syncState);
        }
```

Also add `sync_state_enabled` column to `user_preferences` here (it belongs to the same migration step):

```dart
          // US-018: background_sync_enabled toggle (default ON = 1).
          await migrator.addColumn(
            userPreferences,
            userPreferences.backgroundSyncEnabled,
          );
          await customStatement(
            'UPDATE user_preferences SET background_sync_enabled = 1 WHERE id = 1',
          );
```

> Note: Drift needs the column declared in the table before `addColumn` resolves. Do Step 3 (schema column) before running build_runner.

- [ ] **Step 3: Add `background_sync_enabled` column to `user_preferences` in schema.drift**

In the `CREATE TABLE user_preferences` block, add as the last column (after `biometric_enabled INTEGER NOT NULL DEFAULT 0`):

```sql
    , background_sync_enabled INTEGER NOT NULL DEFAULT 1
```

Update the `upsertUserPreferences` query to include the new column. Add `:backgroundSyncEnabled` to the column list and the VALUES list:

```sql
upsertUserPreferences:
INSERT OR REPLACE INTO user_preferences
    (id, notifications_enabled, notify_on_reply, notify_on_error,
     notify_on_connection_change, dnd_enabled, dnd_start_hour, dnd_start_minute,
     dnd_end_hour, dnd_end_minute, biometric_enabled, background_sync_enabled)
VALUES (1, :notificationsEnabled, :notifyOnReply, :notifyOnError,
        :notifyOnConnectionChange, :dndEnabled, :dndStartHour, :dndStartMinute,
        :dndEndHour, :dndEndMinute, :biometricEnabled, :backgroundSyncEnabled);
```

- [ ] **Step 4: Run code generation**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: succeeds; `_$AppDatabase`, `UserPreference` row class, and `SyncState` companion are regenerated with the new field/table.

- [ ] **Step 5: Write the failing repo test**

```dart
// test/data/repositories/drift_last_sync_repo_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/local/database/database.dart';
import 'lib/data/repositories/drift_last_sync_repo_test_helper.dart' as helper;
// (helper below opens an in-memory AppDatabase; see Step 5b)

void main() {
  late AppDatabase db;
  late helper.RepoHarness harness;

  setUp(() async {
    harness = await helper.openInMemory();
    db = harness.db;
  });
  tearDown(() => harness.close());

  test('get_returnsNullWhenAbsent', () async {
    final repo = helper.makeRepo(db);
    expect(await repo.get('inst-a'), isNull);
  });

  test('upsert_thenGet_returnsMsEpoch', () async {
    final repo = helper.makeRepo(db);
    await repo.upsert('inst-a', 1700000000000);
    expect(await repo.get('inst-a'), 1700000000000);
  });

  test('upsert_overwritesExisting', () async {
    final repo = helper.makeRepo(db);
    await repo.upsert('inst-a', 1000);
    await repo.upsert('inst-a', 2000);
    expect(await repo.get('inst-a'), 2000);
  });

  test('upsert_isPerInstanceIndependent', () async {
    final repo = helper.makeRepo(db);
    await repo.upsert('inst-a', 1000);
    await repo.upsert('inst-b', 2000);
    expect(await repo.get('inst-a'), 1000);
    expect(await repo.get('inst-b'), 2000);
  });
}
```

Step 5b — in-memory harness. Existing repo tests in this codebase open `AppDatabase(NativeDatabase.memory())`. Create the helper to match that pattern:

```dart
// test/data/repositories/drift_last_sync_repo_test_helper.dart
import 'package:drift/native.dart';
import 'package:claw_hub/data/local/database/database.dart';
import 'package:claw_hub/data/repositories/drift_last_sync_repo.dart';

class RepoHarness {
  final AppDatabase db;
  final DriftLastSyncRepo repo;
  RepoHarness(this.db, this.repo);
}

Future<RepoHarness> openInMemory() async {
  final db = AppDatabase(NativeDatabase.memory());
  // beforeOpen runs on first query; force it:
  await db.customSelect('SELECT 1').get();
  return RepoHarness(db, DriftLastSyncRepo(db));
}

DriftLastSyncRepo makeRepo(AppDatabase db) => DriftLastSyncRepo(db);

extension on RepoHarness {
  Future<void> close() async => await db.close();
}
```

> If the codebase already has a shared in-memory DB test fixture (grep `test/data/repositories/` for `NativeDatabase.memory()`), reuse it instead of this helper and delete the helper. Match surrounding test style.

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/data/repositories/drift_last_sync_repo_test.dart`
Expected: FAIL — `drift_last_sync_repo.dart` / `i_last_sync_repo.dart` do not exist (RED).

- [ ] **Step 7: Write the domain interface**

```dart
// lib/domain/repositories/i_last_sync_repo.dart
/// Per-instance "last background sync" cursor (ms epoch).
///
/// Background sync writes; main isolate reads (settings page "last synced").
/// Null = never synced → BackgroundSyncRunner uses now()-1h as start point.
abstract class ILastSyncRepo {
  Future<int?> get(String instanceId);
  Future<void> upsert(String instanceId, int msEpoch);
}
```

- [ ] **Step 8: Write the drift implementation**

```dart
// lib/data/repositories/drift_last_sync_repo.dart
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/domain/repositories/i_last_sync_repo.dart';

class DriftLastSyncRepo implements ILastSyncRepo {
  final db.AppDatabase _database;
  DriftLastSyncRepo(this._database);

  @override
  Future<int?> get(String instanceId) async {
    final rows = await _database.getLastSyncAt(instanceId).get();
    if (rows.isEmpty) return null;
    return rows.first.lastSyncAt;
  }

  @override
  Future<void> upsert(String instanceId, int msEpoch) async {
    await _database.upsertLastSyncAt(instanceId, msEpoch);
  }
}
```

- [ ] **Step 9: Run test to verify it passes**

Run: `flutter test test/data/repositories/drift_last_sync_repo_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 10: Analyze**

Run: `flutter analyze lib/data/repositories/drift_last_sync_repo.dart lib/domain/repositories/i_last_sync_repo.dart`
Expected: no issues.

- [ ] **Step 11: Commit**

```bash
git add lib/data/local/database/schema.drift \
        lib/data/local/database/database.dart \
        lib/domain/repositories/i_last_sync_repo.dart \
        lib/data/repositories/drift_last_sync_repo.dart \
        test/data/repositories/drift_last_sync_repo_test.dart \
        test/data/repositories/drift_last_sync_repo_test_helper.dart
# plus regenerated generated files:
git add lib/data/local/database/database.g.dart
git commit -m "feat(background-sync): sync_state table + LastSyncAtRepository"
```

---

## Task 3: `UserPreferences.backgroundSyncEnabled` + SettingsRepo mapping

Add the toggle field to the domain model + wire the drift mapper. The schema column was already added in Task 2 Step 3; this task makes the model + repo use it.

**Files:**
- Modify: `lib/domain/models/user_preferences.dart`
- Modify: `lib/data/repositories/drift_settings_repo.dart` (`_rowToDomain`, `updatePreferences`)
- Test: `test/domain/models/user_preferences_test.dart` (new — model field defaults/==)
- Test: `test/data/repositories/drift_settings_repo_test.dart` (extend if exists, else add a focused round-trip test)

**Interfaces:**
- Produces: `UserPreferences.backgroundSyncEnabled` (default `true`).

- [ ] **Step 1: Write the failing model test**

```dart
// test/domain/models/user_preferences_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';

void main() {
  test('defaults_hasBackgroundSyncEnabledTrue', () {
    expect(UserPreferences.defaults().backgroundSyncEnabled, isTrue);
  });

  test('defaults_constructorHasBackgroundSyncEnabledTrue', () {
    expect(const UserPreferences().backgroundSyncEnabled, isTrue);
  });

  test('copyWith_backgroundSyncEnabled_togglesValue', () {
    final off = UserPreferences.defaults().copyWith(backgroundSyncEnabled: false);
    expect(off.backgroundSyncEnabled, isFalse);
    final on = off.copyWith(backgroundSyncEnabled: true);
    expect(on.backgroundSyncEnabled, isTrue);
  });

  test('equals_distinguishesBackgroundSyncEnabled', () {
    final a = UserPreferences.defaults();
    final b = a.copyWith(backgroundSyncEnabled: false);
    expect(a == b, isFalse);
    expect(a.hashCode == b.hashCode, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/models/user_preferences_test.dart`
Expected: FAIL — `backgroundSyncEnabled` getter undefined (RED).

- [ ] **Step 3: Add the field to the model**

In `lib/domain/models/user_preferences.dart`:

Add the field declaration (after `biometricEnabled`):
```dart
  // ── Background Sync ───────────────────────────────────────────

  /// 后台同步开关（US-018）。默认启用。
  final bool backgroundSyncEnabled;
```

Add to the const constructor (default `true`):
```dart
    this.backgroundSyncEnabled = true,
```

Add to `copyWith` (param + body):
```dart
    bool? backgroundSyncEnabled,
```
```dart
      backgroundSyncEnabled: backgroundSyncEnabled ?? this.backgroundSyncEnabled,
```

Add to `==`:
```dart
          biometricEnabled == other.biometricEnabled &&
          backgroundSyncEnabled == other.backgroundSyncEnabled;
```
(change the trailing `;` of the last compared field to `&&`)

Add to `hashCode`:
```dart
    biometricEnabled,
    backgroundSyncEnabled,
  );
```

Add to `toString` (append before closing):
```dart
      ', bgSync: $backgroundSyncEnabled)';
```
(adjust the existing closing `)` accordingly so the string still compiles)

- [ ] **Step 4: Run model test to verify it passes**

Run: `flutter test test/domain/models/user_preferences_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Wire the drift mapper**

In `lib/data/repositories/drift_settings_repo.dart`:

`_rowToDomain` — add:
```dart
      backgroundSyncEnabled: _intToBool(row.backgroundSyncEnabled),
```

`updatePreferences` — add the 11th positional arg to `upsertUserPreferences`:
```dart
    await _database.upsertUserPreferences(
      _boolToInt(preferences.notificationsEnabled),
      _boolToInt(preferences.notifyOnReply),
      _boolToInt(preferences.notifyOnError),
      _boolToInt(preferences.notifyOnConnectionChange),
      _boolToInt(preferences.dndEnabled),
      preferences.dndStartHour,
      preferences.dndStartMinute,
      preferences.dndEndHour,
      preferences.dndEndMinute,
      _boolToInt(preferences.biometricEnabled),
      _boolToInt(preferences.backgroundSyncEnabled),
    );
```

- [ ] **Step 6: Write/extend the settings repo round-trip test**

If `test/data/repositories/drift_settings_repo_test.dart` exists, add this test case; otherwise create the file with the in-memory harness pattern from Task 2.

```dart
  test('updatePreferences_roundTripsBackgroundSyncEnabled', () async {
    final repo = DriftSettingsRepo(db, avatarStorageService: ..., logger: ...);
    final off = UserPreferences.defaults().copyWith(backgroundSyncEnabled: false);
    await repo.updatePreferences(off);
    final loaded = await repo.getPreferences();
    expect(loaded.backgroundSyncEnabled, isFalse);

    final on = off.copyWith(backgroundSyncEnabled: true);
    await repo.updatePreferences(on);
    expect((await repo.getPreferences()).backgroundSyncEnabled, isTrue);
  });

  test('getPreferences_defaultsTrue_whenRowAbsent', () async {
    final repo = DriftSettingsRepo(db, ...);
    // Fresh in-memory DB has no user_preferences row yet.
    expect((await repo.getPreferences()).backgroundSyncEnabled, isTrue);
  });
```
> Fill the `avatarStorageService`/`logger` constructor args to match the real `DriftSettingsRepo` signature (see `lib/app/di/providers.dart:452`). Use fakes/mocks consistent with existing settings repo tests.

- [ ] **Step 7: Run tests + analyze**

Run: `flutter test test/data/repositories/drift_settings_repo_test.dart test/domain/models/user_preferences_test.dart`
Expected: PASS.

Run: `flutter analyze lib/domain/models/user_preferences.dart lib/data/repositories/drift_settings_repo.dart`
Expected: no issues.

- [ ] **Step 8: Commit**

```bash
git add lib/domain/models/user_preferences.dart \
        lib/data/repositories/drift_settings_repo.dart \
        test/domain/models/user_preferences_test.dart \
        test/data/repositories/drift_settings_repo_test.dart
git commit -m "feat(settings): backgroundSyncEnabled toggle in UserPreferences"
```

---

## Task 4: `NotificationDispatcher.handlePulledMessages` + `warmupFromPending`

The cross-isolate dedup contract: background pulls route through `pendingRepo.enqueue` (persistent unique index), **never** `show()` and **never** the in-memory LRU. On main-isolate cold start, `warmupFromPending()` reseeds the LRU from `pending_notifications` so the live stream doesn't re-notify already-delivered-via-pending messages.

This task adds the two methods + their decision routing. The dispatcher already has `evaluator`, `repo` (INotificationRepo), `notificationService`, `clock`, `_notifiedKeys`. We reuse `EvaluateNotificationUseCase.evaluate` by constructing `ReplyEvent`s from `Message`s.

**Files:**
- Modify: `lib/data/services/notification_dispatcher.dart`
- Test: `test/data/services/notification_dispatcher_test.dart` (extend existing; if absent, create with fakes)

**Interfaces:**
- Consumes: `Message` (`lib/domain/models/message.dart`), `Agent` (for `agentName` + tombstone check), `EvaluateNotificationUseCase`, `INotificationRepo`, `UserPreferences` (injected via existing `prefsProvider` thunk).
- Produces: `Future<void> handlePulledMessages({required List<Message> messages, required Agent? Function(String instanceId, String agentRemoteId) resolveAgent})` and `Future<void> warmupFromPending()`.

> **Design note on `resolveAgent`:** the dispatcher must not fetch agents itself (it has no `IAgentRepo` today — tombstone suppression lives in `NotificationCoordinator`). We inject a resolver callback so the **Runner** owns agent resolution + tombstone suppression, keeping the dispatcher's deps unchanged. Tombstoned agents → caller passes `null` → dispatcher drops (no enqueue). This keeps `handlePulledMessages` focused on the decision→enqueue contract.

- [ ] **Step 1: Write the failing tests**

```dart
// test/data/services/notification_dispatcher_test.dart (append to existing file or create)
// Assumes existing fakes: FakeNotificationService, FakeNotificationRepo, etc.
// If the existing test file already constructs NotificationDispatcher for other cases,
// reuse its builder; otherwise build one inline.

void main() {
  // ... existing tests ...

  group('handlePulledMessages', () {
    test('writesThroughPendingRepo_neverCallsShow', () async {
      final dispatcher = buildDispatcher(prefs: onPrefs()); // notifications ON, DND off
      final msg = makeReplyMessage(serverId: 's1', preview: 'hi');
      final svc = dispatcher.notificationService as FakeNotificationService;

      await dispatcher.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => makeAgent(name: 'Claw'),
      );

      expect(svc.showCalls, isEmpty);                 // NEVER show
      expect(dispatcher.repo.enqueued, hasLength(1)); // routed through pending
    });

    test('evaluateShowDecision_enqueuesWithNullDeliverAt', () async {
      final dispatcher = buildDispatcher(prefs: onPrefs());
      await dispatcher.handlePulledMessages(
        messages: [makeReplyMessage(serverId: 's1', preview: 'hi')],
        resolveAgent: (iid, aid) => makeAgent(name: 'Claw'),
      );
      final enq = dispatcher.repo.enqueued.single;
      expect(enq.messageServerId, 's1');
      expect(enq.delivered, isFalse);
    });

    test('evaluateDndDecision_stillEnqueues', () async {
      // DND ON (22:00-08:00, now=23:00)
      final dispatcher = buildDispatcher(prefs: dndOnPrefs(), clock: fixedClock(hour: 23));
      await dispatcher.handlePulledMessages(
        messages: [makeReplyMessage(serverId: 's1', preview: 'hi')],
        resolveAgent: (iid, aid) => makeAgent(name: 'Claw'),
      );
      expect(dispatcher.repo.enqueued, hasLength(1)); // suppressed but queued
    });

    test('evaluateDropDecision_doesNotEnqueue', () async {
      // notificationsEnabled=false → DroppedDecision
      final dispatcher = buildDispatcher(prefs: offPrefs());
      await dispatcher.handlePulledMessages(
        messages: [makeReplyMessage(serverId: 's1', preview: 'hi')],
        resolveAgent: (iid, aid) => makeAgent(name: 'Claw'),
      );
      expect(dispatcher.repo.enqueued, isEmpty);
    });

    test('tombstonedAgent_suppressedByNullResolve', () async {
      final dispatcher = buildDispatcher(prefs: onPrefs());
      await dispatcher.handlePulledMessages(
        messages: [makeReplyMessage(serverId: 's1', preview: 'hi')],
        resolveAgent: (iid, aid) => null, // Runner resolved → tombstoned
      );
      expect(dispatcher.repo.enqueued, isEmpty);
    });

    test('skipsAlreadyNotified_swallowsUniqueConstraint', () async {
      final dispatcher = buildDispatcher(prefs: onPrefs());
      final msg = makeReplyMessage(serverId: 's1', preview: 'hi');
      await dispatcher.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => makeAgent(name: 'Claw'),
      );
      // Second pull of the same serverId: repo.enqueue is a no-op (ON CONFLICT
      // DO NOTHING). Dispatcher must not throw.
      await dispatcher.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => makeAgent(name: 'Claw'),
      );
      // Real dedup is the DB's job; the fake should simulate it by ignoring
      // the duplicate. Assert no exception + still no show().
      expect(dispatcher.notificationService.showCalls, isEmpty);
    });
  });

  group('warmupFromPending', () {
    test('seedsLruWithUndeliveredServerIds', () async {
      final repo = FakeNotificationRepo(pending: [
        makePending(serverId: 's1', delivered: false),
        makePending(serverId: 's2', delivered: false),
      ]);
      final dispatcher = buildDispatcher(repo: repo);
      await dispatcher.warmupFromPending();
      expect(dispatcher.isNotified('s1'), isTrue);
      expect(dispatcher.isNotified('s2'), isTrue);
    });

    test('skipsNullServerId', () async {
      final repo = FakeNotificationRepo(pending: [
        makePending(serverId: null, delivered: false),
        makePending(serverId: 's1', delivered: false),
      ]);
      final dispatcher = buildDispatcher(repo: repo);
      await dispatcher.warmupFromPending();
      expect(dispatcher.isNotified('s1'), isTrue);
      // null-serverId entries are not protected by the unique index; do not
      // pollute the LRU (would suppress unrelated null-serverId live events).
    });

    test('skipsDeliveredRows', () async {
      final repo = FakeNotificationRepo(pending: [
        makePending(serverId: 's1', delivered: true),  // already shown
        makePending(serverId: 's2', delivered: false),
      ]);
      final dispatcher = buildDispatcher(repo: repo);
      await dispatcher.warmupFromPending();
      expect(dispatcher.isNotified('s1'), isFalse);
      expect(dispatcher.isNotified('s2'), isTrue);
    });
  });
}
```

> **Test-infra note:** inspect the **existing** `test/data/services/notification_dispatcher_test.dart` first. It already builds `NotificationDispatcher` with fakes for `eventStream`, `prefsProvider`, `repo`, `notificationService`, `evaluator`, `clock`, `logger`, `routeFor`. Reuse its `buildDispatcher` helper and add the two new methods to the assertions. The fakes (`FakeNotificationService.showCalls`, `FakeNotificationRepo.enqueued`, `FakeNotificationRepo.pending`) must exist or be added to match the real interface — do not invent field names the fakes don't have; extend the existing fakes. Expose `isNotified(String)` as a test-only getter on the dispatcher that checks `_notifiedKeys.contains`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/services/notification_dispatcher_test.dart`
Expected: FAIL — `handlePulledMessages` / `warmupFromPending` undefined (RED).

- [ ] **Step 3: Implement `handlePulledMessages`**

In `lib/data/services/notification_dispatcher.dart`, add (after `flushDndSummary`):

```dart
  /// US-018 background sync entry point.
  ///
  /// Routes pulled agent replies through the persistent dedup path
  /// ([repo.enqueue] → `pending_notifications` unique index). **Never** calls
  /// [notificationService.show] — the live `messageStream` (or DND flush) is
  /// the only path that shows. This keeps cross-isolate dedup convergent:
  /// the background isolate has an empty in-memory LRU, so the persistent
  /// index is the single source of truth.
  ///
  /// [resolveAgent] returns the agent (for name + tombstone) or null if the
  /// caller (BackgroundSyncRunner) decided to suppress (e.g. tombstoned).
  /// Null agent → message dropped, not enqueued.
  Future<void> handlePulledMessages({
    required List<Message> messages,
    required Agent? Function(String instanceId, String agentRemoteId)
        resolveAgent,
  }) async {
    final prefs = prefsProvider();
    for (final msg in messages) {
      // Only agent replies are notifiable from a background pull.
      if (msg.role != MessageRole.agent) continue;
      if (msg.serverId == null) continue; // unique index can't dedup null

      final agent = resolveAgent(msg.conversationId.split(':').first, msg.agentId);
      if (agent == null) continue; // tombstoned / unknown → suppress

      final event = ReplyEvent(
        agentId: agent.remoteId,
        instanceId: agent.instanceId,
        agentName: agent.name,
        contentPreview: _preview(msg.content),
        messageServerId: msg.serverId,
        messageClientId: msg.clientId,
      );

      final decision = evaluator.evaluate(event, prefs, clock());
      switch (decision) {
        case ShowDecision():
        case DndSuppressedDecision():
          // Both routes enqueue; the DND timer / coordinator flush will show.
          // Duplicate serverId → ON CONFLICT DO NOTHING → silently no-op.
          try {
            await repo.enqueue(PendingNotification(
              id: 0,
              agentId: agent.remoteId,
              instanceId: agent.instanceId,
              agentName: agent.name,
              summary: _preview(msg.content),
              createdAt: clock().millisecondsSinceEpoch ~/ 1000,
              messageServerId: msg.serverId,
              delivered: false,
            ));
          } catch (e, st) {
            logger.error('[Dispatcher] handlePulledMessages enqueue failed: $e', st);
          }
          // Also record in the in-memory LRU so a concurrent live event for
          // the same serverId is suppressed this session.
          _recordNotified(event.messageServerId ?? event.messageClientId);
        case DroppedDecision():
          // no-op
          break;
      }
    }
  }

  String _preview(String? content) =>
      (content == null || content.isEmpty) ? '(消息)' : content;

  void _recordNotified(String key) {
    _notifiedKeys.add(key);
    _evictIfFull();
  }
```

> Verify against the **real** `ReplyEvent` constructor field names (`lib/domain/models/notification_event.dart:47-52`) and `PendingNotification` (`lib/domain/models/pending_notification.dart`) — the field list above is taken from the exploration summary but the implementer must confirm exact names/defaults before compiling. `MessageRole.agent` is the enum value from `lib/domain/models/message.dart`. `_evictIfFull` already exists (line ~249). If `_evictIfFull` is private and fine to call, do so; otherwise inline the eviction.

- [ ] **Step 4: Implement `warmupFromPending`**

```dart
  /// Reseed the in-memory dedup LRU from persisted pending notifications.
  ///
  /// Called on main-isolate cold start (NotificationBootstrap) so the live
  /// `messageStream` doesn't re-notify messages the background isolate
  /// already enqueued. Only undelivered rows with a non-null serverId are
  /// seeded (delivered = already shown; null-serverId = not index-protected).
  Future<void> warmupFromPending() async {
    try {
      final pending = await repo.getPending();
      for (final p in pending) {
        if (p.delivered) continue;
        final key = p.messageServerId;
        if (key == null) continue;
        _notifiedKeys.add(key);
      }
      _evictIfFull();
    } catch (e, st) {
      logger.error('[Dispatcher] warmupFromPending failed: $e', st);
    }
  }

  /// Test-only: whether a dedup key is currently in the LRU.
  @visibleForTesting
  bool isNotified(String key) => _notifiedKeys.contains(key);
```

Add `import 'package:flutter/foundation.dart';` (for `@visibleForTesting`) if not present.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/data/services/notification_dispatcher_test.dart`
Expected: PASS (all existing + new tests).

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/data/services/notification_dispatcher.dart`
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/data/services/notification_dispatcher.dart \
        test/data/services/notification_dispatcher_test.dart
git commit -m "feat(notifications): handlePulledMessages + warmupFromPending for background sync dedup"
```

---

## Task 5: `BackgroundSyncRunner` — per-agent cursor walk (core)

The heart of background sync. Pure orchestration logic with **all** deps injected (gateway client, message repo, agent repo, last-sync repo, settings repo, dispatcher, gate, clock, logger, budget config) so it is fully unit-testable without a real WebSocket. This is where the spec's 16 test cases live.

**Files:**
- Create: `lib/core/lifecycle/background_sync_runner.dart`
- Test: `test/core/lifecycle/background_sync_runner_test.dart`

**Interfaces:**
- Consumes:
  - `IGatewayClient` (`connect`, `disconnect`, `fetchAgents`, `fetchMessageHistory`)
  - `IMessageRepo.batchInsertByIndexedIds`
  - `IAgentRepo.getAllByInstanceId`
  - `ILastSyncRepo` (`get`, `upsert`)
  - `ISettingsRepo.getPreferences`
  - `IInstanceRepo.getAll` (to list instances)
  - `IDeviceTokenStore.load` (to resolve raw token for `Instance.tokenRef` if needed — see Step design note)
  - `BackgroundSyncGate.shouldSkip`
  - `NotificationDispatcher.handlePulledMessages`
  - `BackgroundSyncBudget` config value object
- Produces: `BackgroundSyncRunner.executeOnce()` returning a `BackgroundSyncResult` (per-instance statuses).

**Design decisions (locked from spec):**

- **Budget config** is a value object so tests inject tiny budgets:
  ```dart
  class BackgroundSyncBudget {
    final int maxMessagesPerPull;   // 100
    final int maxPagesPerAgent;     // 5
    final Duration perInstanceBudget; // 25s
    final Duration connectTimeout;   // 10s
    final Duration pageFetchTimeout; // 5s
    const BackgroundSyncBudget({...defaults...});
  }
  ```
- **Cursor walk filter:** `fetchMessageHistory` has no `since` param. We page forward from the cursor; on each page, keep only messages with `msg.timestamp >= lastSyncMs`, stop paging once the oldest message on a page is `< lastSyncMs` (pages are newest→older, so once we cross the boundary older pages are entirely stale — but verify ordering direction against real behavior; see note). Insert kept messages via `batchInsertByIndexedIds` (dedup handles overlaps).
  > **Verify before implementing:** confirm `fetchMessageHistory` page ordering (newest-first vs oldest-first) from `ws_gateway_client.dart:444`. The walk stop condition depends on it. If newest-first: stop when a page's oldest msg `< lastSyncMs`. If oldest-first: stop when a page's newest msg `< lastSyncMs`. The test `executeOnce_cursorWalkFiltersByServerTs` pins the chosen behavior.
- **Connect timeout:** `WsGatewayClient.connect` has no explicit timeout param (handshake is 15s internal). To enforce the spec's 10s connect budget, wrap `connect` in `.timeout(connectTimeout)`. On `TimeoutException` → skip instance, do not update `last_sync_at`.
- **No double-WS concern (spec Known Risk):** the background isolate builds its **own** `WsGatewayClient` instance (not shared with main isolate). The spec accepts the multi-session possibility. The Runner does NOT try to detect/reuse main-isolate sessions.
- **Per-instance isolation:** each instance wrapped in its own try/catch; failure of B never blocks A.
- **`resolveAgent` for dispatcher:** the Runner resolves via `agentRepo.getAllByInstanceId(instanceId)`, builds a `Map<remoteId, Agent>`, filters out `agent.isRemoved` (returns null → dispatcher drops). This is where tombstone suppression happens (spec test `executeOnce_tombstoneAgentSuppressed`).

- [ ] **Step 1: Write the failing tests (16 cases from spec)**

```dart
// test/core/lifecycle/background_sync_runner_test.dart
import 'package:flutter_test/flutter_test.dart';
// fakes: FakeGatewayClient, FakeMessageRepo, FakeAgentRepo, FakeInstanceRepo,
//        FakeLastSyncRepo, FakeSettingsRepo, FakeDeviceTokenStore,
//        StubBackgroundSyncGate, CapturingDispatcher, FakeClock, StubLogger
// (build these to match the real interfaces; see "Resolved Signatures".)

void main() {
  late BackgroundSyncRunner runner;
  late RunnerDeps deps;

  setUp(() {
    deps = RunnerDeps.withDefaults(); // wires all fakes
    runner = deps.makeRunner();
  });

  test('executeOnce_skipWhenMainIsolateActive', () async {
    deps.gate.skip = true;
    await runner.executeOnce();
    expect(deps.gateway.connectCount, 0);
  });

  test('executeOnce_skipWhenToggleDisabled', () async {
    deps.settings.prefs = UserPreferences.defaults().copyWith(backgroundSyncEnabled: false);
    await runner.executeOnce();
    expect(deps.gateway.connectCount, 0);
  });

  test('executeOnce_pullAllInstances', () async {
    deps.instances.add(inst('A')); deps.instances.add(inst('B'));
    deps.gateway.agents['A'] = [agent('A', 'a1')];
    deps.gateway.agents['B'] = [agent('B', 'b1')];
    deps.gateway.history['A:a1'] = page([msg(serverId: 's1')]);
    deps.gateway.history['B:b1'] = page([msg(serverId: 's2')]);
    await runner.executeOnce();
    expect(deps.gateway.connectCount, 2);
    expect(deps.gateway.disconnectCount, 2);
  });

  test('executeOnce_partialFailure_continues', () async {
    deps.instances.add(inst('A')); deps.instances.add(inst('B'));
    deps.gateway.agents['A'] = [agent('A', 'a1')];
    deps.gateway.agents['B'] = [agent('B', 'b1')];
    deps.gateway.history['A:a1'] = page([msg(serverId: 's1')]);
    deps.gateway.throwOnConnect['B'] = Exception('boom');
    await runner.executeOnce();
    expect(await deps.lastSync.get('A'), isNotNull);   // updated
    expect(await deps.lastSync.get('B'), isNull);      // not updated
  });

  test('executeOnce_perInstanceLastSync', () async {
    deps.instances.add(inst('A')); deps.instances.add(inst('B'));
    await deps.lastSync.upsert('A', 1000);
    await deps.lastSync.upsert('B', 2000);
    deps.gateway.agents['A'] = [agent('A','a1')];
    deps.gateway.agents['B'] = [agent('B','b1')];
    deps.gateway.history['A:a1'] = page([msg(serverId:'s1', ts: 5000)]);  // > 1000
    deps.gateway.history['B:b1'] = page([msg(serverId:'s2', ts: 1500)]); // < 2000 → filtered
    await runner.executeOnce();
    // A pulled 1 (updated to 5000); B pulled 0 (updated to now()).
    expect(await deps.lastSync.get('A'), 5000);
  });

  test('executeOnce_zeroMessages_updatesLastSyncToNow', () async {
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1')];
    deps.gateway.history['A:a1'] = page([]); // empty
    final nowMs = 1700000000000;
    deps.clock.now = DateTime.fromMillisecondsSinceEpoch(nowMs);
    await runner.executeOnce();
    expect(await deps.lastSync.get('A'), nowMs);
  });

  test('executeOnce_notifyViaPendingRepo', () async {
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1')];
    deps.gateway.history['A:a1'] = page([msg(serverId:'s1', role: MessageRole.agent)]);
    await runner.executeOnce();
    expect(deps.dispatcher.handledLists, hasLength(1));   // routed through handlePulledMessages
    expect(deps.dispatcher.showCalled, isFalse);           // never show directly
  });

  test('executeOnce_tombstoneAgentSuppressed', () async {
    deps.instances.add(inst('A'));
    final tombstoned = agent('A','a1')..removedAt = 12345; // isRemoved
    deps.agentRepo.override['A'] = [tombstoned];
    deps.gateway.agents['A'] = [tombstoned];
    deps.gateway.history['A:a1'] = page([msg(serverId:'s1', role: MessageRole.agent)]);
    await runner.executeOnce();
    // handlePulledMessages receives resolveAgent→null for tombstoned → no enqueue.
    expect(deps.dispatcher.enqueuedServerIds, isEmpty);
  });

  test('executeOnce_timeoutDoesNotUpdateSync', () async {
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1')];
    deps.gateway.history['A:a1'] = page([msg(serverId:'s1')]);
    // Make connect exceed the perInstanceBudget (or connectTimeout).
    deps.gateway.connectDelay['A'] = const Duration(seconds: 30);
    runner = deps.makeRunner(budget: Budget(connectTimeout: Duration(milliseconds: 50)));
    await runner.executeOnce();
    expect(await deps.lastSync.get('A'), isNull);
  });

  test('executeOnce_dndRespected', () async {
    // DND on; pulled agent reply still goes through handlePulledMessages
    // (dispatcher evaluates → DndSuppressed → enqueue, no show).
    deps.settings.prefs = dndOnPrefs();
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1')];
    deps.gateway.history['A:a1'] = page([msg(serverId:'s1', role: MessageRole.agent)]);
    await runner.executeOnce();
    expect(deps.dispatcher.handledLists, hasLength(1));
    expect(deps.dispatcher.showCalled, isFalse);
  });

  test('executeOnce_perAgentCursorWalk', () async {
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1')];
    // 5 pages, each with nextCursor != null, all newer than lastSync.
    deps.gateway.history['A:a1'] = chain(pages: 5, perPage: 50, baseTs: 100000);
    await runner.executeOnce();
    expect(deps.gateway.fetchHistoryCalls['A:a1'], 5);
  });

  test('executeOnce_cursorWalkFiltersByServerTs', () async {
    deps.instances.add(inst('A'));
    await deps.lastSync.upsert('A', 5000);
    deps.gateway.agents['A'] = [agent('A','a1')];
    // 100 msgs returned but only 30 have ts >= 5000.
    deps.gateway.history['A:a1'] = page([
      for (var i = 0; i < 30; i++) msg(serverId: 'new$i', ts: 5000 + i),
      for (var i = 0; i < 70; i++) msg(serverId: 'old$i', ts: 1000 + i),
    ]);
    await runner.executeOnce();
    final inserted = deps.messageRepo.inserted;
    expect(inserted.where((m) => m.timestamp >= 5000).length, 30);
    expect(inserted.where((m) => m.timestamp < 5000).length, 0);
  });

  test('executeOnce_maxMessagesPerPullCap', () async {
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1')];
    deps.gateway.history['A:a1'] = chain(pages: 10, perPage: 50, baseTs: 100000); // 500 msgs
    runner = deps.makeRunner(budget: Budget(maxMessagesPerPull: 100));
    await runner.executeOnce();
    final totalInserted = deps.messageRepo.inserted.length;
    expect(totalInserted, lessThanOrEqualTo(100));
  });

  test('executeOnce_maxPagesPerAgentCap', () async {
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1')];
    deps.gateway.history['A:a1'] = chain(pages: 20, perPage: 50, baseTs: 100000);
    runner = deps.makeRunner(budget: Budget(maxPagesPerAgent: 5));
    await runner.executeOnce();
    expect(deps.gateway.fetchHistoryCalls['A:a1'], 5);
  });

  test('executeOnce_perInstanceBudgetTimeout', () async {
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1'), agent('A','a2')];
    // a1 fetch takes longer than perInstanceBudget → a2 skipped gracefully.
    deps.gateway.fetchDelay['A:a1'] = const Duration(seconds: 1);
    runner = deps.makeRunner(budget: Budget(perInstanceBudget: Duration(milliseconds: 200)));
    await runner.executeOnce();
    // a2 never fetched (budget exhausted). No throw.
    expect(deps.gateway.fetchHistoryCalls['A:a2'], isNull);
  });

  test('executeOnce_persistentDedupViaUniqueIndex', () async {
    // batchInsertByIndexedIds dedups; same serverId twice in one pull → inserted once.
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1')];
    deps.gateway.history['A:a1'] = page([
      msg(serverId: 's1', ts: 9000),
      msg(serverId: 's1', ts: 9000), // duplicate within batch
    ]);
    await runner.executeOnce();
    expect(deps.messageRepo.inserted.where((m) => m.serverId == 's1').length, 1);
  });

  test('executeOnce_pageFetchTimeout_skipsPageContinuesAgent', () async {
    deps.instances.add(inst('A'));
    deps.gateway.agents['A'] = [agent('A','a1'), agent('A','a2')];
    deps.gateway.fetchThrow['A:a1'] = TimeoutException('page');
    runner = deps.makeRunner(budget: Budget(pageFetchTimeout: Duration(milliseconds: 50)));
    deps.gateway.history['A:a2'] = page([msg(serverId:'s2', ts: 9000)]);
    await runner.executeOnce();
    expect(deps.gateway.fetchHistoryCalls['A:a2'], 1); // a2 still processed
  });
}
```

> **Test-infra guidance:** `RunnerDeps.withDefaults()` is a builder in the test file that wires all fakes to sensible defaults (2 instances optional, gate inactive, toggle on, fresh clock). `Budget(...)` is the `BackgroundSyncBudget` ctor. Build the fakes against the **real** interfaces from "Resolved Signatures". The fakes for `IGatewayClient` must track `connectCount`, `disconnectCount`, `fetchHistoryCalls`, per-key `history`/`agents`, and support `throwOnConnect`/`fetchThrow`/`fetchDelay`/`connectDelay`. `CapturingDispatcher` wraps a fake that records `handledLists` and exposes `enqueuedServerIds` / `showCalled` — it does **not** call the real `NotificationDispatcher` (keep the runner test isolated from dispatcher internals; the dispatcher's own behavior is covered in Task 4). Inject the dispatcher via an interface — see Step 2.

- [ ] **Step 2: Define the dispatcher injection interface**

The Runner must not depend on the concrete `NotificationDispatcher` (data layer). Define a tiny interface in the runner file (or a sibling) so the Runner stays testable and layer-clean:

```dart
// lib/core/lifecycle/background_sync_runner.dart (top of file)
/// Minimal contract the runner needs from the notification side.
/// Production impl delegates to NotificationDispatcher.handlePulledMessages.
abstract class IBackgroundSyncNotifier {
  Future<void> handlePulledMessages({
    required List<Message> messages,
    required Agent? Function(String instanceId, String agentRemoteId) resolveAgent,
  });
}
```

Task 4's `NotificationDispatcher` already has `handlePulledMessages` with this exact signature, so it implicitly satisfies `IBackgroundSyncNotifier`. (If Dart structural typing isn't enough, add `implements IBackgroundSyncNotifier` to `NotificationDispatcher` in Task 4's follow-up — but only if the signatures diverge; a thin adapter class is the safer choice.) For now the Runner depends on `IBackgroundSyncNotifier`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/core/lifecycle/background_sync_runner_test.dart`
Expected: FAIL — `background_sync_runner.dart` undefined (RED).

- [ ] **Step 4: Implement `BackgroundSyncBudget` + `BackgroundSyncRunner`**

```dart
// lib/core/lifecycle/background_sync_runner.dart
import 'dart:async';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_notifier.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_role.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_last_sync_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/domain/repositories/i_settings_repo.dart';
import 'package:claw_hub/core/utils/logger.dart';

class BackgroundSyncBudget {
  final int maxMessagesPerPull;
  final int maxPagesPerAgent;
  final Duration perInstanceBudget;
  final Duration connectTimeout;
  final Duration pageFetchTimeout;
  const BackgroundSyncBudget({
    this.maxMessagesPerPull = 100,
    this.maxPagesPerAgent = 5,
    this.perInstanceBudget = const Duration(seconds: 25),
    this.connectTimeout = const Duration(seconds: 10),
    this.pageFetchTimeout = const Duration(seconds: 5),
  });
}

enum InstanceSyncStatus { skipped, ok, failed }

class InstanceSyncResult {
  final String instanceId;
  final InstanceSyncStatus status;
  final int pulledCount;
  InstanceSyncResult(this.instanceId, this.status, {this.pulledCount = 0});
}

class BackgroundSyncResult {
  final List<InstanceSyncResult> instances;
  BackgroundSyncResult(this.instances);
}

class BackgroundSyncRunner {
  final IGatewayClient gateway;
  final IMessageRepo messageRepo;
  final IAgentRepo agentRepo;
  final IInstanceRepo instanceRepo;
  final ILastSyncRepo lastSyncRepo;
  final ISettingsRepo settingsRepo;
  final IBackgroundSyncNotifier notifier;
  final BackgroundSyncGate gate;
  final BackgroundSyncBudget budget;
  final DateTime Function() clock;
  final ILogger logger;

  const BackgroundSyncRunner({
    required this.gateway,
    required this.messageRepo,
    required this.agentRepo,
    required this.instanceRepo,
    required this.lastSyncRepo,
    required this.settingsRepo,
    required this.notifier,
    required this.gate,
    this.budget = const BackgroundSyncBudget(),
    required this.clock,
    required this.logger,
  });

  Future<BackgroundSyncResult> executeOnce() async {
    if (await gate.shouldSkip()) {
      logger.info('[BgSync] skipped — main isolate active');
      return BackgroundSyncResult(const []);
    }
    final prefs = await settingsRepo.getPreferences();
    if (!prefs.backgroundSyncEnabled) {
      logger.info('[BgSync] skipped — toggle disabled');
      return BackgroundSyncResult(const []);
    }

    final instances = await instanceRepo.getAll();
    final results = <InstanceSyncResult>[];
    for (final instance in instances) {
      results.add(await _syncInstance(instance));
    }
    return BackgroundSyncResult(results);
  }

  Future<InstanceSyncResult> _syncInstance(Instance instance) async {
    try {
      await gateway.connect(instance).timeout(budget.connectTimeout);
    } catch (e, st) {
      logger.error('[BgSync] connect failed ${instance.id}: $e', st);
      return InstanceSyncResult(instance.id, InstanceSyncStatus.failed);
    }

    try {
      final deadline = clock().add(budget.perInstanceBudget);
      final lastSyncMs = await lastSyncRepo.get(instance.id) ??
          clock().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;

      final agents = await agentRepo.getAllByInstanceId(instance.id);
      // Map remoteId → Agent for the notifier's resolver; tombstoned → null.
      final byRemote = {for (final a in agents) a.remoteId: a};

      var totalPulled = 0;
      var maxTs = lastSyncMs;
      final allNew = <Message>[];

      for (final agent in agents) {
        if (totalPulled >= budget.maxMessagesPerPull) break;
        if (clock().isAfter(deadline)) {
          logger.info('[BgSync] budget exhausted on ${instance.id}, skipping remaining agents');
          break;
        }
        final agentResult = await _walkAgent(
          instance: instance,
          agent: agent,
          lastSyncMs: lastSyncMs,
          deadline: deadline,
        );
        allNew.addAll(agentResult.newMessages);
        totalPulled += agentResult.newMessages.length;
        if (agentResult.maxTs > maxTs) maxTs = agentResult.maxTs;
      }

      // Resolve agent for notifier (tombstoned → null).
      final inserted = allNew.isEmpty
          ? const <Message>[]
          : await messageRepo.batchInsertByIndexedIds(allNew);

      if (inserted.isNotEmpty) {
        // Route to persistent dedup path. resolveAgent filters tombstoned.
        await notifier.handlePulledMessages(
          messages: inserted,
          resolveAgent: (iid, remoteId) {
            final a = byRemote[remoteId];
            if (a == null || a.isRemoved) return null;
            return a;
          },
        );
      }

      // Update last_sync_at: success-with-messages → max(serverTs);
      // success-empty → now(). Inserted empty → now() (covers zero-message case).
      final newCursor = inserted.isEmpty
          ? clock().millisecondsSinceEpoch
          : inserted.fold<int>(0, (m, x) => x.timestamp > m ? x.timestamp : m);
      // If we filtered everything but had pages, still advance to now() so we
      // don't re-walk the same stale pages next tick.
      final effectiveCursor = (inserted.isEmpty && allNew.isNotEmpty)
          ? clock().millisecondsSinceEpoch
          : (inserted.isEmpty ? clock().millisecondsSinceEpoch : newCursor);
      await lastSyncRepo.upsert(instance.id, effectiveCursor);

      await gateway.disconnect(instance.id);
      return InstanceSyncResult(instance.id, InstanceSyncStatus.ok,
          pulledCount: inserted.length);
    } catch (e, st) {
      logger.error('[BgSync] sync failed ${instance.id}: $e', st);
      try {
        await gateway.disconnect(instance.id);
      } catch (_) {}
      return InstanceSyncResult(instance.id, InstanceSyncStatus.failed);
    }
  }

  Future<_AgentWalk> _walkAgent({
    required Instance instance,
    required Agent agent,
    required int lastSyncMs,
    required DateTime deadline,
  }) async {
    final newMessages = <Message>[];
    var maxTs = lastSyncMs;
    String? cursor;
    for (var page = 0; page < budget.maxPagesPerAgent; page++) {
      if (clock().isAfter(deadline)) break;
      final res = await gateway
          .fetchMessageHistory(
            instanceId: instance.id,
            agentId: agent.remoteId,
            cursor: cursor,
            limit: 50,
          )
          .timeout(budget.pageFetchTimeout);
      final fresh = res.messages.where((m) => m.timestamp >= lastSyncMs).toList();
      newMessages.addAll(fresh);
      for (final m in fresh) {
        if (m.timestamp > maxTs) maxTs = m.timestamp;
      }
      // newest-first: once the oldest on this page is older than lastSync,
      // all further pages are entirely stale → stop.
      if (res.messages.isNotEmpty &&
          res.messages.map((m) => m.timestamp).reduce((a, b) => a < b ? a : b) <
              lastSyncMs) {
        break;
      }
      if (res.nextCursor == null) break;
      cursor = res.nextCursor;
    }
    return _AgentWalk(newMessages, maxTs);
  }
}

class _AgentWalk {
  final List<Message> newMessages;
  final int maxTs;
  _AgentWalk(this.newMessages, this.maxTs);
}
```

> **Implementer must verify** (before claiming green):
> 1. Page-ordering assumption (newest-first) against `ws_gateway_client.dart:444` — adjust the "oldest on page < lastSync → stop" condition if oldest-first.
> 2. `IInstanceRepo.getAll()` exists (signature: `Future<List<Instance>> getAll()` — confirm in `lib/domain/repositories/i_instance_repo.dart`). The Runner's `effectiveCursor` logic above is deliberately conservative (advance to `now()` when nothing fresh was inserted) to avoid re-walking stale pages every tick — if a test asserts a specific cursor value, align the test with this semantics.
> 3. `MessageRole.agent` enum import path.
> 4. `Instance.tokenRef` is a secure-storage KEY, not the raw token. The Runner calls `gateway.connect(instance)` which internally resolves the token via `IDeviceTokenStore` (Task 7's `callbackDispatcher` wires the store). The Runner does **not** touch `IDeviceTokenStore` directly — remove it from the "Consumes" list if unused. (It is unused by the Runner itself; only the `callbackDispatcher` needs it to build the `WsGatewayClient`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/core/lifecycle/background_sync_runner_test.dart`
Expected: PASS (16 tests). Iterate on fake/impl until green. Do **not** weaken test assertions to force green — if a test reveals a real logic gap, fix the impl.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/core/lifecycle/background_sync_runner.dart`
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/core/lifecycle/background_sync_runner.dart \
        lib/core/lifecycle/i_background_sync_notifier.dart \
        test/core/lifecycle/background_sync_runner_test.dart
git commit -m "feat(background-sync): BackgroundSyncRunner per-agent cursor walk with budget caps"
```

---

## Task 6: `BackgroundSyncScheduler` — platform abstraction

Thin wrapper over `workmanager`: `ensureScheduled()` / `cancel()` / `notifyInstancesChanged()`. Holds a `WidgetsBindingObserver` to flip the gate on `paused`/`resumed`. No business logic — pure platform wiring, so it is **not** unit-tested for the workmanager calls (those are platform integration; documented in Task 11). The gate-flip logic IS unit-testable by injecting a `BackgroundSyncGate` + a fake lifecycle.

**Files:**
- Create: `lib/core/lifecycle/background_sync_scheduler.dart`
- Test: `test/core/lifecycle/background_sync_scheduler_test.dart` (gate-flip behavior only)

**Interfaces:**
- Consumes: `BackgroundSyncGate`, a `WorkmanagerBackend` interface (tiny, to allow faking).
- Produces: `BackgroundSyncScheduler` with `Future<void> ensureScheduled()`, `Future<void> cancel()`, `void notifyInstancesChanged()`, `void onAppPaused()`, `void onAppResumed()`.

- [ ] **Step 1: Write the failing test (gate-flip on lifecycle)**

```dart
// test/core/lifecycle/background_sync_scheduler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/background_sync_scheduler.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_prefs.dart';

class _RecordingPrefs implements IBackgroundSyncPrefs {
  bool value = true; // start: main active
  @override Future<bool> get mainActive => Future.value(value);
  @override Future<void> setMainActive(bool a) async { value = a; }
  @override Future<void> clear() async { value = false; }
}

class _RecordingBackend implements WorkmanagerBackend {
  int scheduleCalls = 0;
  int cancelCalls = 0;
  @override Future<void> enqueueUniquePeriodic() async { scheduleCalls++; }
  @override Future<void> cancelUniqueWork() async { cancelCalls++; }
}

void main() {
  test('onAppPaused_setsMainInactive_andEnqueues', () async {
    final prefs = _RecordingPrefs();
    final backend = _RecordingBackend();
    final scheduler = BackgroundSyncScheduler(
      gate: BackgroundSyncGate(prefs: prefs),
      backend: backend,
    );
    await scheduler.onAppPaused();
    expect(prefs.value, isFalse);             // gate flipped
    expect(backend.scheduleCalls, 1);          // work enqueued
  });

  test('onAppResumed_setsMainActive_andCancels', () async {
    final prefs = _RecordingPrefs()..value = false;
    final backend = _RecordingBackend();
    final scheduler = BackgroundSyncScheduler(
      gate: BackgroundSyncGate(prefs: prefs),
      backend: backend,
    );
    await scheduler.onAppResumed();
    expect(prefs.value, isTrue);
    expect(backend.cancelCalls, 1);
  });

  test('ensureScheduled_isIdempotent', () async {
    final backend = _RecordingBackend();
    final scheduler = BackgroundSyncScheduler(
      gate: BackgroundSyncGate(prefs: _RecordingPrefs()),
      backend: backend,
    );
    await scheduler.ensureScheduled();
    await scheduler.ensureScheduled();
    expect(backend.scheduleCalls, 2); // REPLACE policy — re-enqueue is safe/idempotent
  });

  test('cancel_callsBackend', () async {
    final backend = _RecordingBackend();
    final scheduler = BackgroundSyncScheduler(
      gate: BackgroundSyncGate(prefs: _RecordingPrefs()),
      backend: backend,
    );
    await scheduler.cancel();
    expect(backend.cancelCalls, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/lifecycle/background_sync_scheduler_test.dart`
Expected: FAIL — scheduler file missing (RED).

- [ ] **Step 3: Implement the scheduler**

```dart
// lib/core/lifecycle/background_sync_scheduler.dart
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';

/// Minimal backend so the scheduler is unit-testable without the real
/// workmanager plugin (which throws outside an app context).
abstract class WorkmanagerBackend {
  Future<void> enqueueUniquePeriodic();
  Future<void> cancelUniqueWork();
}

/// Schedules / cancels the periodic background-sync work and flips the
/// [BackgroundSyncGate] on app lifecycle changes.
///
/// The real production backend (Task 7) wraps `Workmanager().registerPeriodicTask`
/// / `cancelUniqueWork`. REPLACE uniqueness makes [ensureScheduled] idempotent.
class BackgroundSyncScheduler {
  static const uniqueWorkName = 'clawhub.background-sync';

  final BackgroundSyncGate gate;
  final WorkmanagerBackend backend;

  BackgroundSyncScheduler({required this.gate, required this.backend});

  /// Called on app start and on toggle-on. Idempotent (REPLACE policy).
  Future<void> ensureScheduled() => backend.enqueueUniquePeriodic();

  Future<void> cancel() => backend.cancelUniqueWork();

  /// Instances changed (saved/deleted) — reschedule so the next tick sees the
  /// new instance set. (The runner re-reads instances each tick, so this is
  /// belt-and-suspenders; mainly ensures work is scheduled if it was cancelled.)
  Future<void> notifyInstancesChanged() => backend.enqueueUniquePeriodic();

  /// App went to background → mark main inactive + enqueue a tick soon.
  Future<void> onAppPaused() async {
    await gate.setMainActive(false);
    await backend.enqueueUniquePeriodic();
  }

  /// App returned to foreground → mark main active + cancel pending tick
  /// (the live messageStream takes over).
  Future<void> onAppResumed() async {
    await gate.setMainActive(true);
    await backend.cancelUniqueWork();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/lifecycle/background_sync_scheduler_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze lib/core/lifecycle/background_sync_scheduler.dart`
Expected: no issues.

```bash
git add lib/core/lifecycle/background_sync_scheduler.dart \
        test/core/lifecycle/background_sync_scheduler_test.dart
git commit -m "feat(background-sync): BackgroundSyncScheduler platform abstraction"
```

---

## Task 7: Riverpod providers, `callbackDispatcher`, SharedPreferences impl, `main.dart` init

Wires everything: production `WorkmanagerBackend`, `SharedPreferences`-backed `IBackgroundSyncPrefs`, providers for gate/last-sync/runner/scheduler, the top-level `callbackDispatcher` that rebuilds deps in the background isolate, and `Workmanager().initialize` in `main.dart`. Also adds the two pub deps.

**Files:**
- Modify: `pubspec.yaml` (add `workmanager`, `shared_preferences`)
- Create: `lib/core/lifecycle/background_sync_prefs_shared_prefs.dart` (prod `IBackgroundSyncPrefs`)
- Create: `lib/core/lifecycle/background_sync_workmanager_backend.dart` (prod `WorkmanagerBackend`)
- Create: `lib/core/lifecycle/background_sync_runner_factory.dart` (top-level `callbackDispatcher`)
- Modify: `lib/app/di/providers.dart` (providers + background-isolate dep builder)
- Modify: `lib/main.dart` (`Workmanager().initialize`)

**Interfaces:**
- Produces: providers `backgroundSyncGateProvider`, `lastSyncRepoProvider`, `backgroundSyncRunnerProvider`, `backgroundSyncSchedulerProvider`, and a top-level `callbackDispatcher`.

> **Critical workmanager constraint:** `callbackDispatcher` MUST be a top-level/static function annotated `@pragma('vm:entry-point')`. It cannot close over Riverpod `ref`. It must rebuild all deps from scratch in the background isolate (Drift DB, secure storage, notification service, gateway client). There is NO ProviderScope in the background isolate.

- [ ] **Step 1: Add dependencies**

In `pubspec.yaml` `dependencies:`, add (verify latest compatible versions at add time; pin conservatively):
```yaml
  workmanager: ^0.5.2
  shared_preferences: ^2.3.3
```

Run: `flutter pub get`
Expected: resolves.

- [ ] **Step 2: Implement SharedPreferences-backed prefs**

```dart
// lib/core/lifecycle/background_sync_prefs_shared_prefs.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_prefs.dart';

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
```

- [ ] **Step 3: Implement the workmanager backend**

```dart
// lib/core/lifecycle/background_sync_workmanager_backend.dart
import 'package:workmanager/workmanager.dart';
import 'package:claw_hub/core/lifecycle/background_sync_scheduler.dart';

class WorkmanagerBackendImpl implements WorkmanagerBackend {
  const WorkmanagerBackendImpl();

  @override
  Future<void> enqueueUniquePeriodic() async {
    await Workmanager().registerPeriodicTask(
      BackgroundSyncScheduler.uniqueWorkName,
      BackgroundSyncScheduler.uniqueWorkName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  @override
  Future<void> cancelUniqueWork() async {
    await Workmanager().cancelByUniqueName(BackgroundSyncScheduler.uniqueWorkName);
  }
}
```

> **Verify API names** against the installed `workmanager` version's API (`registerPeriodicTask` / `cancelByUniqueName` / `ExistingWorkPolicy.replace` / `Constraints`). If the resolved version differs (e.g. `^0.5.x` vs newer), adjust to the actual API — do not leave compile errors.

- [ ] **Step 4: Implement the top-level `callbackDispatcher`**

```dart
// lib/core/lifecycle/background_sync_runner_factory.dart
import 'dart:isolate';
import 'package:claw_hub/core/acl/ws_gateway_client.dart';
import 'package:claw_hub/core/acl/secure_storage_device_token_store.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/background_sync_prefs_shared_prefs.dart';
import 'package:claw_hub/core/lifecycle/background_sync_runner.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_notifier.dart';
import 'package:claw_hub/core/utils/logger.dart';
import 'package:claw_hub/data/local/database/database_initializer.dart';
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/data/repositories/drift_last_sync_repo.dart';
import 'package:claw_hub/data/repositories/drift_message_repo.dart';
import 'package:claw_hub/data/repositories/drift_settings_repo.dart';
import 'package:claw_hub/data/services/notification_dispatcher.dart';
import 'package:workmanager/workmanager.dart';

/// US-018 background isolate entry point.
///
/// MUST be top-level + @pragma('vm:entry-point') — workmanager calls it from
/// a fresh isolate with NO ProviderScope. Rebuild every dependency here.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final logger = const DebugPrintLogger();
    try {
      final db = await createAppDatabase();
      final gate = BackgroundSyncGate(
        prefs: const SharedPreferencesBackgroundSyncPrefs(),
      );
      if (await gate.shouldSkip()) {
        logger.info('[BgSync] dispatcher: main active, skip');
        await db.close();
        return true;
      }

      final settingsRepo = DriftSettingsRepo(db, logger: logger);
      final prefs = await settingsRepo.getPreferences();
      if (!prefs.backgroundSyncEnabled) {
        logger.info('[BgSync] dispatcher: toggle off, skip');
        await db.close();
        return true;
      }

      final gateway = WsGatewayClient(
        identityProvider: /* rebuild device identity */,
        deviceTokenStore: const SecureStorageDeviceTokenStore(),
      );
      final runner = BackgroundSyncRunner(
        gateway: gateway,
        messageRepo: DriftMessageRepo(db),
        agentRepo: DriftAgentRepo(db),
        instanceRepo: DriftInstanceRepo(db),
        lastSyncRepo: DriftLastSyncRepo(db),
        settingsRepo: settingsRepo,
        notifier: _BackgroundIsolateNotifier(db, logger),
        gate: gate,
        clock: DateTime.now,
        logger: logger,
      );

      await runner.executeOnce();
      await gateway.dispose();
      await db.close();
      return true;
    } catch (e, st) {
      logger.error('[BgSync] dispatcher failed: $e', st);
      return false; // workmanager will retry per its backoff (acceptable)
    }
  });
}

/// Minimal notifier for the background isolate: routes pulled messages
/// through the persistent pending_notifications path (same contract as the
/// main NotificationDispatcher.handlePulledMessages, but without the live
/// event stream / DND timer). Reuses EvaluateNotificationUseCase.
class _BackgroundIsolateNotifier implements IBackgroundSyncNotifier {
  final dynamic _db; // AppDatabase — typed loosely to avoid import cycle here
  final ILogger _logger;
  _BackgroundIsolateNotifier(this._db, this._logger);

  @override
  Future<void> handlePulledMessages({
    required List messages,
    required Agent? Function(String instanceId, String agentRemoteId) resolveAgent,
  }) async {
    // Delegate to a shared helper that both the main dispatcher and this
    // background notifier call. See Step 5.
    await BackgroundNotifierShared.enqueuePulled(
      db: _db,
      messages: messages.cast(),
      resolveAgent: resolveAgent,
      logger: _logger,
    );
  }
}
```

> **Step 5 — DRY the notifier logic.** The main `NotificationDispatcher.handlePulledMessages` (Task 4) and `_BackgroundIsolateNotifier` both do "evaluate → enqueue pending". Extract the shared decision→enqueue logic into a static helper (e.g. `BackgroundNotifierShared.enqueuePulled` in a new `lib/data/services/background_notifier_shared.dart`) that both call. **Update Task 4's `handlePulledMessages` to delegate to this helper** so there is one implementation. This avoids two copies of the dedup contract drifting. The main dispatcher keeps its `warmupFromPending` + `_notifiedKeys` LRU (main-isolate-only concerns); only the evaluate→enqueue body is shared.
>
> **Resolve device identity in the background isolate:** `WsGatewayClient` needs an `IDeviceIdentityProvider`. The main isolate uses `Ed25519IdentityProvider` (`lib/app/di/providers.dart:199`). Rebuild it the same way in `callbackDispatcher` (it reads from secure storage). Confirm the `Ed25519IdentityProvider` ctor params (`lib/core/acl/ed25519_identity_provider.dart:45`) and mirror them. **Verify** `createAppDatabase()` (from `lib/data/local/database/database_initializer.dart`) is safe to call twice (main + background isolate) — it opens the same SQLite file; on Android with WAL mode this is fine concurrently. If the initializer caches a singleton, ensure the background isolate gets its own handle.

- [ ] **Step 6: Add providers in `lib/app/di/providers.dart`**

```dart
// append to providers.dart
final backgroundSyncPrefsProvider = Provider<IBackgroundSyncPrefs>(
  (_) => const SharedPreferencesBackgroundSyncPrefs(),
);

final backgroundSyncGateProvider = Provider<BackgroundSyncGate>((ref) {
  return BackgroundSyncGate(prefs: ref.watch(backgroundSyncPrefsProvider));
});

final lastSyncRepoProvider = Provider<ILastSyncRepo>(
  (ref) => DriftLastSyncRepo(ref.watch(databaseProvider)),
);

final backgroundSyncRunnerProvider = Provider<BackgroundSyncRunner>((ref) {
  return BackgroundSyncRunner(
    gateway: ref.watch(gatewayClientProvider),
    messageRepo: ref.watch(messageRepoProvider),
    agentRepo: ref.watch(agentRepoProvider),
    instanceRepo: ref.watch(instanceRepoProvider),
    lastSyncRepo: ref.watch(lastSyncRepoProvider),
    settingsRepo: ref.watch(settingsRepoProvider),
    notifier: ref.watch(notificationDispatcherProvider), // implements IBackgroundSyncNotifier
    gate: ref.watch(backgroundSyncGateProvider),
    clock: DateTime.now,
    logger: ref.watch(loggerProvider),
  );
});

final backgroundSyncSchedulerProvider = Provider<BackgroundSyncScheduler>((ref) {
  return BackgroundSyncScheduler(
    gate: ref.watch(backgroundSyncGateProvider),
    backend: const WorkmanagerBackendImpl(),
  );
});
```

> **`NotificationDispatcher implements IBackgroundSyncNotifier`:** add `implements IBackgroundSyncNotifier` to the `NotificationDispatcher` class declaration in `lib/data/services/notification_dispatcher.dart` (Task 4) so the provider wiring type-checks. The signature already matches. If it diverges, add a 3-line adapter provider instead.

- [ ] **Step 7: Initialize workmanager in `main.dart`**

In `lib/main.dart`, after `WidgetsFlutterBinding.ensureInitialized();` and **before** `runApp`:

```dart
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: kDebugMode,
  );
  // Note: Workmanager.configureSeparateBackgroundProcess is intentionally NOT
  // called — same-process keeps flutter_secure_storage keychain access working.
```

Add imports:
```dart
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:claw_hub/core/lifecycle/background_sync_runner_factory.dart';
```

- [ ] **Step 8: Analyze + commit**

Run: `flutter analyze lib/`
Expected: no new issues (fix any import/type errors from the wiring).

```bash
git add pubspec.yaml pubspec.lock \
        lib/core/lifecycle/background_sync_prefs_shared_prefs.dart \
        lib/core/lifecycle/background_sync_workmanager_backend.dart \
        lib/core/lifecycle/background_sync_runner_factory.dart \
        lib/data/services/background_notifier_shared.dart \
        lib/app/di/providers.dart \
        lib/main.dart \
        lib/data/services/notification_dispatcher.dart
git commit -m "feat(background-sync): providers, callbackDispatcher, workmanager init"
```

---

## Task 8: "后台同步" toggle UI + ViewModel setter

Surface the toggle in the notification settings page (mirrors the existing toggle pattern exactly), and add the `SettingsViewModel` setter.

**Files:**
- Modify: `lib/features/settings/viewmodels/settings_view_model.dart`
- Modify: `lib/features/settings/notification_settings_page.dart`
- Test: extend `test/features/settings/...` (Law 14: widget needs ≥2 tests). At minimum a ViewModel setter test + a widget toggle test.

**Interfaces:**
- Produces: `SettingsViewModel.setBackgroundSyncEnabled(bool)`.

- [ ] **Step 1: Add the ViewModel setter**

In `lib/features/settings/viewmodels/settings_view_model.dart`, alongside `setBiometricEnabled`:

```dart
  // ---------------------------------------------------------------------------
  // Background Sync
  // ---------------------------------------------------------------------------

  /// Toggle background sync (US-018).
  Future<void> setBackgroundSyncEnabled(bool value) {
    _update(state.copyWith(backgroundSyncEnabled: value));
    return _pendingUpdate;
  }
```

- [ ] **Step 2: Write the failing ViewModel test**

```dart
// test/features/settings/viewmodels/background_sync_toggle_test.dart
// (or extend the existing settings_view_model test file)
test('setBackgroundSyncEnabled_persistsAndUpdatesState', () async {
  final vm = SettingsViewModel(repo: fakeSettingsRepo);
  await vm.init();
  await vm.setBackgroundSyncEnabled(false);
  expect(vm.state.backgroundSyncEnabled, isFalse);
  expect(fakeSettingsRepo.lastSaved!.backgroundSyncEnabled, isFalse);
  await vm.setBackgroundSyncEnabled(true);
  expect(vm.state.backgroundSyncEnabled, isTrue);
});
```
> Reuse the existing `SettingsViewModel` test harness/fake repo. Match its style.

- [ ] **Step 3: Run test to verify it passes**

Run: `flutter test test/features/settings/`
Expected: PASS.

- [ ] **Step 4: Add the toggle row to the notification settings page**

In `lib/features/settings/notification_settings_page.dart`, the `build` method watches a tuple of prefs via `settingsViewModelProvider.select`. Add `backgroundSyncEnabled` to that select tuple and add a new `SettingsToggleRow` after the connection-status row (or in a new grouped container labeled "后台同步"):

```dart
    final prefs = ref.watch(
      settingsViewModelProvider.select(
        (s) => (
          notificationsEnabled: s.notificationsEnabled,
          notifyOnReply: s.notifyOnReply,
          notifyOnError: s.notifyOnError,
          notifyOnConnectionChange: s.notifyOnConnectionChange,
          backgroundSyncEnabled: s.backgroundSyncEnabled,
        ),
      ),
    );
```

Add a new grouped section (after the existing notification-types container, before the explanatory text):

```dart
          const SizedBox(height: XiaSpacing.s5),
          Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.lg),
            ),
            child: SettingsToggleRow(
              emoji: '🔄',
              label: '后台同步',
              subtitle: 'App 闲置时定时拉取新消息（约 15 分钟，由系统调度）',
              value: prefs.backgroundSyncEnabled,
              onChanged: vm.setBackgroundSyncEnabled,
              isLast: true,
            ),
          ),
```

> Place it so `isLast`/`SettingsDivider` continuity is correct (the last row in a container uses `isLast: true`; preceding rows use the divider). Match the exact widget API of `SettingsToggleRow` from `lib/features/settings/shared/settings_widgets.dart`.

- [ ] **Step 5: Write the widget test (Law 14)**

```dart
// test/features/settings/notification_settings_page_test.dart (extend or create)
testWidgets('backgroundSyncToggle_togglesStateOnTap', (tester) async {
  await tester.pumpWidget(makeSettingsApp(initialPrefs: defaultsOn));
  await tester.pumpAndSettle();
  expect(find.text('后台同步'), findsOneWidget);
  final switchFinder = find.byType(Switch).at(/* index of the bg-sync row */);
  expect(tester.widget<Switch>(switchFinder).value, isTrue);
  await tester.tap(switchFinder);
  await tester.pump();
  expect(tester.widget<Switch>(switchFinder).value, isFalse);
});

testWidgets('backgroundSyncToggle_persistsViaViewModel', (tester) async {
  // tap → assert fake repo received setBackgroundSyncEnabled(false)
});
```
> Use the existing settings-page widget test harness. If none exists, build a minimal `ProviderScope` with overridden `settingsViewModelProvider` (or `settingsRepoProvider`) and the page. Verify against the real `SettingsToggleRow` widget's internal Switch type.

- [ ] **Step 6: Run widget tests + analyze**

Run: `flutter test test/features/settings/`
Expected: PASS.

Run: `flutter analyze lib/features/settings/`
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/settings/viewmodels/settings_view_model.dart \
        lib/features/settings/notification_settings_page.dart \
        test/features/settings/
git commit -m "feat(settings): 后台同步 toggle UI + ViewModel setter"
```

---

## Task 9: Bootstrap + lifecycle wiring (WidgetsBindingObserver, warmup, orchestrator hooks)

Wire the scheduler into app startup and the app-lifecycle observer, call `warmupFromPending`, and notify the scheduler on instance save/delete.

**Files:**
- Modify: `lib/app/notifications/notification_bootstrap.dart`
- Modify: `lib/app/connection/connection_orchestrator.dart`

**Interfaces:**
- Consumes: `backgroundSyncSchedulerProvider`, `notificationDispatcherProvider` (`warmupFromPending`).
- Produces: app-lifecycle → gate/scheduler; orchestrator → scheduler notify.

- [ ] **Step 1: Make `NotificationBootstrap` a `WidgetsBindingObserver` + wire scheduler**

In `lib/app/notifications/notification_bootstrap.dart`:

Add `WidgetsBindingObserver` to the class:

```dart
class NotificationBootstrap with WidgetsBindingObserver {
```

In `init()`, after `await _ref.read(notificationCoordinatorProvider).start();`:

```dart
    // US-018: reseed in-memory dedup LRU from persisted pending notifications
    // so the live messageStream doesn't re-notify messages the background
    // isolate already enqueued before this cold start.
    try {
      await _ref.read(notificationDispatcherProvider).warmupFromPending();
    } catch (e, st) {
      logger.error('[NotificationBootstrap] warmupFromPending failed: $e', st);
    }

    // US-018: schedule background sync + observe app lifecycle.
    try {
      await _ref.read(backgroundSyncSchedulerProvider).ensureScheduled();
      WidgetsBinding.instance.addObserver(this);
    } catch (e, st) {
      logger.error('[NotificationBootstrap] scheduler init failed: $e', st);
    }
```

Override the lifecycle callback:

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scheduler = _ref.read(backgroundSyncSchedulerProvider);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // best-effort; gate write is async (see spec Known Risk).
        scheduler.onAppPaused();
      case AppLifecycleState.resumed:
        scheduler.onAppResumed();
      default:
        break;
    }
  }
```

In `dispose()`, remove the observer:

```dart
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _prefsSub?.cancel();
    _prefsSub = null;
  }
```

Add imports:
```dart
import 'package:flutter/widgets.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/data/services/notification_dispatcher.dart';
```

> **Note:** `notificationDispatcherProvider` must expose the dispatcher object. It is currently constructed inside `notificationCoordinatorProvider` and not separately exposed. If `notificationDispatcherProvider` does not exist, either (a) extract it as its own provider that `notificationCoordinatorProvider` watches, or (b) add a `dispatcher` getter on `NotificationCoordinator` and call `_ref.read(notificationCoordinatorProvider).dispatcher.warmupFromPending()`. Prefer (a) for clean DI. **Verify** which exists before wiring — grep `notificationDispatcherProvider` in `providers.dart`; if absent, do (b).

- [ ] **Step 2: Hook the orchestrator instance lifecycle**

In `lib/app/connection/connection_orchestrator.dart`:

Add a nullable scheduler callback field (don't hard-depend on the scheduler — keep the orchestrator's existing dep list; inject via constructor optional param or a setter the provider wires):

```dart
  /// US-018: optional callback to notify background-sync scheduler that the
  /// instance set changed. Null in tests / when background sync is disabled.
  final Future<void> Function()? _onInstancesChanged;
```

Add to constructor (optional, named, default null). In `onInstanceSaved` (after the existing body, both branches) and `onInstanceDeleted` (after `_disconnect`):

```dart
    try {
      await _onInstancesChanged?.call();
    } catch (_) { /* background sync scheduling is best-effort */ }
```

Wire it in `lib/app/di/providers.dart` `connectionOrchestratorProvider`:

```dart
final connectionOrchestratorProvider = Provider<ConnectionOrchestrator>((ref) {
  final scheduler = ref.watch(backgroundSyncSchedulerProvider);
  final coordinator = ConnectionCoordinator(
    // ...existing args...
    onInstancesChanged: scheduler.notifyInstancesChanged,
  );
  // ...
});
```

- [ ] **Step 3: Run existing orchestrator/bootstrap tests to confirm no regressions**

Run: `flutter test test/app/connection/ test/app/notifications/`
Expected: PASS. If existing tests construct `NotificationCoordinator`/`ConnectionOrchestrator` directly, they may need the new optional param defaulted — that's fine (it's optional).

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/app/`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/app/notifications/notification_bootstrap.dart \
        lib/app/connection/connection_orchestrator.dart \
        lib/app/di/providers.dart
git commit -m "feat(background-sync): bootstrap lifecycle wiring + orchestrator instance-change hooks"
```

---

## Task 10: Native layer — Android Manifest + iOS Info.plist / AppDelegate

Platform configuration only. Not unit-testable; verified manually in Task 11.

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Create: `ios/Runner/AppDelegate.swift`
- Verify: `ios/Runner/AppDelegate.m` / `MainFlutterWindow.swift` interplay — if the iOS host is currently Obj-C (`AppDelegate.m`), either (a) keep it Obj-C and register the BG task in Obj-C, or (b) migrate to Swift. **Inspect the actual `ios/Runner/` contents first** and match the existing language; do not assume Swift.

### Android

- [ ] **Step 1: Add permission + disable default WorkManager init**

In `android/app/src/main/AndroidManifest.xml`, add the permission (as a sibling of existing `<uses-permission>`):

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

Inside `<application>`, add the provider that removes the default `WorkManagerInitializer` so our explicit `Workmanager().initialize` controls scheduling:

```xml
        <provider
            android:name="androidx.startup.InitializationProvider"
            android:authorities="${applicationId}.androidx-startup"
            android:exported="false"
            tools:node="merge">
            <meta-data
                android:name="androidx.work.WorkManagerInitializer"
                android:value="androidx.startup"
                tools:node="remove" />
        </provider>
```

> Ensure `xmlns:tools="http://schemas.android.com/tools"` is declared on the `<manifest>` tag. **Verify** the workmanager plugin's Android setup docs for the installed version — the provider-removal snippet is the standard recipe but confirm field names.

### iOS

- [ ] **Step 2: Add background modes to Info.plist**

In `ios/Runner/Info.plist`, add:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.clawhub.background-sync</string>
</array>
```

- [ ] **Step 3: Register the BG task in the AppDelegate**

**First inspect** `ios/Runner/`. The spec assumes Swift; the real host may be `AppDelegate.m` (Obj-C). Match what exists.

If Swift (`AppDelegate.swift`), use (per spec):

```swift
import UIKit
import Flutter
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    WorkmanagerPlugin.registerTask(withIdentifier: "com.clawhub.background-sync")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

If Obj-C (`AppDelegate.m`), add the equivalent registration in `application:didFinishLaunchingWithOptions:`:

```objc
#import "AppDelegate.h"
#import "GeneratedPluginRegistrant.h"
#import <workmanager/WorkmanagerPlugin.h>

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [GeneratedPluginRegistrant registerWithRegistry:self];
  [WorkmanagerPlugin registerTaskWithIdentifier:@"com.clawhub.background-sync"];
  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}
@end
```

> **Verify** the exact `workmanager` iOS API for the installed version (`registerTask(withIdentifier:)` vs `registerBGTaskScheduler`). The plugin's README is authoritative. Do not ship a build that won't compile.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml \
        ios/Runner/Info.plist \
        ios/Runner/AppDelegate.swift   # or .m
git commit -m "feat(background-sync): native WorkManager (Android) + BGTaskScheduler (iOS) registration"
```

---

## Task 11: Manual verification + known-limitations documentation

The automated tests can't cover real OS scheduling. This task runs the spec's Manual Verification Checklist and documents the load-bearing assumptions.

**Files:**
- Modify: `docs/product/user-stories.md` (US-018 acceptance criteria pointer) — optional, only if AC-21 needs adding
- Modify: `docs/technical/acl-protocol-gaps.md` or a new `docs/technical/background-sync-limitations.md` — record the known OS-scheduling limitations
- No code

- [ ] **Step 1: Run the full automated suite**

Run: `flutter test`
Expected: all green (existing + new Task 1–9 tests).

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 2: MVP performance pre-check (load-bearing assumption)**

Per spec, this is a **gate**: if it fails, the strategy must change (split Android pull / switch iOS to `BGProcessingTask`). Do NOT ship without it.

On an Android emulator/device with a 3-agent instance:
1. Seed the instance with ~1h of message history (enough to force a multi-page cursor walk).
2. Trigger a background sync (force via `adb shell am broadcast` to the workmanager, or temporarily lower the interval in a debug build).
3. Measure wall-clock for one `executeOnce` on that instance.
4. **Pass criterion:** completes within the 25s `perInstanceBudget`. If not → stop, escalate per spec's MVP-verification failure path.

- [ ] **Step 3: Execute the Manual Verification Checklist**

Run each item from the spec's "Manual Verification Checklist" on a real device:

```
□ Android 真机：打开 App → 设置 → 后台同步开启 → 杀进程 → 等 30 min → 重开 → 验证杀进程期间通知到达
□ Android 真机：后台同步关闭 → 杀进程 → 等 30 min → logcat 无 BackgroundSyncRunner 调用
□ Android 真机：断网 → 后台拉取静默失败，不弹通知
□ iOS 真机：Debug → Simulate Background Fetch → 验证任务执行
□ iOS 真机：杀 App → 锁屏 → 等 30 min → 解锁 → 验证通知
□ 跨重启：重启手机 → 验证后台同步仍被调度
□ DND 时段：开 DND → 后台拉到消息 → 不立即通知，存入 pending
□ DND 结束：到点 → 验证汇总通知
□ Tombstoned agent：后台拉到被删 agent 的消息 → 不通知
□ 多 instance：A 在线 B 离线 → 后台同步 → A 拉到消息，B 失败不影响 A 的 last_sync_at
□ 设置页：切换后台同步开关 → workmanager 立即 schedule/cancel
```

Record results in the commit message or a verification note.

- [ ] **Step 4: Document known limitations**

Create `docs/technical/background-sync-limitations.md` capturing (from spec "Known Risks" + "Out of Scope"):

- iOS `BGAppRefreshTask` real frequency far below 15 min for low-use apps; fallback to `BGProcessingTask` if observed too low.
- Android OEM power-management (华为/小米/OPPO) may kill the process → no background sync. Not fixed in this story.
- Doze mode delays WorkManager.
- iOS 30s wake window; mitigated by per-instance 25s budget + graceful skip.
- Notification latency is best-effort 15min–hours; AC-16's "real-time" semantics now documented as a known limit.
- `onPaused` SharedPreferences write is async — a background tick landing before flush reads `true` → conservative skip (wastes one window, no correctness issue).

- [ ] **Step 5: Commit**

```bash
git add docs/technical/background-sync-limitations.md
git commit -m "docs(us-018): background sync known limitations + manual verification results"
```

---

## Self-Review (plan author's checklist)

**1. Spec coverage** — mapping spec sections → tasks:

| Spec section | Task |
|---|---|
| New components: `BackgroundSyncGate` | Task 1 |
| `LastSyncAtRepository` + `DriftSyncStateTable` | Task 2 |
| `BackgroundSyncRunner` (cursor walk, caps, persistent dedup) | Task 5 |
| `BackgroundSyncScheduler` + `WidgetsBindingObserver` | Task 6 + Task 9 |
| `BackgroundSyncToggleNotifier` / settings UI | Task 8 |
| `NotificationDispatcher.handlePulledMessages` + `warmupFromPending` | Task 4 |
| `UserPreferences.backgroundSyncEnabled` + Drift ALTER + migration | Task 2 (schema) + Task 3 (model/repo) |
| Native: Android Manifest, iOS Info.plist/AppDelegate, `enableSeparateBackgroundProcess=false` | Task 7 (flag) + Task 10 |
| Data flow (executeOnce steps) | Task 5 |
| Budget params (maxMessagesPerPull / maxPagesPerAgent / perInstanceBudget / connectTimeout / pageFetchTimeout) | Task 5 (`BackgroundSyncBudget`) |
| Cross-isolate dedup contract (pending repo, no show, warmup LRU) | Task 4 |
| Error handling table (skip categories, per-instance independence, no-update-on-fail) | Task 5 (try/catch per instance + gate/toggle skips) |
| Testing strategy (Gate 5, LastSync 4, Runner 16, Dispatcher 7) | Tasks 1/2/4/5 |
| Manual verification + known risks | Task 11 |
| Migration: schemaVersion 7→8, sync_state, ALTER user_preferences, first-sync `now()-1h` | Task 2 (schema/migration) + Task 5 (`lastSyncMs ?? now-1h`) |
| MVP performance pre-check | Task 11 Step 2 |

**Gaps found & addressed during review:**
- The spec's `BackgroundSyncGate` "SharedPreferences atomic flag" needed an injectable interface for Law-compliant unit testing → added `IBackgroundSyncPrefs` (Task 1) + production impl (Task 7). ✓
- The Runner must not depend on the concrete `NotificationDispatcher` (layer cleanliness) → introduced `IBackgroundSyncNotifier` (Task 5 Step 2) and noted `NotificationDispatcher implements IBackgroundSyncNotifier`. ✓
- DRY risk: `handlePulledMessages` logic exists in both main dispatcher and background isolate notifier → Task 7 Step 5 extracts `BackgroundNotifierShared.enqueuePulled` and updates Task 4 to delegate. ✓
- Spec assumes Swift AppDelegate; real iOS host may be Obj-C → Task 10 Step 3 mandates inspecting `ios/Runner/` first and matching language. ✓
- Spec's `fetchMessageHistory` has no `since` param → Runner filters by `msg.timestamp >= lastSyncMs` client-side; page-ordering assumption flagged for implementer verification (Task 5 Step 4). ✓

**2. Placeholder scan:** No "TBD"/"implement later". Where the plan defers a decision, it states the verification step explicitly (e.g. "inspect `ios/Runner/` first", "verify `workmanager` API for installed version", "confirm `IInstanceRepo.getAll()` signature"). These are intentional verify-points, not placeholders — the code shown compiles against the explored signatures, and the verify-points guard against version drift the plan author cannot see.

**3. Type consistency:** `BackgroundSyncGate.shouldSkip()` / `setMainActive(bool)` — used identically in Tasks 1, 5, 6, 7, 9. `IBackgroundSyncNotifier.handlePulledMessages({required List<Message>, required Agent? Function(String, String)})` — identical in Tasks 4, 5, 7. `ILastSyncRepo.get/upsert` — identical in Tasks 2, 5, 7. `BackgroundSyncScheduler.ensureScheduled/cancel/onAppPaused/onAppResumed/notifyInstancesChanged` — identical in Tasks 6, 8(via toggle→scheduler? no, toggle goes through VM→repo; scheduler reacts to lifecycle), 9. `BackgroundSyncBudget` fields — identical in Task 5. `UserPreferences.backgroundSyncEnabled` — identical in Tasks 3, 5, 7, 8.

**One open consistency item flagged for the executor:** Task 7's `_BackgroundIsolateNotifier.handlePulledMessages` uses `List messages` (loosely typed). When extracting `BackgroundNotifierShared.enqueuePulled` (Step 5), make the shared helper's signature `List<Message>` and have `_BackgroundIsolateNotifier` cast at the boundary — do not leave the loosely-typed `List` in the shared path.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-29-us-018-background-sync.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for an 11-task plan with TDD checkpoints.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

Which approach?
