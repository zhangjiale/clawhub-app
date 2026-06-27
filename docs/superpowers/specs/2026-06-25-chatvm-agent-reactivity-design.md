# ChatViewModel Agent 响应式刷新 — Design Doc

**Date**: 2026-06-25
**Status**: Draft — pending user review
**Source**: systematic-debugging Phase 1 根因调查 + brainstorming Phase 方案比较 + 架构评审委员会报告
**Related**: [US-021 spec](../product/specs/us-021-agent-removal-handling.md), [CLAUDE.md iron-laws](../../engineering/iron-laws.md)

## Problem Summary

用户报告："当我在虾编辑页面新建一个快捷指令的时候，保存之后返回到聊天页面，新建的快捷指令没有显示，要打字发送消息后，快捷指令才会显示出来。"

| # | Severity | Problem | Root Cause |
|---|----------|---------|------------|
| 1 | 🟠 数据陈旧 | `ChatRoomPage` 看不到本地刚保存的 profile 字段（nickname / themeColor / quickCommands / avatarUrl），直到下次 Gateway sync | `ChatViewModel._agent` 是私有缓存，仅在 `_init()` 时通过 `_agentRepo.getById(agentId)` 加载一次；本地写不触发任何响应式刷新 |
| 2 | 🟡 体验不可靠 | 用户必须"打字发送消息"才能看到新快捷指令，行为像 feature 不是 bug | 是 WebSocket 活动可能触发 `agentSyncTickerProvider` 间接重查 `_agent`，完全依赖网络抖动 |

## Root Cause（5 步证据链）

1. `chat_room_page.dart:142` → `final agent = vm.agent;`
2. `chat_view_model.dart:296` → `Agent? get agent => _agent;`（getter 直接返回私有字段）
3. `_agent` 只在 4 个点写入：`_init()` (line 321)、`send()` 在 `_tombstoneSuspect==true` 时 (line 677)、`refreshAgent()` (line 921)、`retryMessage()` (line 974)
4. `AgentProfileViewModel.saveProfile()` 写 DB 后仅 refresh 自己的 VM，**不 emit 任何事件**，不触发 `agentSyncTickerProvider`
5. `AgentsSyncedEvent` 只在 `_syncAgentsForInstance()`（Gateway fetch + sync）成功后 emit，本地 `updateFullProfile()` 不触发

## Goals & Non-Goals

### Goals
- 本地保存快捷指令（以及 nickname / themeColor / avatarUrl）后，**返回聊天页立刻能看到最新值**
- 保持 `chat_room_page.dart` **0 改动**
- 保持 `chat_view_model_send_no_redundant_getbyid_test` **不变量成立**（init 1 次 getById，send 路径 0 次冗余 getById）
- 保持 ViewModel **不持有 Riverpod `ref`**（CLAUDE.md / Iron Laws 约束）
- 与 BUG B/C 修复的 `agentSyncTickerProvider` 双保险共存

### Non-Goals
- 不重构 `AgentProfileViewModel._agent`（虽也有相同问题，但当前 spec 范围聚焦 ChatRoom 用户可见 bug）
- 不引入跨 VM 同步机制（如果未来 Profile 页有同样问题，再开新 spec）
- 不改 `InMemoryMessageRepo._messagesChanged` 模式（现有范式已成熟）

## Architecture Principle

**复用现有模式，不发明新抽象**。本次修复对齐 3 个已有范式：

1. **Stream subscription 模式**：仿 `chat_view_model.dart` 已有的 6 个 stream subscription（messageStream / connectionStateStream / toolCallStream / streamingDeltaStream / watchOutboxCount / outboxCountSubscription）
2. **InMemory repo stream 模式**：仿 `InMemoryMessageRepo._messagesChanged`（line 281-289）—— `StreamController.broadcast()` + 6 个 mutation path 加 emit
3. **双保险路径**：watchById（同实例响应式 SSOT）+ `agentSyncTickerProvider`（跨实例 tombstone 显式触发），与 BUG B/C 修复共存

