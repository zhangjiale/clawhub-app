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

# Install Iron Laws pre-commit hook (on fresh clone)
./scripts/pre-commit --install

# Integration test (requires a connected iOS/Android device or emulator)
flutter test integration_test/app_test.dart

# Pre-release checklist (manual, run before tagging a release)
./scripts/pre-release-check
```

## Architecture

The project follows **Clean Architecture** with strict layer separation:

```
lib/
├── app/                  # Application entry & configuration
│   ├── bootstrap.dart    # Pre-runApp startup chain + fatal-screen guardrail (see below)
│   ├── background_sync/  # Workmanager callback dispatcher (background message sync)
│   ├── notifications/    # Local notification service wiring
│   ├── config/           # AppConfig + PlatformInfo (OS/version detection)
│   ├── connection/       # ConnectionOrchestrator (auto-connect on startup)
│   ├── di/               # Riverpod provider definitions (DI container)
│   ├── router/           # go_router with StatefulShellRoute (3-tab bottom nav)
│   └── theme/            # Global theme, 12 agent colors, WCAG utilities
├── core/
│   ├── acl/              # Anti-Corruption Layer — the ONLY code that touches Gateway protocols
│   │   ├── i_gateway_client.dart      # Abstract interface
│   │   ├── gateway_protocol.dart      # OpenClaw v4 protocol messages & parsing
│   │   ├── connection_manager.dart    # WebSocket lifecycle (connect/reconnect/FSM)
│   │   ├── mock_gateway_client.dart   # In-memory mock (offline dev / unit tests)
│   │   ├── ws_gateway_client.dart     # Real WebSocket client (current default)
│   │   └── device_identity*.dart      # Ed25519 device identity + interface
│   ├── (top-level i_*.dart)   # Cross-cutting service interfaces — i_logger, iconnectivity,
│   │                          # i_avatar_storage_service, i_local_notification_service, etc.
│   │                          # Domain/data depend on these abstractions (Law 3), never the
│   │                          # concrete Flutter/platform impl (Law 1). debug_print_logger.dart
│   │                          # is the production ILogger; domain uses `print` or injected ILogger.
│   ├── lifecycle/             # App lifecycle observers
│   └── utils/                 # Pure utilities (CopyWithSentinel, etc.)
├── domain/               # Pure Dart, zero Flutter/database imports (Law 1)
│   ├── models/           # Entities (freezed): Instance, Agent, Message, Conversation, etc.
│   ├── repositories/     # Abstract repository interfaces
│   └── usecases/         # Business logic (SendMessage, SaveInstance, SyncAgents, etc.)
├── data/                 # Repository implementations
│   ├── local/database/   # Drift/SQLite schema (schema.drift → database.dart)
│   ├── local/mapping/    # Drift ↔ Domain model mappers
│   ├── remote/, services/   # Future remote sources + cross-entity services
│   └── repositories/     # Drift-backed impls (drift_*.dart) + legacy in_memory_repos.dart
├── features/             # Feature-based UI pages (one folder per feature)
│   ├── instance_manager/ # Instance CRUD (list, add, QR scan)
│   ├── agent_list/       # Agent list with stats
│   ├── chat_room/        # Chat with message bubbles, thinking indicator, tool calls
│   ├── message_hub/      # Cross-instance conversation aggregation
│   ├── agent_profile/    # Agent profile & config
│   ├── settings/         # Settings with sub-pages (notification, DND, biometric, etc.)
│   └── search/           # Cross-instance search (FTS5-backed)
└── ui_kit/               # Reusable UI components, flat layout (no domain/business coupling)
                          # — press feedback buttons, toast, banners, status icons,
                          #   markdown styles, settings section/toggle, etc.
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
- **ConnectionOrchestrator**: A global singleton (Riverpod-held) that manages all Gateway instance connection lifecycles — auto-connect on startup, connect/disconnect on instance save/delete, network change detection (WiFi ↔ cellular), and GatewayConnectionState → HealthStatus synchronization. Implements `IInstanceLifecycle` so UseCases can trigger lifecycle events without depending on the orchestrator directly.
- **CopyWithSentinel**: A utility pattern (`CopyWithSentinel<T>`) that distinguishes "no change" from "set to null." Used by state classes to avoid ambiguous `copyWith(param: null)` calls — the sentinel value signals "don't update this field" while an explicit null signals "clear this field."

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

