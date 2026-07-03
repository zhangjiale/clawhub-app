# ACL 协议实现差距清单（Remaining Protocol Gaps）

> **状态**：实施计划文档。本文件追踪 OpenClaw Gateway 协议 spec 与 `lib/core/acl/`
> 实现之间的**未完成项**。每条 gap 含严重度、spec 引用、文件位置、建议修法、测试面，
> 方便后续 sprint 直接接续。
>
> **最后更新**：2026-07-02 — F-4 闭环：`BufferOverflowException`（Gap #2 客户端
> reject-new）经 ACL 翻译为 `BufferOverflowNotice`（`GatewayNotice` 子类型）推上
> `gatewayNoticeStream`，复用 Gap #6 toast 基建展示「网关繁忙，将自动重试」。异常
> rethrow → `execute` catch 标 FAILED（Outbox 自动重发），**不动状态机**。纠正上轮
> "rethrow 卡死 SENDING"误判（`execute.catch(e)` 已捕获并标 FAILED，无死锁）。
> Gap #6 收尾深化（诊断事件 sealed union，Step 1–5 全绿）见下。剩余 4 个 P2/P3
> + 3 个 follow-up。
>
> ⚠️ **审计说明**：本节基于实地代码状态，不是文档表面状态。原 doc 报告这三条
> "未完成"实际上各自已落地了部分实现，本轮把它们推进到全绿后归入完成表。

---

## 已完成

| Gap | 标题 | 严重度 | Commit / 状态 |
|---|---|---|---|
| #1 | `hello-ok.auth.deviceToken` 持久化 | P1 | `eae026f` (merge) + `a793453` (存储层) |
| #2 | `hello-ok.policy.maxPayload` / `maxBufferedBytes` 客户端自保护 | P1 | `connection_manager_policy_test.dart`（maxPayload 已绿） + `connection_manager_buffer_test.dart`（maxBufferedBytes 加 `BufferOverflowException` + `_bufferedBytes` 计数器 + reject-new 强制） |
| #4 | `shutdown` 区分主动重连 vs 优雅退避 | P1 | `_handleGracefulShutdown` → `_immediateReconnect(delaySeconds:0)` 已合入；`connection_manager_shutdown_test.dart` 覆盖 |
| #6 | `payload.large` 诊断事件业务处理 | P1 | 端到端 sealed union 落地（2026-07-02 Step 1–5）：domain `GatewayNotice` + `LargePayloadNotice`（`lib/domain/models/gateway_notice.dart`）→ 单一 `IGatewayClient.gatewayNoticeStream` → ChatViewModel 单订阅 → `ChatSessionState` 单 seq + 单 `lastGatewayNotice` → `formatGatewayNotice` sealed switch → toast。文案下沉 UI 层。**新增诊断事件（rate.limit 等）纯增量，不动 state/page/接口/订阅** |

---

## 未完成（按优先级排序）

### Gap #2 — `hello-ok.policy.maxPayload` / `maxBufferedBytes` 客户端自保护【已完结】

**严重度**：🟠 P1（健壮性，会 OOM 或阻塞） — **2026-07-01 收尾**

**Spec 引用**：
- §2.2 hello-ok payload：`policy.maxPayload = 26214400` (~25MB)、`policy.maxBufferedBytes = 52428800` (~50MB)
- §3.5 传输层载荷限制

**症状**：
- `_handleConnectResponse` 只读 `policy.tickIntervalMs` 写入 `_tickIntervalMs`，
  `maxPayload` 和 `maxBufferedBytes` 完全被忽略
- 单帧 > 25MB 时 Gateway 不会主动拒绝（依赖客户端守门），客户端无防御会内存爆
- 出站缓冲 > 50MB 时应停止读 WebSocket 防止 OOM

**文件位置**：
- `lib/core/acl/connection_manager.dart:432-435`（`_handleConnectResponse` 的 policy 读取）
- 守门逻辑可放在 `ws_gateway_client.dart:sendRequest` 或 `connection_manager.dart:sendRequest`