```
UI Layer
  └─ ChatRoomPage          (0 改动，继续读 vm.agent)
        ↑
ViewModel Layer
  └─ ChatViewModel         ★ 加 _agentSubscription，_agent 自动同步
        ↑
Repository Layer
  ├─ IAgentRepo            ★ 新增 watchById 接口
  ├─ DriftAgentRepo        ★ 实现 watchById（基于 Drift .watchSingleOrNull()）
  └─ InMemoryAgentRepo     ★ 加 stream 行为（仿 InMemoryMessageRepo）
```

## Design

### 6.1 Interface change: IAgentRepo.watchById

**修改** `lib/domain/repositories/i_agent_repo.dart`

```dart
abstract class IAgentRepo {
  // ... 现有方法

  /// 响应式订阅指定 agent 的数据变化。
  ///
  /// Drift 实现基于 `agents` 表的 `.watchSingleOrNull()`，DB 任意写入
  /// （updateFullProfile / updateLocalProfile / clearAvatar / syncFromGateway /
  /// togglePin）都会 emit 新值。InMemory 实现基于 `StreamController.broadcast`
  /// + 手动 emit（仿 InMemoryMessageRepo._messagesChanged）。
  ///
  /// 订阅时立即 emit 当前行（seed event）；订阅期间每次 commit emit 一次。
  /// tombstoned agent（removed_at != null）正常 emit，由调用方判断 isRemoved。
  Stream<Agent?> watchById(String localId);
}
```

**不变性**：纯 Dart 接口，无 Flutter / Drift import（CLAUDE.md Law 1）。

### 6.2 DriftAgentRepo.watchById 实现

**修改** `lib/data/repositories/drift_agent_repo.dart`

```dart
@override
Stream<Agent?> watchById(String localId) {
  // Drift .watchSingleOrNull()：订阅时 emit 当前行（如果存在），后续每次
  // 该行 commit 触发 emit。不存在的 localId 立即 emit null。
  return _database.getAgentByLocalId(localId).watchSingleOrNull().map((row) {
    if (row == null) return null;
    return AgentMapper.fromDrift(row);  // 复用现有 mapper
  });
}
```

**Seed event 行为**：Drift `.watchSingleOrNull()` 在订阅时同步 emit 当前行作为 seed。这意味着：

- 第一次订阅 → 立即 emit 当前 `_agent`（如果存在）
- VM `_init()` 中 `_agent = await _agentRepo.getById(agentId)` (line 321) 已经设置好值
- 紧接着 stream emit seed → `_agent = a`（同值）→ `_syncAgentRemoved()`（冗余调用一次）

**缓解**：见 §6.6 seed event 处理。

### 6.3 InMemoryAgentRepo stream 行为

**修改** `lib/data/repositories/in_memory_repos.dart`

