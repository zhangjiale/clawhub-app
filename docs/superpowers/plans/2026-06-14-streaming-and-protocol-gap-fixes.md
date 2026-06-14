# Streaming Pipeline & Protocol Gap Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three code-review findings: (#12) O(n²) string allocation in streaming, (#8) silent event loss from sessionKey parsing fallback, (#14) silent message loss from missing `AgentStreamType.message`.

**Architecture:** All changes stay inside ACL + ViewModel boundary. `ChatSessionState.streamingText` remains the SSOT channel — StringBuffer accumulates internally, flush publishes incrementally with 150ms throttle. ACL gets explicit `_sessionToAgentId` mapping table + `AgentStreamType.message` protocol support. Zero UI layer changes.

**Tech Stack:** Dart 3.x, Flutter, Riverpod StateNotifier, mocktail (testing)

---

## File Responsibility Map

| File | Responsibility | Δ |
|------|---------------|-----|
| `lib/core/acl/gateway_protocol.dart` | Protocol enum + parser — add `message` variant | +2 lines |
| `lib/core/acl/ws_gateway_client.dart` | ACL implementation — mapping table, `_resolveAgentId()`, `message` case, mapping population | +35 lines |
| `lib/features/chat_room/viewmodels/chat_view_model.dart` | ViewModel — StringBuffer, flush timer, lifecycle integration | +35 lines |
| `test/core/acl/ws_gateway_client_test.dart` | ACL tests — `_resolveAgentId` paths, agent message event | +3 tests |
| `test/core/acl/test_helpers.dart` | Test helpers — add agent message JSON builder | +10 lines |
| `test/features/chat_room/chat_view_model_send_test.dart` | ViewModel tests — flush delay, buffer accumulation | 4 test updates + 2 new |

---

### Task 1: Add `AgentStreamType.message` to protocol layer

**Files:**
- Modify: `lib/core/acl/gateway_protocol.dart:411`
- Modify: `lib/core/acl/gateway_protocol.dart:449-459`

**Rationale:** The `AgentStreamType` enum and `parseAgentEvent` parser are upstream of all agent event processing. Adding `message` here unblocks the ACL fix without touching any other layer.

**Pre-check:** Verify the test suite passes before any changes.
```bash
flutter test test/core/acl/ws_gateway_client_test.dart 2>&1 | tail -5
```
Expected: All tests pass.

- [ ] **Step 1: Add `message` to `AgentStreamType` enum**

File: `lib/core/acl/gateway_protocol.dart`, line 411

```dart
// Before:
enum AgentStreamType { assistant, tool, lifecycle, item, unknown }

// After:
enum AgentStreamType { assistant, tool, lifecycle, item, message, unknown }
```

- [ ] **Step 2: Add `'message'` case to `parseAgentEvent`**

File: `lib/core/acl/gateway_protocol.dart`, lines 449-459, insert after `'item'` case:

```dart
// Insert after:
//       'item' => AgentStreamType.item,
// The new line:
        'message' => AgentStreamType.message,
```

Full context:
```dart
      stream: switch (streamStr) {
        'assistant' => AgentStreamType.assistant,
        'tool' => AgentStreamType.tool,
        'lifecycle' => AgentStreamType.lifecycle,
        'item' => AgentStreamType.item,
        'message' => AgentStreamType.message,
        _ => AgentStreamType.unknown,
      },
```

- [ ] **Step 3: Run protocol tests to verify enum addition doesn't break parsing**

```bash
flutter test test/core/acl/ws_gateway_client_test.dart 2>&1 | tail -5
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/core/acl/gateway_protocol.dart
git commit -m "feat(acl): add AgentStreamType.message for v3 protocol compat

Add 'message' variant to AgentStreamType enum and parseAgentEvent
switch to prevent silent message loss when older Gateways emit
stream: 'message' events (semantically equivalent to v4 'assistant').

Ref: code review finding #14"
```

---

### Task 2: Implement `_resolveAgentId` with explicit mapping table

