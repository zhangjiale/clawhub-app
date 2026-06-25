# US-021 Tombstone Coverage Gaps — Design Doc

**Date**: 2026-06-25
**Status**: Draft — pending user review
**Source**: Code review findings (high-effort recall-biased) on unpushed US-021 commits `a1d6976` + `fa3f74e` and working-tree changes
**Parent spec**: [US-021 spec](../product/specs/us-021-agent-removal-handling.md)

## Problem Summary

US-021 的原始 spec (§3.1) 列了 8 个改动文件，但遗漏了 4 个 tombstone 覆盖点。code review 找出 4 个 CONFIRMED bug，其中 1 个工程清理可单开 issue 不在本 spec 范围。

| # | Severity | Problem | Root Cause |
|---|----------|---------|------------|
| 1 | 🔴 Data corruption | agent_profile + agent_config 无 isRemoved 守卫，用户可编辑/保存已删除 Agent 的 nickname/avatar/theme/quickCommands，DB↔Gateway 分歧 | spec §3.1 漏列这两个文件；`updateLocalProfile`/`updateFullProfile`/`clearAvatar` 在 DriftAgentRepo:162-249 没有 `removed_at` 过滤 |
| 2 | 🟠 US-021 AC2 违反 | search_view_model 泄漏 tombstoned Agent 到全局搜索结果，渲染已删除 Agent 的 displayName | spec §3.1 漏列 search；同 `message_hub_providers.dart:62-64` 应有 `isRemoved` 守卫却未加 |
| 3 | 🟠 UX 卡死 | OutboxProcessor 对 tombstoned Agent 消息只 `continue`，未转状态，PENDING/FAILED 消息卡 24h | spec §3.5 只升级 guard 条件，漏了状态转换；同函数 24h 过期分支已用 `updateStatus(expired)` 模式 |
| 4 | 🟡 AC8 错乱 | ChatViewModel.init 失败时 catch 块设 `_agent = null` 但不重置 `isAgentRemoved`，残留上轮 tombstone 状态导致占位页错乱 | spec §3.6 设计 ChatRoom placeholder 时未考虑 init 失败路径 |

## Architecture Principle

**复用现有模式，不发明新抽象**。这 4 个修复都遵循 US-021 已建立的"tombstone 状态从 DB → mapper → Agent.isRemoved → 调用方显式过滤"模式。

- **复用 1**: `ChatSessionState.isAgentRemoved` 响应式字段模式 → 复制到 `AgentProfileState`（不抽基类；3 个 VM 共享基类是过度抽象，参见 `IAgentRepo`/`IInstanceRepo` 的 `getByIds` 重复实现）
- **复用 2**: `ChatViewModel.refreshAgent()` helper → 复制到 `AgentProfileViewModel`
- **复用 3**: `ChatRoomPage` 的 AC8 placeholder Scaffold → 抽到 `ui_kit/placeholders/agent_removed_placeholder.dart`（3 处复用值得抽，参见 ui_kit 现有 16 个 widget）

```
UI Layer
  ├─ ChatRoomPage           (已修，原 US-021 范围)
  ├─ AgentProfilePage       ★ 新增 placeholder
  ├─ AgentConfigPage        ★ 新增 placeholder
  └─ SearchPage             (VM 层过滤，UI 不变)
        ↑
ViewModel Layer
  ├─ ChatViewModel          ★ 新增 init-fail 重置
  ├─ AgentProfileViewModel  ★ 新增 isAgentRemoved + refreshAgent + 写守卫
  └─ SearchViewModel        ★ 新增 map 过滤
        ↑
Domain Layer
  ├─ OutboxProcessor        ★ 新增 tombstone skip 时 updateStatus(expired)
  ├─ Agent.isRemoved        (不变)
  └─ MessageRepo.updateStatus(EXPIRED)  (不变)
```

## Fix 1: agent_profile + agent_config Tombstone Guard

### 1.1 新增 ui_kit placeholder

**新建** `lib/ui_kit/placeholders/agent_removed_placeholder.dart`