```dart
class InMemoryAgentRepo implements IAgentRepo {
  // 现有字段...

  // ★ 新增：仿 InMemoryMessageRepo._messagesChanged (line 281-289)
  final _agentsChanged = StreamController<Agent>.broadcast();

  // ★ 新增 public watchById
  @override
  Stream<Agent?> watchById(String localId) async* {
    // Seed event：立即 emit 当前值
    yield _findById(localId);  // 复用现有 _findById 私有 helper
    // 后续变化
    await for (final changed in _agentsChanged.stream) {
      if (changed.localId == localId) {
        yield changed;
      }
    }
  }

  // ★ 6 个 mutation path 加 _agentsChanged.add(agent)
  Future<Agent> _putAgent(...) async {
    // ... 现有逻辑
    _agentsChanged.add(agent);  // ★ 新增
    return agent;
  }

  Future<Agent> updateLocalProfile(...) async {
    final updated = await /* ... */;
    _agentsChanged.add(updated);  // ★ 新增
    return updated;
  }

  Future<void> updateFullProfile(...) async {
    // ... 现有逻辑（先 update profile fields，再 update quick commands）
    final updated = await _findById(localId);  // 读最新
    if (updated != null) _agentsChanged.add(updated);  // ★ 新增
  }

  Future<void> clearAvatar(...) async {
    final updated = await /* ... */;
    _agentsChanged.add(updated);  // ★ 新增
  }

  Future<Agent> togglePin(...) async {
    final updated = await /* ... */;
    _agentsChanged.add(updated);  // ★ 新增
  }

  Future<List<Agent>> syncFromGateway(...) async {
    // ... 现有逻辑
    for (final agent in upserted) {
      _agentsChanged.add(agent);  // ★ 新增（每个 upserted agent 都 emit）
    }
    return upserted;
  }

  // 现有 dispose 加 _agentsChanged.close()
  @override
  Future<void> dispose() async {
    await _agentsChanged.close();
    // ... 现有清理
  }
}
```

### 6.4 ChatViewModel._init() stream subscription

**修改** `lib/features/chat_room/viewmodels/chat_view_model.dart`

```dart
class ChatViewModel extends StateNotifier<ChatSessionState> {
  // ... 现有字段

  // ★ 新增（field 区域，line ~190 附近）
  StreamSubscription<Agent?>? _agentSubscription;

  // ★ 修改 _init()：在 _loadMessages() 之后，订阅 stream
  Future<void> _init() async {
    try {
      // 1. Look up the agent (existing)
      _agent = await _agentRepo.getById(agentId);
      _syncAgentRemoved();
      if (_agent == null) { /* ... existing return ... */ }
      if (_agent!.isRemoved) { /* ... existing return ... */ }

      // 2. Get or create conversation (existing)
      await _conversationRepo.getOrCreate(instanceId, agentId);

      // 3. Load local messages (existing)
      await _loadMessages();

      // ★ 3.5 订阅 agent 响应式 stream —— 任何路径写入（本地保存 / Gateway sync）
      //     都会 emit 新值，_agent 自动续命，UI 立刻反映
      _agentSubscription = _agentRepo
          .watchById(agentId)
          .listen(
            (agent) {
              _agent = agent;
              _syncAgentRemoved();
            },
            onError: (error, stackTrace) {
              debugPrint(
                '[ChatViewModel] watchById error for $agentId: $error\n$stackTrace',
              );
            },
          );

      // 4-7. 现有 connection / message / toolCall / streaming / history / outbox 订阅
      // ... 保持不变
    } catch (error, stackTrace) {
      // ... 现有 catch 不变，但要在 teardown 时取消新 subscription（见 §6.5）
    }
  }
}
```

**关键设计点**：
- `_agentSubscription` 在 `_loadMessages()` 之后注册，保证本地 seed 与 stream 顺序正确
- `onError` 兜底（Law 8）：stream 异常不中断其他订阅，记日志即可
- `_syncAgentRemoved()` 在 stream 回调里调：tombstone 检测不依赖 ticker
- 保留 BUG B/C ticker 路径（`markTombstoneSuspectAndRefresh()`）作为兜底 —— 详见 §6.7

### 6.5 _teardownSubscriptions cleanup

**修改** `_teardownSubscriptions()` (line 1097-1117)

```dart
void _teardownSubscriptions() {
  // ... 现有 7 个取消调用

  // ★ 新增
  _agentSubscription?.cancel();
  _agentSubscription = null;
}
```

**编译期强制**（评审推荐）：改 `late final` 字段 + 构造时初始化（而不是 nullable）。权衡：本 spec 暂保持 nullable + null check（与现有 7 个 subscription 一致），后续可统一重构。

### 6.6 Seed event 处理

**问题**：Drift `.watchSingleOrNull()` 在订阅时立即 emit 当前行。`_init()` 已经设置 `_agent`，seed 又触发一次 `_syncAgentRemoved()`（冗余但无害）。

