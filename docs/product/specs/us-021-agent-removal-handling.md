# US-021：Gateway 端 Agent 删除的本地处理（Tombstone）

**Spec Owner**: NING MEI
**Status**: Draft — pending implementation
**Created**: 2026-06-23
**User Story**: [US-021](../user-stories.md#us-021gateway-端-agent-删除的本地处理tombstone)
**Architecture Review**: 已完成（4 维度专家 + Skeptic 调停）
**Iron Laws Gate**: Law 1（Domain pure）/ Law 6（batch query）/ Law 8（无空 catch）/ Law 17（TDD）

---

## 1. 问题陈述

### 当前行为

`DriftAgentRepo.syncFromGateway`（`lib/data/repositories/drift_agent_repo.dart:65-113`）是**纯 Upsert**——只对远端 `agents.list` 返回的 Agent 做 insert/update，从不处理"本地有而远端没有"的差集。

### 引发的实际问题

1. **幽灵虾**：Gateway 端 admin 调用 `agents.delete` 移除某 Agent 后，本地行永久残留，继续显示在 AgentList、MessageHub、Search 中。
2. **FAILED 消息死循环**：用户进入幽灵虾的 ChatRoom 发消息 → Gateway 返回 `agent_not_found` → 消息变 FAILED → `OutboxProcessor`（`lib/domain/usecases/outbox_processor.dart:145-155`）下次 flush 重新尝试 → 仍失败 → 重复到 24h 过期。
3. **协议侧无推送**：OpenClaw v4 协议（`docs/technical/api-protocol.md:1442-1480`）的 `agents.list` 响应是单层 `agents` 数组，**无 `agent_removed` / `agent_deleted` 事件、无 pagination 字段**——App 端只能通过下次 `agents.list` 的差集推断远端删除。

---

## 2. 设计决策

经过多轮评估（见会话记录与架构评审委员会报告），核心决策如下：

### 2.1 整体方向：Tombstone 拆分列（修订版 Option C）

| 维度 | 决策 | 理由 |
|---|---|---|
| **数据模型** | 软删 + 双列正交 | 历史消息保留；sync 与 user 写入路径不冲突 |
| **列结构** | `removed_at`（sync 独占）+ `hidden_at`（user 独占，v1 预留不写） | 防止 Option B 合并列的"sync auto-revival 误复活用户隐藏"BUG |
| **API 形态** | 全部封装在 `DriftAgentRepo` 内部，**不扩展 `IAgentRepo` 接口** | 避免接口冗余；in-memory 实现不被拖入 |
| **完整性保护** | 不加 guard，相信协议契约 | scope 不足时 `fetchAgents` 抛错被上层接住；`agents: []` 在协议下唯一含义为"真无 agent"；加 guard 反而会复活原 BUG |
| **UI 影响** | 仅默认过滤 `getAll` / `getByInstanceId`；不加开关、不加 sheet | YAGNI；先解决"消息死循环"主诉求 |

### 2.2 拒绝的方案

- **Option A（硬删 + FK CASCADE）**：永久丢失 messages/conversations；`agent_stats` 缓存表已于 round 3B 删除（统计走 use case 全量聚合），所以不在此担忧范围；远端误判时无法恢复；`syncFromGateway` 还需复刻 `deleteByInstanceId` 的 FTS5 purge 逻辑（当前缺失）。
- **Option B（tombstone 合并列）**：sync 的 auto-revival 与"用户隐藏"语义冲突——用户隐藏后 10 秒内 Agent 又冒出来。
- **Option D（纯 hidden bool）**：无时间戳、无原因区分、无 sync 保护；只是把问题换了个壳。

### 2.3 关于 `removed_reason` 列

**v1 不加**。当前无消费者代码，加了即死列。YAGNI。如未来需要展示"为什么消失"，再走一次小型 migration。

### 2.4 关于"延迟 tombstone"（连续两次 sync 才打标）

**v1 不做**。`ConnectionOrchestrator` 已有重连+重试机制，且协议无分页，单次失败的概率本就低。若上线后观察到误打标，再加状态字段 `suspected_missing_since`。

---

## 3. v1 范围（本 Story）

### 3.1 文件清单

| 文件 | 改动类型 | 行数估算 |
|---|---|---|
| `lib/data/local/database/schema.drift` | 加 2 列（`removed_at`、`hidden_at`） | ~4 行 |
| `lib/data/local/database/database.dart` | `schemaVersion` bump 5→6；`onUpgrade` 加 `if (from < 6)` 分支用 `migrator.addColumn(agents, agents.removedAt)` / `migrator.addColumn(agents, agents.hiddenAt)` | ~5 行 |
| `lib/data/local/database/database.g.dart` | 自动重生成（`dart run build_runner build --delete-conflicting-outputs`） | 由 codegen 决定 |
| `lib/domain/models/agent.dart` | 加 2 个 `final int?` 字段（`removedAt` / `hiddenAt`，毫秒时间戳）+ 构造函数追加 2 个可选命名参数 + `copyWith` body 显式透传（**不暴露这两个参数**，见下）+ 加 2 个 getter (`isRemoved` / `isHidden`) | ~15 行 |
| `lib/data/local/mapping/agent_mapper.dart` | 双向映射新列；这是**唯一**允许"内存中刷新 tombstone 状态"的路径 | ~4 行 |
| `lib/data/repositories/drift_agent_repo.dart` | `syncFromGateway` 加 diff（batch SQL，Law 6 合规）；`getAll` / `getByInstanceId` 改调新命名查询加默认过滤 | ~40 行 |
| `lib/domain/usecases/outbox_processor.dart` | guard 从 `agent == null` 改为 `agent == null \|\| agent.isRemoved`；v1.1 升级为批量转 `MessageStatus.expired`（`outbox_processor.dart:147-156, 190-209`） | ~3 行（v1）+ ~20 行（v1.1 EXPIRED 批量） |
| `lib/features/message_hub/providers/message_hub_providers.dart` | `conversationListProvider:67-69` guard 用 `isRemoved` skip tombstoned conversation（**注：实际通过 watch `agentSyncTickerProvider` 自动失效，无需 `providers.dart` 显式 invalidate**） | ~3 行 |
| `lib/app/di/providers.dart` | 无需修改：`AgentsSyncedEvent` 已通过 `agentSyncTickerProvider` 触发所有订阅它的 provider 重建；`message_hub_providers.dart:40` 已在 watch ticker | 0 行 |
| `lib/features/chat_room/chat_room_page.dart` | 路由 guard：`build` 中检查 `agent.isRemoved`，是则渲染 `AgentRemovedPlaceholder` 占位页（`lib/ui_kit/placeholders/agent_removed_placeholder.dart`），与 AgentProfilePage / AgentConfigPage 共用 widget | ~15 行 |
| `lib/features/chat_room/viewmodels/chat_view_model.dart` | `send()` 入 outbox 前重查 `agent.isRemoved`，是则拒发并 emit 关闭信号；三道护栏：init 缓存、`_tombstoneSuspect` 标志、refreshAgent 复活路径 | ~10 行 |
| **测试文件** | 详见 §6 | 见下 |

**总计**：~11 个生产代码文件，~101 行净增量；5-6 个新测试文件 / 用例组。

### 3.2 Schema 变更（drift）与 Migration

**schema.drift**（agents 表追加 2 列）：

```drift
removed_at INTEGER NULL,   -- Gateway sync 独占写入；非空表示远端已删除
hidden_at  INTEGER NULL,   -- v2 预留：用户主动隐藏；v1 不写入
```

**database.dart**（bump schemaVersion + onUpgrade 分支）：

```dart
@override
int get schemaVersion => 7;  // 原 5

@override
MigrationStrategy get migration {
  return MigrationStrategy(
    // ... onCreate / beforeOpen 不变 ...
    onUpgrade: (migrator, from, to) async {
      // ... 原有 from < 2/3/4/5 分支不变 ...
      if (from < 6) {
        // US-021: Agent tombstone 列。nullable add column 是 SQLite O(1) 操作
        // （只改 schema 不重写行），无需 backfill。
        await migrator.addColumn(agents, agents.removedAt);
        await migrator.addColumn(agents, agents.hiddenAt);
      }
      if (from < 7) {
        // 后置 US-019 重构：删除 agent_stats 缓存表（round 3B）。
        // 统计改走 use case 全量实时聚合，无迁移数据需求。
        await migrator.deleteTable('agent_stats');
      }
    },
  );
}
```

**Schema 版本演进历史**（实施后追补）：
- v5 → v6（本 Story）：tombstone 列 + `getAllActiveAgents`/`getActiveAgentsByInstance` 命名查询
- v6 → v7（后续 US-019 重构）：删除 `agent_stats` 缓存表；统计改 use case 实时聚合

**关于 `insertAgent` 命名查询（已 grep 确认，必须改）**：`schema.drift:175-178` 的 `insertAgent` 是显式命名查询，写死了 11 列。加列后**必须**追加新列到 INSERT 列表，否则 codegen 报错或新插入的 agent `removed_at`/`hidden_at` 始终为 DB default（SQLite 对 INSERT 缺列会填 NULL，本项目这里碰巧可接受，但仍应显式列出来保持一致性）。建议追加 `, removed_at, hidden_at` 与 VALUES 末尾两个 `:removedAt, :hiddenAt`，调用方传 `null`。

**新增命名查询（v1 必须加）**：

```drift
-- 默认过滤的活跃 agent 查询（替代 getAllAgents / getAgentsByInstance 在 active 路径的调用）
getAllActiveAgents: SELECT * FROM agents WHERE removed_at IS NULL AND hidden_at IS NULL ORDER BY is_pinned DESC, name ASC;
getActiveAgentsByInstance: SELECT * FROM agents WHERE instance_id = :instanceId AND removed_at IS NULL AND hidden_at IS NULL ORDER BY is_pinned DESC, name ASC;
```

**注意 1**：原 `getAllAgents` / `getAgentsByInstance` 命名查询**保留不动**——`deleteByInstanceId`（drift_agent_repo.dart:221）的清理逻辑和未来"显示已移除"开关都会用到未过滤版。

**注意 2**：tombstone 写入/复活**不走命名查询**，而是 §3.3 的两条 batch `customStatement` UPDATE（Law 6 要求 batch，命名查询是单行 update 无法表达 `NOT IN (...)` 批量）。早先版本提到过的 `setAgentRemovedAt` 命名查询已废弃——不要加，加了也是死代码。

**Codegen 顺序（关键，错了会编译失败）**：

```
1. 改 schema.drift（加 2 列 + 改 insertAgent VALUES + 加 3 个新命名查询）
2. dart run build_runner build --delete-conflicting-outputs
   → database.g.dart 重新生成，agents table getter 出现 removedAt/hiddenAt 字段，
     新命名查询变为 AppDatabase 方法
3. 改 database.dart（bump schemaVersion=6 + 写 onUpgrade 的 migrator.addColumn）
   ← 必须在步骤 2 之后，否则 agents.removedAt 编译失败
4. 改 agent_mapper.dart / drift_agent_repo.dart（消费新列、调用新命名查询）
```

漏掉步骤 3（bump schemaVersion）的后果：升级用户启动 app 时 Drift 检测 `user_version=5` vs `schemaVersion=6` 不匹配，抛 schema validation 异常 → app crash。

### 3.3 关键代码改动（伪代码）

**`Agent` model（手写 class，非 freezed）** —— 关键设计：

```dart
// agent.dart 改动
final int? removedAt;  // millisecondsSinceEpoch；DriftAgentRepo.syncFromGateway 独占写入
final int? hiddenAt;   // v2 预留；v1 期间没有任何写入路径

bool get isRemoved => removedAt != null;
bool get isHidden  => hiddenAt  != null;

// 构造函数加 2 个可选命名参数：
this.removedAt,
this.hiddenAt,

// copyWith 故意 *不* 暴露 removedAt / hiddenAt 参数 —— 强制所有
// "改 tombstone 状态" 走 DB 命名查询（如 setAgentRemovedAt）：
Agent copyWith({ /* 原有参数 */ }) {
  return Agent(
    /* 原有 */
    removedAt: this.removedAt,  // 透传，外部无法覆盖
    hiddenAt: this.hiddenAt,
  );
}
```

**为什么 copyWith 不暴露这两个参数**：现有 `Agent.copyWith` 用经典的 `nickname: nickname ?? this.nickname` 模式（agent.dart:78），这种模式**无法清空 nullable 字段**——`copyWith(nickname: null)` 会被解读为"保持原值"。项目里 `clearAvatar`（drift_agent_repo.dart:197）和 `CopyWithSentinel`（core/utils/copy_with_nullable.dart）就是为绕这个老坑而生的。如果 `copyWith` 暴露 `removedAt` 参数，未来某人写 `agent.copyWith(removedAt: null)` 想清 tombstone 实际上会失败，且毫无报错。直接不暴露，强制走 `DriftAgentRepo` 的 DB 命名查询，是 v1 最小代价的稳妥方案。整改 `Agent.copyWith` 用 `CopyWithSentinel` 模式是历史欠债，不在 US-021 范围内。

**88 个 `Agent(...)` 直接构造点不需要动**：grep `lib/ test/` 确认全项目 88 处直接 `Agent(...)` 构造点，因为新字段是 nullable + 默认 null，添加后仍编译通过。

---

**`DriftAgentRepo.syncFromGateway`** —— 在现有 transaction 内追加 diff 步骤：

```dart
await _database.transaction(() async {
  // 1) 现有 upsert 循环（保持不变）—— 用 Drift typed insert/update，
  //    不用 customStatement（agents 表目前无 .watch() stream，但 upsert
  //    路径本就走 companion，保持现状）。
  //
  //    *** 顺序不可换 ***：upsert 必须在 diff 之前。diff 的 `NOT IN (remoteIds)`
  //    依赖 remoteIds 是完整的远端列表（含本次刚 upsert 的新 agent）。
  //    若把 diff 提前，新 upsert 的 agent 会因不在旧 remoteIds 里被误 tombstone。
  for (final remote in remoteAgents) { ... }

  // 2) 差集 → tombstone / 复活（batch SQL，Law 6 合规）
  //
  //    协议契约：scope 不足时 fetchAgents 抛错被上层接住，
  //    `agents: []` 在协议下唯一含义为"Gateway 真无 agent"，
  //    必须正常走 tombstone（而非"空列表跳过"），否则用户清空 Gateway
  //    后本地仍残留幽灵虾——这正是 US-021 要修的原 BUG。
  //
  //    用两条 UPDATE 替代 N 行逐行写入：Law 6 禁止 for...await repo/DB 的
  //    N+1 模式，pre-commit hook 的正则会拦下逐行写法（且即便 hook 只 grep
  //    `repo.`，逐行 await _database 也违反 Law 6 精神，manual audit 会抓）。
  //
  //    customStatement 选择：本项目 agents 表当前无 .watch() stream 查询
  //    （grep 确认 lib/data/local/database/database.dart 无 agent 相关 watch，
  //    drift_agent_repo.dart 无 .watch()），UI 全走 agentSyncTickerProvider
  //    脚踏式刷新，故 customStatement 的"不触发 stream 失效"特性对本改动无影响。
  //    未来若给 agents 加 watch，需改用 Drift typed update。
  //
  //    do-while 重入安全：ConnectionOrchestrator._syncAgentsForInstance 的
  //    pending-retry 循环可能对同一实例多次 sync。SQL 的
  //    `WHERE removed_at IS [NOT] NULL` guard 保证同一 agent 不会重复打标/复活
  //    —— 已 tombstoned 的 agent 第二轮 sync 仍缺失时，因 `removed_at IS NULL`
  //    不匹配而跳过；已复活的 agent 第二轮仍在远端时，因
  //    `removed_at IS NOT NULL` 不匹配而跳过。天然幂等。
  final remoteIds = remoteAgents.map((a) => a.remoteId).toList();
  final placeholders = remoteIds.map((_) => '?').join(', ');
  // removed_at 存毫秒（DateTime.now().millisecondsSinceEpoch）。
  // 注意：与 agents.created_at 的秒精度不同（agent.dart:33 ~/ 1000）。
  // 毫秒精度用于排序和"已移除多久"展示，SQLite INTEGER 不会溢出。
  // 跨列时间计算时注意单位换算。
  final now = DateTime.now().millisecondsSinceEpoch;

  // 2a) tombstone：本地存在、远端缺失、且尚未 tombstoned 的 agent
  if (remoteIds.isEmpty) {
    // 远端一个都没有 → 本实例所有 active agent 全部 tombstone
    await _database.customStatement(
      'UPDATE agents SET removed_at = ? '
      'WHERE instance_id = ? AND removed_at IS NULL',
      [now, instanceId],
    );
  } else {
    await _database.customStatement(
      'UPDATE agents SET removed_at = ? '
      'WHERE instance_id = ? AND removed_at IS NULL '
      'AND remote_id NOT IN ($placeholders)',
      [now, instanceId, ...remoteIds],
    );

    // 2b) 复活：远端又出现、且当前 tombstoned 的 agent
    await _database.customStatement(
      'UPDATE agents SET removed_at = NULL '
      'WHERE instance_id = ? AND removed_at IS NOT NULL '
      'AND remote_id IN ($placeholders)',
      [instanceId, ...remoteIds],
    );
  }
});
```

**`getAll` / `getByInstanceId`** —— 默认过滤：

```dart
@override
Future<List<Agent>> getAll() async {
  // 默认过滤 removed_at 和 hidden_at 均为 NULL 的 active agents
  final rows = await _database.getAllActiveAgents().get();
  return rows.map(AgentMapper.toDomain).toList();
}
```

**`getById`** —— **不过滤**（重要！下游 OutboxProcessor、conversationListProvider 依赖此契约）：

```dart
/// **不过滤 tombstoned/hidden agents** —— 调用方需通过 [Agent.isRemoved] /
/// [Agent.isHidden] 自行判断。改动此契约会破坏 OutboxProcessor 与
/// conversationListProvider 的现有 null-skip 模式。
@override
Future<Agent?> getById(String localId) async { ... }
```

**`OutboxProcessor.process()`** —— guard 升级（`outbox_processor.dart:149`）：

```dart
if (agent == null || agent.isRemoved) {
  _logger.info(
    '[OutboxProcessor] Skipped: agent ${message.agentId} '
    '${agent == null ? "not found" : "tombstoned"} '
    'for message ${message.clientId}',
  );
  continue;
}
```

**Provider 失效传播** —— 实际方案**不**用 `ref.invalidate`：

```dart
// lib/app/di/providers.dart - AgentsSyncedEvent 分支（无需修改）
case AgentsSyncedEvent():
  ref.read(agentSyncTickerProvider.notifier).state++;
```

**为什么不需要 `ref.invalidate`**：`message_hub_providers.dart:40` 的 `conversationListProvider` 实际已 `ref.watch(agentSyncTickerProvider)`（不同于本 spec 原稿假设的"未订阅 ticker"）。ticker 在 `AgentsSyncedEvent` 触发时递增，所有 watch 它的 provider 自动重建——`agentListProvider`、`conversationListProvider`、未来任何 watch ticker 的 provider 一并失效。**比 `ref.invalidate` 更通用**：未来若新增依赖 agent 数据的 provider，只需在定义处加一行 `ref.watch(agentSyncTickerProvider)` 即自动跟随 sync 刷新，无需逐个手工 invalidate。

`OutboxProcessor` 不受此问题影响——它每次调度 `process()` 时重新 `getById`，拿到的总是最新 DB 值。

**ChatViewModel watch 路径**：与上述 ticker 失效并行的还有 `drift_agent_repo.watchById`（`drift_agent_repo.dart:81-88`）。但 `syncFromGateway` 的 tombstone/revive 步骤用 `customStatement`，**不触发 `watchSingleOrNull` 的 stream 失效**。当前 ChatViewModel 通过 `agentSyncTickerProvider` 驱动的 `_tombstoneSuspect` 标志 + `refreshAgent`（`chat_view_model.dart:1066-1097`）作为双保险，**双保险设计有效但 `i_agent_repo.dart` 的 `watchById` docstring 未反映这一限制**——详见 §3.5 第 6 项。

### 3.4 不动的代码

- **`findByCompositeKey`**：必须保持不过滤——sync 复活逻辑依赖此查询找到 tombstoned agent。在方法注释中明确标注 `intentionally unfiltered`。
- **`deleteByInstanceId`**：保持硬删 + FK CASCADE 不变（实例都删了，tombstone 没意义）。在方法注释中说明与 tombstone 路径的语义差异。
- **`updateLocalProfile` / `togglePin` / `clearAvatar`**：不需要变动。
- **`IAgentRepo` 接口**：**零变更**。tombstone 字段是 `Agent` 上的 `final` + getter，通过 mapper 从 DB 读取注入；公共方法签名不变。`copyWith` **不暴露**这两个字段（见 §3.3）。
- **`in_memory_repos.dart`**：legacy 路径，不维护（CLAUDE.md 已说明）。

### 3.5 v1.x 实施中的 Silent Additions（spec 未记录但代码已落地）

按实施时序倒序：

1. **`AgentRemovedPlaceholder` widget 统一三处占位页**（v1.2）—— spec §3.1 描述 ChatRoom guard 为"inline pop + toast"，实际抽取为共享 widget（`lib/ui_kit/placeholders/agent_removed_placeholder.dart`），由 ChatRoom + AgentProfilePage + AgentConfigPage 共用，避免三处文案 drift。

2. **OutboxProcessor v1.1：tombstoned-agent 消息批量转 `MessageStatus.expired`**（`outbox_processor.dart:147-156, 190-209`）—— spec AC3 仅要求"跳过"，实际升级为批量 EXPIRED，避免 24h PENDING 卡死（旧 PENDING 消息不再无限重试）。

3. **`ChatViewModel.refreshAgent` + `_tombstoneSuspect` 标志**（`chat_view_model.dart:271, 1066-1097`）—— agent 同步完成后跨实例 ticker 驱动 ChatRoom UI 重建；`refreshAgent` 检测 tombstone→alive 后补订阅，防订阅泄漏。

4. **`watchById` + `chatSessionState.contentRevision`**（`chat_view_model.dart:244, 69-77`）—— 替代 revision 计数器 hack，让 `setAgent` 的 contentEquals-过滤 emit 触发 Riverpod rebuild。

5. **`Agent.contentEquals` + `operator ==` 拆为 identity-only**（`agent.dart:53-93, 168-176`）—— 修 Riverpod dedup blindspot（tombstone 转换不触发 rebuild）。由 `Model == Identity Blindspot` memory 文档驱动。

6. **`AgentTombstonedExt.isTombstoned` 扩展**（`agent.dart:198-200`）—— `agent?.isRemoved ?? false` 模式统一抽到 domain 层，三处 UI 改用。

7. **`getAllByInstanceId` 不过滤出口**（`drift_agent_repo.dart:18-34`）—— spec §3.4 仅列 `findByCompositeKey` 为不过滤，实际新增 `getAllByInstanceId`（host 切换警告场景使用），v2 "显示已移除" 开关会优先复用此方法。

---

## 4. v2 范围（US-022，本 Story 不做）

明确延后到独立 Story，预估 5 points：

- `IAgentRepo.hideAgent(localId)` / `unhideAgent(localId)` / `hardDelete(localId)` 公共接口
- "显示已移除" UI 开关（AgentList 顶部 toolbar）
- MessageHub 中已移除 Agent 的 conversation：点击后弹底部 sheet 展示最近 20 条消息（替代 ChatRoom 进入）
- "隐藏此 Agent" UI 入口（AgentProfile 配置页）
- 硬删按钮：事务清理 agent + conversations + messages + FTS5 + stats + achievements
- 部分列表保护阈值（基于 v1 上线后的生产观察决定是 50% / 70% / 不需要）

---

## 5. TDD 顺序（Law 17 强制）

**每一行 source 必须有对应 test 先红再绿。** 按下列文件顺序逐个推进：

### 5.1 Step 1 — `Agent` model 加 getter

1. **RED** `test/domain/models/agent_test.dart`：新增 group `tombstone state`，测试：
   - `isRemoved` 在 `removedAt != null` 时返回 true
   - `isHidden` 在 `hiddenAt != null` 时返回 true
   - 两者默认值（缺省构造）均为 false
   - `copyWith(removedAt: ...)` 正确传播
2. 运行测试 → 编译错误（getter 不存在） = 合法的 RED
3. **GREEN** 在 `lib/domain/models/agent.dart` 加 2 个 `final int?` 字段（`removedAt` / `hiddenAt`，毫秒）+ 构造函数 2 个可选命名参数 + `copyWith` 透传（不暴露）+ 2 个 getter。`Agent` 是手写 class 非 freezed，无需 build_runner。
4. 运行测试 → 全绿

### 5.2 Step 2 — Schema + Migration + Mapper

**Step 2a — Schema + Migration：**
1. **RED** `test/data/local/database/migration_v5_to_v6_test.dart`（新建）：参照现有 `migration_v4_to_v5_test.dart` 模式，用 raw SQL 插入 v5 形态的 agent 行 → 跑 v5→v6 迁移 → 断言：
   - `removed_at` / `hidden_at` 列存在且默认为 NULL
   - 现有 `theme_color` / `nickname` / `name` 等字段值不变
   - 迁移后 `getAgentByLocalId` 仍能查到行
2. 运行 → 编译错误（v6 未实现）= 合法 RED
3. **GREEN** 改 `schema.drift`（加 2 列 + 改 insertAgent VALUES + 加 3 个新命名查询）→ 跑 codegen → 改 `database.dart`（schemaVersion=6 + onUpgrade 加 `migrator.addColumn` 两行）
4. 运行 migration 测试 → 全绿；运行现有 `migration_v4_to_v5_test.dart` → 仍绿（回归）

**Step 2b — Mapper：**
1. **RED** `test/data/local/mapping/agent_mapper_test.dart`：测试 mapper 正确传递 `removed_at` ↔ `removedAt` 双向映射（含 null 与非 null 两种）
2. **GREEN** 修改 `agent_mapper.dart`
3. 运行 mapper 测试 + 现有 `drift_agent_repo_test.dart` → 全绿（默认值 null，不影响现有行为）

### 5.3 Step 3 — `syncFromGateway` diff 逻辑

1. **RED** 在 `test/data/repositories/drift_agent_repo_test.dart` 的 `syncFromGateway` group 内新增：
   - `tombstones agent that disappears from remote list`
   - `revives agent that reappears on remote list`
   - `does not touch hidden_at column`
   - `tombstones ALL agents when remote list is empty (协议契约：empty == truly empty)`
   - `preserves messages/conversations for tombstoned agents`
   - `is idempotent across repeated sync (do-while 重入不重复打标)`
2. **GREEN** 实施 §3.3 的 diff 逻辑（batch SQL，无 guard）
3. 运行测试 → 全绿；现有 `syncFromGateway upsert` 测试**必须**仍绿

### 5.4 Step 4 — `getAll` / `getByInstanceId` 默认过滤

1. **RED** 测试：
   - `getAll excludes tombstoned agents by default`
   - `getByInstanceId excludes tombstoned agents by default`
   - `getById returns tombstoned agent (unfiltered)` ← 关键契约测试
   - `findByCompositeKey returns tombstoned agent (unfiltered)` ← sync 复活依赖
2. **GREEN** 在 `schema.drift` 新增 `getAllActiveAgents` / `getActiveAgentsByInstance` 命名查询；修改 repo 方法调用新查询；`getById` / `findByCompositeKey` 保持不变
3. 运行测试 → 全绿

### 5.5 Step 5 — `OutboxProcessor` guard

1. **RED** 在 `test/domain/usecases/outbox_processor_test.dart` 新增：
   - `skips PENDING messages for tombstoned agents`
   - `skips FAILED messages for tombstoned agents`
   - `processes messages normally when agent is not tombstoned`
2. **GREEN** 改 `outbox_processor.dart:149` 的 guard 条件
3. 运行测试 → 全绿

### 5.6 Step 6 — ChatRoom 路由 guard + send 兜底

1. **RED** 在 `test/features/chat_room/chat_room_page_test.dart` 新增：
   - `tombstoned agent ChatRoom is popped after first frame with toast`
   - `active agent ChatRoom renders normally`
2. **RED** 在 `test/features/chat_room/chat_view_model_send_test.dart` 新增：
   - `send() refuses to enqueue when agent was tombstoned after init`
   - `send() emits closeRequested signal after refusing`
3. **GREEN** 在 `chat_room_page.dart` 的 `build` 起手 `ref.watch(agentRepoProvider).getById(agentId)`（FutureProvider 化）→ `data` 阶段若 `isRemoved` → `WidgetsBinding.instance.addPostFrameCallback((_) { Navigator.pop(); showSnackBar(...); })`
4. **GREEN** 在 `ChatViewModel.send()` 第一行（`init()` 后、`_startStreaming()` 前）加重查：`final fresh = await _agentRepo.getById(agentId); if (fresh?.isRemoved ?? false) { /* set state.closeRequested = true; toast; return; */ }`
5. 运行测试 → 全绿

### 5.7 Step 7 — 端到端集成测试

`test/integration/agent_tombstone_lifecycle_test.dart`（新建）—— 端到端验证：
1. mock `IGatewayClient.fetchAgents` 返回 `[A, B, C]` → sync → 本地有 3 个 active agent
2. mock 返回 `[A, B]` → sync → C 被 tombstone，`getAll` 返回 2 个
3. 给 C 发一条消息（PENDING）→ OutboxProcessor flush → 消息**不**变 FAILED
4. mock 返回 `[A, B, C]` → sync → C 复活，`getAll` 返回 3 个，C 的历史消息可见
5. mock 返回 `[]` → sync → 本地全部被 tombstone，`getAll` 返回 0 个，历史消息仍可在 messages 表查到

---

## 6. 测试覆盖矩阵

| 测试文件 | 类型 | 新增/修改 |
|---|---|---|
| `test/domain/models/agent_test.dart` | Unit | 修改（加 tombstone group） |
| `test/data/local/mapping/agent_mapper_test.dart` | Unit | 修改 |
| `test/data/local/database/migration_v5_to_v6_test.dart` | Integration（in-mem SQLite） | 新建（参照 v4_to_v5 模式） |
| `test/data/repositories/drift_agent_repo_test.dart` | Integration（in-mem SQLite） | 修改（加 5 个 sync 用例 + 4 个 query filter 用例） |
| `test/domain/usecases/outbox_processor_test.dart` | Unit | 修改（加 3 个 guard 用例） |
| `test/features/chat_room/chat_room_page_test.dart` | Widget | 修改（加路由 guard 用例） |
| `test/features/chat_room/chat_view_model_send_test.dart` | Unit | 修改（加 send 兜底用例） |
| `test/integration/agent_tombstone_lifecycle_test.dart` | E2E | 新建 |

---

## 7. 风险与缓解

| 风险 | 触发场景 | 缓解 |
|---|---|---|
| OutboxProcessor guard 遗漏 | 实施时只改 sync 没改 outbox | 强制同一 PR；§5 TDD Step 5 单独成步；review 时检查 `outbox_processor.dart:149` 必须改 |
| `findByCompositeKey` 误加过滤 | 后续维护者顺手"统一" | 方法注释 `// INTENTIONALLY UNFILTERED — sync revival depends on this` |
| **UI provider 缓存 stale，guard 升级不生效** | `conversationListProvider` 不订阅 `agentSyncTickerProvider`，sync 后无失效信号 → 缓存的 `agent.isRemoved == false` 旧值让 guard 形同虚设 | `providers.dart:275` 同步加 `ref.invalidate(conversationListProvider)`；review 时 grep `lib/features/**/providers/*.dart` 确认无其他依赖 agent 数据的 FutureProvider 遗漏 |
| **`Agent.copyWith` 暴露 `removedAt` 参数导致清不掉 tombstone** | 未来某人觉得"对称"加上参数，落入 `?? this.removedAt` 老坑；`copyWith(removedAt: null)` 实际无效但无报错 | copyWith **故意不暴露** removedAt/hiddenAt 参数；加注释明确"通过 DriftAgentRepo 的 DB 命名查询写入，禁止经过 copyWith"；review 检查 |
| **SQLite 变量数上限（`IN (?, ?, ...)`）** | 单实例 agent 数超过 `SQLITE_MAX_VARIABLE_NUMBER`（SQLite 默认 999，新版 32766）→ `IN` 子句爆错 | 本场景每实例 3-30 agent（pragmatism 专家估算），远低于上限；spec §3.3 注释标注此假设；若未来单实例 agent 破千，需分批 chunk |
| **未来给 agents 表加 `.watch()` stream 后 customStatement 不触发失效** | 当前 agents 无 watch（grep 确认），UI 走 ticker 刷新；若有人加 watch，customStatement 写入不会让 stream 失效 → UI stale | spec §3.3 注释明确"未来若给 agents 加 watch，diff 的 customStatement 需改用 Drift typed update"；review 时检查 |
| **diff 与 upsert 顺序颠倒** | 未来有人把 diff 步骤提到 upsert 之前"优化"，导致本次新 upsert 的 agent 不在旧 remoteIds 里被 `NOT IN` 误 tombstone | spec §3.3 upsert 循环上方加 `*** 顺序不可换 ***` 注释锁死；review 时检查 upsert 仍在 diff 前 |
| 协议未来增加 pagination | OpenClaw v5+ | 当前 spec 假设无分页（§3.1 verified at protocol.md:1442-1480）；若协议演进，须在 ACL 层先拒绝部分响应再下传 |
| `statsProvider.totalAgents` 数字跳变 | sync 后立即从 5 变 4 | v1 接受现状；v2 可考虑文案"X 个虾（Y 个已离线）" |
| `conversationListProvider` 显示孤儿 conversation | conversation 行还在但 agent tombstone 后 `getById` 返回 isRemoved | 该 provider 当前 `if (agent == null) continue;`，改为 `if (agent == null || agent.isRemoved) continue;` —— **此条加入 §3.1 文件清单的检查项** |

---

## 8. 实施待办（追溯记录）

> **状态说明**：本节原为前瞻清单（实施前记录），现作为**实施后追溯记录**。所有项均已完成；部分项的实施路径与原 spec 略有偏差，详见各条备注。

1. [x] **Spike 验证**：`conversationListProvider` 的 null skip 位置确认。**实际位置**：`message_hub_providers.dart:40` 用 `isRemoved` skip（替代原 spec 假设的 `:40-41` null skip）。
2. [x] **TDD Step 1-7**：按 §5 顺序完成，每步独立 commit；最终累计 commit 数 + silent additions（§3.5）整合。
3. [x] **手动验证**：`test/integration/agent_tombstone_lifecycle_test.dart`（5 步完整 lifecycle：sync → tombstone → revive → empty → 消息保留）覆盖模拟链路。
4. [x] **Codegen 顺序核验**：`schema.drift` → `dart run build_runner build --delete-conflicting-outputs` → `database.dart` onUpgrade → mapper/repo 顺序已验证。
5. [x] **`flutter analyze`**：零警告（最近 commit `8e30854`、`3f169e4`、`b952305` 均通过）。
6. [x] **Pre-commit hook**：Iron Laws 1/6/8/11 自动校验通过。
7. [x] **代码评审 checklist**：
   - [x] `findByCompositeKey` 注释明确"intentionally unfiltered"（`drift_agent_repo.dart:70-73`）
   - [ ] `deleteByInstanceId` 注释说明与 tombstone 路径的语义差——**未确认，建议补**
   - [x] `OutboxProcessor` guard 已升级（`outbox_processor.dart:138-157`） + v1.1 批量 EXPIRED
   - [x] `conversationListProvider` 已升级 null skip → isRemoved skip
   - [x] `providers.dart` `AgentsSyncedEvent` 分支**未**加 `ref.invalidate`——方案改为 ticker 失效传播（详见 §3.3）
   - [x] grep `lib/features/**/providers/*.dart` 无其他依赖 agent 数据的 FutureProvider 遗漏 invalidate
   - [x] `Agent.copyWith` 未暴露 `removedAt` / `hiddenAt` 参数
   - [x] `removed_at` 写入只发生在 `syncFromGateway` 内部（grep 验证）
   - [x] `hidden_at` v1 无任何写入点（grep 验证）
   - [x] 所有改动文件总行数 ≤ 120 行（不含测试）—— 实际 ~101 行 + silent additions ~50 行

### 8.1 已知遗留项（优先级 P3，建议后续 Story 处理）

> **状态更新**：以下 4 项 docstring 微修已合入（独立 commit）。代码改动 0 行，仅 docstring 增补。

- [x] **`deleteByInstanceId` 注释**（`drift_agent_repo.dart:322-329`）：补"硬删 vs tombstone 软删语义差异 + tombstoned agent 也被一并清掉（因为实例不存在了）"。
- [x] **`i_agent_repo.dart:57-77` `watchById` docstring**：修正"DB 任意写入...都会 emit 新值"误导，明确 `syncFromGateway` 的 tombstone / revive 步骤走 `customStatement` **不**触发 Drift reactivity；当前通过 `agentSyncTickerProvider` + `ChatViewModel.refreshAgent` 双保险弥补。
- [x] **`drift_agent_repo.dart:43-66` `getById` 注释**：补"`INTENTIONALLY UNFILTERED` —— OutboxProcessor + ChatViewModel.send() 依赖此契约判断 tombstone 状态"；列出已知调用方与文件:行号。
- [x] **`drift_agent_repo.dart:36-49` `getAll` docstring**：注明"默认过滤 tombstoned/hidden agents；不过滤版走 `getAllByInstanceId`"，并补充与 `getByInstanceId` 的粒度差异（跨实例聚合 vs 单实例列表）。

### 8.2 AC9 关闭信号（Phase B 已实施）

详见 user-stories.md AC9 描述（已勾选 `[x]`）。当前 `send()` 在两道 tombstone guard（cached / tombstone-suspect recheck）中除原有 `LoadError` 外追加 `closeRequested: true`，`chat_room_page.dart` 通过新增 `ref.listen` 检测 false→true 转换并 `addPostFrameCallback` 调 `_handleBack()` → `smartBack(context, source: widget.source)` → `Navigator.pop()`（保留 source 参数让 Smart Back Stack 正确回到来源 Tab）。测试：`test/features/chat_room/chat_view_model_close_requested_test.dart`（4 用例）。

**实现选择**：一次性 `bool` 字段而非 `Stream<void>` —— 一次性信号，set true 后不再重置；pop 后 page listener 自然释放，残留 true 状态对其他 watch 该 VM 的 consumer 无影响（VM 不在其他页面被观察）。

---

## 9. 参考资料

- 架构评审报告：本会话上文
- Iron Laws：`docs/engineering/iron-laws.md`
- 现有 sync 实现：`lib/data/repositories/drift_agent_repo.dart:65-113`
- OpenClaw 协议 `agents.list`：`docs/technical/api-protocol.md:1442-1480`
- Drift schema：`lib/data/local/database/schema.drift`
- 现有 deleteByInstanceId（对比硬删模式）：`lib/data/repositories/drift_agent_repo.dart:214-238`