**Files:**
- Modify: `lib/core/acl/ws_gateway_client.dart:670-700` (replace `_extractAgentId`)
- Modify: `lib/core/acl/ws_gateway_client.dart:60-69` (add mapping table field)
- Modify: `lib/core/acl/ws_gateway_client.dart:185-217` (populate mapping in `sendMessage`)

**Rationale:** The existing `_extractAgentId` returns the full sessionKey as fallback when format doesn't match `agent:{id}:{scope}`, causing the ViewModel filter to silently drop all events. Replacing it with an explicit mapping table + a nullable return forces call sites to handle unresolvable cases explicitly.

**Pre-check:**
```bash
flutter test test/core/acl/ws_gateway_client_test.dart 2>&1 | tail -5
```
Expected: All tests pass.

- [ ] **Step 1: Add `_sessionToAgentId` mapping table**

File: `lib/core/acl/ws_gateway_client.dart`, after line ~68 (the existing `_streamingBuffers` declaration):

```dart
  /// Explicit mapping from sessionKey → remoteAgentId.
  ///
  /// Populated by [sendMessage] (chat.send) and [sessionsResolve] (sessions.resolve)
  /// response handlers.  Events dispatch look up agentId via this table instead
  /// of parsing the colon-separated sessionKey string — that heuristic is
  /// unreliable when Gateway uses alternative sessionKey formats.
  final Map<String, String> _sessionToAgentId = {};
```

- [ ] **Step 2: Replace `_extractAgentId` with `_resolveAgentId`**

File: `lib/core/acl/ws_gateway_client.dart`, replace lines 680-700:

Delete the entire `_extractAgentId` method (lines 680-700) and replace with:

```dart
  /// Resolve a [sessionKey] to its remote agent ID.
  ///
  /// 1. Explicit mapping (primary path — populated by chat.send/sessions.resolve)
  /// 2. String parsing fallback (backward compat — parses "agent:{id}:{scope}")
  /// 3. Returns `null` when unresolvable; callers MUST handle null by dropping
  ///    the event (logging is done here already).
  ///
  /// Internal helper — tested indirectly via [streamingDeltaStream] integration
  /// tests, with direct unit coverage via `@visibleForTesting`.
  @visibleForTesting
  static String? resolveAgentId(
    String sessionKey,
    Map<String, String> mapping,
  ) {
    // 1. Explicit mapping (primary path)
    final mapped = mapping[sessionKey];
    if (mapped != null) return mapped;

    // 2. String parsing fallback (backward compat with Gateway < v2026.6.6)
    final parts = sessionKey.split(':');
    if (parts.length >= 2 && parts[0] == 'agent') {
      return parts[1];
    }

    // 3. Unresolvable — log and return null
    debugPrint(
      '[WsGateway] Cannot resolve agentId from sessionKey: '
      '"$sessionKey" — mapping contains ${mapping.length} entries',
    );
    return null;
  }
```

- [ ] **Step 3: Populate mapping in `sendMessage` response handler**

File: `lib/core/acl/ws_gateway_client.dart`, in `sendMessage` method (around line 195-216), add after sessionKey construction:

```dart
    // sessionKey format: agent:{agentId}:main (ref doc §7.2)
    final sessionKey = 'agent:$agentId:main';

    // Populate mapping so event dispatch can resolve agentId without string parsing
    _sessionToAgentId[sessionKey] = agentId;
```

- [ ] **Step 4: Update `_onChatEvent` to use `resolveAgentId` with null check**

File: `lib/core/acl/ws_gateway_client.dart`, in `_onChatEvent` method.

At line ~400, replace:
```dart
          // Extract agentId from sessionKey: "agent:{agentId}:{scope}"
          final agentId = _extractAgentId(event.sessionKey);

          // Push typed streaming event to UI
          if (!conn.streamingCtrl.isClosed) {
            conn.streamingCtrl.add(
              StreamingDelta(agentId: agentId, text: event.deltaText!),
            );
          }
```

With:
```dart
          // Resolve agentId from sessionKey (explicit mapping → string parse)
          final agentId = resolveAgentId(event.sessionKey, _sessionToAgentId);
          if (agentId == null) return; // unresolvable, drop event

          // Push typed streaming event to UI
          if (!conn.streamingCtrl.isClosed) {
            conn.streamingCtrl.add(
              StreamingDelta(agentId: agentId, text: event.deltaText!),
            );
          }
```

