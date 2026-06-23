# ADR 0001: 广播流晚订阅者修复方案

- **状态**：已采纳
- **日期**：2026-06-22
- **驱动问题**："同一个实例，不同 agent 进入聊天页后部分 agent 显示'连接已断开，正在重连...'"

## 背景

`IGatewayClient.connectionStateStream`（`lib/core/acl/i_gateway_client.dart:39`）是业务层唯一可观察 Gateway 连接状态的入口。同一实例下的多个 agent 共享同一条广播流。

### 触发场景

- 用户已连接实例 A，`orchestrator` 在启动时建立 WebSocket 并进入 `connected`
- 用户打开 agent A 的聊天页 → `ChatViewModel._init()` 订阅流 → 收到 `connected` → banner 隐藏 ✓
- 用户打开 agent B 的聊天页（晚订阅者）→ `ChatViewModel._init()` 订阅流 → **收不到任何事件**（broadcast 无 replay）→ `ChatSessionState.connectionState` 停留在默认值 `GatewayConnectionState.disconnected` → `ConnectionBanner` 误显示"连接已断开，正在重连..."

### 根因

`StreamController<GatewayConnectionState>.broadcast()` 不缓存历史事件；`ChatSessionState.connectionState` 默认值是 `disconnected`（`chat_view_model.dart:70`）；晚订阅者二者的组合必然导致误报。

### 约束

- `IGatewayClient` 契约不能轻易变更（3 个上层订阅方：`ConnectionOrchestrator`、`NotificationCoordinator`、`ChatViewModel`）
- 必须不破坏 `ConnectionOrchestrator` 的 `_connecting` 锁时序与事件语义

## 决策

**方案 H + 方案 B 组合**：在 ACL 层引入 `ReplayableConnectionState` 封装类（`lib/core/acl/replayable_connection_state.dart`），向晚订阅者下沉**仅当最后状态为 `connected` 时的初始事件**。

### 核心规则

1. **封装双源真相**：把"最后已知状态"标量与广播 `StreamController` 收敛到单一类 `ReplayableConnectionState`。新增发射点（`emit` / `clear`）无法绕过缓存同步，杜绝"漏改一处"导致的 bug 复发。
2. **仅 seed `connected`**：`stream` getter 在 `last == connected` 时下发 seed，其他情况（含 `null` / `connecting` / `recovering` / 各终态）返回纯广播流。
3. **`_cleanup` 无条件 `clear()`**：`_cleanup(emitDisconnected: false)` 路径（connect() 复用已有 conn 时）必须把 last 缓存置 `null`，否则在 `await` 新 `manager.connect()` 完成前，晚订阅者会拿到陈旧 `connected` seed 而真实底层 manager 已 dispose。
4. **`resetConnectionState` 经封装发射**：必须调用 `ReplayableConnectionState.emit(disconnected)` 而非直接 `ctrl.add`，避免 last 缓存与广播事件不同步。

### 不变量

- `last == connected` ⇔ 当前**真实**连接处于 `connected` 状态
- `last == null` ⇔ 从未连接过 或 已被 `_cleanup` 重置
- 任何 `emit` 操作同时更新 last 与广播事件，原子、不可分

## 后果

### 正面

- 修复报告的 bug：晚订阅者立即收到真实状态，UI 不再误报断连
- 根除双源真相反模式：问题 1（`resetConnectionState` 漏更新 last）和问题 2（`_cleanup` 不更新 last）作为同一根因的实例被一起消除
- 一次性根治所有流订阅方（orchestrator、coordinator、ChatViewModel）
- 接口 `IGatewayClient` 签名不变，对调用方零侵入

### 负面 / 已知边界

- **`recovering` / `connecting` / 终态实例的晚订阅者不获得 seed**：UI 仍会显示默认 `disconnected` banner。这是修复的设计取舍 —— seed 终态会破坏 orchestrator 的锁时序与 Bug 3 守卫（详见 `connectionStateStream` 注释）。这些场景下，ChatViewModel 可另行从 DB `HealthStatus` 兜底（属于不同 fix，见下方"未决问题"）。
- **刷新已连接实例的"重复 agent 同步"**：`reconnect()` 不会先 disconnect 就重订阅，此时 seed=connected 会在新 manager 建立前触发一次基于旧 manager 的幂等 agent 同步。该路径本就有独立的 manager 泄漏问题（非本次引入）。
- **封装类内部 `Stream.value` + `async*` 微任务调度**：seed 通过 microtask 投递，与 broadcast 事件投递时序一致；测试已验证 `pumpMicrotasks()` 之后可见。

## 替代方案

### A. rxdart BehaviorSubject

- **优点**：标准做法，`stream` 自带 `value` + replay，零自封装代码
- **缺点**：新增 `rxdart` 依赖，违反项目"最小依赖"立场（Iron Laws 风格）
- **未采纳**：项目目前零外部流操作库依赖

### B. 给 `IGatewayClient` 加 `getConnectionState(instanceId)` 同步方法

- **优点**：调用方显式同步读，不依赖流语义
- **缺点**：调用方必须"先读后订阅"两步走，时序窗口内仍可能丢失事件；接口膨胀；多个订阅方各自打补丁
- **未采纳**：治标不治本

### C. `ChatViewModel` 读 DB `HealthStatus` 兜底（仅修 ViewModel）

- **优点**：改动最小，仅 5 行；不动 ACL 层
- **缺点**：仅修 `ChatViewModel` 一处；其他订阅方（未来的）仍会踩坑；ViewModel 层多了一个职责
- **未采纳**（作为本次主方案）：决策 ACL 层根治，所有订阅方受益；可作为 `recovering` 等场景的补充方案

### D. `followedBy` 注入 + 早订阅者兼容（subagent 初提方案）

- **缺点**：会向 `ConnectionOrchestrator` 注入多余的 `disconnected` 初始事件，触发 `_connecting` 锁提前释放；`Stream.value.followedBy` 返回单订阅流，破坏 `IGatewayClient` 的广播语义契约
- **未采纳**：详见 systematic-debugging 评估记录

## 实现要点

- `lib/core/acl/replayable_connection_state.dart`：封装类（~80 行）
- `lib/core/acl/ws_gateway_client.dart`：`_InstanceConnection.connectionState` 字段替换为封装；订阅回调 / `_cleanup` / `resetConnectionState` / `connectionStateStream` / `dispose` 迁移到封装 API
- `lib/core/acl/mock_gateway_client.dart`：对齐 Ws 的行为
- 测试覆盖：5 个 `ReplayableConnectionState` 单元测试 + 4 个 Ws 端到端测试（late subscriber gets seed / disconnected no seed / resetConnectionState no stale / connect-reuse no stale）

## 未决问题

- **`recovering` 场景的 ChatViewModel DB 兜底**（问题 4）：晚订阅者在实例 recovering 时仍显示默认 disconnected → banner 误报"连接已断开，正在重连..."。建议作为独立任务处理：从 `instanceListProvider` 或新增 `currentHealthStatus(instanceId)` provider 在订阅前一次性读取 DB。属于本次修复的边界外。

## 相关引用

- 系统化调试记录：会话内 "systematic-debugging" 调用
- 方案推演记录：会话内 "coding-advisor" 调用
- Iron Laws：Law 17（TDD，ACL 层测试先行）