**方案选择**（评审报告建议 3 选项）：

| 方案 | 优点 | 缺点 |
|---|---|---|
| `.skip(1)` | 简单 | 需要先验证 Drift 行为；漏掉用户手动改相同值的真同步 |
| `_seedConsumed = true` flag | 精确 | 多一个 bool 字段 |
| `where((a) => a != _agent)` | 自然去重 | Agent.== 比较所有字段（含 list），可能误判 |

**推荐**：先用 `where((a) => a != _agent)` filter（`.map()` 后）—— 自然去重且无 flag 状态机。如果后续 profiling 显示 `Agent.==` 比较昂贵，可换 `_seedConsumed` flag。

```dart
_agentSubscription = _agentRepo
    .watchById(agentId)
    .where((a) => a != _agent)  // ★ 去重 seed + 相同值
    .listen((agent) {
      _agent = agent;
      _syncAgentRemoved();
    }, ...);
```

**实施步骤（顺序敏感）**：

1. **先验证**：写 DriftAgentRepo 集成测试（§Phase C）观察 `.watchSingleOrNull()` 实际行为，记录是否发 seed event
2. **如果发 seed**：应用 `.where((a) => a != _agent)` filter
3. **如果不发 seed**：移除 `.where()`，避免误吞真实相同值更新

**前提**：§Phase C 的 DriftAgentRepo 集成测试必须**先于** ChatViewModel 集成（§Phase D）跑通，否则 ChatViewModel 端的过滤行为无法验证。

### 6.7 双路径设计（与 BUG B/C 兼容）

**两条独立路径共存**：

| 路径 | 触发条件 | 作用 |
|---|---|---|
| `watchById` stream | 任何 DB 写入（本地保存 / Gateway sync） | 同实例响应式刷新（UI 立即反映） |
| `agentSyncTickerProvider` | Gateway sync 完成（`AgentsSyncedEvent`） | 跨实例 tombstone 显式触发（设置 `_tombstoneSuspect=true`） |

**为什么 ticker 仍需保留**（评审未充分验证的点）：

- ticker 携带 `instanceId` 字段让 ChatRoom 可以按实例过滤（BUG B 修复）—— **已生产验证**
- ticker 显式声明"该实例 sync 完成"是 **跨实例的语义事件**，watchById 是 **单实例的 DB 反应式**，两者事件语义不同（**未充分验证 ticker 是否与 watchById 在 profile 保存路径上有重叠** —— 本 spec 不展开，留作未来观察项）
- **保守策略**：本 spec 不删除 ticker 路径。如果未来 profiling 证实 ticker 完全冗余，再开清理 spec

**doc-comment 必须包含**（防止未来维护者误删）：

```dart
/// 双保险设计：
/// - watchById stream = 同实例 DB 写入响应式 SSOT
/// - agentSyncTickerProvider = 跨实例 tombstone 显式触发
/// 两条路径不冲突，watchById 缺失时 ticker 可作为 tombstone fallback，
/// ticker 缺失时 watchById 已能驱动本地写响应式刷新。
```

## TDD Plan（Law 17 强制）

### Phase A: Domain 接口先行（RED → GREEN）

1. **RED**: `test/domain/repositories/i_agent_repo_test.dart` 新增契约测试（如果文件存在；否则新建）—— 验证 `watchById` 是合法接口方法
2. **GREEN**: `lib/domain/repositories/i_agent_repo.dart` 加 `Stream<Agent?> watchById(String localId);`

### Phase B: InMemoryAgentRepo 实现（RED → GREEN）