```dart
class AgentRemovedPlaceholder extends StatelessWidget {
  const AgentRemovedPlaceholder({
    super.key,
    required this.onBack,
    this.agentName,        // null = init 中途失败 / 完全拿不到 agent 信息
    this.source,           // 路由 source（与 US-011 智能返回栈契约一致）
  });
  final String? agentName;
  final VoidCallback onBack;
  final String? source;

  @override
  Widget build(BuildContext context) {
    // 复用 chat_room_page.dart:146-175 的 Scaffold + AppBar + Icon + 文案
    // ★ 改：onBack 内部用 smartBack(context, source: source) 而非 Navigator.pop，
    //   保证 agentProfile 从 claws/messages/search 等不同 tab 进入时回退到正确源
    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(
          onPressed: () => smartBack(context, source: source),
        ),
        title: const Text('虾已移除'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, size: 48, color: XiaColors.red),
              const SizedBox(height: 16),
              const Text('该 Agent 已从 Gateway 移除', textAlign: TextAlign.center),
              if (agentName != null) ...[
                const SizedBox(height: 8),
                Text(agentName!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

**i18n deferred**：文案 `'虾已移除'` / `'该 Agent 已从 Gateway 移除'` 沿用父 spec 的硬编码字符串（CLAUDE.md 提到 `core/localization` WIP）。**v2 抽取 l10n 资源**——本 spec 不阻塞。

### 1.2 AgentProfileViewModel 改造

**修改** `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart`

```dart
// 1) AgentProfileState 加字段
class AgentProfileState {
  // ... 原有字段
  final bool isAgentRemoved;  // ★ 新增

  const AgentProfileState({
    // ...
    this.isAgentRemoved = false,
  });

  AgentProfileState copyWith({
    // ...
    bool? isAgentRemoved,
  }) => AgentProfileState(
    // ...
    isAgentRemoved: isAgentRemoved ?? this.isAgentRemoved,
  );

  @override
  bool operator ==(Object other) =>
      // 原有 + isAgentRemoved == other.isAgentRemoved
}

// 2) ViewModel 加私有缓存 + helpers（仿 chat_view_model.dart:260-298）
class AgentProfileViewModel extends StateNotifier<AgentProfileState> {
  Agent? _agent;  // ★ 新增私有缓存

  void _syncAgentRemoved() {  // ★ 新增 helper
    state = state.copyWith(isAgentRemoved: _agent?.isRemoved ?? false);
  }

  Future<void> refreshAgent() async {  // ★ 新增，仿 chat_view_model.dart:869-879
    try {
      _agent = await _agentRepo.getById(agentId);
    } catch (e, st) {
      debugPrint('[AgentProfileViewModel] refreshAgent failed: $e\n$st');
      return;
    }
    _syncAgentRemoved();
  }

  // 3) refresh() 必须同步 isAgentRemoved
  Future<void> refresh() async {
    final agent = await _agentRepo.getById(agentId);
    if (agent == null) throw AgentNotFoundError(agentId);
    _agent = agent;            // ★ 新增
    _syncAgentRemoved();       // ★ 新增
    // ... 原 LoadData 写入
  }

  // 4) 写路径加 isRemoved 守卫
  Future<void> updateAvatar(Uint8List bytes) async {
    if (_agent?.isRemoved ?? false) {  // ★ 新增
      debugPrint('[AgentProfileViewModel] updateAvatar blocked: agent tombstoned');
      return;
    }
    // ... 原有逻辑
  }

  // updateFullProfile / clearAvatar / removeAvatar 同模式
}
```

### 1.3 AgentProfilePage + AgentConfigPage 改造

**修改** `lib/features/agent_profile/agent_profile_page.dart` 和 `agent_config_page.dart`

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final state = ref.watch(agentProfileViewModelProvider);
  // ★ 新增：placeholder 守卫，与 ChatRoom 同模式
  if (state.isAgentRemoved) {
    return AgentRemovedPlaceholder(
      agentName: state.agent?.displayName,  // nullable：init 中途失败时为 null
      source: widget.source,                 // 路由 source 透传（'claws'/'messages'/'search'）
    );
  }
  // ... 原 Scaffold
}
```

