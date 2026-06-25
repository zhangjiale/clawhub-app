# ChatViewModel Agent 响应式刷新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `ChatRoomPage` 在 `AgentConfigPage` 保存快捷指令（以及 nickname / themeColor / avatarUrl）后立刻看到新值，无需发消息触发副作用。

**Architecture:** 沿 `IAgentRepo` 新增响应式 `watchById(localId)` 接口；`DriftAgentRepo` 基于 `.watchSingleOrNull()` 实现，`InMemoryAgentRepo` 基于 `StreamController.broadcast()` + 6 个 mutation path emit 实现；`ChatViewModel._init()` 订阅 stream 让 `_agent` 自动续命；保留 `agentSyncTickerProvider` 作为 tombstone 兜底双保险。

**Tech Stack:** flutter_riverpod, drift, freezed, mocktail, InMemoryAgentRepo / DriftAgentRepo 双实现。

**Parent spec:** [2026-06-25-chatvm-agent-reactivity-design.md](../specs/2026-06-25-chatvm-agent-reactivity-design.md)

## Global Constraints

- Iron Laws (CLAUDE.md): Law 1 domain 纯 Dart / Law 6 batch query / Law 8 catch 必有 debugPrint / Law 14 widget ≥2 tests / Law 17 TDD domain 先测试
- 现有 `chat_view_model_send_no_redundant_getbyid_test.dart` 不变量必须保留（init 1 次 getById，send 0 次冗余 getById）
- 现有 8 个 `chat_view_model_*_test.dart` 全部通过
- `chat_room_page.dart` **0 改动**
- `chat_providers.dart` **0 改动**
- TDD 顺序：Domain 接口 → InMemory 实现 → Drift 实现 → ChatViewModel 集成 → 端到端测试
- Commit 消息格式：`feat(scope):` / `fix(scope):` / `test(scope):` / `refactor(scope):`
- 测试运行命令：`flutter test test/path/to/test.dart` （不要加 `--reporter expanded` 除非调试）

---

## File Structure

**Created:**
- `test/data/repositories/in_memory_agent_repo_watch_test.dart` — InMemory watchById + 6 mutation path 测试
- `test/data/repositories/drift_agent_repo_watch_test.dart` — Drift watchById 集成测试
- `test/features/chat_room/chat_view_model_watch_by_id_test.dart` — ChatViewModel 集成测试

**Modified:**
- `lib/domain/repositories/i_agent_repo.dart` — 加 `watchById` 抽象方法
- `lib/data/repositories/in_memory_repos.dart` — InMemoryAgentRepo 加 `_agentsChanged` stream controller + `watchById` + 6 个 mutation path emit
- `lib/data/repositories/drift_agent_repo.dart` — DriftAgentRepo 加 `watchById` 基于 `_database.getAgentByLocalId(...).watchSingleOrNull()`
- `lib/features/chat_room/viewmodels/chat_view_model.dart` — 加 `_agentSubscription` 字段、`_init()` 订阅、`_teardownSubscriptions()` 取消

**Not modified:**
- `lib/features/chat_room/chat_room_page.dart`（消费 `vm.agent` 不变）
- `lib/features/chat_room/providers/chat_providers.dart`（provider 装配不变）
- `lib/app/di/providers.dart`

---

## Task 1: Domain Interface — IAgentRepo.watchById

**Files:**
- Modify: `lib/domain/repositories/i_agent_repo.dart:5-68` （在 `clearAvatar` 之前插入 `watchById`）

**Interfaces:**
- Consumes: 无
- Produces: `IAgentRepo.watchById(String localId) → Stream<Agent?>` 抽象方法签名

- [ ] **Step 1: 写编译期契约测试（确保 InMemoryAgentRepo 必须实现 watchById）**

`lib/domain/repositories/i_agent_repo.dart` 在 line 7（class body）后插入：

```dart
  /// 响应式订阅指定 agent 的数据变化。
  ///
  /// Drift 实现基于 `agents` 表的 `.watchSingleOrNull()`，DB 任意写入
  /// （updateFullProfile / updateLocalProfile / clearAvatar / syncFromGateway /
  /// togglePin）都会 emit 新值。InMemory 实现基于 `StreamController.broadcast`
  /// + 手动 emit（仿 InMemoryMessageRepo._messagesChanged）。
  ///
  /// 订阅时立即 emit 当前行（seed event），后续每次 commit emit 一次。
  /// tombstoned agent（removed_at != null）正常 emit，由调用方判断 isRemoved。
  /// 不存在的 localId 立即 emit null 并保持 open（等待后续创建）。
  Stream<Agent?> watchById(String localId);
```

