# 设计：后台同步游标改为 per-(instance, agent) 粒度

- **日期**：2026-07-01
- **关联**：US-018 后台同步；修复 code-review 头号 bug（跨 agent 丢消息）
- **状态**：已通过架构评审委员会（4/5 维度 7-8/10，GREEN/LOW），待写实现计划

---

## 1. 背景与问题

### 1.1 Bug 机制（已机械验证）

`BackgroundSyncRunner` 当前的 `last_sync_at` 游标是 **按 instance** 粒度。在
`lib/core/lifecycle/background_sync_runner.dart`：

- 行 156：`final lastSyncMs = await lastSyncRepo.get(instance.id) ?? 0;` ——
  游标**每个 instance 只读一次**，所有 agent 共用。
- 行 190：`_syncAgent(..., lastSyncMs: lastSyncMs, ...)` —— 同一游标值传给
  每个agent。
- 行 209-211：`if (result.maxTimestamp > maxServerTs) { maxServerTs =
  result.maxTimestamp; }` —— 聚合取**所有 agent 时间戳的最大值**。
- 行 221-222：`await lastSyncRepo.upsert(instance.id, lastSyncVal);` ——
  最大值写回为**按 instance** 的游标。
- 行 294：`if (msg.timestamp >= lastSyncMs)` —— 客户端过滤丢弃低于游标的
  消息。

**丢消息场景**：Instance 有 Agent A（最新消息 t=300）和 Agent B（最新消息
t=500）。首 tick 后游标 = 500（Agent B 的最大值）。下一 tick，Agent A 收到
新消息 t=350；过滤 `350 >= 500` 为假 → **消息被永久丢弃**。Agent A 在自己
的高水位 (300) 与 Agent B 高水位 (500) 之间的所有新消息都会丢。

**影响**：任何存在消息频率不同 agent 的 instance，慢 agent 系统性丢消息。

### 1.2 单一消费者事实

`lastSyncRepo` 当前仅在两处消费：
- `BackgroundSyncRunner`（读+写游标）
- `lib/app/background_sync/callback_dispatcher.dart`（构造 `DriftLastSyncRepo`）

`grep -r lastSync lib/features/` 为空 —— **无 UI 消费实例级游标**。
`ILastSyncRepo` docstring 里"settings page reads it"是过时/愿望性陈述。因此
可以把实例级游标**整个替换**为 per-agent 粒度，无需为"未来 UI 显示"保留双轨。

### 1.3 架构评审已确认的前提假设

| # | 假设 | 验证结论 |
|---|------|----------|
| 1 | 单 instance agent 数小（十几个） | 用户确认；N 次索引读可忽略，不预留批读接口 |
| 2 | `fetchMessageHistory` 幂等 | `api-protocol.md` §4.3 把 `chat.history` 归类为 scope=`read`；§3.6 幂等键只服务 write 类方法；客户端是纯读 RPC（请求带 sessionKey/limit/cursor，响应 messages+nextCursor，无写回、无"fetched"标记）。置信度：高 |
| 3 | 无重叠 workmanager tick | 现有代码同风险，per-agent 不使其更糟；非本次引入，不在 scope |

---

## 2. 决策

**方案 A+α**（评审通过）：

- **A**：单表 `sync_state_agent(instance_id, agent_remote_id, last_sync_at)`，
  替换 `ILastSyncRepo` 为 per-agent 签名，drop 旧 `sync_state`。
- **α**：游标 read/write 留在 `BackgroundSyncRunner` 的 **agent 循环内**
  （不在 `_syncAgent` 内部），`_syncAgent` 签名不变（仍收 `lastSyncMs`），
  保持单测可隔离。

### 2.1 否决的备选

- **Option B**（保留实例级 `ILastSyncRepo` + 新增 `IAgentSyncCursorRepo`）：
  为不存在的 UI 消费方保留双轨，违反 YAGNI；实例级值可由
  `SELECT MAX(last_sync_at) FROM sync_state_agent WHERE instance_id = ?`
  平凡重算，无需独立接口。
