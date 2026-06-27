# Spec: 架构债清理 — Agent equality / _setAgent / tombstone guard

**Date**: 2026-06-27
**Status**: Approved (pending spec review)
**Scope**: 3 个低严重度架构债（code review Finding #7/#8/#9），零行为变更。

## Context

Code review（`/code-review`，高优先级）发现 unpushed diff + working tree 中除 3 个 correctness bug（已修）外还有 6 个 finding。其中 3 个属于架构债：

- **#7**: `Agent.operator ==` 与 `Agent.contentEquals` 字段列表重叠，新增字段必须三处同步（== / hashCode / contentEquals），违反 DRY。
- **#8**: `_setAgent` 在 `ChatViewModel` 与 `AgentProfileViewModel` 逐字节重复（含 contentEquals guard + contentRevision bump + debugSetAgent），未来加字段/调整守卫语义/调整 revision 策略需同步两处。
- **#9**: `agent?.isRemoved ?? false` 模式在 4 个 UI/VM 点重复（chat_room_page / agent_profile_page / agent_config_page / saveProfile/updateAvatar/removeAvatar guard），未来 `Agent.isRemoved` 签名变化需 4 处同步。

剩下 3 个 (#4 AnimatedScale / #5 InMemoryAgentRepo.deleteByInstanceId 不 emit / #6 _effectiveToken 默认 '') 是 correctness bug，已与本次架构债清理分开（用户选择只做架构债）。

## Goals

- 消除 3 处架构债，零行为变更。
- 复用现有测试：3 个修复不引入新功能，纯结构调整，所有现有测试必须保持绿。
- 提取的 helper 通过新增的 unit test 覆盖关键不变量（防回归）。

## Non-Goals

- 不修 #4/#5/#6 correctness bug。
- 不引入新的运行时行为（tombstone 推送时机、连接状态判定、revision bump 触发条件全部保持现状）。
- 不触碰 `Set<Agent>` / `Map<Agent, V>` 已有语义（grep 验证 0 命中，安全）。
- 不动 pre-existing 的 `search_view_model.dart` tombstone guard（review 报告已标注属于历史代码）。

---

## Fix #7: Agent.operator == 退回 identity-only

### 设计

将 `Agent.operator ==` 从 `{localId, removedAt, hiddenAt}` 退回 `{localId}`，与 `QuickCommand.==` 完全对齐。两层语义明确：

| 层级 | 语义 | 用途 | 例子 |
|---|---|---|---|
| `==` / `hashCode` | identity-only（仅 localId） | Set/Map dedup；Riverpod 默认 identity dedup | `Set<Agent>.contains(agent)` |
| `contentEquals` | 全字段比对（含 tombstone / hidden） | reactive dedup（Riverpod + contentEquals guard 过滤） | `_setAgent` contentEquals 守卫 |

`Operator ==` 的 `removedAt` / `hiddenAt` 字段是冗余的——任何 `localId` 相同的 Agent 即便 tombstone 状态不同，仍是「同一个 Agent」（US-021 v1.1 也强调 tombstone 是 Agent 上的一个属性，不应触发 Set 折叠成「两个不同的 Agent」）。`Set<Agent>.contains()` 的语义本就是「该 ID 是否在集合中」，与 `Agent.removedAt` 无关。

### 改动文件

| 文件 | 改动 |
|---|---|
| `lib/domain/models/agent.dart:154-164` | `==` 改为只比 `localId`；`hashCode` 同步改为 `localId.hashCode`；docstring 明确说明双层语义。 |
| `test/domain/models/agent_test.dart` | 新增 `group('Agent.operator == identity-only (US-021 + Finding #7 fix)')`：1) tombstone vs alive 同 localId == 应 true（与未修改前相反）；2) tombstone state 必须能被 contentEquals 检出。同步更新现有 `Agent equality (US-021)` group 注释，把"alive vs tombstoned 不相等"改成"contentEquals 不相等"（== 可能仍相等）。 |

### TDD 顺序（Law 17 — domain RED-first）

1. **RED**: 改 `test/domain/models/agent_test.dart` 加新断言（alive vs tombstoned 在 contentEquals 层不等、在 == 层相等）。
2. **GREEN**: 改 `agent.dart` `==`/`hashCode`。
3. **REFACTOR**: 更新 `Agent equality (US-021)` group 的断言期望 + 注释。

### 风险与边界

