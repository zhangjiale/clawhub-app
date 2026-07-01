# 🦐 ClawHub (虾Hub)

<p align="center">
  <strong>Multi-Instance OpenClaw Gateway Mobile Client</strong><br>
  多 OpenClaw 实例移动端统一管理客户端 — 随时随地与你的 AI 虾群对话
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue" alt="Platform">
  <img src="https://img.shields.io/badge/framework-Flutter%203.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

---

## What is ClawHub?

ClawHub (虾Hub) is a mobile app that connects to multiple OpenClaw Gateway instances via WebSocket, giving you a unified chat interface to talk to all your AI agents ("Claws" / 虾) across all your servers — from a single app.

**The problem**: OpenClaw users often run multiple instances on different machines (home server, cloud VPS, work machine), each with specialized agents. Managing them through WeChat or multiple browser tabs is cumbersome.

**The solution**: One mobile app. All your Claws. Anywhere.

## Features

| | |
|---|---|
| 🔌 **Multi-Instance Management** | Connect to multiple OpenClaw Gateways simultaneously. Add via QR scan or manual input. Each connection is independently managed. |
| 🦐 **Agent List & Stats** | Browse all agents grouped by instance. Real-time stats bar shows online instances, active agents, and total messages. |
| 💬 **Real-time Chat** | Full chat UI with message bubbles, Markdown rendering, code syntax highlighting, and streaming responses. |
| 🛠️ **Tool Call Visualization** | See agent tool invocations in real-time — running, completed, or failed — with expandable details. |
| 📨 **Message Hub** | WeChat-style conversation list sorted by recent activity, with message previews and unread badges. |
| 🎨 **Per-Agent Themes** | Customize each agent's avatar, nickname, and accent color (12 themes). |
| 🔐 **Ed25519 Device Identity** | Full Ed25519 key-pair authentication with Gateway challenge-signature handshake. |
| 📴 **Offline Queue** | Messages queue locally when offline, auto-send on reconnect with exponential backoff. |
| 🌐 **Smart Back Stack** | Returns to the correct origin tab (Agent List or Messages) when navigating back from chat. |

## Architecture

ClawHub follows **Clean Architecture** with strict layer separation. All business logic lives in the Domain layer (zero Flutter/database imports), the ACL (Anti-Corruption Layer) isolates Gateway protocol details, and the UI layer is purely declarative.

```
┌──────────────────────────────────────────────────┐
│                   FEATURES (UI)                   │
│  instance_manager / agent_list / chat_room / ...  │
├──────────────────────────────────────────────────┤
│               DOMAIN (Pure Dart)                  │
│  UseCases / Entities / Repository Interfaces      │
├──────────────────────────────────────────────────┤
│                  DATA / ACL                       │
│  Drift (SQLite) / WebSocket / Secure Storage      │
└──────────────────────────────────────────────────┘
```

**Key design decisions:**
- **Single Source of Truth** — UI driven by Domain-layer streams, never polls connection state
- **Zero-Trigger Database** — All business logic in repository methods with explicit transactions
- **Dual-ID Messages** — `clientId` (local UUID) + `serverId` (Gateway-assigned) for dedup
- **7-State Message Lifecycle** — `DRAFT → PENDING → SENDING → SENT → DELIVERED`, with `FAILED`/`EXPIRED` branches

## Tech Stack