（先不写实现，纯接口添加后会导致 InMemoryAgentRepo / DriftAgentRepo 编译失败，这是 Phase A 的 "RED"。）

- [ ] **Step 2: 验证 RED —— 跑现有 in_memory_repos 测试，确认编译失败**

Run: `flutter test test/data/repositories/drift_agent_repo_test.dart 2>&1 | head -30`

Expected output: 
```
Error: The non-abstract class 'InMemoryAgentRepo' is missing implementations for these members:
 - IAgentRepo.watchById
 - (Or same for DriftAgentRepo)
```

如果输出是 PASS 或无相关错误，说明编译没失败，停下来检查测试目录是否引入了 InMemoryAgentRepo；如果是真的 PASS，说明抽象方法添加未生效，停下来重新检查文件位置。

- [ ] **Step 3: 暂不修复 RED —— 这是 Task 1 的目标**

不要在这一步添加实现。RED 状态需要保留到 Task 2（InMemoryAgentRepo）添加实现后才变 GREEN。

- [ ] **Step 4: 不 commit（保持工作树 RED 状态）**

直接进入 Task 2。

---

## Task 2: InMemoryAgentRepo — watchById + StreamController

**Files:**
- Modify: `lib/data/repositories/in_memory_repos.dart:83` （InMemoryAgentRepo 类开头加 import + field；类末尾 6 个 mutation path 加 emit；新增 watchById 方法）
- Create: `test/data/repositories/in_memory_agent_repo_watch_test.dart`

**Interfaces:**
- Consumes: `IAgentRepo.watchById(String) → Stream<Agent?>` 签名（Task 1）
- Produces: `InMemoryAgentRepo.watchById(String) → Stream<Agent?>`，订阅立即 emit seed，6 个 mutation path 触发 emit

### Step A: 写测试（RED）

- [ ] **Step 1: 创建测试文件**