The app uses **Drift/SQLite** for persistence (all 4 repositories: Instance, Agent, Message, Conversation — see `lib/data/repositories/drift_*.dart`). The legacy InMemory implementations in `lib/data/repositories/in_memory_repos.dart` are kept for reference but are no longer the active path.

`gatewayClientProvider` points to `wsGatewayClientProvider` (real WebSocket, OpenClaw v4 protocol, v2026.6.6). `MockGatewayClient` (3 instances, 7 agents from `assets/mock/agents.json`) is implemented as an offline-development / unit-test fallback — switch by changing one line in `lib/app/di/providers.dart` from `wsGatewayClientProvider` to `mockGatewayClientProvider`.

Core feature pages implemented: InstanceManager, AgentList, ChatRoom, MessageHub, AgentProfile, Search. `settings/` is in active development with SettingsPage, 6 sub-pages (Notification, DND, Biometric, Network, Storage Management, About), a ViewModel, `ISettingsRepo`/`DriftSettingsRepo`, and tests.

### Pre-runApp Startup Guardrail

The pre-`runApp` startup chain lives in **`lib/app/bootstrap.dart`** (`bootstrapApp()`), wrapped in `runZonedGuarded` inside `main()`. It runs `Workmanager().initialize(...)` → `createAppDatabase()` → `runApp(ProviderScope(...))`. Any throw is caught and surfaced as a **visible fatal screen** (`DefaultErrorFallback` mounted in a dark `MaterialApp`: icon + error + collapsible stack trace + Retry) instead of a frozen splash. This guardrail was added after a 2026-07-01 incident where a `Workmanager` `PlatformException` stranded the app on a blank Android splash with no first frame (infinite `W/VRI cancelAndRedraw` log spam). Full post-mortem: `docs/technical/background-sync-limitations.md`.

**Convention**: when adding a new pre-`runApp` step (plugin init, secure-storage pre-warm, locale load, asset precache), add it as a new typed parameter inside `bootstrapApp()` and wire it at the call site in `lib/main.dart` — do **not** add `await` directly in `main()`. The zone guardrail only covers what `bootstrapApp` calls; `bootstrapApp` exposes a fixed typed parameter set (no generic `yourStep:` slot), so model a new `Future<void> Function()` typedef alongside `WorkmanagerInitializer`. The bootstrap is unit-tested in `test/app/bootstrap_test.dart` — a guardrail with no test is a hope.

### Commit Convention

Use Conventional Commits: `feat(scope):`, `fix(scope):`, `perf(scope):`, `docs:`, `test:`.

### Documentation Map

Key docs for AI-assisted development. Paths relative to repo root unless noted.