- **Option C**（hybrid：agent 游标缺失时回退实例游标）：把两种粒度混进一条
  查询路径，回退分支仍继承跨 agent bug；混淆且仍错。

---

## 3. Schema 与迁移

### 3.1 schema.drift

新增表，删除旧表与旧查询：

```sql
-- 旧（删除）：
-- CREATE TABLE sync_state (instance_id TEXT PRIMARY KEY, last_sync_at INTEGER NOT NULL);
-- getLastSyncAt / upsertLastSyncAt（单参）

-- 新：
CREATE TABLE sync_state_agent (
    instance_id     TEXT NOT NULL,
    agent_remote_id TEXT NOT NULL,
    last_sync_at    INTEGER NOT NULL,
    PRIMARY KEY (instance_id, agent_remote_id)
);

getLastSyncAt:
SELECT last_sync_at FROM sync_state_agent
WHERE instance_id = :instanceId AND agent_remote_id = :agentRemoteId;

upsertLastSyncAt:
INSERT INTO sync_state_agent (instance_id, agent_remote_id, last_sync_at)
VALUES (:instanceId, :agentRemoteId, :lastSyncAt)
ON CONFLICT(instance_id, agent_remote_id) DO UPDATE SET last_sync_at = :lastSyncAt;
```

### 3.2 键选择

主键 `(instance_id, agent_remote_id)` 而非 `localId`：
`fetchMessageHistory` 用 `remoteId` 拉历史，游标与拉取键对齐。

agent 被删除后游标行残留**无害**（同 remoteId 复活时从旧游标续拉 = 正确
语义），故**不加 FK / 级联清理**，与旧 `sync_state` 风格一致（Zero-Trigger
原则：清理靠业务路径，不靠 DB 约束）。

### 3.3 迁移（v8 → v9）

`database.dart`：`schemaVersion` 8 → 9；`onUpgrade` 增加：

```dart
if (from < 9) {
  // US-018 fix: 游标从 per-instance 改为 per-(instance, agent_remote_id)。
  // 旧 sync_state 的 last_sync_at 是"跨 agent 最大值"，回填给慢 agent 会
  // 延续丢消息 bug，故 drop 不回填。首 tick 从 null(=0) 重走；merge 去重
  // 幂等（clientId/serverId 跳过已入库行），并顺带捞回近期丢失的慢 agent
  // 消息（受 maxPagesPerAgent=5 / maxMessagesPerPull=100 约束）。
  await migrator.deleteTable('sync_state');
  await migrator.createTable(syncStateAgent);
}
```

不回填 = 一次性首 tick 重拉，等价于全新安装的首 tick 行为。

---

## 4. Domain 接口

`lib/domain/repositories/i_last_sync_repo.dart` —— 修改既有接口（非新建）：

```dart
/// Per-(instance, agent) "last background sync" cursor (ms epoch).
///
/// 仅后台同步写；首 tick（游标 null）从 0 重走，merge 去重幂等跳过已入库行。
/// 实例级"上次同步时间"若未来需要 UI 显示，可由
/// `SELECT MAX(last_sync_at) FROM sync_state_agent WHERE instance_id = ?`
/// 平凡重算，无需在本接口保留实例级方法。
abstract class ILastSyncRepo {
  Future<int?> get(String instanceId, String agentRemoteId);
  Future<void> upsert(String instanceId, String agentRemoteId, int msEpoch);
}
```

### 4.1 Law 17 合规说明

本改动是**修改既有 domain 接口的契约**（非新建 domain 文件），不触发 Law 17
"新建 domain 源文件须先有 RED 测试"的硬规则。契约变更由 drift 实现测试
（`drift_last_sync_repo_test.dart`）+ runner 回归测试钉死（见 §7）。

---

## 5. DriftLastSyncRepo 实现

`lib/data/repositories/drift_last_sync_repo.dart` —— 两方法各加
`agentRemoteId` 参数，转发到生成代码：