新建 `test/data/repositories/in_memory_agent_repo_watch_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

Agent _agent({
  String localId = 'local-1',
  String remoteId = 'r-1',
  String instanceId = 'inst-1',
  String name = '产品虾',
  List<QuickCommand>? quickCommands,
}) => Agent(
  localId: localId,
  remoteId: remoteId,
  instanceId: instanceId,
  name: name,
  themeColor: '#6c5ce7',
  quickCommands: quickCommands ?? const [],
);

QuickCommand _cmd(String id, String label, String payload, [int sortOrder = 0]) =>
    QuickCommand(
      id: id,
      agentId: 'local-1',
      label: label,
      payload: payload,
      sortOrder: sortOrder,
    );

void main() {
  group('InMemoryAgentRepo.watchById', () {
    late InMemoryAgentRepo repo;

    setUp(() {
      repo = InMemoryAgentRepo();
    });

    tearDown(() async {
      await repo.dispose();
    });

    test('subscribe emits current agent as seed event', () async {
      await repo.syncFromGateway('inst-1', [_agent()]);

      final stream = repo.watchById('local-1');
      final emitted = await stream.first;

      expect(emitted, isNotNull);
      expect(emitted!.localId, 'local-1');
      expect(emitted.name, '产品虾');
    });

    test('subscribe to nonexistent localId emits null', () async {
      final stream = repo.watchById('nonexistent');
      final emitted = await stream.first;

      expect(emitted, isNull);
    });

    test('updateFullProfile with new quickCommands emits updated agent',
        () async {
      await repo.syncFromGateway('inst-1', [_agent()]);

      final emitted = <Agent>[];
      final sub = repo.watchById('local-1').skip(1).listen(emitted.add);

      await repo.updateFullProfile(
        'local-1',
        quickCommands: [_cmd('c1', '状态', '/status', 0)],
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      final last = emitted.last;
      expect(last.quickCommands.length, 1);
      expect(last.quickCommands.first.payload, '/status');
    });

    test('clearAvatar emits agent with avatarUrl=null', () async {
      await repo.syncFromGateway('inst-1', [
        _agent().copyWith(avatarUrl: '/path/to/avatar.png'),
      ]);

      final emitted = <Agent>[];
      final sub = repo.watchById('local-1').skip(1).listen(emitted.add);

      await repo.clearAvatar('local-1');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last.avatarUrl, isNull);
    });

    test('togglePin emits agent with flipped isPinned', () async {
      await repo.syncFromGateway('inst-1', [_agent()]);

      final emitted = <Agent>[];
      final sub = repo.watchById('local-1').skip(1).listen(emitted.add);

      await repo.togglePin('local-1');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last.isPinned, isTrue);
    });

    test('syncFromGateway emits upserted agents', () async {
      final emitted = <Agent>[];
      final sub = repo.watchById('local-1').listen(emitted.add);

      await repo.syncFromGateway('inst-1', [_agent()]);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(2),
          reason: 'syncFromGateway 应 emit seed + upsert');
      final last = emitted.last;
      expect(last.localId, 'local-1');
    });

    test('updateLocalProfile emits agent with new nickname', () async {
      await repo.syncFromGateway('inst-1', [_agent()]);

      final emitted = <Agent>[];
      final sub = repo.watchById('local-1').skip(1).listen(emitted.add);

      await repo.updateLocalProfile('local-1', nickname: '小虾');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last.nickname, '小虾');
    });

    test('multiple subscribers all receive emits (broadcast)', () async {
      await repo.syncFromGateway('inst-1', [_agent()]);

      final sub1 = <Agent>[];
      final sub2 = <Agent>[];
      final s1 = repo.watchById('local-1').skip(1).listen(sub1.add);
      final s2 = repo.watchById('local-1').skip(1).listen(sub2.add);

      await repo.updateLocalProfile('local-1', nickname: 'test');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await s1.cancel();
      await s2.cancel();

      expect(sub1.length, greaterThanOrEqualTo(1));
      expect(sub2.length, greaterThanOrEqualTo(1));
      expect(sub1.last.nickname, 'test');
      expect(sub2.last.nickname, 'test');
    });
  });
}
```

注意：`InMemoryAgentRepo` 当前**没有 `dispose` 方法**。`tearDown` 中的 `await repo.dispose()` 会编译失败 —— 这是 Task 2 的 RED 之一（除了 watchById 缺失）。

- [ ] **Step 2: 跑测试确认 RED**

Run: `flutter test test/data/repositories/in_memory_agent_repo_watch_test.dart 2>&1 | head -30`

Expected: 编译错误（missing watchById implementation + missing dispose method）。

### Step B: 实现 watchById + 6 mutation path emit + dispose

- [ ] **Step 3: 添加 `dart:async` import（如果还没有）**

检查 `lib/data/repositories/in_memory_repos.dart:1-4`。如果 `dart:async` 已存在（InMemoryMessageRepo 使用了），跳过本步；否则在 line 1 前插入：

```dart
import 'dart:async';
```

- [ ] **Step 4: 在 InMemoryAgentRepo 类内（line 86 附近，类字段区域）添加 stream controller**

在 `final Map<String, Agent> _byCompositeKey = {};` 之后插入：

```dart
  /// Agent 变更广播 — 任何 mutation path 写入后 emit 当前 agent（仿
  /// InMemoryMessageRepo._messagesChanged 模式）。watchById 订阅者收到 emit 后
  /// 可立即拿到最新值，实现响应式刷新。
  final StreamController<Agent> _agentsChanged =
      StreamController<Agent>.broadcast();
```

- [ ] **Step 5: 在 InMemoryAgentRepo 类内（line 152 `_putAgent` 末尾）添加 emit**

修改 `_putAgent` 方法（在 `final _byCompositeKey[...] = agent;` 之后）：

```dart
  void _putAgent(Agent agent) {
    _store[agent.localId] = agent;
    _byCompositeKey[_compositeKey(agent.instanceId, agent.remoteId)] = agent;
    if (!_agentsChanged.isClosed) _agentsChanged.add(agent);  // ★ 新增
  }
```

这样所有走 `_putAgent` 的 mutation path（syncFromGateway / updateLocalProfile / updateFullProfile / clearAvatar / togglePin）自动获得 emit，**不需要**在每个 mutation path 单独加。

