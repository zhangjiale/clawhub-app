# 🦐 ClawHub (虾Hub)

<p align="center">
  <strong>Multi-Instance OpenClaw Gateway Mobile Client</strong><br>
  多 OpenClaw 实例移动端统一管理客户端 — 随时随地与你的 AI 虾群对话
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue" alt="Platform">
  <img src="https://img.shields.io/badge/framework-Flutter%203.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/tests-360%20passing-brightgreen" alt="Tests">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

---

## What is ClawHub?

ClawHub (虾Hub) is a mobile app that connects to multiple [OpenClaw](https://github.com/anthropics/openclaw) Gateway instances via WebSocket, giving you a unified chat interface to talk to all your AI agents ("Claws" / 虾) across all your servers — from a single app.

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

# Generate code (required after first clone)
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
│   └── agent_profile/    # Agent profile, stats, achievements, config
└── ui_kit/               # Reusable UI components
```

## Documentation

| Document | Description |
|---|---|
| [PRD](docs/product/prd.md) | Product requirements — features, acceptance criteria, roadmap |
| [User Stories](docs/product/user-stories.md) | Story map, sprint planning, INVEST validation |
| [Design Tokens](docs/design/design-tokens.md) | Color system, typography, spacing, shadows, motion |
| [Component Spec](docs/design/component-spec.md) | Per-page component annotations and interaction specs |
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

## Contributing

Issues and pull requests are welcome. Before submitting code:

1. Read the [Iron Laws](docs/engineering/iron-laws.md)
2. Domain/ACL changes require tests first (see Law 17)
3. New widgets need ≥2 tests (see Law 14)
4. `flutter analyze` must report zero errors
5. `flutter test` must pass all 360+ tests
6. Use [Conventional Commits](https://www.conventionalcommits.org/): `feat(scope):`, `fix(scope):`, etc.

## License

MIT — see [LICENSE](LICENSE) file for details.

---

<p align="center">
  <sub>Built with 🦐 by the ClawHub community</sub>
</p>