**建议修法**：
1. `_handleConnectResponse` 把 `maxPayload` / `maxBufferedBytes` 存到 `_maxPayloadBytes` / `_maxBufferedBytes` 字段
2. `sendRequest` 序列化前检查 JSON 长度，超 `_maxPayloadBytes` 抛 `PayloadTooLargeException`
3. 出站缓冲监控在 `WsGatewayClient._pendingRequests` 排队处加阈值（具体策略待定：
   drop oldest / 拒绝新请求 / 触发 backpressure）
4. 在 `ConnectionConfig` 加 `defaultMaxPayload` (e.g. 25MB) 让 `ConnectionManager` 在
   policy 缺失时降级

**测试面**：
- `test/core/acl/connection_manager_policy_test.dart`（新）：
  - 解析 hello-ok 的 maxPayload 字段
  - 超大 payload 抛异常
  - 出站缓冲监控触发
- `test/core/acl/gateway_protocol_test.dart`：扩 `ConnectionConfig` 默认值测试

---

### Gap #3 — `hello-ok.features.events` 列表未消费

**严重度**：🟡 P2（功能完整性，业务层不知道推送哪些事件）

**Spec 引用**：
- §2.2 hello-ok：`features.events: ["chat", "tick", "health", ...]`
- §4C 完整事件类型列表

**症状**：
- hello-ok 解析时直接丢弃 `features` 字段
- 业务层无法区分"Gateway 实际会推送哪些事件"vs"理论支持但本 Gateway 不推送"
- 前端无法做"Gateway 不支持某个事件"的 fallback UI 提示

**文件位置**：
- `lib/core/acl/connection_manager.dart:432` 起（policy 解析处）
- 暴露可加在 `IGatewayClient.connectionStateStream` 旁边的 features stream，
  或注入到 `ConnectionOrchestrator` 的 instance metadata

**建议修法**：
1. `ConnectionManager` 解析 `features.events` 存入 `Set<String> _supportedEvents`
2. 暴露只读 `Set<String> get supportedEvents`
3. `WsGatewayClient` 转发到 Riverpod `gatewayFeaturesProvider`
4. UI 层（如有需要）通过 provider 读

**测试面**：
- `connection_manager_features_test.dart`（新）：
  - 解析 events 数组
  - 暴露 getter 返回正确 set
  - features 缺失时返回空 set（向后兼容）

---

### Gap #4 — `shutdown` 事件未区分主动重连 vs 优雅退避【已完结】

**严重度**：🟠 P1（UX，所有 shutdown 走 1→30s 退避） — **2026-07-01 收尾**

**Spec 引用**：
- §2.7 shutdown 事件
- §2.6 shutdown 语义："服务端主动通知客户端即将关闭"

**症状**：
- `connection_manager.dart:364` 把 `shutdown` 当 `disconnected` 处理，触发通用重连退避
- 实际语义：服务端 shutdown 是**主动的、可预期的**，应立即重连
  （无需退避，因服务端 ready 即可用）
- 与"网络瞬断"+"对端崩溃"区分不开 → 关闭后用户等 1s → 2s → 4s → 8s 才能恢复

**文件位置**：
- `lib/core/acl/connection_manager.dart:362-367`（`_handleEvent` 的 `Events.shutdown` case）

**建议修法**：
1. `_handleEvent` 的 `Events.shutdown` case 不调通用 `_scheduleReconnect`
2. 改调新方法 `_handleGracefulShutdown()`，逻辑：
   - `_setState(GatewayConnectionState.disconnected)` 立即
   - 不退避：`Timer(Duration.zero, _doConnect)`（或最小 200ms 等待服务端 ready）
   - 保留重连尝试计数（避免触发 reconnectExhausted）
3. 如果用户主动 disconnect（`_intentionalDisconnect=true`），仍跳过重连