- [ ] **Step 6: 添加 `watchById` 方法**

在 `deleteByInstanceId` 方法之后（line 266 之后）插入：

```dart
  @override
  Stream<Agent?> watchById(String localId) async* {
    // Seed event: 立即 emit 当前值（仿 Drift .watchSingleOrNull() 行为）。
    yield _store[localId];
    // 后续变化: filter 该 localId 的 emit
    await for (final changed in _agentsChanged.stream) {
      if (changed.localId == localId) {
        yield _store[localId]; // 重读最新值（含 clearAvatar 后的 null avatar）
      }
    }
  }

  /// 关闭内部 stream controller（测试 cleanup + 未来真实 dispose 路径）。
  Future<void> dispose() async {
    if (!_agentsChanged.isClosed) {
      await _agentsChanged.close();
    }
  }
```

注意：
- `yield _store[localId]` 而不是 `yield changed`：因为 `changed` 是 emit 触发瞬间的 agent 引用，但我们需要重新读 `_store` 以防后续被另一个 mutation 覆盖（防御性，已测试场景中不一定触发）
- `deleteByInstanceId` 删除 agent 时不 emit（合理：被删除的 agent 没人在 watch 了）

- [ ] **Step 7: 跑测试确认 GREEN**

Run: `flutter test test/data/repositories/in_memory_agent_repo_watch_test.dart 2>&1 | tail -20`

Expected: `All tests passed!` 或类似（8 个 test 全过）。

如果失败：
- `subscribe emits current agent as seed event` 失败 → 检查 `watchById` 是否在 syncFromGateway 之后能读到 seed
- `updateFullProfile ... emits updated agent` 失败 → 检查 `_putAgent` 是否正确 emit
- `clearAvatar emits agent with avatarUrl=null` 失败 → 检查 clearAvatar 是否走 _putAgent
- `dispose` 编译错误 → 检查是否漏添加 dispose 方法

- [ ] **Step 8: 跑现有测试确保无回归**

Run: `flutter test test/data/repositories/drift_agent_repo_test.dart 2>&1 | tail -10`

Expected: 现有测试全过（InMemoryAgentRepo 没破坏 Drift 行为）。

- [ ] **Step 9: Commit**

```bash
git add lib/data/repositories/in_memory_repos.dart test/data/repositories/in_memory_agent_repo_watch_test.dart
git commit -m "feat(agent_repo): add InMemoryAgentRepo.watchById stream + 6 mutation path emit"
```

---

## Task 3: DriftAgentRepo — watchById 实现

**Files:**
- Modify: `lib/data/repositories/drift_agent_repo.dart:80` （在 `findAgentByCompositeKey` 之后插入 `watchById`）
- Create: `test/data/repositories/drift_agent_repo_watch_test.dart`

**Interfaces:**
- Consumes: `IAgentRepo.watchById(String) → Stream<Agent?>` 签名（Task 1）
- Produces: `DriftAgentRepo.watchById(String) → Stream<Agent?>`，基于 Drift `.watchSingleOrNull()`

### Step A: 写集成测试（RED）

- [ ] **Step 1: 创建测试文件**