- `grep -rn "Set<Agent>\|Map<Agent" lib/ test/` 0 命中 → 改动 `==` 不会破坏任何 dedup。
- `Agent.removedAt` 字段仍存在（US-021 DB 写入路径仍工作），仅是 `==` 不再参与。
- 所有现有 `==` 使用方：
  - `Agent` 在 `ChatSessionState.messages` / `AgentDetailData.agent` 等结构里通过 `state == other` 比较 → 这些结构都包含 Agent 的「内容字段」比较，**不依赖 `==` 区分 tombstone 状态**（验证：grep `state == other` 或 `value == other` 0 命中 at Agent level）→ 安全。
  - `_setAgent` 的 contentEquals guard → **完全不依赖 `==`**（用 contentEquals 显式调用）→ 安全。

---

## Fix #8: 抽 `AgentReactiveState` mixin 共享 `_setAgent`

### 设计

抽 `mixin AgentReactiveState<S>`：

- 持有 `Agent? _agent` 字段。
- 暴露 `Agent? get agent => _agent;`。
- 暴露 `void _setAgent(Agent? agent)`，内部用 `Agent.contentEquals` 守卫，过滤掉同内容重复 emit，触发外部提供的 `contentRevision` bump。
- 暴露 `@visibleForTesting void debugSetAgent(Agent? agent) => _setAgent(agent);`。

mixin 的泛型 `S` 是 state 类型（`ChatSessionState` / `AgentProfileState`）。contentRevision bump 通过传入 `int Function(S) getContentRevision` + `S Function(S, int) withContentRevision` 两个访问器实现——避免 mixin 依赖具体 State 类型。

### 改动文件

| 文件 | 改动 |
|---|---|
| `lib/features/_shared/agent_reactive_state.dart`（新建） | mixin 定义 + docstring 引用 #8 finding。 |
| `lib/features/chat_room/viewmodels/chat_view_model.dart:219, 320-344` | (a) 删 `Agent? _agent;` + `agent` getter + `_setAgent` + `debugSetAgent`；(b) `with mixin AgentReactiveState<ChatSessionState>`，构造函数里 `withContentRevision: (s, r) => s.copyWith(contentRevision: r)` + `getContentRevision: (s) => s.contentRevision`；(c) `state = ...` 调用替换为 mixin 内 helper `bumpContentRevision()`（mixin 内 update via `super.state`）。 |
| `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart:165-172, 182-195` | 同上对称修改。 |
| `test/features/_shared/agent_reactive_state_test.dart`（新建） | mixin 单元测试：1) 两个内容相同的 Agent 不 bump revision；2) 内容不同的 Agent bump；3) null 转换总是 propagate；4) debugSetAgent 等价于 _setAgent。 |

### 设计权衡

**为什么 mixin 而非基类**：两个 VM 都继承 `StateNotifier<XxxState>`，但 `StateNotifier<X>` 不支持 mixin 泛型同时保留状态类型——mixin 通过 `with` 组合，基类需要 `extends ReactiveAgentNotifier<S extends StateNotifier<S>>` 自递归类型参数，复杂度更高。mixin 形态 `with AgentReactiveState<ChatSessionState>` 直接被现有 `class ChatViewModel extends StateNotifier<ChatSessionState> with AgentReactiveState<ChatSessionState>` 接受。

**为什么不用 mixin 自身持有 state**：mixin 不应越权持有外部 `state`——`_setAgent` 的 bump 通过访问器回调实现，VM 仍是 state 的唯一所有者。Mixin 只负责「filter + 决定是否 bump」，把"如何 apply 到 state"留给 VM。

### TDD 顺序

1. **RED**: 先写 `test/features/_shared/agent_reactive_state_test.dart`，构造 fake StateNotifier + stub state 验证 mixin 行为（contentEquals 守卫 / null propagation / debugSetAgent）。
2. **GREEN**: 实现 mixin。
3. **REFACTOR**: 在两个 VM 应用 mixin，删除重复代码；跑全量回归确认行为不变。

### 风险与边界

- mixin 在 `_shared` 目录新建。Layer 依赖规则：features/_shared 不会被 domain/ 导入；UI 用例共享 utilities 在 ui_kit/ 已经存在，mixin 是 ViewModel 间共享的 helper，放 features/_shared 合适。
- contentEquals 守卫逻辑保持完全一致（从 `_setAgent` 抄过来），行为零变化。
- `debugSetAgent` 的 `@visibleForTesting` 注解移到 mixin 上 → 测试 imports `package:claw_hub/features/_shared/agent_reactive_state.dart` 后能用，但生产代码不会暴露。

---

## Fix #9: extension `Agent?.isTombstoned` 抽提

### 设计

在 `lib/domain/models/agent.dart` 内追加 `extension AgentTombstonedExt on Agent?`：