**测试面**：
- `test/core/acl/connection_manager_shutdown_test.dart`（新）：
  - shutdown 事件后立即进入 disconnected
  - 短间隔内重连成功（不经过 1s 退避）
  - 用户主动 disconnect 期间收到 shutdown 不会触发重连

---

### Gap #5 — `tick.payload.ts` 未消费（时钟漂移检测）

**严重度**：🔵 P3（可观测性，签名 `DEVICE_AUTH_SIGNATURE_EXPIRED` 时无法定位根因）

**Spec 引用**：
- §2.8 心跳保活：tick 事件可包含 `payload.ts`（服务端时间戳）
- §A.8 `DEVICE_AUTH_SIGNATURE_EXPIRED`

**症状**：
- `connection_manager.dart:362-363` 只 reset tick timer，丢弃 payload
- 客户端时钟偏差大时签名会过期（`DEVICE_AUTH_SIGNATURE_EXPIRED`），
  但无任何日志指示"是客户端时钟问题"
- 无法做"对时"或"漂移告警"

**文件位置**：
- `lib/core/acl/connection_manager.dart:362`（`case Events.tick`）

**建议修法**：
1. 解析 `payload?['ts'] as int?`
2. 与 `DateTime.now().millisecondsSinceEpoch` 比对，差 > 5s 时
   `debugPrint` 警告
3. （可选）通过 Riverpod 暴露 `clockDriftMsProvider` 给诊断 UI

**测试面**：
- `connection_manager_tick_test.dart`（新）：
  - tick 带 ts 时记录漂移
  - 漂移 < 5s 不告警
  - tick 不带 ts 时静默忽略

---

### Gap #7 — `agents.list` 响应不含 `description` 字段（name/description 撞车 bug）

**严重度**：🟡 P2（数据正确性，UI 上 agent 简介取值错误）

**Spec 引用**：
- §A.6 `agents.list` 实测响应（probe-verified）
- §5.2 `agents.list` 示意图（**已过时**，含过时字段 `description`）

**症状**：
- `agents.list` RPC 响应里**没有**顶层 `description` 字段
- `openclaw config get agents.list` 返回完整配置（含 `description`）
- `openclaw agents list --format json` 也不含 description
- CLI text 表格无 Description 行
- ClawHub UI 上所有 agent 的 description **绝大多数显示为空（"暂无简介"）**

**identity 块实际语义**（per `config get` 实测，2026-06-28）：

| 字段 | 语义 | 示例 |
|---|---|---|
| `identity.name` | display name（短名/昵称） | "Bob"、"芷若"、"心晴"、"行远" |
| `identity.theme` | 角色描述（仅部分 agent 配了） | "严谨专业的 AI 编程顾问..." |
| `identity.emoji` | emoji | "💻"、"🌿"、"🌙" |

⚠️ 注意：`identity.name` **不是**角色描述。是 display name。ClawHub parser 之前
在 `ws_gateway_client.dart:_parseAgent`（9503d5f 引入）把它当 description fallback，
导致 name 和 description 在 UI 上**完全撞车**（例如 name="编程大师-Bob" 简介也是
"Bob"）。

**已修复**（见本仓库 commit 历史，`fix(acl): stop using identity.name as
agent description fallback`）：`_parseAgent` description fallback 链改为
`json['description'] → identity.theme → identity.description`，**不再**回退到
`identity.name`。测试 `fetchAgents bio field parsing` 8 个用例已对齐新语义。

**真正获取 description 的路径**（修复后仍未解决，需要 follow-up）：
1. 等 OpenClaw 把 `description` 加进 `agents.list` 响应（推荐）
2. ClawHub ACL 加 `config.get` RPC client（需 Gateway 启用 admin RPC），按 agent
   id 匹配填充本地 `Agent.description`
3. Mock 数据 `assets/mock/agents.json` 加 `identity` 块，让 mock parser 走真实路径

**文件位置**：
- `lib/core/acl/ws_gateway_client.dart:_parseAgent`（fallback 链）
- `test/core/acl/ws_gateway_client_test.dart:1134-1187`（测试组 `fetchAgents bio field parsing`）
- `assets/mock/agents.json`（mock 数据，待对齐）