新建 `test/data/repositories/drift_agent_repo_watch_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/data/repositories/drift_agent_repo.dart';
import 'package:claw_hub/data/repositories/drift_instance_repo.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

Future<db.AppDatabase> _createTestDb() async {
  final database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (sqlDb) {
        sqlDb.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
  addTearDown(() => database.close());
  return database;
}

void main() {
  group('DriftAgentRepo.watchById', () {
    late db.AppDatabase database;
    late DriftAgentRepo agentRepo;
    late DriftInstanceRepo instanceRepo;

    setUp(() async {
      database = await _createTestDb();
      agentRepo = DriftAgentRepo(database);
      instanceRepo = DriftInstanceRepo(database);

      // Need an instance first for FK
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'ws://test:18789',
          tokenRef: 'tok',
          healthStatus: HealthStatus.online,
        ),
      );
    });

    test('subscribe emits current agent as seed event', () async {
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      final stream = agentRepo.watchById('local-1');
      final emitted = await stream.first;

      expect(emitted, isNotNull);
      expect(emitted!.localId, 'local-1');
    });

    test('subscribe to nonexistent localId emits null', () async {
      final stream = agentRepo.watchById('nonexistent');
      final emitted = await stream.first;

      expect(emitted, isNull);
    });

    test('updateFullProfile emits agent with new quickCommands', () async {
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      // Skip seed (first emit is current state)
      final emitted = <Agent>[];
      final sub = agentRepo.watchById('local-1').skip(1).listen(emitted.add);

      await agentRepo.updateFullProfile(
        'local-1',
        quickCommands: [
          QuickCommand(
            id: 'c1',
            agentId: 'local-1',
            label: '状态',
            payload: '/status',
            sortOrder: 0,
          ),
        ],
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last.quickCommands.length, 1);
      expect(emitted.last.quickCommands.first.payload, '/status');
    });

    test('clearAvatar emits agent with avatarUrl=null', () async {
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
          avatarUrl: '/path/to/avatar.png',
        ),
      ]);

      final emitted = <Agent>[];
      final sub = agentRepo.watchById('local-1').skip(1).listen(emitted.add);

      await agentRepo.clearAvatar('local-1');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted.last.avatarUrl, isNull);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认 RED**

Run: `flutter test test/data/repositories/drift_agent_repo_watch_test.dart 2>&1 | head -20`

Expected: 编译错误（missing watchById implementation）。

### Step B: 实现 watchById

- [ ] **Step 3: 在 `findAgentByCompositeKey` 之后插入 `watchById`**

修改 `lib/data/repositories/drift_agent_repo.dart`，在 line 80 之后插入：

```dart
  @override
  Stream<Agent?> watchById(String localId) {
    // Drift .watchSingleOrNull()：订阅时立即 emit 当前行（如果存在），后续每次
    // 该行 commit 触发 emit。不存在的 localId 立即 emit null 并保持 open。
    return _database
        .getAgentByLocalId(localId)
        .watchSingleOrNull()
        .map((row) {
          if (row == null) return null;
          return AgentMapper.toDomain(row);
        });
  }
```

- [ ] **Step 4: 跑测试确认 GREEN**

Run: `flutter test test/data/repositories/drift_agent_repo_watch_test.dart 2>&1 | tail -15`

Expected: `All tests passed!` 或 4 个 test 全过。

**关键观察**：注意 `subscribe emits current agent as seed event` 是否通过 —— 这决定 Task 5 ChatViewModel 是否需要 `.where((a) => a != _agent)` 去重。如果 Drift 不发 seed，则 ChatViewModel 端无需 filter。

- [ ] **Step 5: 跑现有测试确保无回归**

Run: `flutter test test/data/repositories/drift_agent_repo_test.dart 2>&1 | tail -10`

Expected: 现有测试全过。

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/drift_agent_repo.dart test/data/repositories/drift_agent_repo_watch_test.dart
git commit -m "feat(agent_repo): add DriftAgentRepo.watchById via .watchSingleOrNull()"
```

---

## Task 4: ChatViewModel — Stream Subscription 集成

**Files:**
- Modify: `lib/features/chat_room/viewmodels/chat_view_model.dart:210` （field 区域加 `_agentSubscription`）；`_init()` 内 line 349 之后加订阅；`_teardownSubscriptions()` line 1097-1117 内加取消
- Create: `test/features/chat_room/chat_view_model_watch_by_id_test.dart`

**Interfaces:**
- Consumes: `IAgentRepo.watchById(String) → Stream<Agent?>` 签名（Task 2/3 已实现）
- Produces: `_agentSubscription` 字段，订阅后 `_agent` 自动同步

### Step A: 写测试（RED）

- [ ] **Step 1: 创建测试文件**

