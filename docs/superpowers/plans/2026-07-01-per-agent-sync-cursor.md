# Per-Agent Sync Cursor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the background-sync `last_sync_at` cursor from per-instance to per-(instance, agent_remote_id) granularity to eliminate systematic cross-agent message loss.

**Architecture:** Single new drift table `sync_state_agent(instance_id, agent_remote_id, last_sync_at)` replaces `sync_state`. `ILastSyncRepo` gains an `agentRemoteId` parameter on `get`/`upsert`. `BackgroundSyncRunner` moves cursor read/write inside the per-agent loop (approach α — `_syncAgent` signature unchanged). Migration v8→v9 drops `sync_state` without backfill; the first tick re-walks from null idempotently (merge dedup skips already-inserted rows by clientId/serverId). Spec: `docs/superpowers/specs/2026-07-01-per-agent-sync-cursor-design.md`.

**Tech Stack:** Flutter, drift (SQLite ORM), mocktail, `dart run build_runner build --delete-conflicting-outputs` for codegen.

## Global Constraints

- **Iron Law 17 (TDD):** Domain-layer changes follow RED→GREEN→REFACTOR per file. This plan modifies the existing `ILastSyncRepo` contract (not a new domain file), so the rule's "test file must predate source file" trigger does not apply — but the contract change is pinned by drift impl tests + runner regression tests.
- **No auto-commit:** Each task ends with a commit; do NOT push. Commit messages use Conventional Commits (`feat(scope):`, `refactor(scope):`, `test(scope):`).
- **Codegen:** After editing `schema.drift` or `database.dart`, run `dart run build_runner build --delete-conflicting-outputs`. The generated `database.g.dart` is checked in.
- **Iron Law 6 (batch queries):** The per-agent cursor read is N indexed PK lookups (one per agent, before network fetch). This is intentionally NOT batched — agent count is ~dozens (premise #1, confirmed), microsecond cost, not a hot path. Do not add `getAllForInstance`.
- **Line numbers** in this plan reference the on-disk state at plan-writing time (post the code-review fixes already in the working tree: `isHidden` filter at runner:168, true-min stop-early at runner:303). They will drift slightly as you edit — match on the code shown, not the number.
- **`_syncAgent` signature stays unchanged** (still receives `lastSyncMs`) — this is approach α, keeping `_syncAgent` unit-testable in isolation.

---

## File Structure

| File | Responsibility | Action |
|------|---------------|--------|
| `lib/data/local/database/schema.drift` | Drift schema + named queries | Modify: replace `sync_state` table + `getLastSyncAt`/`upsertLastSyncAt` queries |
| `lib/data/local/database/database.dart` | schemaVersion + `onUpgrade` migration | Modify: v8→v9, drop+create |
| `lib/data/local/database/database.g.dart` | Generated code | Regenerate via build_runner |
| `lib/domain/repositories/i_last_sync_repo.dart` | Domain interface contract | Modify: per-agent signature + docstring |
| `lib/data/repositories/drift_last_sync_repo.dart` | Drift impl | Modify: forward `agentRemoteId` |
| `lib/core/lifecycle/background_sync_runner.dart` | Cursor read/write orchestration | Modify: move cursor into agent loop |
| `test/data/repositories/drift_last_sync_repo_test.dart` | Drift impl contract tests | Modify: 2-arg→3-arg + new per-agent independence test |
| `test/core/lifecycle/background_sync_runner_test.dart` | Runner behavior tests | Modify: stub signature churn + rewrite F3b + 3 new RED tests |

---

## Task 1: Domain interface — per-agent signature (RED first)

**Why first:** The interface is the contract every other task depends on. Per Law 17 / spec §4.1 this is a contract *modification* (not a new file), but we still write the test that pins the new signature BEFORE changing the interface, so a regression to the old signature fails loudly.

**Files:**
- Modify: `lib/domain/repositories/i_last_sync_repo.dart`
- Test: `test/data/repositories/drift_last_sync_repo_test.dart`

**Interfaces:**
- Produces: `ILastSyncRepo.get(String instanceId, String agentRemoteId) → Future<int?>` and `ILastSyncRepo.upsert(String instanceId, String agentRemoteId, int msEpoch) → Future<void>`. All later tasks consume this signature.

- [ ] **Step 1: Write the failing test (new signature)**

Add this test to `test/data/repositories/drift_last_sync_repo_test.dart` (after the existing `upsert_isPerInstanceIndependent` test, ~line 39):

```dart
  test('upsert_isPerAgentIndependent', () async {
    final repo = helper.makeRepo(db);
    await repo.upsert('inst-a', 'agent-1', 1000);
    await repo.upsert('inst-a', 'agent-2', 2000);
    expect(await repo.get('inst-a', 'agent-1'), 1000);
    expect(await repo.get('inst-a', 'agent-2'), 2000);
  });
```

Also update the 4 existing tests to the 3-arg signature. Replace each `repo.get('inst-a')` with `repo.get('inst-a', 'agent-x')` and each `repo.upsert('inst-a', <ms>)` with `repo.upsert('inst-a', 'agent-x', <ms>)`. Concretely:

- `get_returnsNullWhenAbsent`: `expect(await repo.get('inst-a', 'agent-x'), isNull);`
- `upsert_thenGet_returnsMsEpoch`: `await repo.upsert('inst-a', 'agent-x', 1700000000000);` and `expect(await repo.get('inst-a', 'agent-x'), 1700000000000);`
- `upsert_overwritesExisting`: both upserts and the get use `('inst-a', 'agent-x', ...)`.
- `upsert_isPerInstanceIndependent`: keep two instances, add an agent arg to each: `repo.upsert('inst-a', 'agent-x', 1000)`, `repo.upsert('inst-b', 'agent-x', 2000)`, gets `('inst-a', 'agent-x')` / `('inst-b', 'agent-x')`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/drift_last_sync_repo_test.dart`
Expected: FAIL — compile error: `get`/`upsert` take 1-2 args, not 2-3. (`The method 'get' isn't defined for the type ...` or `Too many positional arguments`.)

- [ ] **Step 3: Change the interface to the new signature**

Replace the entire contents of `lib/domain/repositories/i_last_sync_repo.dart` with:

```dart
/// Per-(instance, agent) "last background sync" cursor (ms epoch).
///
/// Background sync is the only writer; the first tick (cursor null) re-walks
/// from 0, and merge dedup idempotently skips already-inserted rows by
/// clientId/serverId. An instance-level "last synced" time, if ever needed
/// for UI display, is trivially recomputed as
/// `SELECT MAX(last_sync_at) FROM sync_state_agent WHERE instance_id = ?`
/// — no instance-level method is kept on this interface.
abstract class ILastSyncRepo {
  Future<int?> get(String instanceId, String agentRemoteId);
  Future<void> upsert(String instanceId, String agentRemoteId, int msEpoch);
}
```

- [ ] **Step 4: Run test to verify it STILL fails (now on the impl, not the interface)**

Run: `flutter test test/data/repositories/drift_last_sync_repo_test.dart`
Expected: FAIL — `DriftLastSyncRepo` still has the old 1/2-arg methods, so it no longer implements `ILastSyncRepo` (compile error: missing overrides). This is expected; Task 2 fixes the impl.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/repositories/i_last_sync_repo.dart test/data/repositories/drift_last_sync_repo_test.dart
git commit -m "refactor(sync-cursor): per-agent ILastSyncRepo signature (RED)"
```

---

## Task 2: Schema + migration + drift impl (GREEN)

**Files:**
- Modify: `lib/data/local/database/schema.drift` (replace sync_state block, lines ~486-500)
- Modify: `lib/data/local/database/database.dart` (schemaVersion 8→9, onUpgrade block)
- Modify: `lib/data/repositories/drift_last_sync_repo.dart`
- Regenerate: `lib/data/local/database/database.g.dart`

**Interfaces:**
- Consumes: `ILastSyncRepo` per-agent signature (Task 1).
- Produces: `sync_state_agent` table + `getLastSyncAt(instanceId, agentRemoteId)` / `upsertLastSyncAt(instanceId, agentRemoteId, lastSyncAt)` generated queries; `DriftLastSyncRepo` implementing the new interface.

- [ ] **Step 1: Replace the schema.drift sync_state block**

In `lib/data/local/database/schema.drift`, replace the block (currently lines ~486-500):

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

with:

```sql
-- ============================================================
-- 9. Background Sync State — per-(instance, agent) last sync cursor
-- ============================================================
CREATE TABLE sync_state_agent (
    instance_id     TEXT NOT NULL,
    agent_remote_id TEXT NOT NULL,
    last_sync_at    INTEGER NOT NULL,
    PRIMARY KEY (instance_id, agent_remote_id)
);

getLastSyncAt:
SELECT last_sync_at FROM sync_state_agent
WHERE instance_id = :instanceId AND agent_remote_id = :agentRemoteId;

upsertLastSyncAt:
INSERT INTO sync_state_agent (instance_id, agent_remote_id, last_sync_at)
VALUES (:instanceId, :agentRemoteId, :lastSyncAt)
ON CONFLICT(instance_id, agent_remote_id) DO UPDATE SET last_sync_at = :lastSyncAt;
```

- [ ] **Step 2: Bump schemaVersion and add the v9 migration**

In `lib/data/local/database/database.dart`:

Change `int get schemaVersion => 8;` to `int get schemaVersion => 9;`.

In the `onUpgrade` method, immediately after the existing `if (from < 8) { ... }` block (which ends around line 140 with the `customStatement('UPDATE user_preferences ...')` call), add:

```dart
        if (from < 9) {
          // US-018 fix: cursor moved from per-instance to
          // per-(instance, agent_remote_id). The old sync_state's
          // last_sync_at was the cross-agent MAX; backfilling it to each
          // agent would perpetuate the cross-agent message-loss bug, so
          // drop without backfill. First tick re-walks from null (=0);
          // merge dedup idempotently skips already-inserted rows by
          // clientId/serverId and re-covers recently-lost slow-agent
          // messages (bounded by maxPagesPerAgent=5 / maxMessagesPerPull=100).
          await migrator.deleteTable('sync_state');
          await migrator.createTable(syncStateAgent);
        }
```

- [ ] **Step 3: Update DriftLastSyncRepo to forward agentRemoteId**

Replace the body of `lib/data/repositories/drift_last_sync_repo.dart` with:

```dart
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/domain/repositories/i_last_sync_repo.dart';

class DriftLastSyncRepo implements ILastSyncRepo {
  final db.AppDatabase _database;
  DriftLastSyncRepo(this._database);

  @override
  Future<int?> get(String instanceId, String agentRemoteId) async {
    final rows =
        await _database.getLastSyncAt(instanceId, agentRemoteId).get();
    if (rows.isEmpty) return null;
    return rows.first;
  }

  @override
  Future<void> upsert(
    String instanceId,
    String agentRemoteId,
    int msEpoch,
  ) async {
    await _database.upsertLastSyncAt(instanceId, agentRemoteId, msEpoch);
  }
}
```

- [ ] **Step 4: Regenerate drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with `Built build_runner` and updates `database.g.dart` (new `SyncStateAgent` table class, `getLastSyncAt`/`upsertLastSyncAt` with 2 params). No errors.

- [ ] **Step 5: Run the drift impl tests to verify GREEN**

Run: `flutter test test/data/repositories/drift_last_sync_repo_test.dart`
Expected: PASS — all 5 tests (4 updated + 1 new `upsert_isPerAgentIndependent`) green.

- [ ] **Step 6: Verify no stale references to sync_state remain**

Run: `grep -rn "sync_state\b" lib/ test/` (the `\b` avoids matching `sync_state_agent`).
Expected: no matches in lib/ or test/. (If the old table name lingers anywhere, fix it before committing.)

- [ ] **Step 7: Commit**

```bash
git add lib/data/local/database/schema.drift lib/data/local/database/database.dart lib/data/local/database/database.g.dart lib/data/repositories/drift_last_sync_repo.dart
git commit -m "feat(sync-cursor): sync_state_agent table + v9 migration + drift impl"
```

---

## Task 3: BackgroundSyncRunner — move cursor into the agent loop (RED → GREEN)

This is the core fix. The RED test in Step 1 pins the bug; the implementation in Steps 3-5 makes it pass.

**Files:**
- Modify: `lib/core/lifecycle/background_sync_runner.dart` (`_syncInstance`, lines ~124-246)
- Test: `test/core/lifecycle/background_sync_runner_test.dart`

**Interfaces:**
- Consumes: `ILastSyncRepo.get(instanceId, agentRemoteId)` / `.upsert(instanceId, agentRemoteId, msEpoch)` (Tasks 1-2).
- Produces: per-agent cursor read/write; `_syncAgent` signature unchanged.

- [ ] **Step 1: Write the failing regression test (pins the bug)**

In `test/core/lifecycle/background_sync_runner_test.dart`, add this test inside `main()` (near the other `executeOnce_*` tests, e.g. after the `F3b_executeOnce_partialFailure_doesNotAdvanceLastSync` test around line ~1407):

```dart
    // =========================================================================
    // Regression: per-instance cursor caused cross-agent message loss.
    // Two agents, same instance, different message velocities. The slower
    // agent's new messages (timestamp between its own high-water mark and the
    // faster agent's higher max) must NOT be dropped by the >= lastSyncMs
    // filter. This test is the living documentation of the bug.
    // =========================================================================
    test('pins_crossAgentMessageLoss', () async {
      final inst = _inst('i1');

      when(() => settingsRepo.getPreferences())
          .thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => agentRepo.getAllByInstanceId('i1')).thenAnswer(
        (_) async => [_agent('a1', 'i1'), _agent('a2', 'i1')],
      );

      // Pretend a prior tick already synced: agent a1 up to t=300,
      // agent a2 up to t=500. (Under the old per-instance cursor, both
      // would share cursor=500.)
      when(() => lastSyncRepo.get('i1', 'a1')).thenAnswer((_) async => 300);
      when(() => lastSyncRepo.get('i1', 'a2')).thenAnswer((_) async => 500);

      // a1 gets a NEW message at t=350 — strictly between its own high-water
      // (300) and a2's (500). Under the old per-instance cursor (500) this
      // message is dropped by `if (msg.timestamp >= lastSyncMs)`.
      gateway.setHistory('i1', 'a1', [
        (
          messages: [_msg(clientId: 'c350', serverId: 's350', timestamp: 350)],
          nextCursor: null,
        ),
      ]);
      // a2 has no new messages (its page is empty / all below cursor).
      gateway.setHistory('i1', 'a2', [
        (messages: <Message>[], nextCursor: null),
      ]);

      // MergeUseCase is a Mock — stub insert as "new" so the message is
      // counted. (Match the existing F3a/F3b stubbing pattern in this file.)
      when(() => mergeUseCase.mergeWithStatus(any(),
              softMatch: any(named: 'softMatch'),
              recent: any(named: 'recent')))
          .thenAnswer((_) async => MergeResult(
                message: _.positionalArguments[0] as Message,
                wasNew: true,
                wasSkipped: false,
              ));

      await runner.executeOnce();

      // The bug: a1's t=350 message was inserted (not dropped).
      // Fetch was attempted for a1 (the slow agent).
      final a1Fetch = gateway.fetchHistoryCalls
          .where((c) => c.instanceId == 'i1' && c.agentId == 'a1')
          .toList();
      expect(a1Fetch, isNotEmpty, reason: 'a1 must be fetched');

      // a1's cursor advances to its own max (350), NOT a2's (500).
      verify(() => lastSyncRepo.upsert('i1', 'a1', 350)).called(1);
    });
