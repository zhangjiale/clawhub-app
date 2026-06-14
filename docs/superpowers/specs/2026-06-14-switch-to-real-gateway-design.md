# Design: Switch Chat from Mock to Real Gateway

**Date**: 2026-06-14
**Status**: Approved
**Scope**: Configuration change — swap the active `IGatewayClient` implementation

## Goal

Switch the app's Gateway client from `MockGatewayClient` (in-memory simulated responses) to `WsGatewayClient` (real WebSocket connection to an OpenClaw Gateway instance).

## Current State

Both implementations are fully built and wired in `lib/app/di/providers.dart`:

| Provider | Implementation | Status |
|---|---|---|
| `mockGatewayClientProvider` | `MockGatewayClient` — simulated agents, auto-replies, no network | Active (current default) |
| `wsGatewayClientProvider` | `WsGatewayClient` — real WebSocket, OpenClaw v4 protocol, Ed25519 identity | Wired, unused |

The `gatewayClientProvider` (interface-level provider) currently delegates to `mockGatewayClientProvider`. All consumers depend on `IGatewayClient`, so the switch is transparent to the rest of the app.

## Design

### Change: `gatewayClientProvider` return value

**File**: `lib/app/di/providers.dart` (lines 108–113)

```dart
/// Gateway 防腐层接口（面向接口编程，方便 Mock ↔ 真实实现互换）
///
/// 当前指向 WsGatewayClient（生产环境，连接真实 OpenClaw Gateway）。
/// 开发/离线调试：改为 `return ref.watch(mockGatewayClientProvider);`
final gatewayClientProvider = Provider<IGatewayClient>((ref) {
  return ref.watch(wsGatewayClientProvider);
});
```

### No other code changes required

The entire app — use cases, repositories, ConnectionOrchestrator, all UI pages — depends on `IGatewayClient`, never on concrete implementations. The switch is a one-line provider change.

### Preserved but inactive

`MockGatewayClient` and `mockGatewayClientProvider` remain in the codebase. To switch back for offline development, change one line back to `return ref.watch(mockGatewayClientProvider);`.

## Verification

### Manual smoke tests

1. Launch the app with a real Gateway instance configured
2. Add an instance in Instance Manager → verify `testConnection` succeeds
3. Open Agent List → verify agents loaded from Gateway (`fetchAgents`)
4. Open a Chat Room → send a message → verify real Gateway reply arrives via `messageStream`
5. Kill the Gateway → verify ConnectionOrchestrator goes to `offline` state
6. Restart the Gateway → verify exponential backoff reconnects automatically

### Automated tests

```bash
flutter test test/app/di/providers_test.dart
```

Tests must pass — they use `overrideWith` to inject their own mock, independent of the global provider default.

## Risks

| Risk | Mitigation |
|---|---|
| Device pairing required on first connect | `ConnectionOrchestrator` handles `pairingRequired` → `pairingInfoProvider` → UI shows approval instructions |
| Gateway URL / Token misconfigured | `ConnectionManager` exponential backoff retry; user sees `offline` status in UI |
| No internet / Gateway unreachable | Same as above — graceful degradation, automatic reconnect on network restore |

## Rollback

To revert: change `gatewayClientProvider` back to `return ref.watch(mockGatewayClientProvider);`.