新建 `test/features/chat_room/chat_view_model_watch_by_id_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/quick_command.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

class _MockAgentRepo extends Mock implements IAgentRepo {}

const _agentId = 'local-1';
const _instanceId = 'inst-1';
const _remoteId = 'r-1';

Agent _activeAgent({List<QuickCommand>? quickCommands}) => Agent(
      localId: _agentId,
      remoteId: _remoteId,
      instanceId: _instanceId,
      name: '产品虾',
      themeColor: '#6c5ce7',
      quickCommands: quickCommands ?? const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InMemoryAgentRepo agentRepo;
  late InMemoryMessageRepo messageRepo;
  late InMemoryConversationRepo conversationRepo;
  late InMemoryInstanceRepo instanceRepo;
  late MockGatewayClient gateway;

  setUp(() async {
    agentRepo = InMemoryAgentRepo();
    messageRepo = InMemoryMessageRepo();
    conversationRepo = InMemoryConversationRepo();
    instanceRepo = InMemoryInstanceRepo();
    gateway = MockGatewayClient();

    await instanceRepo.save(
      Instance(
        id: _instanceId,
        name: 'Test',
        gatewayUrl: 'wss://test.example.com:443',
        tokenRef: 'test-token-ref',
        healthStatus: HealthStatus.online,
        isLocalNetwork: false,
      ),
    );
  });

  ChatViewModel createViewModel() {
    return ChatViewModel(
      agentRepo: agentRepo,
      conversationRepo: conversationRepo,
      messageRepo: messageRepo,
      instanceRepo: instanceRepo,
      gatewayClient: gateway,
      sendMessageUseCase: SendMessageUseCase(
        messageRepo: messageRepo,
        conversationRepo: conversationRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
      ),
      instanceId: _instanceId,
      agentId: _agentId,
      achievementChecker: _MockAchievementChecker(),
      flushDelay: Duration.zero,
    );
  }

  group('ChatViewModel.watchById reactivity', () {
    test('init() subscribes to watchById (covers bug: local profile save '
        'must reflect immediately in chat room)', () async {
      await agentRepo.syncFromGateway(_instanceId, [_activeAgent()]);

      final vm = createViewModel();
      await vm.init();

      expect(vm.agent, isNotNull);
      expect(vm.agent!.quickCommands, isEmpty);

      // 模拟 AgentConfigPage 保存快捷指令
      await agentRepo.updateFullProfile(
        _agentId,
        quickCommands: [
          QuickCommand(
            id: 'c1',
            agentId: _agentId,
            label: '状态',
            payload: '/status',
            sortOrder: 0,
          ),
        ],
      );

      // 关键: 不需要发消息, vm.agent 应该已经反映新值
      expect(
        vm.agent!.quickCommands.length,
        1,
        reason: 'watchById 应让 vm.agent 在保存后立刻反映新 quickCommands',
      );
      expect(vm.agent!.quickCommands.first.payload, '/status');
    });

    test('init() subscribes to watchById for nickname change', () async {
      await agentRepo.syncFromGateway(_instanceId, [_activeAgent()]);

      final vm = createViewModel();
      await vm.init();

      expect(vm.agent!.nickname, isNull);

      await agentRepo.updateLocalProfile(_agentId, nickname: '小虾');

      expect(vm.agent!.nickname, '小虾');
    });

    test('dispose() cancels agent subscription', () async {
      await agentRepo.syncFromGateway(_instanceId, [_activeAgent()]);

      final vm = createViewModel();
      await vm.init();
      await vm.dispose();

      // dispose 后再更新, vm.agent 不应再变化
      final agentBefore = vm.agent;
      await agentRepo.updateLocalProfile(_agentId, nickname: 'after-dispose');

      expect(vm.agent, same(agentBefore),
          reason: 'dispose 后订阅取消, vm.agent 不再变');
    });

    test('watchById error does not crash init or other subscriptions',
        () async {
      // 用 mocktail 模拟 watchById 抛异常
      final mockRepo = _MockAgentRepo();
      when(() => mockRepo.getById(_agentId))
          .thenAnswer((_) async => _activeAgent());
      when(() => mockRepo.watchById(_agentId))
          .thenAnswer((_) => Stream<Agent?>.error(Exception('simulated stream error')));

      final vm = ChatViewModel(
        agentRepo: mockRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: _instanceId,
        agentId: _agentId,
        achievementChecker: _MockAchievementChecker(),
        flushDelay: Duration.zero,
      );

      // init 应不崩溃 (Law 8: catch 必有 debugPrint, 不影响其他订阅)
      await vm.init();

      // agent 已加载
      expect(vm.agent, isNotNull);

      await vm.dispose();
    });
  });
}
```

- [ ] **Step 2: 跑测试确认 RED**

Run: `flutter test test/features/chat_room/chat_view_model_watch_by_id_test.dart 2>&1 | head -30`

Expected: 编译错误（`_agentSubscription` 字段未定义）或测试失败（vm.agent 在 updateFullProfile 后未更新）。