```dart
/// Returns true iff the Agent has been tombstoned by the Gateway
/// (US-021 removedAt != null).  Null-safe: null → false (Agent not loaded).
///
/// Replaces the `agent?.isRemoved ?? false` pattern repeated across UI / VM
/// call sites (chat_room_page / agent_profile_page / agent_config_page).
/// Centralizes the null-check so future signature changes (e.g. adding
/// hiddenAt guard) only need to touch this extension.
extension AgentTombstonedExt on Agent? {
  bool get isTombstoned => this?.isRemoved ?? false;
}
```

### 改动文件

| 文件 | 改动 |
|---|---|
| `lib/domain/models/agent.dart` | 加 `extension AgentTombstonedExt on Agent?` + docstring。 |
| `lib/features/chat_room/chat_room_page.dart:150` | `if (agent?.isRemoved ?? false)` → `if (agent.isTombstoned)`。 |
| `lib/features/agent_profile/agent_profile_page.dart:68` | `if (vm.agent?.isRemoved ?? false)` → `if (vm.agent.isTombstoned)`。 |
| `lib/features/agent_profile/agent_config_page.dart:344` | `if (vm.agent?.isRemoved ?? false)` → `if (vm.agent.isTombstoned)`。 |
| `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart:365, 409, 458` | `if (_agent!.isRemoved)` 三处保留 `!_agent!.isRemoved`（非 null context，已经经过 `_agent == null` 早退；改成 `!_agent.isTombstoned` 等价但语义模糊——这里 `_agent` 已是 non-null），不修改以保持局部语义清晰。 |
| `test/domain/models/agent_test.dart` | 新增 `group('AgentTombstonedExt (Finding #9 fix)')`：1) null → false；2) alive → false；3) tombstoned → true。 |

### TDD 顺序

1. **RED**: 先写 `agent_test.dart` extension 测试。
2. **GREEN**: 加 extension。
3. **REFACTOR**: UI 三处替换 + 全量回归。

### 风险与边界

- domain layer 加 extension：Law 1 仍满足（无 Flutter / drift 导入）。Extension on nullable type 允许 `agent?.isRemoved ?? false` 和 `agent.isTombstoned` 完全等价调用——前者保持语义兼容（如果调用点忘记切换，行为不变）。
- AgentProfileViewModel 内 `_agent!.isRemoved` 三处不动：这些是已 null-checked 的本地变量，extension 提供的 `isTombstoned` 语义是「null → false」，但此处业务语义是「_agent 必须已 loaded」——混用会让代码意图模糊。

---

## 实施顺序与验证

### 顺序

1. **#7 先做**：改了 == 会影响后续代码对 Set/Map 的预期，但 mixin 抽取不需要依赖 #7 的新 == 行为——两个修复正交。
2. **#9 第二**：extension 加完，UI 三处替换；但 ViewModel 内部 `_agent!.isRemoved` 保留（业务语义不同）。
3. **#8 最后**：mixin 抽取是最高风险步骤（涉及 2 个 VM 大段删除 + mixin 引入），依赖前两个修复到位后做全量回归更稳。

### 验证

```bash
# Fix #7
flutter test test/domain/models/agent_test.dart
# Fix #9
flutter test test/domain/models/agent_test.dart
# Fix #8
flutter test test/features/chat_room/chat_view_model_refresh_agent_test.dart
flutter test test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart
flutter test test/features/agent_profile/providers/agent_profile_provider_test.dart
flutter test test/features/agent_profile/agent_profile_page_test.dart
flutter test test/features/agent_profile/agent_config_page_test.dart

# 全量
flutter test
# Iron Laws
git add -A && git diff --cached --name-only | grep '\.dart$' | xargs ./scripts/pre-commit
# 静态分析
flutter analyze
```

### 预期结果

- 3 个修复后，4 处 `agent?.isRemoved ?? false` → `agent.isTombstoned`，2 处 `_setAgent` 共用 mixin，`Agent.==` 退回 identity-only。
- 现有 1317 tests + 新增的 ~5 个测试全绿。
- Iron Laws pre-commit hook 无新违例。
- `flutter analyze` 无新 warning。

---

## 范围之外（明确不做）

- 不动 `Agent.copyWith` 的 sentinel 模式改造（历史欠债）。
- 不动 pre-existing `search_view_model.dart` tombstone guard（review 标注属于历史代码，独立后续清理）。
- 不引入 Equatable 依赖（项目当前无 Equatable，引入会扩散风格不一致）。
- 不修改 `_setAgent` 的 contentEquals 守卫策略（仅去重，行为不变）。
- 不修改任何 state class 的 `contentRevision` 字段语义。