```dart
@override
Future<int?> get(String instanceId, String agentRemoteId) async {
  final rows = await _database.getLastSyncAt(instanceId, agentRemoteId).get();
  if (rows.isEmpty) return null;
  return rows.first;
}

@override
Future<void> upsert(String instanceId, String agentRemoteId, int msEpoch) async {
  await _database.upsertLastSyncAt(instanceId, agentRemoteId, msEpoch);
}
```

代码生成（`dart run build_runner build --delete-conflicting-outputs`）后即用。

---

## 6. BackgroundSyncRunner 改造（方案 α）

`_syncInstance` 核心改动 —— 游标读写移入 agent 循环、按 agent 粒度：

### 6.1 删除

- 实例级 `maxServerTs`、`anyAgentFailed`、`lastSyncMs`（实例级快照）。
- 末尾实例级 cursor gate 块（现 214-226 行）。
- **no-agents 早退路径的 `lastSyncRepo.upsert(instance.id, now())`**
  （现 144 行）—— 无 agent 即无游标可写，直接 disconnect 返回。

### 6.2 agent 循环内新增

每个 agent 开头（在网络拉取**前**）：

```dart
final lastSyncMs = await lastSyncRepo.get(instance.id, agent.remoteId) ?? 0;
```

- N 次索引查询（每 agent 一次）；早 break 还省读。
- **有意不**加 `getAllForInstance` 批读 —— YAGNI，非热路径，前提 #1 已确认
  agent 数十几个、微秒级开销。

### 6.3 _syncAgent 签名

**不变**（仍收 `lastSyncMs`），保持单测可隔离。

### 6.4 成功路径

仅推进**本 agent** 游标：

```dart
if (!result.failed) {
  await lastSyncRepo.upsert(
    instance.id,
    agent.remoteId,
    result.maxTimestamp > 0 ? result.maxTimestamp : now(),
  );
}
```

`result.maxTimestamp > 0`：本 tick 插入了新消息，用其最大时间戳。
`maxTimestamp == -1`（`failed=false` 但 `inserted.isEmpty`）：本 tick 拉到了
页面但无新消息可插，用 `now()` 标记"已追平到此时刻"，下 tick 只拉更新的。

### 6.5 失败 / throw 路径

不推进该 agent 游标 → 下 tick 重走（merge 去重跳过已入库行，安全）。

**两种失败语义**（`SyncAgentResult`）：
- `failed=true`：预算耗尽早退（`_syncAgent` 行 270-274）或 page 拉取抛错
  （行 313-317）—— 整个 agent 未完成，不推进游标。
- `failed=false` 且 `maxTimestamp=-1`：拉到了但 `inserted.isEmpty` —— 见
  §6.4，按"已追平"处理。

**已知边界**：若一个 agent 拉到了消息但**全部 merge 失败**（per-message
try/catch 吞了所有行，`inserted` 为空、`failed=false`），当前 §6.4 会写
`now()` 推进游标，跳过这些"拉到但 merge 失败"的消息。这与现有代码行为一致
（实例级 gate 在 `!anyAgentFailed` 时同样推进），**非本次回归引入**，但记为
已知风险：merge 失败多为 schema drift / FK 不可满足，重拉也会再失败，推进
游标避免无限重拉 —— 可接受取舍。若未来需精确，可让 `_syncAgent` 区分
"无新消息"与"有消息但全 merge 失败"两种 `maxTimestamp=-1`。

**附带收益**：单个 agent 失败**不再阻塞**同 instance 其他 agent 的游标推进
（当前实例级 gate `anyAgentFailed` 会拖累所有人）。

### 6.6 budgetExpired

保留 break + 日志；去掉其 cursor-gate 用途（游标已按 agent 独立判断）。

### 6.7 内联注释

游标读处加注释，引用回归测试名（评审 Action #5）：