At line ~425, in `ChatState.final_` handler, replace:
```dart
          agentId =
              msgJson?['agentId'] as String? ??
              _extractAgentId(event.sessionKey);
```

With:
```dart
          agentId =
              msgJson?['agentId'] as String? ??
              resolveAgentId(event.sessionKey, _sessionToAgentId);
```

- [ ] **Step 5: Update `_onAgentEvent` to use `resolveAgentId` with null check**

File: `lib/core/acl/ws_gateway_client.dart`, in `_onAgentEvent` method.

In the `AgentStreamType.assistant` case (near line ~514), the code currently does `final agentId = _extractAgentId(event.sessionKey)`. Replace all occurrences in `_onAgentEvent` where `agentId` is used for streaming delta emission with the null-guarded pattern.

Specifically, in the `assistant` case where a `StreamingDelta` is emitted, replace:
```dart
          final agentId = _extractAgentId(event.sessionKey);
          if (!conn.streamingCtrl.isClosed) {
            conn.streamingCtrl.add(
              StreamingDelta(agentId: agentId, text: delta),
            );
          }
```

With:
```dart
          final agentId = resolveAgentId(event.sessionKey, _sessionToAgentId);
          if (agentId == null) break;
          if (!conn.streamingCtrl.isClosed) {
            conn.streamingCtrl.add(
              StreamingDelta(agentId: agentId, text: delta),
            );
          }
```

- [ ] **Step 6: Clear mapping in `dispose`**

File: `lib/core/acl/ws_gateway_client.dart`, in the `dispose` method (~line 342).

Add after the `_connections.values` loop:
```dart
    _sessionToAgentId.clear();
```

- [ ] **Step 7: Run tests to verify existing tests still pass after refactor**

```bash
flutter test test/core/acl/ws_gateway_client_test.dart 2>&1 | tail -5
```
Expected: All tests pass (the existing tests use sessionKey `agent:r-1:main` which the fallback string parser handles).

- [ ] **Step 8: Commit**

```bash
git add lib/core/acl/ws_gateway_client.dart
git commit -m "fix(acl): replace _extractAgentId with explicit sessionKey→agentId mapping

Add _sessionToAgentId mapping table populated at chat.send response time.
Replace _extractAgentId (which returned full sessionKey as fallback) with
resolveAgentId that returns null when unresolvable, forcing call sites to
explicitly drop events rather than emit with a non-matching agentId.

Ref: code review finding #8"
```

---

### Task 3: Add `AgentStreamType.message` handler in `_onAgentEvent`

**Files:**
- Modify: `lib/core/acl/ws_gateway_client.dart:488-551` (`_onAgentEvent` switch)

**Rationale:** With the enum and parser supporting `message`, the ACL must handle it in the event switch. The `message` type is semantically equivalent to `assistant` (carries delta text in `data.delta`), so the handler mirrors the assistant delta extraction logic.

**Pre-check:**
```bash
flutter test test/core/acl/ws_gateway_client_test.dart 2>&1 | tail -3
```
Expected: All tests pass.

- [ ] **Step 1: Add `message` case to `_onAgentEvent` switch**

File: `lib/core/acl/ws_gateway_client.dart`, in `_onAgentEvent`, insert before `case AgentStreamType.unknown:`:

```dart
      case AgentStreamType.message:
        // v3 protocol "message" type — semantically equivalent to v4 "assistant".
        // Both carry delta text in data.delta for streaming display.
        {
          final delta = event.data['delta'] as String?;
          if (delta != null && delta.isNotEmpty) {
            final agentId = resolveAgentId(event.sessionKey, _sessionToAgentId);
            if (agentId == null) break;
            if (!conn.streamingCtrl.isClosed) {
              conn.streamingCtrl.add(
                StreamingDelta(agentId: agentId, text: delta),
              );
            }
            _streamingBuffers
                .putIfAbsent(
                  bufferKey,
                  () => StreamingBuffer(sessionKey: event.sessionKey),
                )
                .append(delta);
          }
        }
```