### 1.4 AgentProfileViewModel Provider 改造

**修改** `lib/features/agent_profile/providers/agent_profile_providers.dart`（或新建如不存在）

```dart
final agentProfileViewModelProvider = StateNotifierProvider.autoDispose<
    AgentProfileViewModel, AgentProfileState>((ref) {
  final vm = AgentProfileViewModel(...);
  ref.listen(agentSyncTickerProvider, (_, __) => vm.refreshAgent());
  return vm;
});
```

## Fix 2: search_view_model Tombstone Filter

**修改** `lib/features/search/viewmodels/search_view_model.dart:166-181`

```dart
// 原代码
final results = pageMessages.map((m) {
  final agent = agents[m.agentId];
  final conv = conversations[m.conversationId];
  return SearchResult(...);
}).toList();

// 新代码（对齐 message_hub_providers.dart:62-64 模式）
final results = pageMessages
    .map((m) {
      final agent = agents[m.agentId];
      // ★ 新增：tombstoned agent 的搜索结果跳过
      if (agent?.isRemoved ?? false) return null;
      final conv = conversations[m.conversationId];
      return SearchResult(...);
    })
    .whereType<SearchResult>()
    .toList();
```

**为什么选结果过滤层（不是 FTS5 查询层、不是页面渲染层）**：
- 与 `message_hub_providers.dart:62-64` 完全对齐（用户已选）
- 不改 Drift schema / repo，改动面最小
- VM 返回的 `List<SearchResult>` 已 self-consistent，不会泄露到其他 consumer

## Fix 3: OutboxProcessor 状态转换

**修改** `lib/domain/usecases/outbox_processor.dart:153-160`

```dart
// 原代码
if (agent == null || agent.isRemoved) {
  _logger.info(
    '[OutboxProcessor] Skipped: agent ${message.agentId} '
    '${agent == null ? "not found" : "tombstoned"} '
    'for message ${message.clientId}',
  );
  continue;
}

// 新代码（对齐同函数 24h 过期分支 line 126-140 的 try/catch + updateStatus 模式）
if (agent == null || agent.isRemoved) {
  _logger.info(
    '[OutboxProcessor] Tombstoned agent ${message.agentId} '
    'for message ${message.clientId}; transitioning to EXPIRED',
  );
  try {
    await _messageRepo.updateStatus(
      message.clientId,
      MessageStatus.expired,
    );
  } catch (e, st) {
    _logger.warning(
      '[OutboxProcessor] Failed to EXPIRE tombstoned-agent message '
      '${message.clientId}: $e\n$st',
    );
    // 不抛：不让单条消息失败阻塞后续消息，与现有 24h 分支对齐
  }
  continue;
}
```

**为什么选 EXPIRED（不是 FAILED）**：
- 与同函数 24h 过期分支语义对齐：「这条消息不再会被发送」（用户已选）
- EXPIRED 是 terminal 状态（`message_status.dart:51` `isTerminal`），不会再被 OutboxProcessor 处理
- FAILED 会让 retry 循环尝试重新发送，浪费 cycles

## Fix 4: ChatViewModel.init-fail Reset

**修改** `lib/features/chat_room/viewmodels/chat_view_model.dart:560-564`

```dart
// 原代码
} catch (error, stackTrace) {
  debugPrint(...);
  _teardownSubscriptions();
  _initFuture = null;
  _agent = null;
  // 注：此处不调 _syncAgentRemoved —— init 失败时 state.messages 已变
  // LoadError,占位页不依赖 isAgentRemoved,后续 init() 会重新同步。
}

// 新代码（与 init/send/refreshAgent 的 `_agent =` 写入点同模式：
//        都调 `_syncAgentRemoved()` helper 保持 SSOT）
} catch (error, stackTrace) {
  debugPrint(...);
  _teardownSubscriptions();
  _initFuture = null;
  _agent = null;
  // ★ 新增：显式重置，避免上轮 tombstone 状态残留导致 AC8 错乱占位
  // 必须用 _syncAgentRemoved() helper 而非内联 copyWith：
  //   - 与 line 314 (init success) / line 634 (send recheck) / line 878 (refreshAgent) 同模式
  //   - 维护者将来重命名 helper 或调整 `_agent =` 同步逻辑时不会被遗漏
  _syncAgentRemoved();
}
```