1. **RED**: `test/data/repositories/in_memory_agent_repo_watch_test.dart`（新建）
   - 测试 1: `watchById` 订阅时立即 emit 当前行（seed event）
   - 测试 2: `updateFullProfile` 后 stream emit 新值（含新 quickCommands）
   - 测试 3: `clearAvatar` 后 stream emit 新值（avatarUrl=null）
   - 测试 4: `syncFromGateway` 后 stream emit upserted agent
   - 测试 5: `togglePin` 后 stream emit 新值
   - 测试 6: 多订阅者都收到 emit（broadcast 验证）
2. **GREEN**: `lib/data/repositories/in_memory_repos.dart` 实现

### Phase C: DriftAgentRepo 实现（RED → GREEN）

1. **RED**: `test/data/repositories/drift_agent_repo_watch_test.dart`（新建）
   - 集成测试：建库 → insert → watchById → expect 收到 emit
   - seed event 验证
   - dispose 后 stream 关闭验证
2. **GREEN**: `lib/data/repositories/drift_agent_repo.dart` 实现

### Phase D: ChatViewModel 集成（RED → GREEN）

1. **RED**: `test/features/chat_room/chat_view_model_watch_by_id_test.dart`（新建）
   - 测试 1: `_init()` 后 `_agentSubscription` 不为 null
   - 测试 2: 外部 `agentRepo.updateFullProfile()` 触发 `_agent.quickCommands` 同步
   - 测试 3: 外部 `agentRepo.updateFullProfile()` 触发 `state.isAgentRemoved` 响应（tombstone）
   - 测试 4: dispose 后 `_agentSubscription` 取消
   - 测试 5: stream error 不影响其他 subscription（Law 8 兜底）
2. **GREEN**: `lib/features/chat_room/viewmodels/chat_view_model.dart` 加 stream subscription + teardown

### Phase E: 端到端集成测试

1. **RED**: `test/features/chat_room/chat_room_quick_command_reactivity_test.dart`（新建）
   - 模拟真实场景：AgentConfigPage 保存 → ChatRoomPage 立刻看到新 quickCommands
   - 此测试跨 VM，需要 widget test 或集成 test
2. **GREEN**: 已有代码覆盖（不需要新增实现）

## Test Impact Analysis

| 测试文件 | 影响 | 处理 |
|---|---|---|
| `chat_view_model_send_no_redundant_getbyid_test.dart` | **不变** —— init 1 次 getById + send 0 次冗余 getById 不变量保留 | 保持 |
| `chat_view_model_send_test.dart` | **不变** —— 现有 send 行为不变 | 保持 |
| `chat_view_model_retry_test.dart` | **不变** —— retry 行为不变 | 保持 |
| `chat_view_model_refresh_agent_test.dart` | **不变** —— refreshAgent (ticker 路径) 仍存在 | 保持 |
| `chat_view_model_init_fail_tombstone_test.dart` | **不变** —— init 失败路径不变 | 保持 |
| `chat_view_model_streaming_guard_test.dart` | **不变** | 保持 |
| `chat_view_model_highlight_test.dart` | **不变** | 保持 |
| `chat_room_tombstone_guard_test.dart` | **不变** | 保持 |
| `chat_room_page_test.dart` | **不变** —— UI 0 改动 | 保持 |
| `quick_command_bar_test.dart` | **不变** —— widget 0 改动 | 保持 |

**新增 3 个测试文件**：见 TDD Plan §Phase B/C/D。

## Risk Mitigation Plan

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Drift `watchById` 不发 seed event（假设错误） | Low | Low | 先写 DriftAgentRepo 集成测试验证；如果不发则移除 `.where()` |
| `Agent.==` 比较昂贵导致 `.where()` 性能问题 | Low | Low | 如果 profiling 触发，换 `_seedConsumed` flag |
| `_agentSubscription` 在 retry 路径未正确重订阅 | Low | Medium | 加 retry 路径测试；与现有 7 个 subscription 同模式 |
| 未来维护者误删 ticker 路径 | Low | Medium | doc-comment 解释双路径语义（见 §6.7） |
| InMemoryAgentRepo mutation path 漏 emit（部分 mutation 不会触发 stream） | Medium | Medium | 6 个 mutation path 全覆盖测试（Phase B 测试 2-5） |