### Step B: 实现订阅

- [ ] **Step 3: 在 ChatViewModel field 区域（line 210 附近）添加 `_agentSubscription`**

修改 `lib/features/chat_room/viewmodels/chat_view_model.dart`，在 line 210 `Agent? _agent;` 之后插入：

```dart
  Agent? _agent;

  /// 响应式 agent 订阅 —— _init() 中订阅 watchById(agentId) stream，
  /// 任何 DB 写入（本地保存 / Gateway sync）触发 emit 后自动同步 _agent，
  /// UI 经 vm.agent getter 立即看到最新值（quickCommands / nickname 等）。
  /// 仿现有 7 个 stream subscription 模式（messageStream / connectionStateStream /
  /// toolCallStream / streamingDeltaStream / watchOutboxCount / outboxCount /
  /// outboxFlushTickerProvider）。
  StreamSubscription<Agent?>? _agentSubscription;

  // ... existing fields continue
```

- [ ] **Step 4: 在 `_init()` 内 line 349 之后（`_loadMessages()` 之后）插入订阅**

修改 `_init()`，找到 `await _loadMessages();`（line 349），在其后插入：

```dart
      // 3. Load local messages (existing)
      await _loadMessages();

      // ★ 3.5 订阅 agent 响应式 stream
      _agentSubscription = _agentRepo.watchById(agentId).listen(
        (agent) {
          _agent = agent;
          _syncAgentRemoved();
        },
        onError: (error, stackTrace) {
          // Law 8: catch 必有 debugPrint
          debugPrint(
            '[ChatViewModel] watchById error for $agentId: $error\n$stackTrace',
          );
        },
      );

      // 4-7. 现有 connection / message / toolCall / streaming / history / outbox 订阅
```

**重要**：注释 `// 4-7.` 后面代码保持不变，**不要**重写。

- [ ] **Step 5: 在 `_teardownSubscriptions()` 内（line 1097-1117）添加取消**

找到 `_teardownSubscriptions()` 方法，在 `_outboxCountSubscription?.cancel();` 之后、`_timeoutTimer?.cancel();` 之前插入：

```dart
  void _teardownSubscriptions() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _toolCallSubscription?.cancel();
    _toolCallSubscription = null;
    _streamingSubscription?.cancel();
    _streamingSubscription = null;
    _isStreaming = false;
    _outboxCountSubscription?.cancel();
    _outboxCountSubscription = null;
    _agentSubscription?.cancel();      // ★ 新增
    _agentSubscription = null;          // ★ 新增
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _stallTimer?.cancel();
    _stallTimer = null;
    _overallTimeoutTimer?.cancel();
    _overallTimeoutTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
  }
```

- [ ] **Step 6: 跑新测试确认 GREEN**

Run: `flutter test test/features/chat_room/chat_view_model_watch_by_id_test.dart 2>&1 | tail -15`

Expected: 4 个 test 全过。

- [ ] **Step 7: 跑现有 chat_view_model 测试确保无回归**

Run: `flutter test test/features/chat_room/ 2>&1 | tail -20`

Expected: 全部测试通过（含 `chat_view_model_send_no_redundant_getbyid_test.dart` 1 次 getById 不变量、`chat_view_model_send_test.dart`、`chat_view_model_retry_test.dart`、`chat_view_model_refresh_agent_test.dart` 等）。

如果任何现有测试失败，停下来回滚本 Task 的修改，调查原因。

- [ ] **Step 8: Commit**

```bash
git add lib/features/chat_room/viewmodels/chat_view_model.dart test/features/chat_room/chat_view_model_watch_by_id_test.dart
git commit -m "feat(chat_view_model): subscribe to agentRepo.watchById for reactive profile updates"
```

---

## Task 5: 端到端集成验证

**Files:**
- 无新文件
- 可选：手测脚本（不需要提交）

**Interfaces:**
- 验证: 完整 User Story 路径 —— AgentConfigPage 保存 → ChatRoomPage 立刻看到

### Step A: 静态分析 + 完整测试套件

- [ ] **Step 1: 跑 flutter analyze 确保无 warning**

Run: `flutter analyze 2>&1 | tail -20`

Expected: `No issues found!` 或仅遗留 lint（与本 spec 无关）。