**为什么用 `_syncAgentRemoved()` helper（不是内联 `copyWith(isAgentRemoved: false)`）**：
- SSOT 单一来源：所有 `_agent =` 写入点都通过 helper 同步，catch 块成为唯一不调的写入点会破坏模式
- chat_view_model.dart:295-298 已明确「所有 `_agent =` 写入点必须同步此字段」的契约
- retry() line 1008 也用同模式（虽然 retry 路径用内联 copyWith 是历史遗留，重构时可统一改 helper）
- 单行代码改写两行，维护性收益最大

## File Manifest

### 新增（3 文件）

| 文件 | 用途 |
|---|---|
| `lib/ui_kit/placeholders/agent_removed_placeholder.dart` | 复用 placeholder widget |
| `test/features/chat_room/chat_view_model_init_fail_tombstone_test.dart` | Fix 4 单测 |
| `test/ui_kit/placeholders/agent_removed_placeholder_test.dart` | placeholder widget 单测 |

### 修改（6 生产代码 + 5 测试）

| 文件 | 改动 |
|---|---|
| `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart` | Fix 1.2: state 字段 + 私有缓存 + helper + 写守卫 |
| `lib/features/agent_profile/agent_profile_page.dart` | Fix 1.3: build 守卫 |
| `lib/features/agent_profile/agent_config_page.dart` | Fix 1.3: build 守卫 |
| `lib/features/agent_profile/providers/agent_profile_providers.dart` | Fix 1.4: ref.listen ticker |
| `lib/features/search/viewmodels/search_view_model.dart` | Fix 2: map 过滤 |
| `lib/domain/usecases/outbox_processor.dart` | Fix 3: updateStatus(expired) |
| `lib/features/chat_room/viewmodels/chat_view_model.dart` | Fix 4: catch 重置 |
| `test/domain/usecases/outbox_processor_test.dart` | Fix 3 测试 |
| `test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart` | Fix 1.2 测试 |
| `test/features/search/viewmodels/search_view_model_test.dart` | Fix 2 测试 |
| `test/features/agent_profile/agent_profile_page_test.dart` | Fix 1.3 测试 |
| `test/features/agent_profile/agent_config_page_test.dart` | Fix 1.3 测试 |
| `test/integration/agent_tombstone_lifecycle_test.dart` | 端到端集成 |

**总增量**：~150 行生产代码（含 placeholder）+ ~350 行测试代码。

## TDD Order (Law 17)

按 4 个独立修复的 RED→GREEN 顺序，每修复一个提交一个 commit：

### Commit 1: Fix 4 (最小、最独立)

1. RED: `test/features/chat_room/chat_view_model_init_fail_tombstone_test.dart`
   - `init failure resets isAgentRemoved to false even when prior tombstone state was true`
2. GREEN: 改 `chat_view_model.dart:560` 加 `_syncAgentRemoved()`（与 init/send/refreshAgent 的 `_agent =` 写入点同模式，SSOT）

### Commit 2: Fix 3 (OutboxProcessor 状态转换)

1. RED: 在 `outbox_processor_test.dart` 加 4 个用例：
   - `transitions PENDING messages to EXPIRED when agent is tombstoned`
   - `transitions FAILED messages to EXPIRED when agent is tombstoned`
   - `does not transition status when agent is alive (regression)`
   - `continues to next message when updateStatus throws for tombstoned agent`
2. GREEN: 改 `outbox_processor.dart:153-160`

### Commit 3: Fix 2 (search 过滤)

