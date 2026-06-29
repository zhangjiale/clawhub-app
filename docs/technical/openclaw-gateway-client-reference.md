# OpenClaw Gateway 协议 v4 — 客户端集成参考

> **目标读者**：任何要对接 OpenClaw Gateway 的客户端开发者（不限语言 / 框架）
> **对齐版本**：OpenClaw Gateway v2026.6.x / 协议 v4
> **本文件与具体项目无关**。可作为通用模板直接复用。

---

## 目录

- [0. 30 秒集成示意](#0-30-秒集成示意)
- [1. 协议基础](#1-协议基础)
- [2. 连接与握手](#2-连接与握手)
- [3. 核心 RPC](#3-核心-rpc)
  - [3.1 鉴权与握手](#31-鉴权与握手)
  - [3.2 消息收发（chat.*）](#32-消息收发chat)
  - [3.3 Agent 管理](#33-agent-管理)
  - [3.4 Session 管理](#34-session-管理)
  - [3.5 流式控制与中止](#35-流式控制与中止)
  - [3.6 模型与用量](#36-模型与用量)
  - [3.7 配置与更新](#37-配置与更新)
  - [3.8 健康 / 日志 / 诊断](#38-健康--日志--诊断)
  - [3.9 定时任务](#39-定时任务)
  - [3.10 工具 / 技能](#310-工具--技能)
  - [3.11 Talk / TTS](#311-talk--tts)
  - [3.12 设备与节点配对](#312-设备与节点配对)
  - [3.13 审批](#313-审批)
- [4. 服务器推送事件](#4-服务器推送事件)
- [5. 鉴权与签名](#5-鉴权与签名)
- [6. 错误处理](#6-错误处理)
- [7. 协议常量](#7-协议常量)
- [8. 权限 scopes](#8-权限-scopes)
- [9. 客户端上线 checklist](#9-客户端上线-checklist)
- [10. 常见陷阱](#10-常见陷阱)
- [附录 A：完整 RPC 索引](#附录-a完整-rpc-索引)
- [附录 B：完整事件索引](#附录-b完整事件索引)
- [附录 C：参考实现 — Flutter/Dart (ClawHub)](#附录-c参考实现--flutterdart-clawhub)
- [附录 D：术语表](#附录-d术语表)
- [附录 E：参考链接](#附录-e参考链接)
- [附录 F：多模态 Input（图片 / 文件）](#附录-f多模态-input图片--文件)

---

## 0. 30 秒集成示意

任何想对接 OpenClaw Gateway 的客户端，最少要做这 7 件事：

```
1. WS 升级到 Gateway
2. 等 push event "connect.challenge"，拿到 nonce
3. 用本地 Ed25519 私钥签 nonce，构造 req "connect"，发出去
4. 等 res "hello-ok"，确认 protocol==4，拿到 policy.tickIntervalMs
5. 调 req "agents.list" 获取 agent 列表（启动渲染）
6. 用户发消息 → req "chat.send"（带 idempotencyKey）
7. 监听 push event "chat" 拿到 stream delta，"state=final" 时拿完整 message
```

下面章节是这 7 步的细节。

---

## 1. 协议基础

### 1.1 传输

- **WebSocket**（文本帧），载荷为 JSON。
- 第一帧**必须**是 `connect` 请求。
- **预握手阶段**单帧 ≤ 64 KiB。
- **握手成功后**，单帧大小遵 `hello-ok.policy.maxPayload`（默认 25 MB）。
- 单连接缓冲遵 `hello-ok.policy.maxBufferedBytes`（默认 50 MB）。

### 1.2 协议版本

- 当前协议版本：**4**（`PROTOCOL_VERSION=4`，`MIN_CLIENT_PROTOCOL_VERSION=4`）。
- 客户端在 `connect` 时声明 `minProtocol` / `maxProtocol`（如 `minProtocol=3, maxProtocol=4`）。
- 服务端拒绝不兼容的协议版本（会返 `INVALID_REQUEST`）。

### 1.3 帧格式（三类）

| 类型 | 字段 |
|---|---|
| **req** | `type`, `id`(uuid), `method`, `params` |
| **res** | `type`, `id`, `ok`, `payload\|error` |
| **event** | `type`, `event`, `payload`, `seq?`, `stateVersion?` |

```jsonc
// 请求
{ "type": "req", "id": "<uuid>", "method": "chat.send", "params": { ... } }

// 成功响应
{ "type": "res", "id": "<uuid>", "ok": true, "payload": { ... } }

// 失败响应
{ "type": "res", "id": "<uuid>", "ok": false, "error": { "code": "...", "message": "..." } }

// 服务器推送事件
{ "type": "event", "event": "chat", "payload": { ... }, "seq": 123 }
```

### 1.4 关键约束

- **幂等性**：所有有副作用的 RPC（`chat.send` / 配置写入 / cron 写入等）**必须**带 `idempotencyKey`。
- **作用域**：聊天/Agent/工具结果事件需至少 `operator.read`；plugin.* 事件需 `operator.write`/`operator.admin`；心跳类事件不限。
- **序列号**：每个客户端连接保持自己的 `seq`，即使 scope 过滤了部分事件，剩余事件在该 socket 上仍单调有序。

---

## 2. 连接与握手

### 2.1 时序

```
Client                              Gateway
  │── WS Upgrade ────────────────────►│
  │◄── event: connect.challenge ──────│  (payload: { nonce, ts })
  │── req: connect (Ed25519 signed) ──►│
  │◄── res: hello-ok ─────────────────│  (payload: { protocol, server, features, snapshot, auth, policy })
  │◄── event: tick ───────────────────│  (周期性)
  │── req: agents.list ──────────────►│
  │◄── res: agents.list ──────────────│
  │   [业务: chat.send / chat.history / 监听 chat / agent 事件]
```

### 2.2 必做项

1. 收到 `connect.challenge` 后**才**能发 `connect`。
2. `connect.params.device.signature` 是 V3 Ed25519 签名（payload 见 [§5.2](#52-设备身份--v3-签名)）。
3. `hello-ok.auth.deviceToken` 应**持久化**，未来重连优先使用。
4. 服务端握手期间可能暂返 `UNAVAILABLE (startup-sidecars)`，客户端应在 `retryAfterMs` 内重试。

### 2.3 connect 请求参数

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `minProtocol` | int | ✅ | 最低兼容协议版本 |
| `maxProtocol` | int | ✅ | 最高协议版本 |
| `client.id` | string | ✅ | 客户端标识（约定见官方规范） |
| `client.version` | string | ✅ | 客户端版本 |
| `client.platform` | string | ✅ | 平台标识（自定义） |
| `client.mode` | string | ✅ | `ui` (operator) / `node` (节点) |
| `client.displayName` | string | ❌ | 设备显示名 |
| `client.deviceFamily` | string | ❌ | `phone`/`tablet`/`desktop` |
| `client.modelIdentifier` | string | ❌ | 设备型号 |
| `role` | string | ✅ | `operator` 或 `node` |
| `scopes` | string[] | ✅ | 请求的权限列表 |
| `caps`/`commands`/`permissions` | — | ❌ | 仅 `role=node` 时使用 |
| `auth.token` | string | ✅ | Gateway Token（取决于鉴权模式） |
| `device.id` | string | ✅ | 设备指纹（SHA256 of public key） |
| `device.publicKey` | string | ✅ | Ed25519 公钥（base64） |
| `device.signature` | string | ✅ | V3 签名（base64） |
| `device.signedAt` | int | ✅ | 签名时间戳（毫秒） |
| `device.nonce` | string | ✅ | 来自 `connect.challenge` |
| `locale` | string | ✅ | `zh-CN` / `en-US` 等 |
| `userAgent` | string | ✅ | 自定义 UA |

### 2.4 hello-ok 响应 payload

| 字段 | 类型 | 说明 |
|---|---|---|
| `protocol` | int | 协商后版本（`4`） |
| `server.version` | string | 服务端版本 |
| `server.connId` | string | 连接 ID |
| `features.methods` | string[] | RPC 方法列表（**功能发现**，非完整） |
| `features.events` | string[] | 推送事件列表 |
| `snapshot` | object | 初始状态快照 |
| `auth.role` | string | 协商后角色 |
| `auth.scopes` | string[] | 协商后 scopes |
| `auth.deviceToken` | string | 可选 — 持久化用于后续重连 |
| `policy.maxPayload` | int | 单帧最大字节 |
| `policy.maxBufferedBytes` | int | 缓冲队列最大字节 |
| `policy.tickIntervalMs` | int | 心跳间隔 |

---

## 3. 核心 RPC

> **目录原则**：本章只列**最常用**的 RPC，每个一段说明 + 关键参数表。完整 RPC 索引见 [附录 A](#附录-a完整-rpc-索引)。

### 3.1 鉴权与握手

#### `connect`

详见 [§2](#2-连接与握手)。**唯一**的第一帧。

### 3.2 消息收发（chat.*）

#### `chat.send` — 发送一条用户消息

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `sessionKey` | string | ✅ | `agent:{agentId}:{scope}`（如 `:main`/`:dm`/`:cron`） |
| `message` | string | ✅ | 消息文本 |
| `idempotencyKey` | string | ✅ | 幂等键（UUID） |
| `overrides` | object | ❌ | 模型覆盖，如 `{"model": "deepseek/deepseek-v4-pro"}` |
| `fastMode` | string | ❌ | `"auto"` 在截止前启用 fast mode |
| `fastAutoOnSeconds` | int | ❌ | fast mode 截止秒数（覆盖默认 60s） |

**响应 payload**: `{ "runId": string, "timestamp": int }`。

流式响应通过 `chat` 事件推送（见 [§4.2](#42-chat-流式消息)）。

#### `chat.history` — 拉历史消息

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `agentId` | string | ✅ | 目标 agent ID |
| `sessionId` | string | ❌ | 限定某个 session（注意 schema 严格性） |
| `limit` | int | ❌ | 默认 `50` |
| `cursor` | string | ❌ | 翻页游标 |

**响应 payload**: `{ "messages": [...], "nextCursor": string|null }`。

**Display-Normalization**（重要）：响应消息已做显示归一化处理：
- 内联指令标签被剥离
- 工具调用 XML 块（`tool_call`/`function_call` 等）被剥离
- 纯静默 token 行（`NO_REPLY`/`no_reply`）被省略
- 超大行被替换为占位符

如需原始数据，用 `chat.message.get(sessionKey, messageId)`。

#### `chat.abort` — 中止生成

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `sessionKey` | string | ✅ | 同 `chat.send` |
| `runId` | string | ❌ | 指定要中止的运行 |

更通用的是 `sessions.abort`（支持 `key+runId` 或单独 `runId`）。

#### `chat.inject` / `chat.message.get`

- `chat.inject`: 注入一条消息到 transcript（不触发 LLM）
- `chat.message.get`: 拉取单条完整消息（避开 history 截断）

### 3.3 Agent 管理

#### `agents.list` — 拉取 agent 列表

**响应 payload**: `{ "agents": [AgentRow, ...] }`，每条包含：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | agent ID（远程唯一） |
| `name` | string | 显示名 |
| `nickname` | string | 可选昵称 |
| `avatarUrl` | string | 头像 URL |
| `themeColor` | string | 主题色（hex） |
| `description` | string | 描述 |
| `identity.{name,theme,avatarUrl,description}` | object | Gateway 内部身份（**部分服务端把字段放进 `identity` 而非顶层**） |
| `quickCommands` | array | 快捷命令 |

#### `agents.create` / `agents.update` / `agents.delete`

管理 agent 记录（需 `operator.write` / `operator.admin`）。

#### `agents.files.list` / `agents.files.get` / `agents.files.set`

管理 agent 工作区的 bootstrap 文件（`AGENTS.md`、`SOUL.md` 等）。

#### `agent.identity.get`

返回 agent 或 session 的有效 assistant identity（角色 / 系统 prompt / 头像）。

#### `agent.wait` — 等待 run 完成

传入 `runId`，等服务端给出终端快照（或超时）。

### 3.4 Session 管理

| RPC | 说明 |
|---|---|
| `sessions.list` | 拉取 session 索引（含 `agentRuntime` 元数据） |
| `sessions.describe` | 单条 session 详情（精确 `sessionKey`） |
| `sessions.resolve` | 解析 `agentId` → `sessionKey` |
| `sessions.create` | 创建 session |
| `sessions.send` | 向已存在 session 发消息（等价于 chat.send） |
| `sessions.steer` | 中断并转向（steer）活跃 session |
| `sessions.abort` | 中止活跃 run（`key`+`runId` 或 `runId`） |
| `sessions.patch` | 更新 session 元数据 / overrides |
| `sessions.preview` | 拉取 bounded transcript 预览 |
| `sessions.subscribe` / `sessions.unsubscribe` | 订阅 session 变更事件 |
| `sessions.messages.subscribe` / `sessions.messages.unsubscribe` | 订阅 session 消息事件 |
| `sessions.get` | 拉完整 session 行 |
| `sessions.reset` / `sessions.delete` / `sessions.compact` | 维护操作 |

> **注**：`sessions.send` 是 Chat 层的语义化封装；低层仍是 `chat.send`。

### 3.5 流式控制与中止

- `chat.abort` — 见上
- `sessions.abort` — 更通用
- `agent.wait` — 同步等待（适合同步调用方）

流式响应的事件格式见 [§4.2 / §4.3](#4-服务器推送事件)。

### 3.6 模型与用量

| RPC | 说明 |
|---|---|
| `models.list` | 模型目录（支持 `view: "configured"\|"all"\|default`） |
| `usage.status` | 提供商用量窗口 / 配额 |
| `usage.cost` | 成本聚合（按日期范围，可 `agentId` 或 `agentScope: "all"`） |
| `sessions.usage` / `sessions.usage.timeseries` / `sessions.usage.logs` | 按 session 用量详情 |

### 3.7 配置与更新

| RPC | 说明 |
|---|---|
| `config.get` | 当前配置快照 + hash |
| `config.set` | 写入完整配置 payload |
| `config.patch` | 增量合并，**数组替换**需 `replacePaths` |
| `config.apply` | 校验 + 全量替换 |
| `config.schema` | 完整 schema（含 `uiHints`、版本、plugin metadata） |
| `config.schema.lookup` | 单 path schema lookup（`reloadKind: restart\|hot\|none`） |
| `secrets.reload` / `secrets.resolve` | 重新解析 SecretRefs |
| `update.run` | 触发更新 + 重启（支持 `continuationMessage`） |
| `update.status` | 最新更新重启 sentinel |
| `wizard.start` / `wizard.next` / `wizard.status` / `wizard.cancel` | 引导向导 |

### 3.8 健康 / 日志 / 诊断

| RPC | 说明 |
|---|---|
| `health` | 健康快照 |
| `status` | `/status` 风格摘要（敏感字段需 admin） |
| `diagnostics.stability` | bounded 诊断稳定性记录器 |
| `logs.tail` | 文件日志 tail（cursor / limit / maxBytes） |
| `system-presence` | 设备在线状态 |
| `last-heartbeat` | 最新心跳 |
| `set-heartbeats` | 切换心跳处理 |
| `system-event` | 注入系统事件 / 广播 presence |

### 3.9 定时任务

| RPC | 说明 |
|---|---|
| `wake` | 立即或下次心跳注入 |
| `cron.add` / `cron.get` / `cron.list` / `cron.status` / `cron.update` / `cron.remove` | CRUD 定时任务 |
| `cron.run` | 手动触发（异步，返回 `runId`） |
| `cron.runs` | 拉历史（支持 `runId` 过滤） |

`cron.run` 是 enqueue-style；**有完成语义的客户端应读 `runId` 后轮询 `cron.runs`**。

### 3.10 工具 / 技能

| RPC | 说明 |
|---|---|
| `commands.list` | 运行时命令清单（agent-aware） |
| `skills.list` / `skills.search` / `skills.detail` / `skills.status` | 技能清单 / 检索 / 详情 |
| `skills.upload.begin` / `.chunk` / `.commit` | 上传私域技能压缩包（admin） |
| `skills.install` | 三种模式（ClawHub / upload / gateway installer） |
| `skills.update` | 更新已安装技能 |
| `tools.catalog` | 工具清单（按 `source`: core/plugin/mcp/channel） |
| `tools.effective` | 当前 session 实际生效的工具 |
| `tools.invoke` | 调用一个工具（`operator.write`） |

### 3.11 Talk / TTS

Talk = 实时语音 / 转写 / TTS 统一通道；TTS 是单纯文本→语音。

| 类别 | 代表 RPC |
|---|---|
| Talk 目录 / 配置 | `talk.catalog`, `talk.config` |
| Gateway-owned sessions | `talk.session.create`/`.join`/`.appendAudio`/`.startTurn`/`.endTurn`/`.cancelTurn`/`.cancelOutput`/`.submitToolResult`/`.steer`/`.close` |
| Client-owned sessions | `talk.client.create`/`.toolCall`/`.steer` |
| Talk mode / event | `talk.mode`, `talk.event`, `talk.speak` |
| TTS | `tts.status`, `tts.providers`, `tts.enable`/`.disable`, `tts.setProvider`, `tts.convert` |

### 3.12 设备与节点配对

| RPC | 说明 |
|---|---|
| `device.pair.list` / `.approve` / `.reject` / `.remove` | 设备配对 |
| `device.token.rotate` / `device.token.revoke` | 设备 token 管理 |
| `node.pair.request` / `.list` / `.approve` / `.reject` / `.remove` / `.verify` | 节点配对 |
| `node.list` / `node.describe` | 节点列表 / 详情 |
| `node.rename` | 重命名节点 |
| `node.invoke` / `node.invoke.result` | 命令 invoke |
| `node.event` | 节点发起的事件 |
| `node.pending.pull` / `.ack` | 节点队列 |
| `node.pending.enqueue` / `.drain` | 持久化 pending work |

### 3.13 审批

| RPC | 说明 |
|---|---|
| `exec.approval.request` / `.get` / `.list` / `.resolve` | 单次执行审批 |
| `exec.approval.waitDecision` | 阻塞等待审批结果 |
| `exec.approvals.get` / `.set` | gateway 审批策略 |
| `exec.approvals.node.get` / `.node.set` | 节点本地审批策略 |
| `plugin.approval.request` / `.list` / `.waitDecision` / `.resolve` | 插件审批 |

---

## 4. 服务器推送事件

> **作用域门控**（v4 重要）：
> - chat / agent / tool-result 事件 → 需至少 `operator.read`
> - plugin.* 事件 → 需 `operator.write`/`operator.admin`
> - tick / heartbeat / presence / 生命周期事件 → 不限 scope
> - 未知事件族 → 默认 fail-closed（不允许）

### 4.1 connect.challenge（握手前，仅一次）

```json
{ "type": "event", "event": "connect.challenge", "payload": { "nonce": "...", "ts": 123 } }
```

收到后**必须**用 `nonce` + 设备私钥做 V3 签名（见 [§5.2](#52-设备身份--v3-签名)）。

### 4.2 chat（流式消息）

```json
{ "type": "event", "event": "chat", "payload": {
    "runId": "...",
    "sessionKey": "agent:{agentId}:{scope}",
    "state": "delta" | "final",
    "deltaText": "incremental text",
    "message": { ... },
    "seq": 123
} }
```

- **`state=delta`**: 携带 `deltaText`，客户端**追加**到 streaming buffer。
- **`state=final`**: 携带**完整 `message` 对象**，客户端消费 buffer + 推送完整消息 + 通知 UI 流结束。

### 4.3 agent（详细后端事件）

```json
{ "type": "event", "event": "agent", "payload": {
    "runId": "...",
    "sessionKey": "...",
    "stream": "assistant" | "message" | "tool" | "lifecycle" | "item",
    "data": { ... }
} }
```

| `stream` | 说明 | `data` 字段 |
|---|---|---|
| `assistant` / `message` | 文本增量（v4 用 `assistant`，v3 用 `message`） | `{"delta": "..."}` |
| `tool` | 工具调用 | `{"phase":"start"\|"result", "toolCallId":"...", "name":"...", ...}` |
| `lifecycle` | Run 生命周期 | `{"phase":"start"\|"end"}` |
| `item` | 工具项 | （结构待定义） |

### 4.4 tick / heartbeat / presence（系统事件）

| 事件 | payload | 说明 |
|---|---|---|
| `tick` | `{ ts }` | 周期性保活。**静默**超过 `tickIntervalMs*2` → 服务端断开（close code 4000） |
| `heartbeat` | (结构) | 应用层心跳（与 `tick` 不同） |
| `presence` | (结构) | 设备在线状态变更 |

### 4.5 其他事件族（按领域）

| 领域 | 事件 |
|---|---|
| Session | `session.message` / `session.operation` / `session.tool` / `sessions.changed` |
| Cron | `cron` |
| 生命周期 | `shutdown` |
| 配对 | `node.pair.requested` / `node.pair.resolved` / `device.pair.requested` / `device.pair.resolved` |
| 唤醒词 | `voicewake.changed` |
| 审批 | `exec.approval.requested` / `.resolved` / `plugin.approval.requested` / `.resolved` |
| Node | `node.invoke.request` |

---

## 5. 鉴权与签名

### 5.1 Token 模式

- **共享 Token**: `auth.token` 填用户配置的 Gateway Token。
- **Trusted proxy**: 鉴权信息走 HTTP 头（`gateway.auth.mode: "trusted-proxy"`）。
- **None**: 仅私有 ingress 使用，禁对外。

### 5.2 设备身份 + V3 签名

新客户端必须支持：

1. 本地生成 Ed25519 密钥对（持久化到安全存储）。
2. `device.id` = SHA-256 of public key（base64url）。
3. `device.publicKey` = 公钥（base64）。
4. `device.signature` = V3 签名（base64），payload 格式如下：

```
v3|{deviceId}|{clientId}|{clientMode}|{role}|{csvScopes}|{signedAtMs}|{token}|{nonce}|{lowercasePlatform}|{lowercaseDeviceFamily}
```

其中 scopes 是**逗号分隔**字符串，platform / deviceFamily 必须**小写**。

签名时序：
```
sign_time_ms = current
payload = "v3|device|clientId|mode|role|scopes|sign_time|token|nonce|platform|family"
signature = ed25519_sign(private_key, payload)
```

### 5.3 配对流程

1. 新设备首次 connect → 服务端返 `PAIRING_REQUIRED`（含 `requestId`/`deviceId`/`requestedRole`/`requestedScopes`）。
2. 用户在服务端（CLI / Web）执行 `openclaw devices approve <requestId>`。
3. 客户端重连 → 通过 → 返 `hello-ok.auth.deviceToken`。
4. 客户端**持久化 deviceToken** 用于后续重连（避免重复审批）。

### 5.4 重连策略

| 参数 | 默认值 |
|---|---|
| 初始 backoff | 1s |
| 最大 backoff | 30s |
| Fast-retry clamp | 250ms（device-token close 后） |
| Force-stop grace | 250ms |
| Tick-timeout close code | 4000 |

`AUTH_TOKEN_MISMATCH` 可选：受信任客户端（loopback 或 pin TLS fingerprint）尝试一次 deviceToken 重试。

---

## 6. 错误处理

### 6.1 错误响应结构

```json
{
  "type": "res",
  "id": "...",
  "ok": false,
  "error": {
    "code": "AUTH_FAILED",
    "message": "Token mismatch",
    "retryable": false,
    "retryAfterMs": null,
    "details": {
      "code": "AUTH_TOKEN_MISMATCH",
      "canRetryWithDeviceToken": true,
      "recommendedNextStep": "retry_with_device_token"
    }
  }
}
```

### 6.2 错误码分类

| 错误码 | 分类 | 推荐处理 |
|---|---|---|
| `AUTH_FAILED` | 鉴权 | 提示重新配对 |
| `AUTH_TOKEN_MISMATCH` | 鉴权 | 受信任端可尝试 deviceToken |
| `AUTH_SCOPE_MISMATCH` | 鉴权 | 提示重新配对（更大 scope） |
| `PAIRING_REQUIRED` / `NOT_PAIRED` | 配对 | 等待用户审批 |
| `RATE_LIMITED` | 限流 | 等待 `retryAfterMs` |
| `INVALID_REQUEST` | 客户端 bug | 检查调用 |
| `NOT_CONNECTED` | 客户端 bug | 重连 |
| `UNAVAILABLE` (`startup-sidecars`) | 服务端启动中 | 在 `retryAfterMs` 内重试 |
| `INTERNAL` | 服务端错误 | 记录日志 + 可重试 |

### 6.3 `recommendedNextStep` 取值

- `retry_with_device_token`
- `update_auth_configuration`
- `update_auth_credentials`
- `wait_then_retry`
- `review_auth_configuration`

客户端应根据 `details.canRetryWithDeviceToken` 决定是否自动重试（**仅受信任端**）。

---

## 7. 协议常量

> 来源：OpenClaw 官方 `src/gateway/client.ts` + `src/gateway/server-constants.ts` + `packages/gateway-protocol/src/version.ts`

| 常量 | 默认值 |
|---|---|
| `PROTOCOL_VERSION` | `4` |
| `MIN_CLIENT_PROTOCOL_VERSION` | `4` |
| 请求超时（每 RPC） | `30_000` ms |
| 预握手 / connect-challenge 超时 | `15_000` ms |
| 初始重连 backoff | `1_000` ms |
| 最大重连 backoff | `30_000` ms |
| Fast-retry clamp（device-token close 后） | `250` ms |
| Force-stop grace | `250` ms |
| `stopAndWait()` 默认超时 | `1_000` ms |
| 默认 tick 间隔（pre `hello-ok`） | `30_000` ms |
| Tick-timeout close code | `4000` |
| `MAX_PAYLOAD_BYTES` | `25 * 1024 * 1024` (25 MB) |
| 预握手最大帧 | `64 KiB` |

握手成功后，**应优先用 `hello-ok.policy.*` 中的值**（服务端可能调整）。

---

## 8. 权限 scopes

### 8.1 角色

| 角色 | 用途 |
|---|---|
| `operator` | 控制平面客户端（CLI / UI / 自动化） |
| `node` | 能力宿主（camera / screen / canvas / system.run） |

### 8.2 Operator scopes

| Scope | 用途 |
|---|---|
| `operator.read` | 读（agent 列表 / history / 状态） |
| `operator.write` | 写（chat.send / chat.abort / 配置） |
| `operator.admin` | 管理员（`/config set` / 所有 admin 方法） |
| `operator.approvals` | 审批（`exec.approval.resolve`） |
| `operator.pairing` | 设备配对（`device.pair.*`） |
| `operator.talk.secrets` | Talk 密钥读取（`talk.config` with `includeSecrets: true`） |

### 8.3 命令级覆盖

部分方法在 `chat.send` 里有**额外**命令级 scope 检查：

| 场景 | 额外要求 |
|---|---|
| `/config set` / `/config unset` 写入 | `operator.admin` |
| `node.pair.approve` 含非 exec 节点命令 | `operator.pairing` + `operator.write` |
| `node.pair.approve` 含 `system.run` / `system.run.prepare` / `system.which` | `operator.pairing` + `operator.admin` |

插件注册的 RPC 可自定义 scope；保留前缀（`config.*` / `exec.approvals.*` / `wizard.*` / `update.*`）强制 `operator.admin`。

---

## 9. 客户端上线 checklist

- [ ] 支持 V3 签名（持久化 Ed25519 密钥到 OS 安全存储）
- [ ] 重连后复用 deviceToken（如有）
- [ ] 处理 `PAIRING_REQUIRED` + 展示配对说明
- [ ] 处理 `AUTH_TOKEN_MISMATCH` 且支持 deviceToken 自动重试（仅 loopback / pin TLS）
- [ ] 处理 `chat.history` display-normalization（不假设原文）
- [ ] 处理 `chat.delta` + `agent.assistant` 重复到达（去重）
- [ ] 处理 `chat.final` + `agent.lifecycle.end` 重复到达（去重）
- [ ] 监听 `tick` 并实现超时断开检测（≥ 2× tickIntervalMs 静默 → 重连）
- [ ] 所有有副作用的 RPC 带 `idempotencyKey`
- [ ] 实现流式 backpressure（不要让 buffer 撑爆 maxBufferedBytes）
- [ ] 处理 `chat.abort` / `sessions.abort` 触发的 `agent.lifecycle.end`
- [ ] 显式监听 `presence` / `shutdown` / `sessions.changed`（提升 UX）
- [ ] 多 agent 场景下，用显式 sessionKey→agentId 映射（不要 string parse 兜底）
- [ ] 协议版本 `< 4` 时按需降级（v3 用 `agent.message` 代替 `agent.assistant`）

---

## 10. 常见陷阱

1. **协议版本只填 max**: 必须同时填 `minProtocol` — 服务端范围检查需要两端。
2. **预握手发非 connect 请求**: 第一帧必须是 connect；否则直接断开。
3. **省略 idempotencyKey**: 重试会导致同一个 `chat.send` 多次执行。
4. **chat.history schema 严格**: 不要传 schema 之外的字段（如 `sessionId` 当前能跑但不保证未来）。
5. **chat.message.get vs chat.history**: 需要完整单条消息用前者（不被 history 截断）。
6. **token 不持久化**: 重连效率低 + 易触发 `AUTH_TOKEN_MISMATCH`。
7. **跑题信任 deviceToken 推送路径**: 仅 loopback + pin TLS fingerprint 端允许；公开 wss 不允许。
8. **错误码字符串匹配**: 用 `error.code` 字段，不要匹配 message。
9. **tick 超时不连**: 服务端在 2× tickIntervalMs 静默后 close code 4000。
10. **scope 过滤掉关键事件**: chat/agent 事件需 `operator.read`；plugin 事件需 `operator.write/admin`。
11. **display-normalization 让 history 与 chat.final 不一致**: 前者无工具调用 XML，后者有；以 `chat.message.get` 取原始。
12. **`runId` 不等于 message id**: 响应里只有 `runId`，真正的 message id 在 `chat.final` 事件。

---

## 附录 A：完整 RPC 索引

按族分组，按字母排序。

### System & Identity

| RPC | Scope |
|---|---|
| `diagnostics.stability` | `operator.read` |
| `gateway.identity.get` | — |
| `health` | — |
| `last-heartbeat` | — |
| `set-heartbeats` | — |
| `status` | (`operator.admin` for sensitive fields) |
| `system-event` | — |
| `system-presence` | — |

### Models & Usage

| RPC | Scope |
|---|---|
| `doctor.memory.status` / `.dreamDiary` / `.backfillDreamDiary` / `.resetDreamDiary` / `.resetGroundedShortTerm` / `.repairDreamingArtifacts` / `.dedupeDreamDiary` / `.remHarness` | varies |
| `models.list` | — |
| `sessions.usage` / `.timeseries` / `.logs` | — |
| `usage.status` / `usage.cost` | — |

### Channels & Login

| RPC | Scope |
|---|---|
| `channels.logout` / `channels.status` | — |
| `push.test` | — |
| `voicewake.get` / `voicewake.set` | — |
| `web.login.start` / `web.login.wait` | — |

### Messaging & Logs

| RPC | Scope |
|---|---|
| `logs.tail` | — |
| `send` | — |

### Talk & TTS

`talk.catalog`, `talk.config`, `talk.event`, `talk.mode`, `talk.speak`,
`talk.client.create` / `.toolCall` / `.steer`,
`talk.session.create` / `.join` / `.appendAudio` / `.startTurn` / `.endTurn` / `.cancelTurn` / `.cancelOutput` / `.submitToolResult` / `.steer` / `.close`,
`tts.convert` / `.disable` / `.enable` / `.providers` / `.setProvider` / `.status`

### Secrets / Config / Update / Wizard

`secrets.reload`, `secrets.resolve`,
`config.get` / `.set` / `.patch` / `.apply` / `.schema` / `.schema.lookup`,
`update.run`, `update.status`,
`wizard.start` / `.next` / `.status` / `.cancel`

### Agents & Tasks

| RPC | Scope |
|---|---|
| `agent.identity.get` / `agent.wait` | — |
| `agents.create` / `.delete` / `.list` / `.update` | `operator.write`/`admin` |
| `agents.files.get` / `.list` / `.set` | — |
| `artifacts.download` / `.get` / `.list` | — |
| `environments.list` / `.status` | — |
| `tasks.cancel` / `.get` / `.list` | `operator.read` / `.write` |

### Sessions

`sessions.abort` / `.compact` / `.create` / `.delete` / `.describe` / `.get` / `.list` / `.messages.subscribe` / `.messages.unsubscribe` / `.patch` / `.preview` / `.reset` / `.resolve` / `.send` / `.steer` / `.subscribe` / `.unsubscribe`

### Chat Execution

| RPC | Scope |
|---|---|
| `chat.abort` / `chat.history` / `chat.send` / `chat.inject` | `operator.read` |
| `chat.message.get` | `operator.read` |

### Device Pairing & Tokens

| RPC | Scope |
|---|---|
| `device.pair.approve` / `.list` / `.reject` / `.remove` | `operator.pairing` |
| `device.token.revoke` / `.rotate` | `operator.pairing` (+ `operator.admin` for non-operator roles) |

### Node Pairing & Invoke

| RPC | Scope |
|---|---|
| `node.describe` / `node.list` | `operator.read` |
| `node.event` | (node-side) |
| `node.invoke` / `.result` | `operator.write` |
| `node.pair.approve` / `.list` / `.reject` / `.remove` / `.request` / `.verify` | `operator.pairing` (+ extras for system.run) |
| `node.pending.ack` / `.drain` / `.enqueue` / `.pull` | (node-side) |
| `node.rename` | — |

### Approvals

`exec.approval.get` / `.list` / `.request` / `.resolve` / `.waitDecision`,
`exec.approvals.get` / `.node.get` / `.node.set` / `.set`,
`plugin.approval.list` / `.request` / `.resolve` / `.waitDecision`

### Automation / Skills / Tools

| RPC | Scope |
|---|---|
| `automation.wake` / `wake` | — |
| `commands.list` | `operator.read` |
| `cron.add` / `.get` / `.list` / `.remove` / `.run` / `.runs` / `.status` / `.update` | — |
| `skills.upload.begin` / `.chunk` / `.commit` | `operator.admin` |
| `skills.detail` / `.install` / `.list` / `.search` / `.status` / `.update` | varies |
| `tools.catalog` / `tools.effective` | `operator.read` |
| `tools.invoke` | `operator.write` |

---

## 附录 B：完整事件索引

按领域分组，按字母排序。

### Auth / Lifecycle

- `connect.challenge`
- `shutdown`

### Tick / Heartbeat / Presence

- `heartbeat`
- `presence`
- `tick`

### Chat / Stream

- `chat` (state: `delta`/`final`)
- `agent` (stream: `assistant`/`message`/`tool`/`lifecycle`/`item`)

### Session

- `session.message`
- `session.operation`
- `session.tool`
- `sessions.changed`

### Cron

- `cron`

### Pairing

- `device.pair.requested`, `device.pair.resolved`
- `node.pair.requested`, `node.pair.resolved`

### Approvals

- `exec.approval.requested`, `exec.approval.resolved`
- `plugin.approval.requested`, `plugin.approval.resolved`

### Node

- `node.invoke.request`

### Misc

- `voicewake.changed`

---

## 附录 C：参考实现 — Flutter/Dart (ClawHub)

> **本附录展示一个真实实现，仅供参考**，不是协议要求。

**仓库**: [claw-hub-app](https://gitee.com/zjl899/claw-hub-app) · 路径: `/tmp/claw-hub-app/`

| 关注点 | Dart 文件 |
|---|---|
| 协议常量 + 帧解析 + 请求构造 | `lib/core/acl/gateway_protocol.dart` |
| 防腐层接口 | `lib/core/acl/i_gateway_client.dart` |
| WebSocket 真实实现 | `lib/core/acl/ws_gateway_client.dart` |
| Mock 实现 | `lib/core/acl/mock_gateway_client.dart` |
| 连接生命周期 | `lib/core/acl/connection_manager.dart` |
| Ed25519 设备身份 | `lib/core/acl/ed25519_identity_provider.dart` |
| 连接编排（含 agents.list 同步） | `lib/app/connection/connection_orchestrator.dart` |

**关键实现要点**：

1. **领域映射**：`_parseAgent` / `_parseMessage` / `_parseToolCall` 完成 JSON → Dart 对象，注意 `identity.*` 字段映射（不要从顶层找）。
2. **流式去重**：用 `_deltaSource` map 锁定首个源（`chat` vs `agent`）。
3. **去重 final**：用 `_finalizedSessions` set 防止 `chat.final` + `agent.lifecycle.end` 重复触发 `Message` push。
4. **fallback message**：当 `chat.final` 没有 `message` 对象时，用聚合 buffer 构建 fallback message。
5. **V3 签名**：见 `gateway_protocol.dart::buildV3SignaturePayload`。

**已知 Bug 状态**（基于 ClawHub master `9ab78a8`，截至 2026-06-29）：

| # | 位置 | 问题 | 状态 | 修复 commit |
|---|---|---|---|---|
| 1 | `fetchMessageHistory` | 缺 `sessionKey`（schema required） | ✅ 已修 | `ac97271` |
| 2 | `sendMessage` | 多传 `metadata` 字段（schema strict） | ⚠️ 仍存在 | — |
| 3 | `_parseAgent` | `identity.name` 被错误用作 description fallback，导致 UI 上 name/description 撞车 | ✅ 已修 | `cfc6eef` |

**ClawHub 额外的协议对齐工作**（不在 v1 bug 清单里，但值得参考）：

| commit | 内容 |
|---|---|
| `ac97271` | **feat(acl): align with OpenClaw spec — 7 gaps closed + F-2 rollback** — 一并关闭 7 个 P1/P2 级别协议 gap，含 graceful shutdown reconnect、payload.large 诊断流、client-side policy guard、etc. |
| `eae026f` + `a793453` | **deviceToken 持久化** — `IDeviceTokenStore` + `SecureStorageDeviceTokenStore`，重连复用 deviceToken (避免重复审批) |
| `10deb9d` | `fetchMessageHistory` 改从 `cursor` 字段读 nextCursor（不是 `nextCursor`），与 Gateway v2026.6.6 实测对齐 |
| `1d8a740` | V3 签名 deviceFamily 与 connect wire 字符串一致（`phone` 小写） |
| `4cb1ed9` | `ConnectionConfig` 默认 `platform` 对齐 OpenClaw spec enum |
| `cfc6eef` | `_parseAgent` description fallback chain 重写 |
| `d412893` | chat 层 5 个 dedup/timestamp/N+1 finding |
| `3288b2d` | ACL connection/streaming 层 4 个 review finding |

详见 commit log: `docs/technical/` 下如果存在 `acl-protocol-gaps.md` 即为 7 gaps 的源头跟踪文档。

---

## 附录 D：术语表

| 术语 | 含义 |
|---|---|
| **Operator** | 控制平面客户端（CLI / Web / mobile app） |
| **Node** | 能力宿主（手机节点、PC 上的 macOS app 等） |
| **Gateway** | OpenClaw 的中央服务进程 |
| **Agent** | Gateway 配置的一个 AI 角色 |
| **Session** | 一次连续对话（按 sessionKey 唯一定位） |
| **Run** | 一次 LLM 生成调用（runId 标识） |
| **Idempotency Key** | 幂等键，防止重试导致重复执行 |
| **V3 Signature** | OpenClaw 的 Ed25519 设备签名规范 v3 |
| **Device Token** | 配对后 Gateway 颁发的 token，绑定 deviceId + role + scopes |
| **Scope** | 权限范围 |
| **Display-Normalization** | chat.history 的显示归一化处理（剥指令 / 静默 token） |

---

## 附录 E：参考链接

| 主题 | 链接 |
|---|---|
| Gateway WebSocket 协议 | https://docs.openclaw.ai/gateway/protocol |
| TypeBox schemas | https://docs.openclaw.ai/concepts/typebox |
| Operator scopes | https://docs.openclaw.ai/gateway/operator-scopes |
| 设备配对 | https://docs.openclaw.ai/gateway/pairing |
| 会话管理 | https://docs.openclaw.ai/concepts/session |
| 流式行为 | https://docs.openclaw.ai/concepts/streaming |
| 消息生命周期 | https://docs.openclaw.ai/concepts/messages |
| 模型与 failover | https://docs.openclaw.ai/concepts/model-failover |
| 多 agent | https://docs.openclaw.ai/concepts/multi-agent |
| 鉴权语义 | https://docs.openclaw.ai/auth-credential-semantics |
| 源码：协议 schema | `packages/gateway-protocol/src/schema.ts` |
| 源码：RPC 方法列表 | `src/gateway/server-methods-list.ts` |
| 源码：客户端参考 | `src/gateway/client.ts` |
| 源码：常量 | `src/gateway/server-constants.ts` |

---

## 修订记录

- 2026-06-29 — v2.2 **新增附录 F：多模态 Input（图片 / 文件）**。覆盖 WebSocket `chat.send.attachments` 与 HTTP `/v1/responses` OpenResponses 两条路径，含 schema / MIME / 大小限制 / 安全策略。
- 2026-06-29 — v2.1 附录 C 更新：`已知 Bug` 列表对齐 ClawHub master `9ab78a8` 现状（Bug #1 / #3 已修，#2 仍存），增加"ClawHub 额外协议对齐工作"小节
- 2026-06-29 — v2 通用化重写：从 ClawHub 项目特定文档改为通用集成参考。结构重排为 10 章主文 + 5 附录，覆盖全部 RPC 与事件族；ClawHub 实现细节下沉到附录 C
- 2026-06-29 — v1 初版（已废弃，见 git 历史）

---

## 附录 F：多模态 Input（图片 / 文件）

> **状态**：实验性/弱约束——OpenClaw v2026.6.x 协议层支持，但官方 markdown 文档几乎未涵盖。本附录基于 TypeBox schema + 测试用例 + 类型定义整理。生产使用建议先在测试 Gateway 上验证实际行为。

### F.1 两条路径对比

| 维度 | WebSocket `chat.send.attachments` | HTTP `/v1/responses` OpenResponses |
|---|---|---|
| **传输** | 通过 Gateway WS 协议 | 直接 HTTP POST |
| **文档完整度** | ⚠️ 弱（schema 是 `TArray<TUnknown>`） | ✅ 完整 |
| **适合场景** | 客户端主动向某个 session 发多模态消息 | 服务端测试 / PoC / 单次调用 |
| **多模态能力** | `attachments` 数组元素任意 shape | `content[]` 用 `input_image` / `input_file` block |
| **持久化** | 进入 session transcript（默认） | ephemeral / system prompt 注入 |
| **推荐度** | 中（生产前需实测） | 高（先验证格式） |

### F.2 WebSocket 路径

#### Schema

`chat.send` 的 TypeBox schema（来自 `dist/schema-*.d.ts`）：

```ts
ChatSendParams: TObject<{
  sessionKey: TString;
  agentId: TOptional<TString>;
  sessionId: TOptional<TString>;
  message: TString;
  thinking: TOptional<TString>;
  fastMode: TOptional<TUnion<[TBoolean, TLiteral<"auto">]>>;
  fastAutoOnSeconds: TOptional<TInteger>;
  deliver: TOptional<TBoolean>;
  originatingChannel: TOptional<TString>;
  originatingTo: TOptional<TString>;
  originatingAccountId: TOptional<TString>;
  originatingThreadId: TOptional<TString>;
  attachments: TOptional<TArray<TUnknown>>;   // ← 不约束元素
  timeoutMs: TOptional<TInteger>;
  systemInputProvenance: TOptional<TObject<{...}>>;
  systemProvenanceReceipt: TOptional<TString>;
  suppressCommandInterpretation: TOptional<TBoolean>;
  idempotencyKey: TString;
}>
```

> ⚠️ `attachments: TArray<TUnknown>` — schema **不强约束**元素结构，任意 shape 都能通过 TypeBox 校验，运行时由 Gateway 内部处理。生产前**必须**实测以确认实际接收的字段。

#### Attachment 元素实际格式（从源码拼凑）

**观察 1**：`docs/help/testing-live.md` 示例
```json
{ "mimeType": "image/png", "content": "<base64>" }
```

**观察 2**：`dist/types*.d.ts` 中的 `MediaAttachment` 类型
```ts
type MediaAttachment = {
  path?: string;
  url?: string;
  mime?: string;       // 注：这里叫 mime 不是 mimeType
  index: number;
  alreadyTranscribed?: boolean;
};
```

**推测的标准格式**（结合两处来源）：
```json
{
  "attachments": [
    {
      "mimeType": "image/png",
      "filename": "cat.png",
      "content": "<base64-encoded>"
    },
    {
      "mime": "image/jpeg",
      "url": "https://cdn.example.com/photo.jpg",
      "index": 1
    }
  ]
}
```

字段命名有两套：`mimeType` (testing-live.md) vs `mime` (types.d.ts)。**生产前用 capture 工具抓一次实际 payload 确认**。

### F.3 HTTP 路径（OpenResponses）

`gateway.http.endpoints.responses` 启用时，`POST /v1/responses` 是 OpenAI Responses 风格的多模态接口。

#### `input_image`

```json
{
  "type": "input_image",
  "source": { "type": "url", "url": "https://example.com/image.png" }
}
```

或 base64：
```json
{
  "type": "input_image",
  "source": {
    "type": "base64",
    "media_type": "image/png",
    "data": "<base64>"
  }
}
```

**支持 MIME**：`image/jpeg`, `image/png`, `image/gif`, `image/webp`, `image/heic`, `image/heif`
**最大大小**：10 MB

#### `input_file`

```json
{
  "type": "input_file",
  "source": {
    "type": "base64",
    "media_type": "text/plain",
    "data": "SGVsbG8gV29ybGQh",
    "filename": "hello.txt"
  }
}
```

**支持 MIME**：`text/plain`, `text/markdown`, `text/html`, `text/csv`, `application/json`, `application/pdf`
**最大大小**：5 MB

**特殊行为**：
- 文件内容解码后注入到 **system prompt**（不是 user message）
- 是 **ephemeral**（**不**持久化到 session history）
- 解码文本包成 "untrusted external content"（防止 prompt injection）
- PDF 由 `document-extract` 插件提供（`clawpdf` + WASM PDFium）
- 超大 PDF 自动 rasterize 成图片传给模型

#### URL 抓取的安全控制

OpenClaw 默认开 URL 抓取，但有严格的安全门：

| 配置 | 默认 | 说明 |
|---|---|---|
| `files.allowUrl` | `true` | 是否允许 URL-based input_file |
| `images.allowUrl` | `true` | 是否允许 URL-based input_image |
| `maxUrlParts` | `8` | 单请求 URL 类附件总数上限 |
| `files.urlAllowlist` | `[]` | 主机白名单（exact 或 `*.domain`） |
| `images.urlAllowlist` | `[]` | 主机白名单 |

URL 抓取时强制：
- DNS resolution 检查
- 私有 IP 拦截（防 SSRF）
- redirect 次数上限
- timeout 控制

### F.4 配置示例

```json5
{
  gateway: {
    http: {
      endpoints: {
        responses: {
          enabled: true,
          maxBodyBytes: 20000000,
          maxUrlParts: 8,
          files: {
            allowUrl: true,
            urlAllowlist: ["cdn.example.com", "*.assets.example.com"],
            allowedMimes: [
              "text/plain", "text/markdown", "text/html",
              "text/csv", "application/json", "application/pdf"
            ]
          },
          images: {
            allowUrl: true,
            urlAllowlist: ["*.img.example.com"],
            allowedMimes: [
              "image/jpeg", "image/png", "image/gif",
              "image/webp", "image/heic", "image/heif"
            ]
          }
        }
      }
    }
  }
}
```

### F.5 流式输出（Agent 响应包含图片）

`chat.history` 返回的 message `content` 字段是**多模态数组**结构（不限于文本）：

```json
{
  "content": [
    { "type": "text", "text": "这是图表：" },
    { "type": "image", "url": "https://cdn.example.com/chart.png" }
  ]
}
```

客户端 UI 需要渲染多种 content type，不能只 strip 到 string。

### F.6 已知风险与注意点

1. **WebSocket `attachments` schema 弱**：未来版本可能调整形状，**强类型客户端会被破坏**。建议：
   - 用最少字段（`mimeType` + `content`）
   - 实测 capture 确认
2. **WebSocket attachment 是否进入 history**：根据 schema 看，是附在 `chat.send` 上；Gateway 内部会决定是否持久化。如果你的客户端需要不可见的 attachments，需要 `chat.inject` 路径。
3. **大文件不要走 `chat.send`**：超 5MB 文件 / 10MB 图片会导致 Gateway 拒收或超时。生产客户端应：
   - **小文件（< 10MB）**：base64 inline 到 `attachments`
   - **大文件（> 10MB）**：先上传到自己的对象存储 (OSS / S3)，用 URL 引用
4. **PDF 解析依赖 `document-extract` 插件**：默认装但需要确认。生产前用样例 PDF 实测。
5. **Vision 模型要求**：`input_image` 必须 LLM 支持 vision（如 Claude 3+、GPT-4V、Gemini 等）。OpenClaw 路由会自动把 vision 能力 mismatch 的请求拒绝或降级。

### F.7 客户端实施清单

接入多模态 input 的最低步骤：

- [ ] `Message` 模型加 `attachments: List<Attachment>` 字段
- [ ] `Attachment` 模型定义（mimeType / filename / content or url / index）
- [ ] UI 加图片选择（`image_picker` 等）+ 预览 + 压缩（>10MB 客户端先压）
- [ ] `chat.send` payload 加 `attachments` 透传
- [ ] 流式接收 `chat.history` 多模态 `content[]`，UI 渲染
- [ ] 大文件路径（自建 OSS / MinIO）— 可选
- [ ] 单元测试覆盖：base64 inline / URL 引用 / 混合附件
- [ ] 实测 capture：确认 Gateway 实际接收的 attachment shape（不依赖 schema 推测）

### F.8 参考资源

| 来源 | 路径 |
|---|---|
| OpenResponses HTTP API 完整 spec | `docs/gateway/openresponses-http-api.md` |
| TypeBox schema (chat.send) | `dist/schema-*.d.ts`（`ChatSendParams`） |
| MediaAttachment 类型定义 | `dist/types*.d.ts`（`MediaAttachment`） |
| Attachment 使用示例 | `docs/help/testing-live.md` |
| 流式 content 多模态 | `docs/concepts/messages.md` + `docs/concepts/streaming.md` |
| Image generation (反方向) | `docs/tools/image-generation.md` |