| Document | Path | Use When |
|---|---|---|
| Docs Index | `docs/README.md` | Top-level entry point for all design/technical/product docs |
| Iron Laws (coding rules) | `docs/engineering/iron-laws.md` | Before every code change — mandatory gate check |
| PRD | `docs/product/prd.md` | Understanding feature requirements, acceptance criteria |
| User Stories | `docs/product/user-stories.md` | Sprint planning, INVEST validation, dependency tracing |
| Design Tokens | `docs/design/design-tokens-v2.md` | Any UI color/spacing/radius/shadow/motion change |
| Component Spec | `docs/design/component-spec-v2.md` | Building/modifying any page widget or component |
| API Protocol | `docs/technical/api-protocol.md` | Gateway WebSocket work — handshake, RPC, events, auth |
| ACL Protocol Gaps | `docs/technical/acl-protocol-gaps.md` | 剩余 ACL 协议实现差距（deviceToken 已修，maxPayload / shutdown / payload.large 等待续） |
| Architecture | `docs/technical/architecture.md` | Understanding project structure, data models, provider inventory |
| ADRs | `docs/adr/` | Consulting past architectural decisions (e.g. broadcast-stream late-subscriber contract) |
| Database Schema | `docs/technical/database-schema.sql` | Schema changes, migration, FTS5 query design |
| Design Assets | `docs/design/assets/` | App icon, splash screen, shrimp state images |
| AgentTheme (per-agent branding) | `lib/app/theme/agent_theme.dart` | Wiring per-agent theme color into widget tree via `ThemeExtension<AgentTheme>` + `AgentTheme.of(context).primary`. Sibling consumers: `QuickCommandBar` (pill text), `MessageBubble` (user bubble bg), `ThinkingIndicator` (dot color). Falls back to `XiaColors.accent` (V2 sapphire `#4F83FF`) when no agent is in scope. |

### Iron Laws

Before any code change, verify compliance with `docs/engineering/iron-laws.md` (17 unbreakable coding rules). Key constraints:
- **Law 1**: `lib/domain/` must have zero Flutter/Riverpod/drift imports
- **Law 2**: Widgets render UI only — no business logic or direct API calls
- **Law 4**: Never bridge ValueNotifier + addListener + setState; use StateNotifier/Notifier + ref.watch
- **Law 6**: Always use batch queries (no `for...await repo.` N+1 patterns)
- **Law 11**: Any list >20 items must use `ListView.builder`
- **Law 14**: Every new widget needs ≥2 tests
- **Law 17**: Layered TDD — Domain/ACL must write tests first; ViewModel should; Repository/Widget no later than same commit

### TDD Enforcement Rule

**For Domain-layer code (Law 17), the following sequence is MANDATORY and non-negotiable:**

When creating a new domain model or repository interface:

1. **RED (test first)** — Create the test file FIRST. Run it. Confirm it FAILS (compilation error = acceptable red).
2. **GREEN (minimal code)** — Create the source file with just enough code to make the test pass. Run the test. Confirm it PASSES.
3. **REFACTOR (if needed)** — Clean up. Run the test again.

**Violation indicator**: If you have created a source file in `lib/domain/` whose corresponding test file in `test/domain/` does not yet exist or was created AFTER the source file, you have violated Law 17.

**Per-file granularity**: This applies per-file, not per-phase. Creating `agent_stats.dart` + `achievement.dart` + `i_achievement_repo.dart` before writing any test is a violation. The correct sequence is:

```
test/domain/models/agent_stats_test.dart → RED
lib/domain/models/agent_stats.dart       → GREEN
test/domain/models/achievement_test.dart → RED
lib/domain/models/achievement.dart       → GREEN
test/domain/repositories/...             → RED
lib/domain/repositories/...              → GREEN
```

**Checkpoint**: Before creating any new file in `lib/domain/`, pause and ask: "Does the test file for this already exist?" If the answer is no, STOP — create the test file first.

See `docs/engineering/iron-laws.md` for the complete list and the Code Review gate checklist.

#### Automated Enforcement (Pre-commit Hook)

A pre-commit hook enforces 4 mechanically-verifiable laws on staged `.dart` files:
- **Law 1**: domain/ import purity (grep)
- **Law 6**: N+1 query patterns (grep)
- **Law 8**: Empty catch blocks (grep)
- **Law 11**: ListView(children:) usage (warning)

The hook also runs `dart format` on staged files and re-adds them.

**Suppression**: Add `// iron-law-allow: LawN -- justification` on the violating line, or `// iron-law-allow-file: LawN -- justification` within the first 20 lines for file-level suppression.
**Escape hatch**: `git commit --no-verify` (for prototype branches, emergency hotfixes).

**Periodic audit**: Every ~20 commits, run a manual full-codebase iron-law review to catch architectural drift (laws that grep cannot verify: Law 2, 3, 5, 7, 9, 10, 14-17).