1. RED: 在 `test/features/search/viewmodels/search_view_model_test.dart` 加 2 个用例：
   - `filters out tombstoned agents from search results`
   - `preserves non-tombstoned agents in search results`
   （注：第 3 个「保留消息但跳过 agent name」用例的语义与当前 `return null + whereType` 实现矛盾，挪到 v2 deferred）
2. GREEN: 改 `search_view_model.dart:166-181`

### Commit 4: Fix 1 (agent_profile + agent_config) — 最大的修复

1. RED 1: `test/ui_kit/placeholders/agent_removed_placeholder_test.dart`
   - `shows agent name when provided`
   - `omits agent name row when agentName is null`
   - `back button invokes smartBack with provided source`
   - `back button invokes smartBack with null source when not provided`
2. GREEN 1: 新建 `agent_removed_placeholder.dart`
3. RED 2: 在 `test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart` 加 6 个用例（state 字段 + refresh + 4 个写守卫）
4. GREEN 2: 改 `agent_profile_view_model.dart`
5. RED 3: 在 `agent_profile_page_test.dart` + `agent_config_page_test.dart` 各加 2 个用例
6. GREEN 3: 改两个 page
7. RED 4: 改 `agent_profile_providers.dart`（加 ref.listen）
8. GREEN 4: provider wiring

### Commit 5: 集成测试

1. 扩展 `agent_tombstone_lifecycle_test.dart` 加一组端到端用例
2. 跑 `flutter test` 全绿

## Error Handling

| 场景 | 处理 |
|---|---|
| search VM `getByIds` 抛 DB 异常 | 异常冒泡 → SearchPage 显示错误（不在本 PR 范围） |
| OutboxProcessor `_messageRepo.updateStatus` 抛异常 | catch + log，**不阻塞后续消息**；对齐 24h 过期分支模式 |
| AgentProfileVM `refreshAgent` 抛异常 | catch + log + early return（与 chat_view_model refreshAgent 模式对齐） |
| AgentProfileVM 写路径 `_agent?.isRemoved==true` 时被调 | 早 return + debug log；UX 上 AgentRemovedPlaceholder 已拦截 |
| ChatViewModel.init `_updateState` 在 disposed StateNotifier 抛 | 不加额外防护（同 retry() 现存模式） |

## Risk & Mitigation

| 风险 | 缓解 |
|---|---|
| ui_kit/placeholders 抽错导致三处 UX 不一致 | placeholder widget test 必须包含所有现有 chat_room placeholder 文案/颜色断言；先写 placeholder RED，再写 VM/Page RED，最后 GREEN placeholder |
| AgentProfileViewModel `_agent` 私有缓存与 state 双源不同步 | **实施步骤**：① 先 `grep -nE '_agent\s*=' lib/features/agent_profile/viewmodels/agent_profile_view_model.dart` 确认实际写入点数量 N；② 断言每个写入点紧邻调 `_syncAgentRemoved()`；③ 如果未来新增 `_agent =` 写入点未调 helper，pre-commit hook + code review 拦住 |
| OutboxProcessor updateStatus 失败但消息仍 PENDING | 24h 过期兜底；log warning 让监控能抓到 |
| OutboxProcessor 单条 updateStatus 不走 batch | 见 Open Questions v1 限制说明 |
| ChatViewModel.init-fail `_syncAgentRemoved()` 在已 dispose VM 上抛 | 与 retry() 同模式，不加防护 |
| placeholder `source` 字段从 widget 哪一层传入 | 由 `agent_profile_page.dart` 接收 widget.source 参数透传（已有 AgentProfilePage source 路由参数模式）；agent_config_page 复用 profile 的 source |
| search 过滤掉 tombstoned agent 后用户困惑"为什么消息不见了" | v1 接受现状（占位页已显式说明"该 Agent 已从 Gateway 移除"）；v2 调研是否在 search UI 加"X 条结果已隐藏"提示 |
| placeholder 三处复用导致 smartBack source 失配 | placeholder widget test 必须覆盖 source=null 和 source='xxx' 两种分支（见 TDD Order Commit 4 RED 1） |

