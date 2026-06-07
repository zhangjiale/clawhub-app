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

# Code generation (after modifying models or providers)
dart run build_runner build --delete-conflicting-outputs

# Watch mode for code generation
dart run build_runner watch --delete-conflicting-outputs
```

## Architecture

The project follows **Clean Architecture** with strict layer separation:

```
lib/
├── app/           # Application entry & configuration
│   ├── router/    # go_router with StatefulShellRoute (3-tab bottom nav)
│   ├── theme/     # Global theme, 12 agent colors, WCAG utilities
│   └── di/        # Riverpod provider definitions (DI container)
├── core/
│   └── acl/       # Anti-Corruption Layer — Gateway protocol adapter
├── domain/        # Pure Dart, zero Flutter/database imports
│   ├── models/    # Entities: Instance, Agent, Message, Conversation, etc.
│   ├── repositories/  # Abstract repository interfaces
│   └── usecases/  # Business logic (SendMessage, AddInstance, GeneratePreview)
├── data/
│   └── repositories/  # Repository implementations (currently InMemory for MVP)
├── features/      # Feature-based UI pages (one folder per screen)
│   ├── instance_manager/  # Instance CRUD + connection management
│   ├── agent_list/        # Agent list (stub)
│   ├── chat_room/         # Chat room (stub)
│   ├── message_hub/       # Conversation aggregation (stub)
│   └── agent_profile/     # Agent profile (stub)
└── ui_kit/        # Reusable UI components
```

### Layer Dependency Rules (Enforced in Code Review)

1. **UI layer** (features/) must never import `drift`, `web_socket_channel`, or any data source directly — go through ViewModels and UseCases
2. **Domain layer** has no external dependencies — pure Dart only
3. **Data layer** implements domain repository interfaces
4. **ACL (Anti-Corruption Layer)** is the only code that touches Gateway protocols — business logic depends on `IGatewayClient`, never on raw WebSocket or JSON

### Key Design Decisions

- **SSOT (Single Source of Truth)**: All UI state is driven by Domain-layer streams/providers. UI must never poll connection state or maintain ephemeral boolean flags.
- **Zero-Trigger Database**: All business logic (message limit enforcement, FTS5 index sync, conversation aggregation) lives in application-layer Repository methods using explicit transactions — never in SQLite triggers.
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

All providers are defined in `lib/app/di/providers.dart`. The pattern:
- Interface providers expose the abstraction (`gatewayClientProvider` → `IGatewayClient`)
- Implementation providers wire the concrete type (`mockGatewayClientProvider` → `MockGatewayClient`)
- UseCase providers receive their dependencies via Riverpod `ref.watch()`
- Feature providers (e.g., `instanceListProvider`) are defined in the feature's own `providers/` folder

### Current State: MVP with Mock Backend

The app currently runs entirely against a `MockGatewayClient` (`lib/core/acl/mock_gateway_client.dart`) that reads preset data from `assets/mock/agents.json` (3 instances, 7 agents). The InMemory repositories in `lib/data/repositories/in_memory_repos.dart` serve as placeholders — the architecture doc specifies they should eventually be replaced with `drift`-backed implementations.

Feature pages that are still stubs (placeholders): `AgentListPage`, `ChatRoomPage`, `MessageHubPage`, `AgentProfilePage`. The only fully functional feature is `InstanceListPage` + `AddInstancePage`.

### Database Schema

The final schema is defined in `docs/database_v3.sql` but is **not yet wired in**. Key tables: `instances`, `agents`, `conversations`, `messages`, `tool_calls`, `quick_commands`, `agent_stats`, `notification_queue`, `sync_cursors`, `messages_fts` (FTS5).

### Commit Convention

Use Conventional Commits: `feat(scope):`, `fix(scope):`, `perf(scope):`, `docs:`, `test:`.