```

> **Note on `MergeResult` / stubbing:** match the exact constructor and import the existing test file already uses for `mergeUseCase` stubs (search the file for `mergeWithStatus` to confirm the `MergeResult` field names — they are `message`/`wasNew`/`wasSkipped` per `lib/domain/usecases/merge_inbound_message.dart`). If the existing tests stub merge differently, copy that pattern verbatim. The assertion that matters is `verify(() => lastSyncRepo.upsert('i1', 'a1', 350)).called(1)`.

- [ ] **Step 2: Run test to verify it fails (RED)**

Run: `flutter test test/core/lifecycle/background_sync_runner_test.dart --plain-name "pins_crossAgentMessageLoss"`
Expected: FAIL. Under the current per-instance code: `lastSyncRepo.get('i1')` is stubbed with a single-arg matcher (the test stubs `get('i1','a1')` — not matched, returns null→0), OR the upsert is called with a different value. The precise failure mode depends on stubbing, but the `verify(...upsert('i1','a1',350))` will not pass because (a) the runner calls `get(instance.id)` not `get(instance.id, agent.remoteId)`, and (b) upsert is called once per instance, not per agent. Confirm the failure is the cross-agent drop, not a stubbing typo.

- [ ] **Step 3: Update ALL existing runner-test stubs to the new signature**

Before changing the runner source, the rest of the test file must compile against the new interface. In `test/core/lifecycle/background_sync_runner_test.dart`:

- Every `when(() => lastSyncRepo.get('i1'))` → `when(() => lastSyncRepo.get('i1', 'a1'))` (and `a2` where a test uses two agents — match the agent the test sets up).
- Every `when(() => lastSyncRepo.get('iB'))` → `when(() => lastSyncRepo.get('iB', <that test's agent>))`.
- Every `verify(() => lastSyncRepo.upsert('i1', any()))` → `verify(() => lastSyncRepo.upsert('i1', any(), any()))`.
- Every `verify(() => lastSyncRepo.upsert('iB', any()))` → `verify(() => lastSyncRepo.upsert('iB', any(), any()))`.
- `verifyNever(() => lastSyncRepo.upsert(any(), any()))` → `verifyNever(() => lastSyncRepo.upsert(any(), any(), any()))`.

Use grep to find every call site: `grep -n "lastSyncRepo\.\(get\|upsert\)" test/core/lifecycle/background_sync_runner_test.dart`. Fix each.

> The `MockLastSyncRepo` class (line 37) uses mocktail and needs NO change — it inherits the new signature from `ILastSyncRepo` automatically.

- [ ] **Step 4: Rewrite F3b's assertion (semantics changed)**

The `F3b_executeOnce_partialFailure_doesNotAdvanceLastSync` test (line ~1362) currently asserts `verifyNever(() => lastSyncRepo.upsert('i1', any()))` — "instance cursor never advances because anyAgentFailed". Under per-agent semantics this changes to: **a1 (success) advances its own cursor; a2 (failure) does not**.

Replace the test's final assertion block:

```dart
      // anyAgentFailed == true → last_sync_at MUST NOT be advanced.
      verifyNever(() => lastSyncRepo.upsert('i1', any()));
```

with:

```dart
      // Per-agent cursor: a1 succeeded → its cursor advances.
      // a2 threw → its cursor does NOT advance (re-walks next tick).
      // (Pre-fix: a single instance-level gate skipped ALL agents on
      // anyAgentFailed, penalizing a1 for a2's failure.)
      verify(() => lastSyncRepo.upsert('i1', 'a1', any())).called(1);
      verifyNever(() => lastSyncRepo.upsert('i1', 'a2', any()));
```

Also add the missing `get` stubs for both agents near the top of that test (after the existing `when(() => lastSyncRepo.get('i1'))` line, ~1368):

```dart
      when(() => lastSyncRepo.get('i1', 'a1')).thenAnswer((_) async => 0);
      when(() => lastSyncRepo.get('i1', 'a2')).thenAnswer((_) async => 0);
```

and remove the now-wrong single-arg stub `when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);`.

- [ ] **Step 5: Rewrite the no-agents test**

Find the existing no-agents test (search `grep -n "no agents\|noAgents" test/core/lifecycle/background_sync_runner_test.dart`). Rename it to `executeOnce_noAgents_connectsWithoutUpsert` and change its assertion to verify NO upsert happens (per spec §6.1, the no-agents path no longer writes a cursor):

```dart
      // No agents → no cursor to write. Must NOT upsert (pre-fix wrote
      // now() — a phantom "synced" marker for a tick that synced nothing).
      verifyNever(() => lastSyncRepo.upsert(any(), any(), any()));
```

Remove any assertion that previously verified the now-deleted `upsert(instance.id, now())` call.

- [ ] **Step 6: Implement the runner change — move cursor into the agent loop**

In `lib/core/lifecycle/background_sync_runner.dart`, replace the `_syncInstance` body from the `// Per-agent cursor walk` comment (line ~149) through the end of the cursor-gate block (line ~228, just before `await gatewayClient.disconnect(instance.id);`).

Replace this whole region:

```dart
      // Per-agent cursor walk
      int totalInserted = 0;
      int maxServerTs = -1;
      bool budgetExpired = false;
      bool anyAgentFailed = false;

      // Snapshot lastSyncMs once per instance for consistent filtering
      final lastSyncMs = await lastSyncRepo.get(instance.id) ?? 0;

      // Build the resolveAgent closure once, shared across all agents.
      // ... (existing comment block, keep as-is) ...
      final byRemote = <String, Agent>{for (final a in agents) a.remoteId: a};
      Agent? resolveAgent(String remoteId) {
        final a = byRemote[remoteId];
        return (a == null || a.isRemoved || a.isHidden) ? null : a;
      }

      for (final agent in agents) {
        if (totalInserted >= budget.maxMessagesPerPull) break;
        if (now() >= deadline) {
          budgetExpired = true;
          logger.info('Instance ${instance.id}: per-instance budget expired');
          break;
        }

        // ... (per-agent try/catch comment, keep as-is) ...
        SyncAgentResult result;
        try {
          result = await _syncAgent(
            instance: instance,
            agent: agent,
            lastSyncMs: lastSyncMs,
            maxMessagesPerPull: budget.maxMessagesPerPull - totalInserted,
            deadline: deadline,
            resolveAgent: resolveAgent,
          );
        } catch (e, st) {
          logger.error(
            'Agent ${agent.remoteId} sync threw on ${instance.id}: $e — '
            'isolating to this agent, continuing with others',
            st,
          );
          anyAgentFailed = true;
          continue; // keep processing remaining agents
        }

        if (result.failed) {
          anyAgentFailed = true;
        }
        totalInserted += result.insertedCount;
        if (result.maxTimestamp > maxServerTs) {
          maxServerTs = result.maxTimestamp;
        }
      }

      // Update last_sync_at
      if (budgetExpired || anyAgentFailed) {
        // Graceful skip: don't update last_sync_at
        logger.info(
          'Instance ${instance.id}: sync incomplete, last_sync_at not updated',
        );
      } else {
        final lastSyncVal = maxServerTs > 0 ? maxServerTs : now();
        await lastSyncRepo.upsert(instance.id, lastSyncVal);
        logger.info(
          'Instance ${instance.id}: synced, last_sync_at=$lastSyncVal',
        );
      }
```

with:

```dart
      // Per-agent cursor walk
      int totalInserted = 0;
      bool budgetExpired = false;

      // Build the resolveAgent closure once, shared across all agents.
      // ... (existing comment block, keep as-is) ...
      final byRemote = <String, Agent>{for (final a in agents) a.remoteId: a};
      Agent? resolveAgent(String remoteId) {
        final a = byRemote[remoteId];
        return (a == null || a.isRemoved || a.isHidden) ? null : a;
      }

      for (final agent in agents) {
        if (totalInserted >= budget.maxMessagesPerPull) break;
        if (now() >= deadline) {
          budgetExpired = true;
          logger.info('Instance ${instance.id}: per-instance budget expired');
          break;
        }

        // Per-agent cursor: prevents cross-agent message loss. A shared
        // per-instance cursor lets a faster agent's max timestamp overwrite a
        // slower agent's high-water mark, dropping the slower agent's newer
        // messages via the >= lastSyncMs filter (see regression test
        // pins_crossAgentMessageLoss). Read per-agent, before the fetch.
        final lastSyncMs =
            await lastSyncRepo.get(instance.id, agent.remoteId) ?? 0;

        // ... (per-agent try/catch comment, keep as-is) ...
        SyncAgentResult result;
        try {
          result = await _syncAgent(
            instance: instance,
            agent: agent,
            lastSyncMs: lastSyncMs,
            maxMessagesPerPull: budget.maxMessagesPerPull - totalInserted,
            deadline: deadline,
            resolveAgent: resolveAgent,
          );
        } catch (e, st) {
          logger.error(
            'Agent ${agent.remoteId} sync threw on ${instance.id}: $e — '
            'isolating to this agent, continuing with others',
            st,
          );
          continue; // keep processing remaining agents; cursor not advanced
        }

        totalInserted += result.insertedCount;

        // Advance ONLY this agent's cursor on success. A failed agent's
        // cursor stays put → re-walks next tick (merge dedup skips
        // already-inserted rows). Per-agent isolation means one agent's
        // failure no longer blocks other agents' cursor advancement.
        if (!result.failed) {
          final lastSyncVal =
              result.maxTimestamp > 0 ? result.maxTimestamp : now();
          await lastSyncRepo.upsert(instance.id, agent.remoteId, lastSyncVal);
          logger.info(
            'Instance ${instance.id}/${agent.remoteId}: synced, '
            'last_sync_at=$lastSyncVal',
          );
        } else {
          logger.info(
            'Instance ${instance.id}/${agent.remoteId}: incomplete, '
            'last_sync_at not updated',
          );
        }
      }
```

- [ ] **Step 7: Remove the no-agents upsert**

In the same `_syncInstance` method, the no-agents early-return (lines ~140-147) currently does:

```dart
      if (agents.isEmpty) {
        logger.info(
          'Instance ${instance.id}: no agents, updating last_sync_at',
        );
        await lastSyncRepo.upsert(instance.id, now());
        await gatewayClient.disconnect(instance.id);
        return;
      }
```

Replace with (remove the upsert — no agent means no cursor to write):

```dart
      if (agents.isEmpty) {
        logger.info('Instance ${instance.id}: no agents, skipping cursor');
        await gatewayClient.disconnect(instance.id);
        return;
      }
```

- [ ] **Step 8: Run the full runner test file (GREEN)**

Run: `flutter test test/core/lifecycle/background_sync_runner_test.dart`
Expected: PASS — `pins_crossAgentMessageLoss` green, F3b green with new per-agent assertions, no-agents test green, all other tests green (stub churn from Step 3 applied).

If a test fails because its stub used the wrong agent id in the 2nd arg, fix the stub to match the agent that test sets up — the agent id must match what `_syncInstance` passes (`agent.remoteId`).

- [ ] **Step 9: Commit**

```bash
git add lib/core/lifecycle/background_sync_runner.dart test/core/lifecycle/background_sync_runner_test.dart
git commit -m "fix(sync-cursor): per-agent cursor in runner, eliminates cross-agent message loss"
```

---

## Task 4: Budget-expiry multi-agent test + final verification

**Files:**
- Test: `test/core/lifecycle/background_sync_runner_test.dart`

- [ ] **Step 1: Write the budget-expiry multi-agent test**

Add this test to `test/core/lifecycle/background_sync_runner_test.dart` (after `pins_crossAgentMessageLoss`):

```dart
    test('executeOnce_budgetExpiry_advancesCompletedAgentOnly', () async {
      final inst = _inst('i1');
      when(() => settingsRepo.getPreferences())
          .thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => agentRepo.getAllByInstanceId('i1')).thenAnswer(
        (_) async => [_agent('a1', 'i1'), _agent('a2', 'i1'), _agent('a3', 'i1')],
      );

      when(() => lastSyncRepo.get('i1', 'a1')).thenAnswer((_) async => 0);
      when(() => lastSyncRepo.get('i1', 'a2')).thenAnswer((_) async => 0);
      when(() => lastSyncRepo.get('i1', 'a3')).thenAnswer((_) async => 0);

      // a1 completes with a message; a2's fetch delays past the deadline.
      gateway.setHistory('i1', 'a1', [
        (
          messages: [_msg(clientId: 'c1', serverId: 's1', timestamp: 100)],
          nextCursor: null,
        ),
      ]);
      gateway.fetchDelay = const Duration(milliseconds: 50);

      when(() => mergeUseCase.mergeWithStatus(any(),
              softMatch: any(named: 'softMatch'),
              recent: any(named: 'recent')))
          .thenAnswer((_) async => MergeResult(
                message: _.positionalArguments[0] as Message,
                wasNew: true,
                wasSkipped: false,
              ));

      // Construct the runner with a tiny per-instance budget so a2's
      // 50ms fetchDelay expires the deadline mid-loop.
      final tightRunner = BackgroundSyncRunner(
        gate: gate,
        settingsRepo: settingsRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        agentRepo: agentRepo,
        messageRepo: messageRepo,
        conversationRepo: conversationRepo,
        mergeUseCase: mergeUseCase,
        lastSyncRepo: lastSyncRepo,
        dispatcher: dispatcher,
        budget: const BackgroundSyncBudget(
          connectTimeout: Duration(seconds: 10),
          pageFetchTimeout: Duration(seconds: 30),
          perInstanceBudget: Duration(milliseconds: 20),
          maxMessagesPerPull: 100,
          maxPagesPerAgent: 5,
        ),
        logger: logger,
        now: clock.now,
      );

      await tightRunner.executeOnce();

      // a1 completed before budget expired → cursor advanced.
      verify(() => lastSyncRepo.upsert('i1', 'a1', any())).called(1);
      // a2 expired mid-fetch (failed=true) → cursor NOT advanced.
      verifyNever(() => lastSyncRepo.upsert('i1', 'a2', any()));
      // a3 never reached (loop broke on budget) → cursor never read or written.
      verifyNever(() => lastSyncRepo.get('i1', 'a3'));
      verifyNever(() => lastSyncRepo.upsert('i1', 'a3', any()));
    });
```

> **Note:** Confirm the `BackgroundSyncRunner` constructor arg order and the test-local variable names (`gate`, `settingsRepo`, `gateway`, `agentRepo`, `messageRepo`, `conversationRepo`, `mergeUseCase`, `lastSyncRepo`, `dispatcher`, `logger`, `clock`) by reading the existing `setUp` in this test file — copy the same variable names the file already uses. `BackgroundSyncBudget` is imported from `background_sync_runner.dart`.

- [ ] **Step 2: Run the new test**

Run: `flutter test test/core/lifecycle/background_sync_runner_test.dart --plain-name "budgetExpiry_advancesCompletedAgentOnly"`
Expected: PASS.

If it fails because the deadline check happens before a1's fetch (a1 also expires), widen `perInstanceBudget` to `Duration(milliseconds: 60)` — the point is a1 completes, a2/a3 don't.

- [ ] **Step 3: Run the whole touched test suite**

Run: `flutter test test/core/lifecycle/background_sync_runner_test.dart test/data/repositories/drift_last_sync_repo_test.dart`
Expected: PASS — all green.

- [ ] **Step 4: Static analysis**

Run: `flutter analyze lib/core/lifecycle/background_sync_runner.dart lib/data/repositories/drift_last_sync_repo.dart lib/domain/repositories/i_last_sync_repo.dart lib/data/local/database/database.dart`
Expected: `No issues found!`

- [ ] **Step 5: Verify no consumer of the old 2-arg signature remains**

Run: `grep -rn "lastSyncRepo\.\(get\|upsert\)" lib/ test/`
Expected: every call site has the per-agent signature (3 args for upsert, 2 for get). Fix any straggler (likely in `callback_dispatcher.dart` if it ever called get/upsert — it only constructs `DriftLastSyncRepo`, so probably none).

- [ ] **Step 6: Commit**

```bash
git add test/core/lifecycle/background_sync_runner_test.dart
git commit -m "test(sync-cursor): budget-expiry advances completed agent only"
```

---

## Self-Review (run after writing — already done)

**1. Spec coverage:** ✓ Schema (Task 2), migration (Task 2), ILastSyncRepo (Task 1), DriftLastSyncRepo (Task 2), runner cursor-in-loop (Task 3), no-agents no-upsert (Task 3 Step 7), inline comment (Task 3 Step 6), `pins_crossAgentMessageLoss` (Task 3 Step 1), budget multi-agent test (Task 4 Step 1), no-agents test rewrite (Task 3 Step 5), F3b rewrite (Task 3 Step 4), drift impl independence test (Task 1 Step 1), docstring update (Task 1 Step 3). All §10 acceptance criteria mapped.

**2. Placeholder scan:** No TBD/TODO. One guarded note (Task 3 Step 1) tells the implementer to confirm `MergeResult` field names against the actual source rather than guessing — this is a verification instruction, not a placeholder.

**3. Type consistency:** `get(instanceId, agentRemoteId)` and `upsert(instanceId, agentRemoteId, msEpoch)` used identically in Tasks 1, 2, 3, 4. `_syncAgent` signature explicitly unchanged (Task 3 keeps `lastSyncMs: lastSyncMs` arg). `syncStateAgent` (drift camelCase table class) used in Task 2 migration. `SyncAgentResult` fields `failed`/`maxTimestamp`/`insertedCount` match the source (runner lines 407-413).

**Scope note (spec §7.1 test-helpers extraction):** Deliberately NOT a task here. Extracting `FakeGatewayClient`/`CapturingDispatcher`/`StubGate`/etc. from a 1106-line file is a mechanical refactor with real breakage risk that doesn't serve the bug fix, and the file is not yet over the 1200-line threshold the spec cited as the trigger. Leave it as a follow-up if the file crosses 1200 lines after these tests land.