**测试面**：已在 `fetchAgents bio field parsing` 组覆盖（8 个用例）：

| 场景 | 用例 |
|---|---|
| 只有 `identity.name`（旧 bug 现场） | `description is null when only identity.name is present` |
| 顶层 `description` 优先 | `prefers top-level description when other fields coexist` |
| `identity.theme` 兜底 | `falls back to identity.theme when no top-level description` |
| `identity.theme` 优先于 `identity.description` | `prefers identity.theme over identity.description` |
| 空字符串跳过（`_nonEmpty`） | `skips empty description string` |
| `identity.theme` 空时再兜底 | `skips empty identity.theme string` |
| `identity.description` 兜底（legacy v3 兼容） | `falls back to identity.description` |
| 完全无 bio 来源（默认 agent `main`） | `description is null when no bio source is present` |

---

### Gap #6 — `payload.large` 诊断事件无业务处理【已完结】

**严重度**：🟠 P1（用户体验差，用户看到"消息没到"无解释） — **2026-07-01 收尾**

**Spec 引用**：
- §2.7 事件类型表：`payload.large` 事件
- spec 语义："单帧超过 maxPayload 限制时由 Gateway 主动发此事件给客户端"

**症状**：
- `ws_gateway_client.dart:_handleEvent` switch 只 case `chat` 和 `agent`，
  `payload.large` 被静默吞掉
- 实际场景：用户发大附件 / 长 message → Gateway 拒收 → 客户端以为发出去了 → 静默失败
- 应触发 UI 提示 + 写入诊断日志

**文件位置**：
- `lib/core/acl/ws_gateway_client.dart:_handleEvent`（switch on `event.event`）

**建议修法**：
1. 新增 `Events.payloadLarge = 'payload.large'` 到 `gateway_protocol.dart`
2. `ws_gateway_client.dart` 加 `case Events.payloadLarge:` → emit 诊断 stream
3. 新 `payload.large` 事件类（如 `LargePayloadNotice`）含 sessionKey + size + limit
4. `IGatewayClient` 加 `largePayloadNoticeStream(String instanceId)`
5. UI 层（chat_room）订阅 stream → 弹 SnackBar 提示用户

**测试面**：
- `test/core/acl/ws_gateway_client_test.dart`：
  - 收到 payload.large 时 emit LargePayloadNotice
  - notice 包含 size + limit 字段
  - 走 stream 不阻塞主流程

**2026-07-02 深化（Step 1–5，sealed union 端到端）**：原 ACL 层用每事件
一套「seq + message 字段 + StreamSubscription + `ref.listen`」样板，新增
事件要复制 7 文件。本轮收敛为：

1. **Step 1**（Law 17 RED→GREEN）：`lib/domain/models/gateway_notice.dart`
   建 `sealed class GatewayNotice` + `final class LargePayloadNotice`（带 value
   `==`/`hashCode`）。`test/domain/models/gateway_notice_test.dart` 钉 sealed
   穷尽性。
2. **Step 2**：`gateway_protocol.dart` 删本地 `LargePayloadNotice`，`import`+
   `export` domain 类型，`parseLargePayloadEvent` 体不变。`i_gateway_client.dart`
   的 `export ... show` 链让调用方零改动。
3. **Step 3**：`IGatewayClient` 加 `gatewayNoticeStream`（sealed union），旧
   `largePayloadNoticeStream` 暂存过渡。
4. **Step 4**：`ChatSessionState` 两字段 → 单 `gatewayNoticeSeq` + 单
   `lastGatewayNotice`；`ChatViewModel` 删硬编码中文，state 只持结构化 notice；
   `chat_room_page` 顶层 `formatGatewayNotice(GatewayNotice)` switch 派生文案
   （l10n 友好）。`formatGatewayNotice` 视觉契约测试锁住 toast 含 size/limit。