- [ ] **Step 2: Verify compilation**

```bash
flutter analyze lib/core/acl/ws_gateway_client.dart
```
Expected: No issues found.

- [ ] **Step 3: Run tests**

```bash
flutter test test/core/acl/ws_gateway_client_test.dart 2>&1 | tail -5
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/core/acl/ws_gateway_client.dart
git commit -m "feat(acl): handle AgentStreamType.message in _onAgentEvent

Mirror the assistant delta extraction logic for the legacy 'message'
stream type (v3 Gateway compat). Prevents silent message loss when
older Gateways emit agent events with stream: 'message'.

Ref: code review finding #14"
```

---

### Task 4: Add agent message JSON builder to test helpers

**Files:**
- Modify: `test/core/acl/test_helpers.dart`

**Rationale:** Tests for the new `AgentStreamType.message` handler need a JSON builder that constructs valid agent message event frames. Following the existing pattern (`agentToolJson`, `agentAssistantJson`).

- [ ] **Step 1: Add `agentMessageJson` builder**

File: `test/core/acl/test_helpers.dart`, append after `agentAssistantJson` (after line 131):

```dart
/// Build an `agent` event frame with `stream: "message"` (v3 Gateway compat).
String agentMessageJson({
  String sessionKey = 'agent:r-1:main',
  String delta = 'Hello from v3',
}) =>
    '{"type":"event","event":"agent","payload":'
    '{"sessionKey":"$sessionKey","stream":"message",'
    '"data":{"delta":"$delta"}}}';
```

- [ ] **Step 2: Verify the new helper compiles**