| Concern | Library |
|---|---|
| State Management | [Riverpod](https://riverpod.dev) |
| Database | [Drift](https://drift.simonbinder.eu) (type-safe SQLite) |
| Security | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) + Ed25519 |
| WebSocket | [web_socket_channel](https://pub.dev/packages/web_socket_channel) |
| Routing | [go_router](https://pub.dev/packages/go_router) (StatefulShellRoute) |
| Network Monitor | [connectivity_plus](https://pub.dev/packages/connectivity_plus) |
| Code Generation | freezed / json_serializable / riverpod_generator / drift_dev |
| Testing | flutter_test + mocktail |

## Quick Start

```bash
# Install dependencies
flutter pub get

# Generate code — REQUIRED on fresh clone, otherwise the build will fail
# (freezed / drift / riverpod / json_serializable codegen)
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run

# Run all tests
flutter test

# Static analysis
flutter analyze
```

The app defaults to the real WebSocket `WsGatewayClient` (OpenClaw v4 protocol, v2026.6.6) and connects to configured Gateway instances. For offline development and unit tests, a `MockGatewayClient` backed by mock data at `assets/mock/agents.json` (3 instances, 7 agents) is provided as a fallback.

To connect to a real OpenClaw Gateway, see [`docs/technical/api-protocol.md`](docs/technical/api-protocol.md) for the WebSocket protocol specification and authentication setup.

## Project Structure

```
lib/
├── app/                  # Entry point, DI, routing, theme
│   ├── config/           # AppConfig constants
│   ├── connection/       # ConnectionOrchestrator (auto-connect on startup)
│   ├── di/               # Riverpod provider definitions
│   ├── router/           # go_router with 3-tab bottom nav
│   └── theme/            # Design tokens, 12 agent colors, WCAG utils
├── core/
│   └── acl/              # Anti-Corruption Layer — Gateway protocol
│       ├── i_gateway_client.dart      # Abstract interface
│       ├── gateway_protocol.dart      # OpenClaw v4 protocol messages
│       ├── connection_manager.dart    # WebSocket lifecycle (state machine)
│       ├── ws_gateway_client.dart     # Real WebSocket client
│       └── mock_gateway_client.dart   # In-memory mock for dev/testing
├── domain/               # Pure Dart — no Flutter/database imports
│   ├── models/           # Entities (Instance, Agent, Message, etc.)
│   ├── repositories/     # Abstract repository interfaces
│   └── usecases/         # Business logic (SendMessage, SyncAgents, etc.)
├── data/                 # Repository implementations
│   ├── local/database/   # Drift/SQLite schema
│   └── repositories/     # Drift-backed implementations
├── features/             # Feature-based UI pages
│   ├── instance_manager/ # Instance CRUD (list, add, QR scan)
│   ├── agent_list/       # Agent list with stats bar
│   ├── chat_room/        # Chat with bubbles, thinking indicator, tool cards
│   ├── message_hub/      # Cross-instance conversation aggregation
│   ├── agent_profile/    # Agent profile, stats, achievements, config
│   ├── settings/         # Settings page + 6 sub-pages (notification, DND, biometric, network, storage, about)
│   └── search/           # Cross-instance FTS5 search
└── ui_kit/               # Reusable UI components
```

## Documentation

| Document | Description |
|---|---|
| [PRD](docs/product/prd.md) | Product requirements — features, acceptance criteria, roadmap |
| [User Stories](docs/product/user-stories.md) | Story map, sprint planning, INVEST validation |
| [Design Tokens](docs/design/design-tokens-v2.md) | Color system, typography, spacing, shadows, motion |
| [Component Spec](docs/design/component-spec-v2.md) | Per-page component annotations and interaction specs |
| [API Protocol](docs/technical/api-protocol.md) | OpenClaw Gateway WebSocket protocol reference |
| [Architecture](docs/technical/architecture.md) | Technical architecture, data models, provider inventory |
| [Database Schema](docs/technical/database-schema.sql) | SQLite schema with zero-trigger design |
| [Iron Laws](docs/engineering/iron-laws.md) | 17 unbreakable coding rules + code review checklist |

## Development

### Switching Between Mock and Real Gateway

The gateway client is configured in `lib/app/di/providers.dart`:

```dart
// Real WebSocket (default — production)
final gatewayClientProvider = Provider<IGatewayClient>((ref) {
  return ref.watch(wsGatewayClientProvider);
});

// Mock (offline development / unit tests)
final gatewayClientProvider = Provider<IGatewayClient>((ref) {
  return ref.watch(mockGatewayClientProvider);
});
```

### Running a Single Test

```bash
flutter test test/domain/usecases/send_message_test.dart
flutter test --plain-name "should generate text preview"
```

### Code Generation

After modifying models, database schema, or Riverpod providers:

```bash
dart run build_runner build --delete-conflicting-outputs
# or watch mode:
dart run build_runner watch --delete-conflicting-outputs
```

### Pre-runApp Initialization (Startup Guardrail)

The pre-`runApp` startup chain (`Workmanager().initialize(...)` + `createAppDatabase()` + `runApp(ProviderScope(...))`) lives in **`lib/app/bootstrap.dart`** and is wrapped in `runZonedGuarded` inside `main()`. Any exception thrown by these awaits is caught and surfaced as a visible `StartupFatalScreen` (icon + error message + collapsible stack trace + Retry button) instead of a frozen splash.

**If you need to add a new pre-`runApp` initialization step** — another plugin, secure-storage pre-warm, locale load, asset precache, etc. — **add it inside `bootstrapApp()` in `lib/app/bootstrap.dart`**, not directly in `main()`. The zone guardrail only covers what `bootstrapApp` calls.

Pattern (replace `yourStep()` with whatever you need):

```dart
// in lib/main.dart, inside the bootstrapApp call:
bootstrapApp(
  initializeWorkmanager: () => Workmanager().initialize(...),
  createDatabase: createAppDatabase,
  yourStep: () => doYourExpensiveStartup(),  // <- add new await here
  buildSuccess: (db) => ProviderScope(...),
  showFatal: (e, st) => runApp(StartupFatalScreen(...)),
);

// in lib/app/bootstrap.dart, inside the try block:
try {
  await initializeWorkmanager();
  await yourStep();                           // <- add new await here
  ...
  final database = await createDatabase();
  runApp(buildSuccess(database));
} catch (error, stackTrace) {
  _logger.error('[bootstrap] startup failed: $error', stackTrace);
  showFatal(error, stackTrace);
}
```

If your new step is a `Future<void> Function()` (no return value), name it after its purpose (e.g. `prewarmSecureStorage`, `loadLocale`) and inject it the same way as `initializeWorkmanager`. If you need a return value (e.g. a parsed config), pass a typed `Function` and have `bootstrapApp` thread it through to `buildSuccess`.

The bootstrap is also unit-testable: see `test/app/bootstrap_test.dart` for the pattern. A guardrail with no test is a hope.

Why this matters: a 2026-07-01 incident showed that an unhandled `PlatformException` from `Workmanager().initialize(...)` stranded the app on a blank Android splash (with the engine never producing a first frame), producing infinite `W/VRI[MainActivity]: performTraversals: cancelAndRedraw ...` log spam and no visible UI to diagnose from. The startup guardrail was added in response. See [docs/technical/background-sync-limitations.md](docs/technical/background-sync-limitations.md) for the full incident post-mortem and the workmanager 0.9.0 manifest trap.

## Contributing

Issues and pull requests are welcome. Before submitting, please read:

- [Iron Laws](docs/engineering/iron-laws.md) — the 17 coding rules (TDD for domain/ACL, ≥2 tests per widget, etc.)
- [CLAUDE.md](CLAUDE.md) — architecture overview and layer boundaries

`flutter analyze` and `flutter test` must both pass. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat(scope):`, `fix(scope):`, etc.

## License

MIT — see [LICENSE](LICENSE) file for details.

---

<p align="center">
  <sub>Built with 🦐 by the ClawHub community</sub>
</p>
