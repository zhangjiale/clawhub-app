# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClawHub (虾Hub) is a Flutter mobile app for managing multiple OpenClaw Gateway instances and their AI agents ("Claws"). It connects to OpenClaw Gateways via WebSocket, providing a unified chat client with multi-instance, multi-agent support.

## Commands

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run

# Run all tests
flutter test

# Run a single test file
flutter test test/domain/usecases/send_message_test.dart

# Run tests with filtering
flutter test --plain-name "should generate text preview"

# Static analysis / lint
flutter analyze

# Code generation (after modifying models, database schema, or providers)
dart run build_runner build --delete-conflicting-outputs

# Watch mode for code generation
dart run build_runner watch --delete-conflicting-outputs
```

## Architecture

The project follows **Clean Architecture** with strict layer separation:

```
lib/
├── app/                  # Application entry & configuration
│   ├── config/           # AppConfig constants
│   ├── connection/       # ConnectionOrchestrator (auto-connect on startup)
│   ├── di/               # Riverpod provider definitions (DI container)
│   ├── router/           # go_router with StatefulShellRoute (3-tab bottom nav)
│   └── theme/            # Global theme, 12 agent colors, WCAG utilities
├── core/
│   └── acl/              # Anti-Corruption Layer — all Gateway protocol code
│       ├── i_gateway_client.dart      # Abstract interface
│       ├── gateway_protocol.dart      # OpenClaw v4 protocol messages & parsing
│       ├── connection_manager.dart    # WebSocket lifecycle (connect/reconnect/FSM)
│       ├── mock_gateway_client.dart   # In-memory mock for development/testing
│       └── ws_gateway_client.dart     # Real WebSocket client (production)
├── domain/               # Pure Dart, zero Flutter/database imports
│   ├── models/           # Entities (freezed): Instance, Agent, Message, Conversation, etc.
│   ├── repositories/     # Abstract repository interfaces
│   └── usecases/         # Business logic (SendMessage, SaveInstance, SyncAgents, etc.)
├── data/
│   ├── local/database/   # Drift/SQLite schema (schema.drift → database.dart)
│   ├── local/mapping/    # Drift ↔ Domain model mappers
│   └── repositories/     # Drift-backed implementations + legacy InMemory repos
├── features/             # Feature-based UI pages
│   ├── instance_manager/ # Instance CRUD (list, add, QR scan)
│   ├── agent_list/       # Agent list with stats
│   ├── chat_room/        # Chat with message bubbles, thinking indicator, tool calls
│   ├── message_hub/      # Cross-instance conversation aggregation
│   ├── agent_profile/    # Agent profile & config
│   └── shrimp_profile/   # Placeholder (empty)
└── ui_kit/               # Reusable UI components (no domain/business coupling)
```

### Layer Dependency Rules (Enforced in Code Review)

1. **UI layer** (`features/`) must never import `drift`, `web_socket_channel`, or any data source directly — go through ViewModels and UseCases
2. **Domain layer** (`domain/`) has no external dependencies — pure Dart only
3. **Data layer** (`data/`) implements domain repository interfaces
4. **ACL (Anti-Corruption Layer)** is the only code that touches Gateway protocols — business logic depends on `IGatewayClient`, never on raw WebSocket or JSON

### Key Design Decisions

- **SSOT (Single Source of Truth)**: All UI state is driven by Domain-layer streams/providers. UI must never poll connection state or maintain ephemeral boolean flags.
- **Zero-Trigger Database**: All business logic (message limit enforcement, FTS5 index sync, conversation aggregation) lives in repository methods using explicit transactions — never in SQLite triggers.
- **Dual-ID Messages**: Every message has `clientId` (local UUID for dedup) and `serverId` (Gateway-assigned, for global dedup).
- **Logical Clock**: Messages use a `logicalClock` integer to order messages with identical timestamps.
- **Message Lifecycle (7-state)**: `DRAFT → PENDING → SENDING → SENT → DELIVERED`, with `FAILED` and `EXPIRED` as retry/terminal branches.
- **Conversation Composite Key**: `hash(instanceId + agentId)` guarantees global uniqueness across instances.
- **Smart Back Stack**: Routes carry a `source` parameter so the back button returns to the correct origin tab (e.g., navigating from Messages tab vs Agent list).

### Technology Stack

| Concern | Library |
|---|---|
| State management | `flutter_riverpod` (Riverpod) |
| Database | `drift` (type-safe SQLite ORM) |
| Security | `flutter_secure_storage` (Keychain/Keystore) |
| WebSocket | `web_socket_channel` |
| Network monitoring | `connectivity_plus` |
| Routing | `go_router` (StatefulShellRoute for tabs) |
| Code generation | `freezed`, `json_serializable`, `riverpod_generator`, `drift_dev` |
| Testing | `flutter_test` + `mocktail` |

### Provider Pattern

All infrastructure/domain providers are defined in `lib/app/di/providers.dart`. The pattern:
- Interface providers expose the abstraction (`gatewayClientProvider` → `IGatewayClient`)
- Implementation providers wire the concrete type (`mockGatewayClientProvider` → `MockGatewayClient`, `wsGatewayClientProvider` → `WsGatewayClient`)
- UseCase providers receive their dependencies via Riverpod `ref.watch()`
- Feature-specific providers (e.g., `instanceListProvider`) are defined in the feature's own `providers/` folder

### Current State

The app uses **Drift/SQLite** for persistence (all 4 repositories: Instance, Agent, Message, Conversation). The legacy InMemory implementations in `lib/data/repositories/in_memory_repos.dart` are kept for reference but are no longer the active path.

The `gatewayClientProvider` currently points to `MockGatewayClient` (3 instances, 7 agents from `assets/mock/agents.json`). A production-ready `WsGatewayClient` (OpenClaw v4 protocol) is implemented and wired — switch by changing one line in `gatewayClientProvider` from `mockGatewayClientProvider` to `wsGatewayClientProvider`.

All five feature pages are fully implemented: InstanceManager, AgentList, ChatRoom, MessageHub, and AgentProfile. Only `shrimp_profile/` is an empty placeholder.

### Commit Convention

Use Conventional Commits: `feat(scope):`, `fix(scope):`, `perf(scope):`, `docs:`, `test:`.

### Iron Laws

Before any code change, verify compliance with `docs/iron-laws.md` (15 unbreakable coding rules). Key constraints:
- **Law 1**: `lib/domain/` must have zero Flutter/Riverpod/drift imports
- **Law 2**: Widgets render UI only — no business logic or direct API calls
- **Law 4**: Never bridge ValueNotifier + addListener + setState; use StateNotifier/Notifier + ref.watch
- **Law 6**: Always use batch queries (no `for...await repo.` N+1 patterns)
- **Law 11**: Any list >20 items must use `ListView.builder`
- **Law 14**: Every new widget needs ≥2 tests

See `docs/iron-laws.md` for the complete list and the Code Review gate checklist.