## Open Questions

### Fix 3 batch 写入（已显式承认 v1 限制）

**未实现**：本 spec 的 OutboxProcessor tombstone skip 路径走**逐条** `await _messageRepo.updateStatus(clientId, EXPIRED)`，对齐父 spec §3.5 24h 过期分支的同模式。

**为什么不走 batch**：
- 父 spec §3.5 24h 分支是已稳定存量模式，强行改 batch 会越界
- batch 升级需在 OutboxProcessor 顶部先 query tombstoned agentIds → batch UPDATE messages WHERE agent_id IN (...) AND status IN ('PENDING','FAILED')，跨多层改动

**v1 接受的代价**：单实例 50 条 tombstoned-agent PENDING 消息 = 50 次串行单行 UPDATE + 50 次 try/catch。极端场景性能可感知，但正确性不受影响（24h 自然过期兜底）。

**v2 路径**：若生产监控显示此路径成为热点，可单独提 spec 改 batch（参考父 spec §3.3 sync diff 的 customStatement batch 模式）。

## Parent spec §8 复检（实施前必走）

父 spec `docs/product/specs/us-021-agent-removal-handling.md` §8 实施待办 checklist 中的部分条目应在本 spec 实施时一并复检，确保不重复造轮子：

| 父 spec §8 条目 | 本 spec 状态 |
|---|---|
| `findByCompositeKey` 注释明确"intentionally unfiltered" | ✅ 父 spec 已实施，本 spec 不动 |
| `deleteByInstanceId` 注释说明与 tombstone 路径的语义差 | ✅ 父 spec 已实施，本 spec 不动 |
| `OutboxProcessor` guard 已升级 | ✅ 父 spec 已实施 + 本 spec Fix 3 升级到状态转换 |
| `conversationListProvider` 已升级 null skip → isRemoved skip | ✅ 父 spec 已实施 |
| `providers.dart` 的 `AgentsSyncedEvent` 分支已加 `ref.invalidate(conversationListProvider)` | ✅ 父 spec 已实施 |
| grep `lib/features/**/providers/*.dart` 确认无其他依赖 agent 数据的 FutureProvider 需要 invalidate | ⚠️ 本 spec 实施时重 grep：Fix 2 search VM 通过 FutureProvider 直接 query messageRepo.search + enrichment 不订阅 ticker；本 spec 加 `ref.listen(agentSyncTickerProvider)` 在 search_providers（若需要）让 search 跟着 sync 重建。**open**：决定是否补这一步（v1 search 不需要 invalidate 因为 VM 内每次键入都重新 executeSearch） |
| `Agent.copyWith` 未暴露 `removedAt` / `hiddenAt` 参数 | ✅ 父 spec 已实施，本 spec 不动 |
| `removed_at` 写入只发生在 `syncFromGateway` 内部 | ✅ 父 spec 已实施，本 spec 不动（Fix 1 守卫只是**拒绝写**，不实际写 removed_at） |
| `hidden_at` v1 无任何写入点 | ✅ 父 spec 已实施，本 spec 不动 |
| 所有改动文件总行数 ≤ 120 行（不含测试） | ❌ 本 spec 预估 ~150 行（超过 30 行因 placeholder widget + AgentProfileViewModel state 字段扩展）；**owner 决定**：接受 v1.1 spec 例外，或裁剪 placeholder 内容 |

## Reference

- 父 spec: `docs/product/specs/us-021-agent-removal-handling.md`
- Review 输出: 本会话上文 code review JSON
- 现有 ChatRoom placeholder 实现: `lib/features/chat_room/chat_room_page.dart:142-175`
- 现有 ChatViewModel 响应式字段模式: `lib/features/chat_room/viewmodels/chat_view_model.dart:67-90, 295-298, 869-879`
- 现有 message_hub 过滤模式: `lib/features/message_hub/providers/message_hub_providers.dart:62-64`
- 现有 OutboxProcessor 24h 过期模式: `lib/domain/usecases/outbox_processor.dart:126-140`