```dart
// Per-agent cursor: 防跨 agent 丢消息。共享的 per-instance 游标会让快
// agent 的最大时间戳覆盖慢 agent 的高水位（见回归测试
// pins_crossAgentMessageLoss）。不要批读。
```

---

## 7. 测试

### 7.1 测试组织（评审 Action #2）

加新测试**前**，先从 `background_sync_runner_test.dart`（现 1106 行）抽出
测试基础设施到独立 support 文件，避免破 1200 行：
- `FakeGatewayClient`、`CapturingDispatcher`、`StubBackgroundSyncGate`、
  `FakeClock`、`StubLogger` 及 helper 函数 →
  `test/core/lifecycle/_background_sync_test_helpers.dart`。

### 7.2 drift_last_sync_repo_test.dart

- 4 个现有测试改 2 参签名（`get`/`upsert` 加 `agentRemoteId`）。
- 新增 `upsert_isPerAgentIndependent`：同 instance 不同 `agent_remote_id`
  互不干扰。

### 7.3 background_sync_runner_test.dart

- 所有 `when(() => lastSyncRepo.get('i1'))` → `get('i1', 'a1')`。
- 所有 `verify(() => lastSyncRepo.upsert('iB', any()))` →
  `upsert('iB', any(), any())`。
- **F3b `partialFailure_doesNotAdvanceLastSync`** 断言语义变化：从"实例级
  不推进"改为"失败 agent 游标不推进、成功 agent 游标推进"——分别 verify。

### 7.4 新增测试（TDD RED 锚点）

1. **`pins_crossAgentMessageLoss`**（评审 Action #1，最有价值）：
   两 agent、同 instance、不同游标。Agent A 慢（t=300）、Agent B 快（t=500）。
   验证 Agent A 的新消息（t=350）**不被** `>= lastSyncMs` 过滤丢弃。
   兼作 bug 活文档。

2. **budget 过期多 agent**（评审 Action #3）：3 agent，A 完成、B 中途预算
   耗尽。验证：A 游标推进、B 未推进、C 游标从未读。

3. **`executeOnce_noAgents_connectsWithoutUpsert`**（评审 Action #7）：
   无 agent 时 `verifyNever(() => lastSyncRepo.upsert(any(), any(), any()))`。

### 7.5 _helpers/mocks.dart

若有 `MockLastSyncRepo`，方法签名自动跟随 mocktail；仅调用点变。

---

## 8. 接线

- `lib/app/di/providers.dart:615` `lastSyncRepoProvider` —— 实现类不变
  （`DriftLastSyncRepo`），签名变化由接口传导，provider 无需改。
- `lib/app/background_sync/callback_dispatcher.dart:180` —— 同上。

---

## 9. 不在本次 scope

- agent/instance 删除时清理 `sync_state_agent` 残留行 —— 无害，留后续。
- batch-merge 修复 N+1（code-review finding #2）—— 独立大改，另开。
- 重叠 workmanager tick 的并发审计（前提 #3）—— 现有风险，非本次引入。
- 实例级"上次同步时间"UI 显示 —— 当前无消费方，YAGNI。

---

## 10. 验收标准

- [ ] schema v9 迁移：drop `sync_state`、create `sync_state_agent`，不回填。
- [ ] `ILastSyncRepo` 为 per-agent 签名，docstring 更新（删过时 UI 陈述）。
- [ ] `BackgroundSyncRunner` 游标按 agent 读/写；no-agents 路径不 upsert。
- [ ] `pins_crossAgentMessageLoss` 回归测试通过（RED → GREEN）。
- [ ] budget 过期多 agent 测试通过。
- [ ] `executeOnce_noAgents_connectsWithoutUpsert` 测试通过。
- [ ] 现有 `background_sync_runner_test.dart` 全部更新通过。
- [ ] `drift_last_sync_repo_test.dart` 全部通过（含新 per-agent 独立性测试）。
- [ ] `flutter analyze` 无新增告警。
- [ ] 代码生成成功（`build_runner build`）。