5. **Step 5**：删 `largePayloadNoticeStream` 窄接口；controller 拓宽为
   `StreamController<GatewayNotice>` 并重命名 `gatewayNoticeCtrl`；hook 重命名
   `emitGatewayNoticeForTesting`。`grep` 确认全 repo 无 `largePayload*` 残留。

**收益**：`ChatSessionState` 不再加字段、`ChatViewModel` 不再加订阅、
page 不再加 `ref.listen`、ACL 接口不变。7-subscription / 5-listen /
13-字段 的扩张永久封顶。验证：`flutter analyze` 0 issue、`flutter test`
全量 1590 绿。

**附带**：同轮修了 `law17-gate.py` 的 off-by-one（`repo_root` 少算一层 `.parent`，
对新 domain 文件一律误拦；既有文件靠"已存在则放行"溜过，bug 一直未暴露）。

---

### Gap #1+ — §A.9 `AUTH_TOKEN_MISMATCH` 设备令牌重试（之前 #1 修复的延期项）

**严重度**：🟡 P2（增强鲁棒性，目前依赖首次配对码兜底）

**Spec 引用**：
- §A.9 `AUTH_TOKEN_MISMATCH` 处理：
  > 可信客户端（环回或带 tlsFingerprint 的 wss://）可尝试一次使用缓存设备令牌的重试。
  > 若仍失败，停止自动重连并提示用户。
- `error.details.canRetryWithDeviceToken`（布尔）
- `error.details.recommendedNextStep: "retry_with_device_token"`

**症状**：
- 当前 `_handleConnectResponse` 的 error 分支只 switch `NOT_PAIRED` 和
  `DEVICE_AUTH_DEVICE_ID_MISMATCH`，其他错误码直接 `_handleAuthFailure`
- 没有 `AUTH_TOKEN_MISMATCH` 特殊路径 → 不会触发"用缓存 deviceToken 重试一次"
- 也没有 `canRetryWithDeviceToken` 检查

**文件位置**：
- `lib/core/acl/connection_manager.dart:502-525`（error 分支 switch）

**建议修法**：
1. error 分支新增 `errorCode == 'AUTH_TOKEN_MISMATCH'` case
2. 检查 `details['canRetryWithDeviceToken'] == true`
3. 如果是环回（`isLocalNetwork`）或 wss:// + tlsFingerprint（待确认）→ 重试一次
4. 第二次失败 → `_handleAuthFailure` 终态，不退避
5. 字段结构可在 `ProtocolError.details` 加 `canRetryWithDeviceToken` getter
6. `i_device_token_store` 已经有 `delete()`，可用于重试前清空旧缓存（如果服务
   端轮换了 token）

**测试面**：
- `connection_manager_auth_retry_test.dart`（新）：
  - AUTH_TOKEN_MISMATCH + canRetryWithDeviceToken=true → 用缓存重试一次
  - 重试仍失败 → 终态
  - canRetryWithDeviceToken=false → 不重试
  - 非可信连接（公网）→ 不重试（即使 canRetryWithDeviceToken=true）

---

## Follow-up（小问题，非阻塞）

### Gap #8 — `chat.send` 图片/文件 wire format【✅ 已解决 — appendix F attachments 路径,capture 确认】

**严重度**：✅ 已解决(2026-07-03 真机 capture 确认 `mimeType` 字段正确,Agent 端到端看到图)

**解决历程**:
1. **首次 probe**:发 content-blocks `message` + 顶层 `metadata` → Gateway 返回
   `INVALID_REQUEST: "at /message: must be string" + "at root: unexpected property 'metadata'"`。
   误判为"chat.send 纯文本、无法传图"。
2. **补查 `openclaw-gateway-client-reference.md` 附录 F**:chat.send 有顶层
   `attachments: TOptional<TArray<TUnknown>>` 字段(§3.2 主表省略,附录 F/TypeBox schema 才有)。
   首次 probe 失败是因为发了非法字段,**没测 `attachments`**。