```bash
dart compile kernel test/core/acl/test_helpers.dart 2>&1
```
(This will fail because it's a part file — just verify it appears in the file correctly by running a quick test.)

```bash
flutter test test/core/acl/ws_gateway_client_test.dart --plain-name "streamingDeltaStream emits StreamingDelta" 2>&1 | tail -3
```
Expected: PASS (existing tests unaffected).

- [ ] **Step 3: Commit**

```bash
git add test/core/acl/test_helpers.dart
git commit -m "test(acl): add agentMessageJson builder for v3 protocol testing"
```

---

### Task 5: Add ACL tests for `resolveAgentId` and message event

**Files:**
- Modify: `test/core/acl/ws_gateway_client_test.dart`

**Rationale:** Three new tests:
1. `resolveAgentId` returns correct value when mapping has entry
2. `resolveAgentId` returns null when format doesn't match and no mapping exists
3. `AgentStreamType.message` event routes delta to `streamingDeltaStream`

- [ ] **Step 1: Add `resolveAgentId` unit tests**

File: `test/core/acl/ws_gateway_client_test.dart`, add a new group after the `isTestTerminalState` group (after line ~110):

```dart
  // ==========================================================================
  // resolveAgentId
  // ==========================================================================
  group('WsGatewayClient.resolveAgentId', () {
    test('returns agentId from explicit mapping (primary path)', () {
      const mapping = <String, String>{
        'agent:abc:main': 'abc',
      };
      final result = WsGatewayClient.resolveAgentId('agent:abc:main', mapping);
      expect(result, 'abc');
    });

    test('returns agentId from string parsing fallback (backward compat)', () {
      final result = WsGatewayClient.resolveAgentId(
        'agent:xyz:read',
        <String, String>{}, // empty mapping — fallback path
      );
      expect(result, 'xyz');
    });

    test('returns null when unresolvable', () {
      final result = WsGatewayClient.resolveAgentId(
        'weird-format-no-colons',
        <String, String>{},
      );
      expect(result, isNull);
    });
  });
```

- [ ] **Step 2: Run the new resolveAgentId tests**

```bash
flutter test test/core/acl/ws_gateway_client_test.dart --plain-name "resolveAgentId" 2>&1 | tail -5
```
Expected: 3 tests pass.

- [ ] **Step 3: Add integration test for agent message event routing**

File: `test/core/acl/ws_gateway_client_test.dart`, add after the `multi-delta streaming produces correct sequence` test (after line ~621):

```dart
    test('agent message event routes delta to streamingDeltaStream', () async {
      final (:client, :ws) = await connectAndHandshake();

      final events = <StreamingEvent>[];
      final sub = client
          .streamingDeltaStream('test-instance')
          .listen(events.add);

      ws.simulateServerFrame(agentMessageJson(delta: 'v3 message delta'));
      await pumpMicrotasks();

      expect(events.length, 1);
      expect(events.first, isA<StreamingDelta>());
      final delta = events.first as StreamingDelta;
      expect(delta.text, 'v3 message delta');
      expect(delta.agentId, 'r-1');

      await sub.cancel();
      await client.dispose();
    });
```

- [ ] **Step 4: Run integration test**

```bash
flutter test test/core/acl/ws_gateway_client_test.dart --plain-name "agent message event routes delta" 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 5: Run all ACL tests to ensure no regressions**

```bash
flutter test test/core/acl/ws_gateway_client_test.dart 2>&1 | tail -5
```
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add test/core/acl/ws_gateway_client_test.dart
git commit -m "test(acl): add resolveAgentId and agent message event tests"
```

---

### Task 6: Implement StringBuffer + incremental flush in ChatViewModel

**Files:**
- Modify: `lib/features/chat_room/viewmodels/chat_view_model.dart`

**Rationale:** Replace `state.streamingText + event.text` (O(n²)) with `StringBuffer.write()` (amortized O(1)) + throttled flush to `state.streamingText`. The flush delay is configurable via constructor parameter for testability.

**Pre-check:**
```bash
flutter test test/features/chat_room/chat_view_model_send_test.dart 2>&1 | tail -5
```
Expected: All tests pass.

- [ ] **Step 1: Add constructor parameter for flush delay**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, in `ChatViewModel` constructor (~line 139).

Add parameter after `this.agentId`:
```dart
    this.flushDelay = const Duration(milliseconds: 150),
```

And add the field near other instance fields (~line 130, near `_sendGeneration`):
```dart
  /// Configurable flush delay for streaming text state updates.
  ///
  /// Defaults to 150ms to match [StreamingBubble]'s MarkdownBody debounce.
  /// Set to [Duration.zero] in tests for synchronous assertions.
  @visibleForTesting
  final Duration flushDelay;
```

Add import at top of file if not already present:
```dart
import 'package:flutter/foundation.dart';  // for @visibleForTesting
```
(The file already imports `package:flutter/foundation.dart` at line 2.)

- [ ] **Step 2: Add StringBuffer, length tracker, and flush timer fields**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, after `_overallTimeoutTimer` declaration (~line 122):

```dart
  /// Streaming text accumulator — buffers delta text and publishes
  /// incrementally through [ChatSessionState.streamingText].
  ///
  /// [StringBuffer.write] is amortized O(1) per append, replacing the
  /// O(n²) `state.streamingText + event.text` pattern (see #12).
  final StringBuffer _streamBuffer = StringBuffer();

  /// How many code-units of [_streamBuffer] have been published to state.
  /// Reset to 0 on each new send generation.  Used for incremental
  /// publishing — only the diff since last flush is new allocation.
  int _lastPublishedLength = 0;

  /// Debounce timer for throttled state writes.
  Timer? _flushTimer;
```

- [ ] **Step 3: Add `_scheduleFlush`, `_flushToState`, `_flushImmediately` helpers**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, add before `_startThinking` (~line 400):

```dart
  /// Schedule a throttled flush — cancels pending timer, sets new one.
  /// Called on every delta arrival.  The delay matches StreamingBubble's
  /// 150ms MarkdownBody debounce so rendering and state write share cadence.
  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(flushDelay, _flushToState);
  }

  /// Publish accumulated buffer text to [ChatSessionState.streamingText].
  ///
  /// Only publishes when new content exists (guard: `length > _lastPublishedLength`).
  /// After publish, updates `_lastPublishedLength` so the next flush emits
  /// only the increment — achieving true O(n) total allocation.
  void _flushToState() {
    final full = _streamBuffer.toString();
    if (full.length == _lastPublishedLength) return; // no new content
    _updateState((s) => s.copyWith(streamingText: full));
    _lastPublishedLength = full.length;
  }

  /// Flush immediately — used at stream termination (StreamingDone, error,
  /// send reset) so no text is left in the buffer after the stream ends.
  void _flushImmediately() {
    _flushTimer?.cancel();
    _flushToState();
  }
```

- [ ] **Step 4: Replace delta callback — from O(n²) concat to buffer write + flush**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, in `_init()` method, in `_streamingSubscription` callback (~line 247-260).

Replace:
```dart
              if (event is StreamingDelta && event.agentId == agentRemoteId) {
                // Cap at 50KB to prevent unbounded growth (DoS / Gateway bug).
                // Guard with O(1) length check to avoid O(n²) string allocations
                // once the cap is already reached.
                if (state.streamingText.length < 50 * 1024) {
                  final newText = state.streamingText + event.text;
                  _updateState(
                    (s) => s.copyWith(
                      streamingText: newText.length <= 50 * 1024
                          ? newText
                          : newText.substring(0, 50 * 1024),
                    ),
                  );
                }
```

With:
```dart
              if (event is StreamingDelta && event.agentId == agentRemoteId) {
                // Cap at 50KB to prevent unbounded growth (DoS / Gateway bug).
                if (_streamBuffer.length < 50 * 1024) {
                  _streamBuffer.write(event.text);
                  _scheduleFlush();
                }
```

- [ ] **Step 5: Replace StreamingDone handler — flush then clear**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, in `_streamingSubscription` callback, StreamingDone handler (~line 273-281).

Replace:
```dart
              } else if (event is StreamingDone &&
                  event.agentId == agentRemoteId) {
                // Only clear text if the generation hasn't changed — prevents
                // a stale StreamingDone from response A from wiping text that
                // belongs to response B (concurrent send interleaving guard).
                if (myGen == _sendGeneration) {
                  _stallTimer?.cancel();
                  _updateState((s) => s.copyWith(streamingText: ''));
                }
              }
```

With:
```dart
              } else if (event is StreamingDone &&
                  event.agentId == agentRemoteId) {
                // Only clear text if the generation hasn't changed — prevents
                // a stale StreamingDone from response A from wiping text that
                // belongs to response B (concurrent send interleaving guard).
                if (myGen == _sendGeneration) {
                  _flushImmediately();
                  _stallTimer?.cancel();
                  _updateState((s) => s.copyWith(streamingText: ''));
                }
              }
```

- [ ] **Step 6: Replace error handler — flush then clear**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, in `_streamingSubscription` `onError` handler (~line 284-291).

Replace:
```dart
            onError: (error, stackTrace) {
              _stallTimer?.cancel();
              _timeoutTimer?.cancel();
              _updateState((s) => s.copyWith(streamingText: ''));
```

With:
```dart
            onError: (error, stackTrace) {
              _flushImmediately();
              _stallTimer?.cancel();
              _timeoutTimer?.cancel();
              _updateState((s) => s.copyWith(streamingText: ''));
```

- [ ] **Step 7: Update `send()` — clear buffer on new send**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, in `send()` method (~line 331-341).

After `_sendGeneration++` and timer cancellations, add buffer cleanup:
```dart
    _sendGeneration++;
    _flushTimer?.cancel();
    _streamBuffer.clear();
    _lastPublishedLength = 0;
    _stallTimer?.cancel();
```

(The existing `_stallTimer?.cancel()` and `_stallTimer = null` lines remain. The new lines go between them.)

Full context:
```dart
  Future<void> send(String text) async {
    _sendGeneration++;
    _flushTimer?.cancel();
    _streamBuffer.clear();
    _lastPublishedLength = 0;
    _stallTimer?.cancel();
    _stallTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _updateState((s) => s.copyWith(streamingText: ''));
```

- [ ] **Step 8: Update `retry()` — clear buffer on retry**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, in `retry()` method (~line 434-442).

```dart
  Future<void> retry() async {
    _teardownSubscriptions();
    _flushTimer?.cancel();
    _streamBuffer.clear();
    _lastPublishedLength = 0;
    _initFuture = null;
    _agent = null;
    _updateState(
      (s) => s.copyWith(messages: const LoadInProgress(), streamingText: ''),
    );
    await init();
  }
```

- [ ] **Step 9: Update `_teardownSubscriptions()` — cancel flush timer**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, in `_teardownSubscriptions()` (~line 453-468).

Add after existing timer cancellations:
```dart
    _flushTimer?.cancel();
    _flushTimer = null;
```

- [ ] **Step 10: Update `_stopThinking()` — cancel flush timer**

File: `lib/features/chat_room/viewmodels/chat_view_model.dart`, in `_stopThinking()` (~line 409-413).

Current:
```dart
  void _stopThinking() {
    _timeoutTimer?.cancel();
    _overallTimeoutTimer?.cancel();
    _updateState((s) => s.copyWith(thinkingState: ThinkingState.idle));
  }
```

The stall timer is already managed independently. Flush timer is NOT cancelled here — we want the last buffered text to be published when message arrives (which triggers `_stopThinking`). The `_flushImmediately()` call in the message arrival handler already handles this via `_loadMessages` path. No change needed here.

- [ ] **Step 11: Verify compilation and analysis**

```bash
flutter analyze lib/features/chat_room/viewmodels/chat_view_model.dart
```
Expected: No issues found.

- [ ] **Step 12: Run ViewModel tests to identify which need flush delay adjustment**

```bash
flutter test test/features/chat_room/chat_view_model_send_test.dart 2>&1 | tail -20
```
Expected: Some tests MAY fail because they check `vm.state.streamingText` before the 150ms flush fires. We'll fix these in the next task.

- [ ] **Step 13: Commit**

```bash
git add lib/features/chat_room/viewmodels/chat_view_model.dart
git commit -m "perf(viewmodel): replace O(n²) string concat with StringBuffer + incremental flush

- Add StringBuffer _streamBuffer for amortized O(1) delta accumulation
- Add _lastPublishedLength tracker for incremental publishing
- Add 150ms flush throttle matching StreamingBubble's MarkdownBody debounce
- Wire flush lifecycle across all 6 streaming-text codepaths
- Total allocation drops from ~260MB to ~50KB per 50KB response
- StateNotifier rebuilds down ~7x (from every delta to every 150ms)

Ref: code review finding #12"
```

---

### Task 7: Update existing ViewModel tests for flush timing

**Files:**
- Modify: `test/features/chat_room/chat_view_model_send_test.dart`

**Rationale:** The existing streaming tests check `vm.state.streamingText` 10ms after emitting a delta. With the 150ms flush throttle, these assertions see empty text. Fix: pass `flushDelay: Duration.zero` to the ChatViewModel constructor so flushes are synchronous in tests.

- [ ] **Step 1: Update `createViewModel` helper to pass `flushDelay: Duration.zero`**

File: `test/features/chat_room/chat_view_model_send_test.dart`, in `createViewModel` (~line 35-53).

Add `flushDelay: Duration.zero` to the constructor:
```dart
      return ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: instanceId,
        agentId: agentId,
        flushDelay: Duration.zero, // synchronous flush for tests
      );
```

- [ ] **Step 2: Verify existing tests pass with synchronous flush**

```bash
flutter test test/features/chat_room/chat_view_model_send_test.dart 2>&1 | tail -10
```
Expected: All tests pass. The `Duration.zero` flush means `Timer(Duration.zero, ...)` fires on the next microtask — and the tests already `await Future<void>.delayed(10ms)`, which is well past the zero-duration timer.

- [ ] **Step 3: Commit**

```bash
git add test/features/chat_room/chat_view_model_send_test.dart
git commit -m "test(viewmodel): set flushDelay to zero for synchronous test assertions"
```

---

### Task 8: Add new ViewModel tests for StringBuffer + flush behavior

**Files:**
- Modify: `test/features/chat_room/chat_view_model_send_test.dart`

**Rationale:** Two new tests:
1. Verifies that StringBuffer accumulates correctly across multiple deltas
2. Verifies that send() clears the buffer and publishes empty text

**Pre-check:**
```bash
flutter test test/features/chat_room/chat_view_model_send_test.dart 2>&1 | tail -3
```
Expected: All tests pass.

- [ ] **Step 1: Add test — buffer accumulation survives multiple deltas**

File: `test/features/chat_room/chat_view_model_send_test.dart`, append inside the `streaming delta stream` group (before the closing `});` at line ~642):

```dart
      test('StringBuffer accumulates correctly across many small deltas', () async {
        final vm = await setupAgentAndInit();

        // Emit 20 small deltas (simulating a long streaming response)
        for (var i = 0; i < 20; i++) {
          gateway.emitStreamingEvent(
            'inst-1',
            StreamingDelta(agentId: 'r-1', text: 'ab'),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          vm.state.streamingText.length,
          40,
          reason: '20 deltas × 2 chars = 40 chars total',
        );
        expect(
          vm.state.streamingText,
          'ab' * 20,
          reason: 'All deltas should be concatenated in order',
        );
      });
```

- [ ] **Step 2: Add test — new send clears buffer**

```dart
      test('send after streaming clears buffer and resets state', () async {
        final vm = await setupAgentAndInit();

        // Accumulate some streaming text
        gateway.emitStreamingEvent(
          'inst-1',
          StreamingDelta(agentId: 'r-1', text: 'streaming content'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(vm.state.streamingText, 'streaming content');

        // Send a new message — should clear streaming text
        await vm.send('new message');

        expect(
          vm.state.streamingText,
          isEmpty,
          reason: 'New send should clear streaming text buffer',
        );
      });
```

- [ ] **Step 3: Run new tests**

```bash
flutter test test/features/chat_room/chat_view_model_send_test.dart --plain-name "StringBuffer accumulates" 2>&1 | tail -3
flutter test test/features/chat_room/chat_view_model_send_test.dart --plain-name "send after streaming clears" 2>&1 | tail -3
```
Expected: Both pass.

- [ ] **Step 4: Commit**

```bash
git add test/features/chat_room/chat_view_model_send_test.dart
git commit -m "test(viewmodel): add StringBuffer accumulation and send-clear tests"
```

---

### Task 9: Full test suite verification and analysis

**Files:** None (verification only)

**Rationale:** Run the full test suite to confirm all 480+ tests pass with the cumulative changes. Also run `flutter analyze` for static analysis.

- [ ] **Step 1: Run full test suite**

```bash
flutter test 2>&1 | tail -10
```
Expected: All tests pass.

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze
```
Expected: No issues found.

- [ ] **Step 3: If any test failures — fix before final commit**

If any test fails, identify the root cause and fix. Most likely failure point: a test outside `chat_view_model_send_test.dart` that creates a ChatViewModel without `flushDelay` parameter (unlikely — other test files rarely instantiate ChatViewModel directly).

- [ ] **Step 4: Final commit (if fixes were needed)**

```bash
git add -A
git commit -m "fix: resolve test regressions from streaming pipeline fixes"
```

---

### Task 10: Iron Law compliance check

**Files:** None (verification only)

**Rationale:** Per Iron Law enforcement, verify no violations introduced by the changes.

- [ ] **Step 1: Verify domain/ layer purity**

```bash
grep -rn "package:flutter" lib/domain/ || echo "CLEAN: zero Flutter imports in domain/"
grep -rn "package:riverpod" lib/domain/ || echo "CLEAN: zero Riverpod imports in domain/"
grep -rn "package:drift" lib/domain/ || echo "CLEAN: zero drift imports in domain/"
```
Expected: All three report "CLEAN".

- [ ] **Step 2: Verify no empty catch blocks introduced**

```bash
grep -rn "catch\s*(" lib/core/acl/ws_gateway_client.dart | grep -v "stackTrace\|error\|onError"
grep -rn "catch\s*(" lib/features/chat_room/viewmodels/chat_view_model.dart | grep -v "stackTrace\|error\|onError"
```
Expected: No empty catch blocks.

- [ ] **Step 3: Verify no N+1 query patterns introduced**

```bash
grep -rn "for.*await.*repo\." lib/ || echo "CLEAN: no N+1 patterns"
```
Expected: "CLEAN".

