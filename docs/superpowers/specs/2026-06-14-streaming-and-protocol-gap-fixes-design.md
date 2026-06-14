# Streaming Pipeline & Protocol Gap Fixes — Design Doc

**Date**: 2026-06-14  
**Status**: Approved  
**Source**: Code review findings #8, #12, #14 from max-effort review on `refactor/fix-architecture-review-issues`

## Problem Summary

Three remaining issues from the 15-finding code review:

| # | Severity | Problem | Root Cause |
|---|----------|---------|-------------|
| 12 | 🟢 Performance | O(n²) string allocation (∼260MB per 50KB response) | `state.streamingText + event.text` copies entire accumulated string per delta |
| 8 | 🟠 Silent data loss | Streaming events dropped when sessionKey format unexpected | `_extractAgentId` returns full sessionKey as fallback; ViewModel filter rejects it |
| 14 | 🟠 Silent data loss | Old-protocol `"message"` agent stream type silently dropped | `AgentStreamType` enum lacks `message` variant; switch breaks on unknown |

## Design

### Architecture Principle

All three fixes stay inside the **ACL + ViewModel boundary**. No UI layer changes. The SSOT (Single Source of Truth) architecture is preserved: `ChatSessionState.streamingText` remains the sole published streaming state, and all agent ID resolution stays inside the ACL.

```
UI Layer (unchanged)
  ↑ ref.watch(chatViewModelProvider)
ViewModel Layer
  ChatViewModel: StringBuffer + incremental flush → state.streamingText
  ↑ streamingDeltaStream
ACL Layer
  WsGatewayClient: _sessionToAgentId mapping + _resolveAgentId() + AgentStreamType.message
```

### Fix 12: Incremental Publishing with Throttle

**File**: `lib/features/chat_room/viewmodels/chat_view_model.dart`

Add three instance fields to `ChatViewModel`:

- `StringBuffer _streamBuffer` — accumulates delta text (amortized O(1) per append)
- `int _lastPublishedLength` — tracks how much of the buffer has been published to state, enabling incremental publishing (only the diff since last publish is emitted)
- `Timer? _flushTimer` — 150ms debounce timer, matching `StreamingBubble`'s existing MarkdownBody debounce

Delta handler changes from:
```dart
final newText = state.streamingText + event.text;      // O(n²)
_updateState((s) => s.copyWith(streamingText: newText));
```
To:
```dart
_streamBuffer.write(event.text);                        // O(1) amortized
_scheduleFlush();                                       // 150ms throttle
```

New helper methods:

- `_scheduleFlush()` — cancels pending timer, sets 150ms timer → `_flushToState()`
- `_flushToState()` — publishes `_streamBuffer.toString()` to `state.streamingText`, updates `_lastPublishedLength`
- `_flushImmediately()` — flushes synchronously (used at stream termination: StreamingDone, error, send reset, retry)

Lifecycle integration (6 codepaths that clear streaming text):

| Codepath | Action |
|----------|--------|
| `send()` before sending | `_streamBuffer.clear()` + `_lastPublishedLength = 0` |
| `StreamingDone` (same generation) | `_flushImmediately()` → clear state.streamingText |
| `StreamingDone` (stale generation) | No-op (already guarded by `myGen == _sendGeneration`) |
| `stream error` handler | `_flushImmediately()` → clear state.streamingText |
| `retry()` | `_streamBuffer.clear()` + `_lastPublishedLength = 0` |
| `_teardownSubscriptions()` | `_flushTimer?.cancel()` |

**`ChatSessionState`**: `streamingText` field **retained unchanged**. Equality/hashCode unchanged.

**Performance**: Total allocation drops from ∼260MB to ∼50KB per 50KB response. State updates drop from every delta (30-80ms) to every 150ms (∼7x reduction in StateNotifier rebuilds).

### Fix 8: Explicit sessionKey → agentId Mapping

**File**: `lib/core/acl/ws_gateway_client.dart`