3. **改用 `attachments` 实现 + capture**:真机发图,Agent 回复准确描述了图片内容
   ("皱眉怒视、白毛红眼+红黑条纹衣服"),证明 `mimeType` 字段正确、Agent 端到端看到图。

**最终实现(appendix F 对齐,capture-confirmed)**：
- seam:`WsGatewayClient.serializeChatSendPayload(message, {base64Data})` →
  `({String message, List<Map>? attachments})`(`ws_gateway_client.dart`)。
- chat.send params:`{ sessionKey, message(字符串), idempotencyKey, attachments? }`。
  **无 `metadata`**(已移除,修预存在 bug)。
- attachment 元素:`{ mimeType, content: base64, filename? }` —— **`mimeType` 字段经
  capture 确认正确**(Agent 真实看到图片内容)。
- 字节由 `_readFileBase64` 从 `message.content`(本地路径)读取 base64,DB 只存路径。
  大小守卫(F.6):图片 >10MB / 文件 >5MB → 抛错 → FAILED(提示用 OSS URL)。
- 响应侧 `extractImageRef` 覆盖三种 image block shape:
  F.5 实测 `{type:image, url}` + OpenAI `{type:image_url, image_url:{url}}` + 防御 `{type:image, image:{url}}`。
- 测试:`serializeChatSendPayload (PROTOCOL-VERIFY appendix F)` 组(7 用例)+
  `extractImageRef` 组(含 F.5 shape)。全量 1639 测试绿,analyze 0 issues。

**已知限制(非阻塞)**：
- 大文件(>10MB 图片 / >5MB 文件):客户端直接抛错 FAILED。未来若需支持,按 F.6 走
  OSS/S3 URL 引用(`attachments: [{mime, url, index}]` 形态),另立 story。
- `filename` 字段是否被 Gateway 使用未单独 capture(不影响功能,Agent 已看到图)。

---



### F-1 — `ProtocolError.details` 类型守卫

**严重度**：🟡 P2（崩溃风险，服务端 schema 变更可触发）

**位置**：`lib/core/acl/gateway_protocol.dart:331`

**症状**：
- `details: json['details'] as Map<String, dynamic>?` 假设 details 总是 Map
- 服务端某些错误码可能返回 string 类型的 details（如
  `error.details: "retry_with_device_token"`），此时 `as Map` 抛 TypeError
- 当前 `error.details['canRetryWithDeviceToken']` 也会因 TypeError 崩溃

**建议修法**：
```dart
details: json['details'] is Map
    ? json['details'] as Map<String, dynamic>
    : null,
```

**测试面**：1-2 个单元测试覆盖 string/int 类型 details 不崩

---

### F-2 — `scopes` 列表顺序敏感（签名一致性）

**严重度**：🔵 P3（理论风险，目前所有调用方都传常量）

**位置**：
- `lib/core/acl/gateway_protocol.dart:218`（`buildV3SignaturePayload`）
- `lib/core/acl/connection_manager.dart:354`（调用处）

**症状**：
- `scopesStr = scopes.join(',')` 不排序
- 如果某天调用方传乱序 scopes，客户端/服务端 SHA256 不一致
- 当前 `operatorScopes` 常量是有序的所以没问题，但缺少防御

**建议修法**：
```dart
// 在 buildV3SignaturePayload 内部
final sortedScopes = List<String>.from(scopes)..sort();
final scopesStr = sortedScopes.join(',');
```

**测试面**：1 个测试验证乱序输入产生相同 payload

---

**⚠️ ROLLBACK (2026-06-27)** — 上述修法**实测破坏签名一致性**。

**真实症状**：在真实 Gateway 上启用 F-2 后立即报 `DEVICE_AUTH_SIGNATURE_INVALID`：
```
INVALID_REQUEST / DEVICE_AUTH_SIGNATURE_INVALID / device-signature
```