## Files Changed

| 文件 | 改动量 | 性质 |
|---|---|---|
| `lib/domain/repositories/i_agent_repo.dart` | +5 行 | 新接口 |
| `lib/data/repositories/drift_agent_repo.dart` | +8 行 | 实现 |
| `lib/data/repositories/in_memory_repos.dart` | +30 行 | 实现 + dispose |
| `lib/features/chat_room/viewmodels/chat_view_model.dart` | +25 行（含 comment） | 加 subscription + teardown |
| `test/data/repositories/in_memory_agent_repo_watch_test.dart` | +60 行 | 新测试 |
| `test/data/repositories/drift_agent_repo_watch_test.dart` | +50 行 | 新测试 |
| `test/features/chat_room/chat_view_model_watch_by_id_test.dart` | +70 行 | 新测试 |
| **总计** | **~250 行新增** | 4 src + 3 test |

## Open Questions

1. **AgentProfileViewModel 是否同步改造？**
   - 同样有 `_agent` 缓存问题（profile 页保存后 profile 页面看到新值，因为同 VM；但跨 VM 场景需要审）
   - 当前 spec 范围聚焦 ChatRoom 用户可见 bug，Profile 暂不动
   - **决策**：保持范围聚焦。如果后续发现 Profile 有问题，新开 spec

2. **InMemory repo broadcast vs single-subscription？**
   - `StreamController.broadcast()` 允许多订阅者，但本场景只有一个订阅者
   - **决策**：保持 broadcast，与 `InMemoryMessageRepo._messagesChanged` 模式一致

3. **Drift seed event 是否会引发 ChatSessionState 反复重建？**
   - seed event 触发 `_syncAgentRemoved()` → `state.copyWith(isAgentRemoved: ...)`
   - 如果新值 == 旧值，`state.==` 返回 true → Riverpod 不通知重建
   - 但 `copyWith` 内部会重新构造 state 对象；需验证 `==` 实现
   - **决策**：现有 `ChatSessionState.==` 已比较所有字段，相同值不重建。无需特殊处理

## Acceptance Criteria

- [ ] `IAgentRepo.watchById` 接口添加，纯 Dart 无外部依赖
- [ ] `DriftAgentRepo.watchById` 基于 Drift `.watchSingleOrNull()` 实现
- [ ] `InMemoryAgentRepo.watchById` 基于 `StreamController.broadcast()` 实现
- [ ] 6 个 mutation path（`_putAgent` / `updateLocalProfile` / `updateFullProfile` / `clearAvatar` / `togglePin` / `syncFromGateway`）全部 emit stream
- [ ] `ChatViewModel._init()` 加 `_agentSubscription`
- [ ] `_teardownSubscriptions()` 加 `_agentSubscription?.cancel()`
- [ ] `chat_room_page.dart` **0 改动**
- [ ] `chat_view_model_send_no_redundant_getbyid_test.dart` 通过
- [ ] 新增 3 个测试文件覆盖 RED → GREEN 路径
- [ ] 端到端测试：模拟 AgentConfigPage 保存 → ChatRoomPage 立刻看到新 quickCommands
- [ ] doc-comment 解释双路径设计
- [ ] 现有 8 个 chat_view_model_*_test.dart 全部通过
- [ ] flutter analyze 无 warning
- [ ] 手动 e2e 验证：在真实设备上保存快捷指令 → 返回聊天页 → 立刻看到新指令（无需发消息）

## Out of Scope

- `AgentProfileViewModel._agent` 改造（同模式重构，独立 spec）
- 跨 VM 通用响应式框架（如果未来多 VM 共享需求出现，再开 spec）
- Riverpod 3.x 迁移（如果项目计划升级，独立 spec）
- `Agent.==` 性能优化（与本 spec 无关）