如果有本 spec 引入的新 warning，停下来修复。

- [ ] **Step 2: 跑全 chat_room + chat_view_model 测试**

Run: `flutter test test/features/chat_room/ test/data/repositories/in_memory_agent_repo_watch_test.dart test/data/repositories/drift_agent_repo_watch_test.dart 2>&1 | tail -10`

Expected: 全部测试通过。

- [ ] **Step 3: 跑全项目测试**

Run: `flutter test 2>&1 | tail -30`

Expected: 全项目测试通过。

如果有任何失败，按"修复最小集"原则回退本次 commit 修改后再调查。

- [ ] **Step 4: 不 commit**

本 Task 无源码改动，无需 commit。

---

## Task 6: 文档收尾

**Files:**
- Modify: `lib/features/chat_room/viewmodels/chat_view_model.dart` （`_agentSubscription` 字段 doc-comment 加双路径设计说明）

**Interfaces:**
- 无（仅 doc-comment）

- [ ] **Step 1: 在 `_agentSubscription` 字段的 doc-comment 加双路径说明**

修改 `lib/features/chat_room/viewmodels/chat_view_model.dart`，把 `_agentSubscription` 字段的 doc-comment 扩展为：

```dart
  /// 响应式 agent 订阅 —— _init() 中订阅 watchById(agentId) stream，
  /// 任何 DB 写入（本地保存 / Gateway sync）触发 emit 后自动同步 _agent，
  /// UI 经 vm.agent getter 立即看到最新值（quickCommands / nickname 等）。
  /// 仿现有 7 个 stream subscription 模式。
  ///
  /// **双保险设计（重要：不要简化其中一条）**：
  /// - watchById stream = **同实例** DB 写入响应式 SSOT（修本 spec bug）
  /// - agentSyncTickerProvider = **跨实例** tombstone 显式触发（BUG B/C 修复）
  ///
  /// 两条路径不冲突：watchById 缺失时 ticker 可作为 tombstone fallback；
  /// ticker 缺失时 watchById 已能驱动本地写响应式刷新。
  /// 删除任一条都会让对应场景失效。修改前请先阅读设计文档：
  /// docs/superpowers/specs/2026-06-25-chatvm-agent-reactivity-design.md §6.7
  StreamSubscription<Agent?>? _agentSubscription;
```

- [ ] **Step 2: 跑 analyze 确认无 warning**

Run: `flutter analyze 2>&1 | tail -10`

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/chat_room/viewmodels/chat_view_model.dart
git commit -m "docs(chat_view_model): document dual-path design for _agentSubscription"
```

---

## Self-Review Checklist (执行者必查)

执行每个 Task 前请确认：

- [ ] **Spec coverage**: spec 中所有需求都有 Task 覆盖？
  - Domain 接口 → Task 1
  - DriftAgentRepo.watchById → Task 3
  - InMemoryAgentRepo.watchById + 6 mutation path → Task 2
  - ChatViewModel._init() 订阅 → Task 4
  - ChatViewModel teardown → Task 4
  - 双保险设计 doc-comment → Task 6
  - 端到端测试 → Task 5

- [ ] **Placeholder scan**: 没有 TBD / TODO / "later" / "similar to Task N"
  - ✅ 全部代码块都是完整代码

- [ ] **Type consistency**: 
  - `IAgentRepo.watchById(String) → Stream<Agent?>` 在 Task 1/2/3 一致
  - `InMemoryAgentRepo._agentsChanged` 在 Task 2 一致
  - `ChatViewModel._agentSubscription` 在 Task 4 一致

- [ ] **DRY**: 没有跨 Task 重复代码（除非必须）

- [ ] **YAGNI**: 没有不必要的过度设计
  - seed event filter (`where(a => a != _agent)`) 在 spec 中是"先验证后决定"，Task 4 当前不强制要求；如果 Task 3 测试显示 Drift 不发 seed 则不需要

- [ ] **TDD**: 每个 Task 先 RED 后 GREEN
  - Task 1 是接口，纯编译 RED
  - Task 2/3/4 都是先写测试跑失败再实现

- [ ] **Frequent commits**: 每个 Task 独立 commit
  - Task 1 不 commit（保持 RED）
  - Task 2/3/4/6 各 1 commit
  - Task 5 无 commit