**根因**：服务端从 wire-order 重建签名（spec §2.2，server 端参考实现在
`api-protocol.md:1321` 直接读 `connectParams.scopes` 数组不排序）。我
们 sort 了 `buildV3SignaturePayload` 内部的 scopes 字符串，但 wire 的
`params.scopes` 数组仍是 `operatorScopes` 默认顺序
`[admin, read, write, approvals, pairing]`：
- wire 字符串（server 重建用）：`admin,read,write,approvals,pairing`
- 签名 payload 字符串（client 签名用）：`admin,approvals,pairing,read,write`
- SHA256 不匹配 → 拒

**结论**：单边 sort 签名 payload 不安全 — 必须**wire + signature 同
时 sort**才能保证 server 重建与 client 签名一致。但 wire sort 改变
了对外协议字段顺序，是 breaking change，需 spec 团队协调。

**当前状态**：F-2 实现已回滚，4 个 F-2 测试已删除，ACL 测试套件
恢复 213/213 通过。doc 建议保留作为"已知理论风险，不修"。

**未来若需修复**：
1. 与 spec 团队确认服务端是否也期望 sorted scopes
2. 若 server 已 sort → 仅 sort signature（当前修法）
3. 若 server 未 sort → 同时 sort wire + signature（破坏性）
4. 若 server 期望完全相同顺序 → 维持现状，文档化 operatorScopes 必须按 canonical 顺序定义

---

### F-3 — DI 路径 desktop 平台 deviceFamily

**严重度**：🔵 P3（spec 不明确，但 production 未测）

**位置**：`lib/app/di/providers.dart:204`
```dart
final deviceFamily = os == 'ios' || os == 'android' ? 'phone' : 'desktop';
```

**症状**：
- Bug #1 修复后 `ConnectionConfig` 默认 `'phone'`
- DI 路径显式覆盖为 `'phone'` 或 `'desktop'`（二分）
- 但 spec §2.5 没列 `'desktop'` 作为 deviceFamily 合法值
- 服务端未来加 enum 校验可能拒掉

**建议修法**：
- 当前通过即可
- 后续对接真实 Gateway 时验证 desktop 是否被接受；如果不接受改成 `'phone'` 兜底
- 或在 spec 不明确时统一用 `'phone'`（让 spec 团队澄清）

**测试面**：等真实 Gateway 验证

---

### F-4 — `BufferOverflowException` 客户端 reject-new UX 通路 ✅ 已闭环 (2026-07-02)

**严重度**：🟡 P2 → ✅ 已闭环

**位置**：`lib/core/acl/connection_manager.dart:380`（throw）→
`lib/core/acl/ws_gateway_client.dart` `sendMessage`（catch + emit notice + rethrow）→
`lib/domain/usecases/send_message.dart:144`（`catch (e)` 标 FAILED）

**闭环方案**：ACL 把 `BufferOverflowException` 翻译成 `BufferOverflowNotice`
（domain sealed `GatewayNotice` 子类型，无字段标记）推上 `gatewayNoticeStream`，
复用 Gap #6 的 toast 基建（`gatewayNoticeSeq` + `formatGatewayNotice`）展示「网关
繁忙，消息未能发送，将自动重试」。异常仍 rethrow，`SendMessageUseCase.execute` /
`.retry` 的 catch 照常标 FAILED（可重试），OutboxProcessor 在缓冲排空后自动重发
—— 数据不丢。**不动 `execute` / `ChatViewModel` / 状态机**，零状态迁移风险。

**纠正上轮误判（重要，避免重蹈覆辙）**：原"安全约束"称 `rethrow` 会卡死 SENDING
丢消息 —— 经实地代码核实为**误判**。`execute` 的 `catch (e)`（`send_message.dart:144`）
捕获**任何**异常（含 rethrow 的 `BufferOverflowException`）并标 FAILED，故 rethrow
落点是 FAILED（retryable），**非 SENDING 死锁**，不丢消息。且 reject-new 在
`sendRequest` 内 `_channel.sink.add` 之前抛出，不写 socket、不注册 completer，
无副作用需清理。故无需"回退 PENDING"的新状态迁移——本方案比上轮设想的更简单安全。