Add an explicit mapping table:

```dart
final Map<String, String> _sessionToAgentId = {};
```

Populated at two call sites:

1. **`chat.send` response handler** — when we construct the sessionKey and know the agentId
2. **`sessions.resolve` response handler** — when the Gateway returns the sessionKey→agentId correspondence

Replace `_extractAgentId(String) → String` with `_resolveAgentId(String, Map<String, String>) → String?`:

```dart
static String? _resolveAgentId(
  String sessionKey,
  Map<String, String> mapping,
) {
  // 1. Explicit mapping (primary path)
  final mapped = mapping[sessionKey];
  if (mapped != null) return mapped;

  // 2. String parsing fallback (backward compat)
  final parts = sessionKey.split(':');
  if (parts.length >= 2 && parts[0] == 'agent') return parts[1];

  // 3. Unresolvable — log and return null
  return null;
}
```

Call sites (`_onChatEvent`, `_onAgentEvent`) change from:
```dart
final agentId = _extractAgentId(event.sessionKey);
conn.streamingCtrl.add(StreamingDelta(agentId: agentId, text: ...));
```
To:
```dart
final agentId = _resolveAgentId(event.sessionKey, _sessionToAgentId);
if (agentId == null) return; // silently drop unresolvable events
conn.streamingCtrl.add(StreamingDelta(agentId: agentId, text: ...));
```

**Cleanup**: `dispose()` clears `_sessionToAgentId`.

### Fix 14: AgentStreamType.message Support

**File**: `lib/core/acl/gateway_protocol.dart`

Add `message` to the `AgentStreamType` enum:

```dart
enum AgentStreamType { assistant, tool, lifecycle, item, message, unknown }
```

Update `parseAgentEvent`:
```dart
'message' => AgentStreamType.message,
```

**File**: `lib/core/acl/ws_gateway_client.dart`

Add case in `_onAgentEvent` switch:

```dart
case AgentStreamType.message:
  // v3 protocol "message" type — semantically equivalent to v4 "assistant"
  final delta = event.data['delta'] as String?;
  if (delta != null && delta.isNotEmpty) {
    final agentId = _resolveAgentId(event.sessionKey, _sessionToAgentId);
    if (agentId == null) break;
    if (!conn.streamingCtrl.isClosed) {
      conn.streamingCtrl.add(StreamingDelta(agentId: agentId, text: delta));
    }
    _streamingBuffers
        .putIfAbsent(bufferKey, () => StreamingBuffer(sessionKey: event.sessionKey))
        .append(delta);
  }
```

The `unknown` case keeps its debugPrint but makes no heuristic extraction attempt — protocol-strict approach.

## File Change Summary

| File | Issues | Δ Lines | Notes |
|------|--------|---------|-------|
| `chat_view_model.dart` | #12 | +35 | StringBuffer + flush + lifecycle wiring |
| `ws_gateway_client.dart` | #8, #14 | +30 | Mapping table + _resolveAgentId + message case |
| `gateway_protocol.dart` | #14 | +2 | Enum value + parser case |
| `chat_view_model_test.dart` | #12 | +2 tests | Buffer accumulation + flush timing |
| `ws_gateway_client_test.dart` | #8, #14 | +3 tests | _resolveAgentId paths + message event routing |

**Not changed**: `ChatSessionState`, `ChatRoomPage`, `StreamingBubble`, any other UI file.

## Constraints Verified

- ✅ `lib/domain/` untouched — zero Flutter/drift imports (Iron Law 1)
- ✅ UI layer untouched — widgets render UI only (Iron Law 2)
- ✅ ACL is the only code touching Gateway protocols
- ✅ SSOT preserved: `ChatSessionState.streamingText` remains single published source
- ✅ 480 existing tests must stay green; added tests for new logic only
- ✅ Zero new package dependencies
- ✅ `StreamingBubble` API unchanged (`String text` parameter)