**附带清理**（同 commit）：
- `BufferOverflowException` docstring（`i_gateway_client.dart`）原"不可恢复 / 可重试"
  并存矛盾 → 改为「瞬时可重试」+ 注明 F-4 notice 通路。
- `connection_manager_buffer_test.dart` 死代码 `unawaited(f.catchError(...))`
  （`_failAllPending` 用 `complete()` 非 `completeError()`，catchError 永不触发）+
  基于错误前提的注释一并修正。
- `chat_view_model_large_payload_test.dart` 给 `_MockAgentRepo.watchById` 加空 stream
  stub，消除 `MissingStubError` 测试噪音。

**测试面**：
- `test/domain/models/gateway_notice_test.dart`：`BufferOverflowNotice` 字段/相等/
  sealed 穷尽性（Law 17 RED→GREEN）。
- `test/core/acl/ws_gateway_client_test.dart`：buffer 满时 `sendMessage` 抛
  `BufferOverflowException` **且** emit `BufferOverflowNotice`；非溢出发送不 emit。
- `test/features/chat_room/chat_view_model_large_payload_test.dart`：
  `formatGatewayNotice(BufferOverflowNotice)` 文案契约（含「自动重试」、不含字节数）。

---

## 总结

| 类型 | 数量 | 工作量估计 |
|---|---|---|
| 🟠 P1 | 3 (#2, #4, #6) | 各 1-2 个 commit，每个 ~150-300 行 |
| 🟡 P2 | 5 (#3, #7, #1+, F-1, F-4) | 各 1 个 commit，~100-200 行 |
| 🔵 P3 | 3 (#5, F-2, F-3) | 零散小改，~50 行 |

**建议实施顺序**（价值/风险比）：
1. **F-1** ProtocolError details 守卫（5 行代码，1 测试，1 commit）
2. **Gap #4** shutdown 区分（UX 提升明显，~150 行）
3. **Gap #6** payload.large（用户能感知到，价值高）
4. **Gap #2** policy 客户端保护（健壮性，避免 OOM）
5. 其余按需

**完成此清单的 1 个全部 P1 + F-1 后** 即可认为 ACL 协议层对齐 spec 100%。

> ✅ **2026-07-01 更新**：3 个 P1（#2 / #4 / #6）已全部推进到全绿并加测试
> 覆盖。剩余缺口仅剩 4 个 P2/P3 + 3 个 follow-up + 1 个 §A.9 retry
> 增强项（#1+），均非阻塞 sprint 优先级。ACL 协议层对齐 spec 进度达到
> 「P1 100%」。
>
> ✅ **2026-07-02 深化**：Gap #6 诊断事件链路收敛为 domain sealed `GatewayNotice`
> union 端到端单一接口（Step 1–5，全量 1590 测试绿），新增诊断事件纯增量。
> 同轮架构审查发现 F-4（`BufferOverflowException` 客户端 reject-new 的 UX
> 半截，Gap #2 ACL 层已完结、应用层接入待补），降为 P2 追踪——现状靠
> FAILED+Outbox 兜底可接受为稳态。
>
> ✅ **2026-07-02 F-4 闭环**：`BufferOverflowException` 经 ACL 翻译为
> `BufferOverflowNotice` 推上 `gatewayNoticeStream`，复用 Gap #6 toast 基建。
> 异常 rethrow → `execute.catch(e)` 标 FAILED（Outbox 自动重发），不动状态机。
> 纠正上轮"rethrow 卡死 SENDING"误判（`execute.catch(e)` 已捕获并标 FAILED）。

---

**导航**：
- 上游：[api-protocol.md](api-protocol.md)（协议 spec）
- 上游：[architecture.md](architecture.md)（ACL 模块边界）
- 已完成 audit：差距 #1 修复 commit `eae026f`（merge `d02fb8e`）
- 已完成 audit：差距 #2 / #4 / #6 收尾 - 见「已完成」表(2026-07-01)
