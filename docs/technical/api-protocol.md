# 虾Hub × OpenClaw 后端交互协议规格书

> 基于 OpenClaw 源码逆向分析，面向虾Hub 移动端开发团队

---

## 一、架构总览

虾Hub 在 OpenClaw 生态中扮演一个 **自定义 Channel** 的角色，通过 WebSocket 直连 OpenClaw Gateway 服务器，无需修改 OpenClaw 本身。

```
┌────────────────────────────────────────────────────────────────┐
│                      OpenClaw Instance                         │
│                                                                │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────────┐ │
│  │ Agent A  │◄──►│              │◄──►│  WeChat Channel      │ │
│  │ (产品虾)  │    │              │    │  (ClawBot Plugin)    │ │
│  └──────────┘    │   Gateway    │    └──────────────────────┘ │
│                  │   Server     │                              │
│  ┌──────────┐    │  (port 18789)│    ┌──────────────────────┐ │
│  │ Agent B  │◄──►│              │◄──►│  Slack Channel       │ │
│  │ (代码虾)  │    │              │    │                      │ │
│  └──────────┘    │              │    └──────────────────────┘ │
│                  │              │                              │
│  ┌──────────┐    │              │    ┌──────────────────────┐ │
│  │ Agent C  │◄──►│              │◄──►│  虾Hub (WebSocket)   │ │
│  │ (设计虾)  │    │              │    │  ← 我们的 App        │ │
│  └──────────┘    └──────────────┘    └──────────────────────┘ │
│                         ▲                                      │
└─────────────────────────┼──────────────────────────────────────┘
                          │ WebSocket (ws:// or wss://)
                          │ Port 18789
                          ▼
                   ┌─────────────┐
                   │   虾Hub App  │
                   │  (iOS/Android)
                   └─────────────┘
```

**关键认知**：虾Hub 不需要作为 Channel Plugin 注册到 OpenClaw 内部，而是作为 **外部 operator 客户端** 通过 Gateway WebSocket API 与 OpenClaw 通信。这类似于 ClawPanel（Web 管理面板）的工作方式。

---

## 二、连接建立与认证

### 2.1 认证层级

虾Hub 需要经历 **多层认证** 才能与 Gateway 建立完整通信：

```
第一层：Gateway 连接认证 (Shared-Secret Token)
   ↓ WebSocket URL query: ?token={token}
第二层：设备身份认证 (Ed25519 密钥对)       ← 必须！否则所有 operator 权限被清空
   ↓ 客户端生成密钥对，签名 challenge nonce
第三层：操作权限 Scope 声明                  ← 在 connect 请求中声明所需 scopes
   ↓ 服务端根据设备身份绑定 scope，后续 API 鉴权
```

> **关键发现（实测验证）**：仅使用第一层 Token 认证（不带设备身份），WebSocket 连接虽然可以成功建立（收到 `hello-ok`），但服务端会**清空所有 operator scope**，导致所有核心 API 方法（如 `agents.list`、`chat.send`、`status`）均返回 `missing scope: operator.read` 错误。因此，**设备身份（Ed25519）是必须的**。

### 2.2 完整连接握手流程（实测验证）

以下为经过实际连接验证的完整握手流程：

```
虾Hub App                              OpenClaw Gateway (v2026.6.1)
    │                                       │
    │  ① WebSocket 连接                      │
    │     URL: ws://ip:18789?token={token}  │
    │  ─────────────────────────────────────►│
    │                                       │
    │  ② 服务端下发 Challenge                 │
    │  EventFrame:                          │
    │  {                                    │
    │    "type": "event",                   │
    │    "event": "connect.challenge",      │
    │    "payload": {                       │
    │      "nonce": "uuid-v4",             │  ← 一次性随机数
    │      "ts": 1700000000000              │  ← 服务端时间戳
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
    │  ③ 客户端构造 Connect 请求:              │
    │     - 生成/加载 Ed25519 密钥对           │
    │     - deviceId = SHA256(pubKeyRaw).hex │
    │     - 构造 V3 签名 Payload (见下文)      │
    │     - 用私钥签名 payload                │
    │                                       │
    │  RequestFrame:                        │
    │  {                                    │
    │    "type": "req",                     │
    │    "id": "xh-1",                     │
    │    "method": "connect",               │  ← 方法名必须是 "connect"
    │    "params": {                        │
    │      "minProtocol": 3,               │  ← 协议版本范围（推荐 3-4 兼容）
    │      "maxProtocol": 4,               │
    │      "client": {                      │
    │        "id": "openclaw-ios",          │  ← 枚举值 (见 2.3)
    │        "displayName": "虾Hub",        │
    │        "version": "1.0.0",            │  ← 必须非空
    │        "platform": "mobile",          │
    │        "mode": "ui",                 │  ← 枚举值 (见 2.3)
    │        "deviceFamily": "phone"        │
    │      },                               │
    │      "caps": ["tool-events"],         │
    │      "role": "operator",             │
    │      "scopes": [                      │  ← 请求的权限列表
    │        "operator.admin",             │
    │        "operator.read",              │
    │        "operator.write",             │
    │        "operator.approvals",         │
    │        "operator.pairing"            │
    │      ],                               │
    │      "auth": {                        │
    │        "token": "59a12c..."           │  ← Gateway Token (或 password)
    │      },                               │
    │      "locale": "zh-CN",               │  ← (可选) 客户端语言
    │      "userAgent": "xiahub/1.0.0",     │  ← (可选) UA 标识
    │      "device": {                      │  ← Ed25519 设备身份
    │        "id": "sha256hex...",          │
    │        "publicKey": "base64url...",   │  ← 32字节公钥 raw bytes
    │        "signature": "base64url...",   │  ← 签名
    │        "signedAt": 1700000005000,     │  ← 签名时间戳 (ms)
    │        "nonce": "challenge-nonce"     │  ← 来自 connect.challenge
    │      }                                │
    │    }                                  │
    │  }                                    │
    │  ─────────────────────────────────────►│
    │                                       │
    │  ④ 服务端验证并回复:                     │
    │                                       │
    │  [首次连接 - 需要配对审批]                 │
    │  ResponseFrame:                       │
    │  {                                    │
    │    "type": "res",                     │
    │    "id": "xh-1",                     │
    │    "ok": false,                       │
    │    "error": {                         │
    │      "code": "NOT_PAIRED",            │
    │      "message": "pairing required:    │
    │        device is not approved yet",   │
    │      "details": {                     │
    │        "code": "PAIRING_REQUIRED",    │
    │        "reason": "not-paired",        │
    │        "requestId": "uuid",           │  ← 配对请求 ID
    │        "deviceId": "sha256hex",       │
    │        "requestedRole": "operator",   │
    │        "requestedScopes": [...]       │
    │      }                                │
    │    }                                  │
    │  }                                    │
    │  → WebSocket 被关闭 (code=1008)        │
    │                                       │
    │  [已配对设备 - 连接成功]                  │
    │  ResponseFrame:                       │
    │  {                                    │
    │    "type": "res",                     │
    │    "id": "xh-1",                     │
    │    "ok": true,                        │
    │    "payload": {                       │
    │      "type": "hello-ok",             │
    │      "protocol": 4,                  │
    │      "server": {                      │
    │        "version": "2026.6.1",        │
    │        "connId": "uuid"              │
    │      },                               │
    │      "features": {                    │
    │        "methods": [                   │  ← 187 个可用方法
    │          "health", "status",          │
    │          "agents.list", "chat.send",  │
    │          ...                          │
    │        ],                             │
    │        "events": [                    │  ← 可用事件类型列表
    │          "chat", "tick", "health",    │
    │          ...                          │
    │        ]                              │
    │      },                               │
    │      "auth": {                        │  ← 协商后的认证信息
    │        "deviceToken": "dt-xxx",       │  ← 设备令牌（首次配对签发，务必持久化）
    │        "role": "operator",            │
    │        "scopes": [...]               │  ← 实际授予的 scope 列表
    │      },                               │
    │      "policy": {                      │  ← 连接策略限制
    │        "maxPayload": 26214400,        │  ← 单帧最大载荷 ~25 MB
    │        "maxBufferedBytes": 52428800,  │  ← 出站缓冲上限 ~50 MB
    │        "tickIntervalMs": 15000        │  ← tick 心跳间隔 (ms)
    │      },                               │
    │      "snapshot": { "…": "…" },        │  ← 初始状态快照
    │      "pluginSurfaceUrls": {}          │  ← (可选) 插件 UI URL 映射
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
    │  ⑤ 紧接着推送 Health 事件:               │
    │  EventFrame:                          │
    │  {                                    │
    │    "type": "event",                   │
    │    "event": "health",                 │
    │    "payload": {                       │
    │      "ok": true,                      │
    │      "plugins": { "loaded": [...] },  │
    │      "channels": {                    │
    │        "openclaw-weixin": { ... }     │  ← 已配置的消息渠道
    │      },                               │
    │      "defaultAgentId": "main",        │
    │      "agents": [                      │  ← Agent 列表和会话信息
    │        {                              │
    │          "agentId": "main",           │
    │          "isDefault": true,           │
    │          "sessions": { "count": 4 }   │
    │        }                              │
    │      ],                               │
    │      "heartbeatSeconds": 1800         │
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
    │  ⑥ 周期性 Tick 心跳:                    │
    │  EventFrame:                          │
    │  {                                    │
    │    "type": "event",                   │
    │    "event": "tick",                   │
    │    "payload": { "ts": 1700000010000 },│
    │    "seq": 2                           │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
    │  ⑦ 连接就绪，可调用 operator API         │
    │                                       │
```

### 2.3 client.id 和 client.mode 枚举值（源码验证）

**client.id** — 客户端标识，必须是以下枚举值之一：

| 值 | 说明 |
|---|------|
| `webchat-ui` | Web 聊天界面 |
| `openclaw-control-ui` | Control UI 管理面板 |
| `openclaw-tui` | 终端 UI |
| `webchat` | Web 聊天 |
| `cli` | 命令行 |
| `gateway-client` | 通用 Gateway 客户端 |
| `openclaw-macos` | macOS 客户端 |
| `openclaw-ios` | iOS 客户端 |
| `openclaw-android` | Android 客户端 |
| `node-host` | 节点主机 |
| `test` | 测试 |
| `fingerprint` | 指纹 |
| `openclaw-probe` | 探针 |

**虾Hub 推荐使用**：`openclaw-ios` 或 `openclaw-android`（根据平台自动选择）。

**client.mode** — 客户端模式：

| 值 | 说明 |
|---|------|
| `webchat` | Web 聊天 |
| `cli` | 命令行 |
| `ui` | 图形界面 |
| `backend` | 后端服务 |
| `node` | 节点 |
| `probe` | 探针 |
| `test` | 测试 |

**虾Hub 推荐使用**：`ui`

### 2.4 Operator Scope 权限体系（源码验证）

| Scope | 含义 | 包含关系 |
|-------|------|---------|
| `operator.read` | 只读：状态查询、列表、目录、日志、会话读取 | 基础权限 |
| `operator.write` | 读写：发送消息、调用工具、更新配置 | 包含 read |
| `operator.admin` | 管理：配置变更、敏感操作、高级审批 | 包含所有 |
| `operator.pairing` | 配对管理：设备审批、吊销、轮换 | 独立权限 |
| `operator.approvals` | 执行/插件审批 API | 独立权限 |
| `operator.talk.secrets` | 读取含密钥的 Talk 配置 | 独立权限 |

**虾Hub 推荐的 scope 列表**（与官方 iOS 客户端一致）：
```json
["operator.admin", "operator.read", "operator.write", "operator.approvals", "operator.pairing"]
```

### 2.5 Ed25519 设备身份签名算法（源码验证）

```
1. 生成 Ed25519 密钥对 (32字节私钥种子 + 32字节公钥)
2. 公钥 base64url 编码 → publicKey
3. deviceId = SHA-256(公钥 raw bytes).hex()   → 64字符 hex 字符串

4. 收到 connect.challenge 事件中的 nonce

5. 构造 V3 签名 Payload (管道符分隔):
   "v3|{deviceId}|{clientId}|{clientMode}|{role}|{scopes}|{signedAtMs}|{token}|{nonce}|{platform}|{deviceFamily}"

   其中:
   - scopes = 逗号分隔的 scope 列表字符串
   - token = auth.token 的值（无 token 则为空字符串）
   - platform = client.platform 的小写形式
   - deviceFamily = client.deviceFamily 的小写形式
   - signedAtMs = 当前时间戳（毫秒）

6. 用 Ed25519 私钥签名 payload 的 UTF-8 字节
   signature = Ed25519.sign(payload_utf8, privateKey)

7. signature 和 publicKey 均使用 base64url 编码

8. 在 connect 请求的 device 字段中传入:
   { id, publicKey, signature, signedAt, nonce }
```

> **注意事项**：
> - `signedAt` 有有效期限制，服务端会校验时间偏移
> - `nonce` 必须与 `connect.challenge` 中下发的完全一致
> - 签名 payload 中的 `platform` 和 `deviceFamily` 必须小写

### 2.6 设备配对审批流程

**首次连接时**（新设备 ID），服务端会创建 pending 配对请求并关闭连接：

```
服务端返回:
{
  "error": {
    "code": "NOT_PAIRED",
    "details": {
      "code": "PAIRING_REQUIRED",
      "requestId": "uuid",     ← 配对请求 ID
      "deviceId": "sha256hex"
    }
  }
}
```

**审批方式**（在 OpenClaw 服务器终端执行）：
```bash
# 查看待审批列表
$ openclaw devices list --pending

# 批准配对请求
$ openclaw devices approve <requestId>
```

**审批后**，设备使用相同的密钥对重新连接即可成功（hello-ok），后续连接无需再次审批。

**自动审批条件**（无需人工干预）：
- 本地回环连接（127.0.0.1/localhost）+ Control UI / WebChat 客户端
- CLI 容器本地等效连接
- 配置了 `autoApproveCidrs` 的可信网段（仅限 node 角色）
- 配置了 `dangerouslyDisableDeviceAuth=true`（仅限 Control UI，不推荐）

### 2.7 本地连接 vs 远程连接对比

| 特性 | 本地连接 (localhost/127.0.0.1) | 远程连接 (公网/内网IP) |
|------|------|------|
| Token 认证 | 通过 | 通过 |
| 设备签名验证 | 通过 | 通过 |
| 自动配对审批 | 支持（Control UI / WebChat / CLI） | **不支持**，需手动审批 |
| Scope 保留 | 保留（有设备身份时） | 保留（有设备身份 + 已审批时） |
| 无设备身份时 Scope | **被清空** | **被清空** |

> **对虾Hub 的意义**：远程连接是主要使用场景（手机连远程服务器），因此**必须实现 Ed25519 设备身份 + 配对审批流程**。首次连接时需要用户在服务器端手动审批一次。

### 2.8 心跳保活

服务端会定期发送 `tick` 事件：
```json
{
  "type": "event",
  "event": "tick",
  "payload": { "ts": 1700000010000 },
  "seq": 2
}
```

- `tick` 间隔由 `hello-ok.policy.tickIntervalMs` 控制（默认 15000ms，即 15 秒）
- 握手完成前使用默认值 30000ms（30 秒）
- 客户端无需主动发送心跳，WebSocket 底层 ping/pong 由库自动处理
- **tick 超时断开**：若客户端静默超过 `tickIntervalMs × 2`，服务端以 close code `4000` 断开连接
- 客户端应遵循 `hello-ok.policy` 中的值，而非使用硬编码默认值

### 2.9 连接错误与重连策略

虾Hub 应实现 **指数退避重连**（与官方客户端常量一致）：

```
断开连接
  │
  ├─ 第 1 次重试: 1s 后
  ├─ 第 2 次重试: 2s 后
  ├─ 第 3 次重试: 4s 后
  ├─ 第 4 次重试: 8s 后
  ├─ 第 5 次重试: 16s 后
  └─ 后续: min(previous × 2, 30s)  ← 最大退避 30s
```

特殊错误处理：
- `PAIRING_REQUIRED`：提示用户在服务器审批，定期重试
- `AUTH_TOKEN_MISMATCH`：Token 不匹配，可信客户端可尝试一次设备令牌重试，仍失败则停止重连并提示用户
- `AUTH_SCOPE_MISMATCH`：Scope 不匹配，提示用户重新配对或调整 scope
- `UNAVAILABLE` (`startup-sidecars`)：Gateway 启动中，按 `retryAfterMs` 等待后重试
- `device_identity_required`：缺少设备身份字段
- `device-signature-invalid`：签名错误，检查密钥对（参考 A.8 诊断码）
- `gateway auth changed` (close code 4001)：Token 已轮换，需更新

### 2.10 获取 Token 的方式

```bash
# 方式一：查看当前 Token
$ openclaw gateway token

# 方式二：查看配置文件中的 Token
$ cat ~/.openclaw/config.yaml | grep gateway

# 方式三：通过环境变量设置
$ export OPENCLAW_GATEWAY_TOKEN=your-token-here
```

### 2.11 虾Hub 本地存储设计

```json
{
  "instances": [
    {
      "id": "inst-001",
      "name": "我的云服务器",
      "url": "ws://127.0.0.1:18789",
      "authMode": "token",
      "token": "59a12c904f52...",
      "deviceKeypair": {
        "publicKey": "base64url...",
        "privateKey": "base64url..."
      },
      "deviceId": "sha256hex...",
      "paired": true,
      "pairedAt": "2026-06-13T02:00:00Z"
    }
  ]
}
```

> **安全要求**：`token` 和 `deviceKeypair.privateKey` 必须使用系统级安全存储（iOS Keychain / Android Keystore），禁止明文存储。Ed25519 密钥对应在设备上持久化，避免每次连接生成新密钥对导致需要重新审批。

---

## 三、消息协议格式

### 3.1 帧类型

Gateway 使用三种帧类型，所有帧均为 JSON 格式：

**RequestFrame（客户端 → 服务端）**
```json
{
  "type": "req",
  "id": "uuid-xxx",
  "method": "chat.send",
  "params": { ... }
}
```

**ResponseFrame（服务端 → 客户端）**
```json
{
  "type": "res",
  "id": "uuid-xxx",
  "ok": true,
  "payload": { ... }
}
```

**ErrorResponseFrame（服务端 → 客户端，出错时）**
```json
{
  "type": "res",
  "id": "uuid-xxx",
  "ok": false,
  "error": {
    "code": "METHOD_NOT_FOUND",
    "message": "Method 'xxx' not found"
  }
}
```

**EventFrame（服务端 → 客户端，单向推送）**
```json
{
  "type": "event",
  "event": "chat.message",
  "payload": { ... }
}
```

### 3.2 请求/响应关联

- 每个请求必须携带唯一 `id`（推荐 UUID）
- 响应通过相同的 `id` 关联到请求
- 事件帧没有 `id`，通过 `event` 字段标识类型

### 3.3 错误码

| 错误码 | 说明 |
|--------|------|
| `PARSE_ERROR` | JSON 解析失败 |
| `INVALID_REQUEST` | 请求格式不合法，或 scope 不足（如 `missing scope: operator.read`） |
| `METHOD_NOT_FOUND` | 方法不存在 |
| `INVALID_PARAMS` | 参数校验失败（schema 验证） |
| `INTERNAL_ERROR` | 服务端内部错误 |
| `NOT_PAIRED` | 设备未配对，需审批（details 中包含 `PAIRING_REQUIRED`） |
| `UNAUTHORIZED` | 认证失败 |
| `AUTH_TOKEN_MISMATCH` | Token 不匹配（可信客户端可尝试一次设备令牌重试） |
| `AUTH_SCOPE_MISMATCH` | 设备令牌已识别但不覆盖请求的 role/scope |
| `UNAVAILABLE` | 服务暂不可用（`details.reason: "startup-sidecars"` 时可重试） |

错误响应中的 `error.details` 可能包含：
- `canRetryWithDeviceToken`（布尔值）：是否可使用设备令牌重试
- `recommendedNextStep`：推荐恢复操作（如 `retry_with_device_token`、`update_auth_credentials` 等）
- `retryAfterMs`（仅 `UNAVAILABLE`）：建议等待时间

错误响应示例（scope 不足）：
```json
{
  "type": "res",
  "id": "xh-2",
  "ok": false,
  "error": {
    "code": "INVALID_REQUEST",
    "message": "missing scope: operator.read"
  }
}
```

### 3.4 协议版本

当前 Gateway 协议版本为 **v4**，在连接握手时协商。客户端发送 `minProtocol` + `maxProtocol` 范围（推荐 `minProtocol: 3, maxProtocol: 4`），服务端会拒绝不包含其当前协议版本的范围。原生客户端使用 v3 下界以保证向前兼容。

### 3.5 传输层载荷限制

- **握手前帧大小上限**：64 KiB（65536 字节）。超过此限制的帧会被服务端直接拒绝。
- **握手后限制**：连接成功后，客户端应遵循 `hello-ok.policy` 中的值：
  - `maxPayload`：单帧最大载荷（默认 26214400 字节，约 25 MB）
  - `maxBufferedBytes`：出站缓冲上限（默认 52428800 字节，约 50 MB）
- **`payload.large` 事件**：当启用诊断后，接近限制时 Gateway 会先发出 `payload.large` 事件警告（包含大小、限制、表面和安全原因代码），然后再执行关闭或丢弃。该事件不会保留消息正文、附件、Token 或秘密值。

### 3.6 幂等键

有副作用的方法（如 `chat.send`、`sessions.create`、`tools.invoke` 等）支持 **幂等键**（`idempotencyKey`），防止网络重试导致重复执行。客户端应在这些请求中包含唯一的幂等键。

### 3.7 帧序列号

每个客户端连接维护独立的每客户端序列号（`seq`），即使不同客户端因作用域过滤看到事件流的不同子集，广播事件在每条套接字上仍保持单调顺序。

---

## 四、核心 API 方法（实测验证，共 187 个）

以下为 Gateway 服务器在 `hello-ok` 响应中实际返回的完整方法列表。根据虾Hub 的需求，按功能域分组。

### 4.1 系统与健康

| 方法 | Scope | 说明 |
|------|-------|------|
| `health` | read | 系统健康检查 |
| `status` | read | 实例运行状态（含 agents、channels、plugins 信息） |
| `diagnostics.stability` | read | 稳定性诊断 |
| `logs.tail` | read | 实时日志流 |
| `usage.status` | read | 用量统计 |
| `usage.cost` | read | 费用统计 |

### 4.2 Agent 管理

| 方法 | Scope | 说明 |
|------|-------|------|
| `agents.list` | read | 列出所有 Agent |
| `agents.create` | write | 创建 Agent |
| `agents.update` | write | 更新 Agent 配置 |
| `agents.delete` | admin | 删除 Agent |
| `agents.files.list` | read | 列出 Agent 文件 |
| `agents.files.get` | read | 获取 Agent 文件内容 |
| `agents.files.set` | write | 设置 Agent 文件 |

### 4.3 会话与消息

| 方法 | Scope | 说明 |
|------|-------|------|
| `sessions.list` | read | 列出所有会话 |
| `sessions.create` | write | 创建新会话 |
| `sessions.send` | write | 向会话发送消息 |
| `sessions.get` | read | 获取会话详情（不公开） |
| `chat.send` | write | 发送聊天消息 |
| `chat.history` | read | 获取聊天历史 |
| `chat.abort` | write | 中止当前响应 |

### 4.4 渠道管理（Channel = WeChat 等消息通道）

| 方法 | Scope | 说明 |
|------|-------|------|
| `channels.status` | read | 获取渠道状态 |
| `channels.start` | write | 启动渠道 |
| `channels.stop` | write | 停止渠道 |
| `channels.logout` | write | 登出渠道 |

### 4.5 模型管理

| 方法 | Scope | 说明 |
|------|-------|------|
| `models.list` | read | 列出可用模型 |
| `models.authStatus` | read | 模型认证状态 |
| `models.authLogout` | write | 登出模型认证 |

### 4.6 工具调用

| 方法 | Scope | 说明 |
|------|-------|------|
| `tools.catalog` | read | 工具目录 |
| `tools.effective` | read | 当前生效的工具列表 |
| `tools.invoke` | write | 直接调用工具 |

### 4.7 任务管理

| 方法 | Scope | 说明 |
|------|-------|------|
| `tasks.list` | read | 列出任务 |
| `tasks.get` | read | 获取任务详情 |
| `tasks.cancel` | write | 取消任务 |

### 4.8 环境与配置

| 方法 | Scope | 说明 |
|------|-------|------|
| `environments.list` | read | 列出运行环境 |
| `environments.status` | read | 环境状态 |
| `config.get` | read | 获取配置 |
| `config.set` | admin | 设置配置 |
| `config.apply` | admin | 应用配置 |
| `config.patch` | admin | 部分更新配置 |
| `config.schema` | read | 获取配置 Schema |
| `config.schema.lookup` | read | 查找配置 Schema |

### 4.9 Artifacts & Skills

| 方法 | Scope | 说明 |
|------|-------|------|
| `artifacts.list` | read | 列出产物 |
| `artifacts.get` | read | 获取产物 |
| `artifacts.download` | read | 下载产物 |
| `skills.status` | read | 技能状态 |
| `skills.search` | read | 搜索技能 |
| `skills.detail` | read | 技能详情 |
| `skills.securityVerdicts` | read | 技能安全判定 |
| `skills.skillCard` | read | 技能卡片 |

### 4.10 执行审批

| 方法 | Scope | 说明 |
|------|-------|------|
| `exec.approvals.get` | approvals | 获取审批配置 |
| `exec.approvals.set` | approvals | 设置审批配置 |
| `exec.approval.list` | approvals | 列出待审批请求 |
| `exec.approval.request` | write | 创建审批请求 |
| `exec.approval.resolve` | approvals | 审批决策 |

### 4.11 设备配对管理

| 方法 | Scope | 说明 |
|------|-------|------|
| `device.pair.list` | pairing | 列出配对设备 |
| `device.pair.approve` | pairing | 审批配对请求 |
| `device.pair.reject` | pairing | 拒绝配对请求 |
| `device.pair.remove` | pairing | 移除已配对设备 |
| `device.token.rotate` | pairing | 轮换设备令牌（同设备调用时回传新 bearer token） |
| `device.token.revoke` | pairing | 撤销设备令牌 |

> **设备令牌生命周期**：配对成功后，`hello-ok.auth.deviceToken` 会返回签发的设备令牌，客户端应持久化。后续重连复用该令牌时也应复用已批准的 scope 集合。令牌可通过 `device.token.rotate` 轮换（返回新 token，需持久化替换旧 token）和 `device.token.revoke` 撤销。令牌签发/轮换/撤销受限于设备配对条目中已批准的角色集，不能扩展到审批未授予的角色。

### 4.12 TTS 语音

| 方法 | Scope | 说明 |
|------|-------|------|
| `tts.status` | read | TTS 状态 |
| `tts.providers` | read | TTS 提供商列表 |
| `tts.personas` | read | TTS 人设列表 |
| `tts.enable` / `tts.disable` | write | 启用/禁用 TTS |
| `tts.convert` | write | 文字转语音 |
| `tts.speak` | write | 语音输出 |

### 4.13 Talk 实时会话（语音通话）

| 方法 | Scope | 说明 |
|------|-------|------|
| `talk.catalog` | read | Talk 提供商目录（语音、转写、实时语音） |
| `talk.config` | read/talk.secrets | Talk 生效配置（`includeSecrets: true` 需 `operator.talk.secrets`） |
| `talk.session.create` | write | 创建 Talk 会话（gateway-relay / transcription / managed-room） |
| `talk.session.join` | write | 加入托管房间会话 |
| `talk.session.appendAudio` | write | 追加 base64 PCM 音频输入 |
| `talk.session.startTurn` | write | 开始轮次 |
| `talk.session.endTurn` | write | 结束轮次 |
| `talk.session.cancelTurn` | write | 取消轮次 |
| `talk.session.cancelOutput` | write | 停止助手音频输出（VAD 打断） |
| `talk.session.submitToolResult` | write | 提交工具调用结果 |
| `talk.session.steer` | write | 实时引导 |
| `talk.session.close` | write | 关闭会话 |
| `talk.client.create` | write | 创建客户端拥有的实时会话（WebRTC / provider-websocket） |
| `talk.client.toolCall` | write | 客户端实时会话工具调用转发 |
| `talk.client.steer` | write | 客户端实时会话引导 |
| `talk.speak` | write | 语音合成 |
| `talk.mode` | write | 设置/广播 Talk 模式状态 |
| `talk.event` | — | Talk 事件通道（实时、转写、STT/TTS 等） |

### 4.14 命令与插件

| 方法 | Scope | 说明 |
|------|-------|------|
| `commands.list` | read | 列出命令 |
| `plugins.uiDescriptors` | read | 插件 UI 描述 |
| `plugins.sessionAction` | write | 插件会话操作 |
| `plugin.approval.list/request/resolve` | approvals | 插件审批 |
| `plugin.approval.waitDecision` | approvals | 等待插件审批决定（超时返回 null） |

### 4.15 会话高级控制

> 以下方法在官方文档中有详细说明，虾Hub 后续版本可能需要用到。

| 方法 | Scope | 说明 |
|------|-------|------|
| `sessions.subscribe` | read | 订阅会话变更事件（实时推送会话状态变化） |
| `sessions.unsubscribe` | read | 取消会话变更事件订阅 |
| `sessions.messages.subscribe` | read | 订阅某个会话的转录/消息事件流 |
| `sessions.messages.unsubscribe` | read | 取消转录/消息事件流订阅 |
| `sessions.preview` | read | 返回会话的有界转录预览 |
| `sessions.describe` | read | 返回精确会话键对应的会话行 |
| `sessions.resolve` | read | 解析/规范化会话目标 |
| `sessions.steer` | write | 活动会话的中断并引导 |
| `sessions.abort` | write | 中止会话的活动工作（支持 key + runId） |
| `sessions.patch` | write | 更新会话元数据/覆盖项 |
| `sessions.reset` | write | 重置会话 |
| `sessions.delete` | admin | 删除会话 |
| `sessions.compact` | admin | 压缩会话历史 |
| `sessions.usage` | read | 每个会话的用量摘要 |
| `sessions.usage.timeseries` | read | 会话时间序列用量 |
| `sessions.usage.logs` | read | 会话使用日志条目 |
| `chat.inject` | write | 注入仅转录的聊天消息（不触发 Agent 响应） |

### 4.16 节点管理

> 节点（Node）是能力宿主设备，如 iPhone 摄像头、屏幕录制等。虾Hub 作为 operator 客户端，可管理已连接的节点。

| 方法 | Scope | 说明 |
|------|-------|------|
| `node.pair.request` | — | 请求节点配对 |
| `node.pair.list` | pairing | 列出节点配对请求 |
| `node.pair.approve` | pairing + (write/admin) | 审批节点配对（根据 commands 可能需要额外 scope） |
| `node.pair.reject` | pairing | 拒绝节点配对 |
| `node.pair.remove` | pairing | 移除已配对节点 |
| `node.pair.verify` | pairing | 校验节点配对 |
| `node.list` | read | 列出已知/已连接节点 |
| `node.describe` | read | 节点详情 |
| `node.rename` | write | 更新节点标签 |
| `node.invoke` | write | 将命令转发到已连接节点 |
| `node.invoke.result` | read | 获取调用结果 |
| `node.event` | — | 节点发起的事件 |
| `node.pending.pull` | — | 节点拉取待处理工作 |
| `node.pending.ack` | — | 节点确认待处理工作 |
| `node.pending.enqueue` | write | 入队离线节点的持久待处理工作 |
| `node.pending.drain` | write | 排空离线节点待处理队列 |
| `node.pluginSurface.refresh` | — | 刷新插件表面 URL |

> **node.pair.approve 的额外 Scope 检查**：审批时除基础方法 scope 外，还会根据节点的 commands 执行额外检查 — 无 commands 需 `operator.pairing`；含非 exec commands 需额外 `operator.write`；含 `system.run` 等危险命令需额外 `operator.admin`。

### 4.17 定时自动化（Cron）

| 方法 | Scope | 说明 |
|------|-------|------|
| `cron.get` | read | 获取 cron 作业 |
| `cron.list` | read | 列出所有 cron 作业 |
| `cron.status` | read | cron 系统状态 |
| `cron.add` | write | 添加 cron 作业 |
| `cron.update` | write | 更新 cron 作业 |
| `cron.remove` | write | 删除 cron 作业 |
| `cron.run` | write | 手动触发 cron 作业 |
| `cron.runs` | read | 查看 cron 运行历史 |
| `wake` | write | 调度一次性或下一次心跳的唤醒文本注入 |

### 4.18 其他补充方法

| 方法 | Scope | 说明 |
|------|-------|------|
| `gateway.identity.get` | read | Gateway 设备身份（relay 和配对使用） |
| `system-presence` | read | 已连接 operator/node 的在线状态快照 |
| `system-event` | write | 追加系统事件/更新在线状态 |
| `last-heartbeat` | read | 最新持久化的心跳事件 |
| `set-heartbeats` | admin | 切换 Gateway 心跳处理 |
| `agent.identity.get` | read | Agent 或会话的生效助手身份 |
| `agent.wait` | read | 等待运行完成，返回终止快照 |
| `web.login.start` | write | 启动 QR 码 / Web 登录流程 |
| `web.login.wait` | write | 等待 QR 码登录流程完成 |
| `push.test` | write | 向 iOS 节点发送测试 APNs 推送 |
| `voicewake.get` | read | 获取唤醒词触发器 |
| `voicewake.set` | write | 更新唤醒词触发器 |
| `secrets.reload` | admin | 重新解析活动 SecretRefs |
| `secrets.resolve` | admin | 解析命令目标密钥分配 |
| `update.run` | admin | 运行 Gateway 更新流程 |
| `update.status` | read | 最新更新重启哨兵 |
| `skills.install` | admin | 安装技能（ClawHub / 上传 / Gateway 安装器） |
| `skills.update` | admin | 更新技能 |
| `skills.upload.begin/chunk/commit` | admin | 上传私有技能归档（需 `allowUploadedArchives`） |
| `skills.bins` | — | 技能可执行文件列表（节点用） |
| `exec.approval.waitDecision` | approvals | 等待 exec 审批决定（超时返回 null） |
| `exec.approvals.node.get` | approvals | 获取节点 exec 审批策略 |
| `exec.approvals.node.set` | approvals | 设置节点 exec 审批策略 |

---

## 4B、广播事件作用域门控

服务端推送的 WebSocket 广播事件受作用域门控，确保配对作用域受限的会话不会被动接收敏感内容：

- **聊天、Agent 和工具结果帧**（包括流式 `agent` 事件和工具调用结果）：至少需要 `operator.read`。没有该 scope 的会话会完全跳过这些帧。
- **插件定义的 `plugin.*` 广播**：根据插件注册方式受 `operator.write` 或 `operator.admin` 门控。
- **Status 和传输事件**（`heartbeat`、`presence`、`tick`、连接/断开生命周期等）：不受限制，所有已认证会话均可接收。
- **未知广播事件族**：默认受作用域门控（失败关闭），除非已注册的处理器明确放宽限制。

> **对虾Hub 的意义**：只要请求了 `operator.read` scope（虾Hub 推荐请求中包含），就能正常接收所有聊天和 Agent 事件。无需特别处理，但需确保 scope 不被服务端降级。

## 4C、完整事件类型列表

以下为官方文档中列出的所有事件类型：

| 事件 | 说明 | 门控 |
|------|------|------|
| `chat` | UI 聊天更新（含 `chat.inject` 等仅转录事件） | `operator.read` |
| `chat.message` / `chat.typing` / `chat.delta` / `chat.done` | 聊天流式响应事件 | `operator.read` |
| `chat.tool_call` / `chat.tool_result` | 工具调用通知 | `operator.read` |
| `session.message` | 已订阅会话的转录/消息流更新 | `operator.read` |
| `session.tool` | 已订阅会话的工具事件流 | `operator.read` |
| `sessions.changed` | 会话索引或元数据已更改 | `operator.read` |
| `presence` | 系统在线状态快照更新 | 不受限 |
| `tick` | 周期性 keepalive 事件 | 不受限 |
| `health` | Gateway 健康快照更新 | 不受限 |
| `heartbeat` | 心跳事件流更新 | 不受限 |
| `cron` | cron 运行/作业变更事件 | 不受限 |
| `shutdown` | Gateway 关闭通知 | 不受限 |
| `connect.challenge` | 连接前质询（nonce + ts） | 不受限 |
| `node.pair.requested` | 节点配对请求 | 不受限 |
| `node.pair.resolved` | 节点配对结果 | 不受限 |
| `node.invoke.request` | 节点调用请求广播 | 不受限 |
| `device.pair.requested` | 设备配对请求 | 不受限 |
| `device.pair.resolved` | 设备配对结果 | 不受限 |
| `exec.approval.requested` | exec 审批请求 | 不受限 |
| `exec.approval.resolved` | exec 审批结果 | 不受限 |
| `plugin.approval.requested` | 插件审批请求 | 不受限 |
| `plugin.approval.resolved` | 插件审批结果 | 不受限 |
| `voicewake.changed` | 唤醒词触发器配置已更改 | 不受限 |
| `payload.large` | 载荷接近/超过限制警告（诊断模式） | 不受限 |

---

## 五、核心交互场景

### 5.1 发送消息并接收流式响应

这是虾Hub 最核心的交互——用户在聊天页发消息：

```
虾Hub App                              OpenClaw Gateway
    │                                       │
    │  ① 用户输入消息，点击发送                 │
    │                                       │
    │  RequestFrame:                        │
    │  {                                    │
    │    "type": "req",                     │
    │    "id": "msg-001",                   │
    │    "method": "chat.send",             │
    │    "params": {                        │
    │      "agentId": "product-shrimp",     │
    │      "text": "帮我分析一下这个需求",      │
    │      "sessionId": "session-xxx"       │
    │    }                                  │
    │  }                                    │
    │  ─────────────────────────────────────►│
    │                                       │
    │  ② 立即确认收到                          │
    │  ResponseFrame:                       │
    │  {                                    │
    │    "type": "res",                     │
    │    "id": "msg-001",                   │
    │    "ok": true,                        │
    │    "payload": { "messageId": "m-123" }│
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
    │  ③ Agent 开始思考，流式推送                │
    │  EventFrame (typing):                 │
    │  {                                    │
    │    "type": "event",                   │
    │    "event": "chat.typing",            │
    │    "payload": {                       │
    │      "agentId": "product-shrimp",     │
    │      "sessionId": "session-xxx"       │
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
    │  ④ 流式文本推送 (多次)                    │
    │  EventFrame (delta):                  │
    │  {                                    │
    │    "type": "event",                   │
    │    "event": "chat.delta",             │
    │    "payload": {                       │
    │      "agentId": "product-shrimp",     │
    │      "sessionId": "session-xxx",      │
    │      "delta": "从产品角度来看",           │  ← 增量文本片段
    │      "role": "assistant"              │
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
    │  ⑤ 工具调用通知 (可选，如果 Agent 调了工具) │
    │  EventFrame (tool_call):              │
    │  {                                    │
    │    "type": "event",                   │
    │    "event": "chat.tool_call",         │
    │    "payload": {                       │
    │      "agentId": "product-shrimp",     │
    │      "toolName": "数据分析工具",         │
    │      "status": "running",             │
    │      "params": { ... }                │
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
    │  ⑥ 工具完成通知                          │
    │  EventFrame (tool_result):            │
    │  {                                    │
    │    "type": "event",                   │
    │    "event": "chat.tool_result",       │
    │    "payload": {                       │
    │      "toolName": "数据分析工具",         │
    │      "status": "completed",           │
    │      "result": { ... }                │
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
    │  ⑦ 响应完成                             │
    │  EventFrame (done):                   │
    │  {                                    │
    │    "type": "event",                   │
    │    "event": "chat.done",              │
    │    "payload": {                       │
    │      "agentId": "product-shrimp",     │
    │      "sessionId": "session-xxx",      │
    │      "usage": {                       │
    │        "promptTokens": 520,           │
    │        "completionTokens": 380        │
    │      }                                │
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
```

**虾Hub 侧处理逻辑：**
1. 发送 `chat.send` 请求后，UI 立即显示用户消息气泡
2. 收到 `chat.typing` 事件 → 显示"正在思考..."动画
3. 收到 `chat.delta` 事件 → 逐片段追加到 Agent 消息气泡中（流式渲染）
4. 收到 `chat.tool_call` → 在消息中插入工具调用卡片
5. 收到 `chat.tool_result` → 更新工具卡片状态
6. 收到 `chat.done` → 标记消息完成，移除 typing 状态

### 5.2 获取 Agent 列表

虾Hub 首页需要展示所有可用的虾：

```
虾Hub App                              OpenClaw Gateway
    │                                       │
    │  RequestFrame:                        │
    │  {                                    │
    │    "type": "req",                     │
    │    "id": "init-001",                  │
    │    "method": "agents.list",           │
    │    "params": {}                       │
    │  }                                    │
    │  ─────────────────────────────────────►│
    │                                       │
    │  ResponseFrame:                       │
    │  {                                    │
    │    "type": "res",                     │
    │    "id": "init-001",                  │
    │    "ok": true,                        │
    │    "payload": {                       │
    │      "agents": [                      │
    │        {                              │
    │          "id": "product-shrimp",      │
    │          "name": "产品虾",             │
    │          "model": "gpt-4o",           │
    │          "description": "...",        │
    │          "status": "idle",            │
    │          "tools": ["analyze","prd"]   │
    │        },                             │
    │        {                              │
    │          "id": "code-shrimp",         │
    │          "name": "代码虾",             │
    │          ...                          │
    │        }                              │
    │      ]                                │
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
```

### 5.3 多实例并行连接

虾Hub 的核心价值是管理多个 OpenClaw 实例，每个实例独立连接：

```
┌──────────────────────────────────────────────────────┐
│                    虾Hub App                          │
│                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ Connection 1 │  │ Connection 2 │  │ Connection 3 │ │
│  │ MacBook      │  │ 云服务器      │  │ 办公室        │ │
│  │              │  │              │  │              │ │
│  │ ws://192.168 │  │ wss://bj.my │  │ ws://10.0.0 │ │
│  │ .1.100:18789│  │ server:18789│  │ .50:18789   │ │
│  │              │  │              │  │              │ │
│  │ Token: aaa..│  │ Token: bbb..│  │ Token: ccc..│ │
│  │ DeviceId: 11│  │ DeviceId: 22│  │ DeviceId: 33│ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │
│         │                 │                 │         │
└─────────┼─────────────────┼─────────────────┼─────────┘
          │                 │                 │
          ▼                 ▼                 ▼
   OpenClaw Instance 1  Instance 2       Instance 3
   (3 agents)         (2 agents)        (2 agents, offline)
```

**关键设计原则：**
- 每个实例维护独立的 WebSocket 连接、独立的认证状态、独立的重连策略
- 实例之间完全隔离，一个实例断连不影响其他实例
- 虾Hub 本地维护一个实例注册表，存储每个实例的 URL + Device Token

### 5.4 加载历史消息

```
虾Hub App                              OpenClaw Gateway
    │                                       │
    │  RequestFrame:                        │
    │  {                                    │
    │    "type": "req",                     │
    │    "id": "hist-001",                  │
    │    "method": "chat.history",          │
    │    "params": {                        │
    │      "agentId": "product-shrimp",     │
    │      "sessionId": "session-xxx",      │
    │      "limit": 50                      │
    │    }                                  │
    │  }                                    │
    │  ─────────────────────────────────────►│
    │                                       │
    │  ResponseFrame:                       │
    │  {                                    │
    │    "type": "res",                     │
    │    "id": "hist-001",                  │
    │    "ok": true,                        │
    │    "payload": {                       │
    │      "messages": [                    │
    │        {                              │
    │          "id": "m-100",               │
    │          "role": "user",              │
    │          "text": "帮我分析需求",        │
    │          "timestamp": 1718000000      │
    │        },                             │
    │        {                              │
    │          "id": "m-101",               │
    │          "role": "assistant",         │
    │          "text": "从产品角度...",       │
    │          "timestamp": 1718000005,     │
    │          "toolCalls": [               │
    │            {                          │
    │              "name": "analyze",       │
    │              "status": "completed"    │
    │            }                          │
    │          ]                            │
    │        }                              │
    │      ],                               │
    │      "hasMore": true,                 │
    │      "cursor": "cursor-xxx"           │
    │    }                                  │
    │  }                                    │
    │  ◄─────────────────────────────────────│
    │                                       │
```

### 5.5 离线消息队列

当实例离线时，虾Hub 应实现本地消息队列：

```
虾Hub 本地                              OpenClaw 实例
    │                                       │
    │  用户发送消息                           │
    │  → 检测到实例离线                       │
    │  → 存入本地 pendingQueue               │
    │  → UI 显示消息(带"发送中"标记)           │
    │                                       │
    │  ... 实例离线中 ...                     │
    │                                       │
    │  实例恢复上线                            │
    │  → 检测到连接恢复                       │
    │  → 按顺序逐条发送 pendingQueue           │
    │  ─────────────────────────────────────►│
    │  ─────────────────────────────────────►│
    │  → 收到确认 → 更新消息状态为"已发送"      │
    │  → 清空 pendingQueue                   │
    │                                       │
```

---

## 六、本地存储设计

### 6.1 虾Hub 本地需要持久化的数据

| 数据 | 存储方式 | 说明 |
|------|---------|------|
| 实例列表 | SQLite / Hive | 每个实例的 name, url, 连接状态 |
| Device Token | 加密存储 (Keychain/EncryptedSharedPreferences) | 每个实例一个 token |
| Ed25519 密钥对 | 加密存储 | 每个实例一对密钥 |
| 聊天历史缓存 | SQLite | 最近 N 条消息，离线可查看 |
| Agent 元数据缓存 | SQLite / Hive | agent 名称、描述、头像等 |
| 快捷指令 | SQLite / Hive | 每个 agent 的自定义指令 |
| 个性化配置 | SQLite / Hive | 昵称、主题色、头像等 |
| 待发送消息队列 | SQLite | 离线时暂存的消息 |

### 6.2 安全存储要求

- **Device Token** 和 **Ed25519 私钥** 必须使用系统级安全存储，禁止明文存储
- iOS: 使用 Keychain Services，设置 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Android: 使用 EncryptedSharedPreferences 或 Android Keystore
- 聊天历史等普通数据可使用 SQLite 或 Hive

---

## 七、Agent 路由机制

### 7.1 消息如何路由到正确的虾

OpenClaw 使用 **9 级优先级匹配** 决定哪个 Agent 处理消息：

```
优先级从高到低:
1. peer 精确匹配 (特定用户 → 特定 Agent)
2. peer 通配符匹配
3. accountId + channel 匹配
4. guildId / teamId 匹配
5. channel 级匹配
6. role 匹配
7. thread 继承
8. 跨 channel 身份链接
9. 默认 Agent
```

**对虾Hub 的意义：**

虾Hub 作为 operator 客户端，可以直接通过 `agentId` 指定与哪个 Agent 通信，无需依赖路由规则。这意味着虾Hub 可以自由选择与任何 Agent 对话。

### 7.2 Session Key 格式

OpenClaw 的 session key 格式为：`agent:<agentId>:<rest>`

其中 `<rest>` 取决于 `dmScope` 配置：
- `main` → 所有对话共享一个 session
- `per-peer` → 每个用户一个 session
- `per-channel-peer` → 每个 channel × 用户一个 session

虾Hub 应为每个 Agent 维护独立的 sessionId。

---

## 八、完整生命周期时序图

```
用户打开虾Hub App
    │
    ├─ 加载本地实例列表
    │
    ├─ 对每个在线实例发起 WebSocket 连接
    │   ├─ 使用已存储的 Device Token 认证
    │   ├─ 完成 challenge-nonce 握手
    │   └─ 接收初始 snapshot
    │
    ├─ 调用 agents.list 获取每个实例的 Agent 列表
    │
    ├─ 渲染首页 (虾列表 + 统计栏)
    │
    │   用户点击某个虾
    │   │
    │   ├─ 调用 chat.history 加载历史消息
    │   ├─ 进入聊天页面
    │   │
    │   │   用户发送消息
    │   │   │
    │   │   ├─ 发送 chat.send
    │   │   ├─ 接收 chat.typing → 显示思考动画
    │   │   ├─ 接收 chat.delta × N → 流式渲染文本
    │   │   ├─ 接收 chat.tool_call → 显示工具卡片
    │   │   ├─ 接收 chat.tool_result → 更新卡片状态
    │   │   └─ 接收 chat.done → 完成
    │   │
    │   │   用户点击返回
    │   │   └─ 保持 WebSocket 连接，后台继续接收事件
    │   │
    │   用户切换到"消息"tab
    │   └─ 根据本地缓存的消息列表渲染
    │
    │   用户切换到"实例"tab
    │   └─ 显示所有实例状态
    │
    │   用户添加新实例
    │   │
    │   ├─ 扫码 → 解码 QR Code
    │   ├─ 生成 Ed25519 密钥对
    │   ├─ 使用 Bootstrap Token 连接
    │   ├─ 发起配对请求
    │   ├─ 等待 Owner 审批
    │   ├─ 审批通过 → 保存 Device Token
    │   └─ 使用新 Token 重连 → 获取 Agent 列表
    │
    └─ 用户退出 App
        └─ 关闭所有 WebSocket 连接
            (下次打开时自动重连)
```

---

## 九、虾Hub 客户端开发要点

### 9.1 连接管理器设计（必须实现设备身份）

```
class WebSocketManager {
  connections: Map<instanceId, WebSocketConnection>
  
  connect(instanceId, url, token, deviceKeypair)
  disconnect(instanceId)
  reconnect(instanceId)  // 指数退避
  send(instanceId, method, params) → Promise<Response>
  on(instanceId, event, callback)  // 事件监听
  getStatus(instanceId) → 'connected' | 'connecting' | 'disconnected' | 'pairing_required'
  
  // 设备身份管理
  generateDeviceKeypair() → { publicKey, privateKey, deviceId }
  loadDeviceKeypair(instanceId) → DeviceKeypair
  signChallenge(nonce, keypair, connectParams) → DeviceAuth
}
```

**连接状态机：**
```
IDLE → CONNECTING → CHALLENGE_RECEIVED → SIGNING → AUTHENTICATING
  → CONNECTED (hello-ok)
  → PAIRING_REQUIRED (等待审批，定期重试)
  → ERROR (Token错误等，提示用户)
  → DISCONNECTED (断线，指数退避重连)
```

### 9.2 关键技术选型建议

| 能力 | Flutter | React Native |
|------|---------|-------------|
| WebSocket | `web_socket_channel` | 原生 WebSocket API |
| Ed25519 签名 | `ed25519_edwards` / `cryptography` | `react-native-ed25519` |
| 安全存储 | `flutter_secure_storage` | `react-native-keychain` |
| 本地数据库 | `drift` (SQLite) | `react-native-mmkv` + SQLite |
| QR 解码 | `mobile_scanner` | `react-native-vision-camera` |
| 状态管理 | `riverpod` | `zustand` / `jotai` |

### 9.3 必须处理的边界情况

1. **首次连接需设备审批**：新设备 ID 首次连接会收到 `PAIRING_REQUIRED`，需引导用户在服务器端执行 `openclaw devices approve <requestId>`。虾Hub 应在 UI 中展示清晰的审批指引。
2. **Ed25519 密钥对持久化**：密钥对必须在 App 升级、重启后保持不变，否则每次生成新密钥对会导致需要重新审批。使用 iOS Keychain / Android Keystore 存储。
3. **Token 过期/吊销**：收到 `token_mismatch` 或 `UNAUTHORIZED` 错误时，提示用户重新输入 Token
4. **多实例部分离线**：一个实例断连不影响其他实例的正常通信
5. **Agent 繁忙**：同一 Agent 正在处理请求时，新请求应排队或提示
6. **消息顺序**：流式 delta 可能乱序，需按序号拼接
7. **后台保活**：iOS/Android 后台 WebSocket 会被系统杀死，需要本地通知机制
8. **Gateway Token 轮换**：close code 4001 表示 Token 已变更，需提示用户更新
9. **签名时间偏移**：`signedAt` 有有效期限制，确保客户端时间与服务端偏差不超过阈值

---

## 附录 A：实测验证记录

> 测试环境：OpenClaw Gateway v2026.x.x（示例版本），协议版本 4，服务器 `ws://127.0.0.1:18789`
> 测试时间：2026-06-13

### A.1 握手流程实测结果

| 步骤 | 预期 | 实际 | 结论 |
|------|------|------|------|
| WebSocket 连接 (带 token query) | 连接成功 | ✅ 连接成功 | 通过 |
| 收到 connect.challenge | 包含 nonce + ts | ✅ `nonce: "uuid-v4"`, `ts: 1700000000000` | 通过 |
| 无设备身份 + Token 认证 | 连接成功，有权限 | ⚠️ 连接成功 (hello-ok) 但 **所有 scope 被清空** | 重要发现 |
| 无设备身份调用 API | 正常返回 | ❌ 全部返回 `missing scope: operator.read` | 确认必须设备身份 |
| Ed25519 设备签名 | 签名验证通过 | ✅ 签名验证通过，设备 ID 正确 | 通过 |
| 新设备首次连接 | 配对审批 | ✅ 返回 `PAIRING_REQUIRED` + `requestId` | 符合预期 |
| hello-ok 响应 | 包含方法列表 | ✅ 包含 187 个可用方法 | 通过 |
| health 事件 | 系统状态推送 | ✅ 包含 agents、channels、plugins 详细信息 | 通过 |
| tick 事件 | 心跳 | ✅ 约每 30 秒一次，包含 seq 序号 | 通过 |

### A.2 无设备身份时的 Scope 清空机制（源码级验证）

关键源码路径：`src/gateway/server/ws-connection/message-handler.ts`

```typescript
// Line 698-701: Default-deny: scopes must be explicit
let scopes = Array.isArray(connectParams.scopes) ? connectParams.scopes : [];

// Line 842-847: Clear unbound scopes when no device identity
const clearUnboundScopes = () => {
  if (scopes.length > 0) {
    scopes = [];
    connectParams.scopes = scopes;
  }
};

// Line 895-907: Device-less shared-auth connections have scopes cleared
if (!device && !skipLocalBackendSelfPairing &&
    shouldClearUnboundScopesForMissingDeviceIdentity({ ... })) {
  clearUnboundScopes();
}
```

**根本原因**：服务端的安全策略是 "default-deny" — 没有设备身份（Ed25519 keypair）的客户端，即使提供了有效的 Gateway Token，也会被清空所有 operator scope。这是一个安全设计决策，防止无法追踪的匿名连接获取操作权限。

### A.3 已确认的可用方法列表（187 个）

从 `hello-ok` 响应的 `features.methods` 数组中提取：

```
health, diagnostics.stability, doctor.memory.status, doctor.memory.dreamDiary,
doctor.memory.backfillDreamDiary, doctor.memory.resetDreamDiary,
doctor.memory.resetGroundedShortTerm, doctor.memory.repairDreamingArtifacts,
doctor.memory.dedupeDreamDiary, doctor.memory.remHarness, logs.tail,
channels.status, channels.start, channels.stop, channels.logout, status,
usage.status, usage.cost, tts.status, tts.providers, tts.personas, tts.enable,
tts.disable, tts.convert, tts.setProvider, tts.setPersona, config.get,
config.set, config.apply, config.patch, config.schema, config.schema.lookup,
exec.approvals.get, exec.approvals.set, exec.approvals.node.get,
exec.approvals.node.set, exec.approval.get, exec.approval.list,
exec.approval.request, exec.approval.waitDecision, exec.approval.resolve,
plugin.approval.list, plugin.approval.request, plugin.approval.waitDecision,
plugin.approval.resolve, plugins.uiDescriptors, plugins.sessionAction,
wizard.start, wizard.next, wizard.cancel, wizard.status, talk.catalog,
talk.config, talk.client.create, talk.client.toolCall, talk.client.steer,
talk.session.create, talk.session.join, talk.session.appendAudio,
talk.session.startTurn, talk.session.endTurn, talk.session.cancelTurn,
talk.session.cancelOutput, talk.session.submitToolResult, talk.session.steer,
talk.session.close, talk.speak, talk.mode, commands.list, models.list,
models.authStatus, models.authLogout, tools.catalog, tools.effective,
tools.invoke, tasks.list, tasks.get, tasks.cancel, environments.list,
environments.status, agents.list, agents.create, agents.update, agents.delete,
agents.files.list, agents.files.get, agents.files.set, artifacts.list,
artifacts.get, artifacts.download, skills.status, skills.search, skills.detail,
skills.securityVerdicts, skills.skillCard, ...
```

### A.4 已加载的插件列表

从 `health` 事件中提取：
```json
{
  "plugins": {
    "loaded": [
      "browser", "canvas", "device-pair", "file-transfer",
      "memory-core", "openclaw-weixin", "phone-control", "talk-voice"
    ],
    "errors": []
  }
}
```

### A.5 已配置的 Channel

```json
{
  "channels": {
    "openclaw-weixin": {
      "accountId": "example-im-bot",
      "enabled": true,
      "configured": true,
      "running": true
    }
  },
  "channelOrder": ["openclaw-weixin"],
  "defaultAgentId": "main",
  "agents": [{ "agentId": "main", "isDefault": true, "sessions": { "count": 4 } }]
}
```

### A.6 实测 API 响应格式（2026-06-13 验证通过）

以下为在 `ws://127.0.0.1:18789`（OpenClaw v2026.x.x 示例版本）上实测的完整响应结构（已脱敏）。

#### status — 系统状态
```json
{
  "ok": true,
  "payload": {
    "runtimeVersion": "2026.x.x",
    "heartbeat": {
      "defaultAgentId": "main",
      "agents": [
        { "agentId": "main", "enabled": true, "every": "30m", "everyMs": 1800000 }
      ]
    },
    "channelSummary": ["openclaw-weixin: configured"],
    "tasks": {
      "total": 0, "active": 0, "terminal": 0, "failures": 0,
      "byStatus": { "queued":0,"running":0,"succeeded":0,"failed":0,
                    "timed_out":0,"cancelled":0,"lost":0 },
      "byRuntime": { "subagent":0,"acp":0,"cli":0,"cron":0 }
    },
    "sessions": {
      "count": 7,
      "defaults": { "model": "example-model", "contextTokens": 200000 },
      "recent": [{
        "agentId": "main", "key": "agent:main:main", "kind": "direct",
        "sessionId": "uuid", "model": "example-model",
        "inputTokens": 6000, "outputTokens": 300,
        "totalTokens": 38000, "percentUsed": 19, "contextTokens": 200000
      }]
    }
  }
}
```

#### agents.list — Agent 列表
```json
{
  "ok": true,
  "payload": {
    "defaultId": "main",
    "mainKey": "main",
    "scope": "per-sender",
    "agents": [
      {
        "id": "main",
        "workspace": "/path/to/openclaw/workspace",
        "agentRuntime": { "id": "auto", "source": "implicit" },
        "thinkingDefault": "high",
        "thinkingOptions": ["off","minimal","low","medium","high","xhigh","max"],
        "model": { "primary": "example/model-name" }
      },
      {
        "id": "agent_example_01",
        "name": "示例虾A",
        "identity": { "name": "示例角色描述" },
        "model": { "primary": "example/model-name" }
      },
      {
        "id": "agent_example_02",
        "name": "示例虾B",
        "identity": { "name": "示例角色描述" },
        "model": { "primary": "example/model-name" }
      },
      {
        "id": "agent_example_03",
        "name": "示例虾C",
        "model": { "primary": "example/model-name" }
      }
    ]
  }
}
```
> **对虾Hub的意义**：`agents` 数组直接映射到首页"虾列表"。`id` 用于路由，`name` 用于显示名，`identity.name` 可用作描述，`model.primary` 可展示模型标签。

#### models.list — 可用模型
```json
{
  "ok": true,
  "payload": {
    "models": [
      {
        "id": "example-model-v1", "name": "example-model-v1",
        "provider": "example-provider", "api": "openai-completions",
        "contextWindow": 200000, "reasoning": true,
        "input": ["text", "image"], "available": true
      },
      {
        "id": "example-model-v2", "name": "example-model-v2",
        "provider": "example-provider", "api": "openai-completions",
        "contextWindow": 200000, "reasoning": true,
        "input": ["text", "image"], "available": true
      }
    ]
  }
}
```

#### environments.list — 运行环境
```json
{
  "ok": true,
  "payload": {
    "environments": [{
      "id": "gateway", "type": "local", "label": "Gateway local",
      "status": "available",
      "capabilities": ["agent.run", "sessions", "tools", "workspace"]
    }]
  }
}
```

#### tasks.list — 任务列表
```json
{ "ok": true, "payload": { "tasks": [] } }
```

#### usage.status — 用量与余额
```json
{ "ok": true, "payload": { "summary": "Balance ¥XX.XX" } }
```

#### sessions.list — 会话列表
返回每个 Agent 的活跃会话，包含 `key`（格式 `agent:{agentId}:{type}:{id}`）、`sessionId`（UUID）、`model`、Token 用量、上下文窗口使用率等信息。

#### config.get — 实例配置
返回 13 个顶层配置键。敏感字段（token 等）会被标记为 `__OPENCLAW_REDACTED__`。

#### artifacts.list — 产物列表
> 需要传入 `sessionKey`、`runId` 或 `taskId` 参数之一，否则返回：
> `"artifacts require one of sessionKey, runId, or taskId"`

### A.7 客户端常量参考值（官方文档）

> 来源：`src/gateway/client.ts` 和 `src/gateway/server-constants.ts`，协议 v4 下保持稳定，第三方客户端的推荐基线。

| 常量 | 默认值 | 来源 |
|------|--------|------|
| `PROTOCOL_VERSION` | `4` | `protocol/version.ts` |
| `MIN_CLIENT_PROTOCOL_VERSION` | `3` | `protocol/version.ts` |
| 请求超时（每个 RPC） | `30_000` ms | `client.ts` (`requestTimeoutMs`) |
| 预认证/连接质询超时 | `15_000` ms | `handshake-timeouts.ts` |
| 初始重连退避 | `1_000` ms | `client.ts` (`backoffMs`) |
| 最大重连退避 | `30_000` ms | `client.ts` (`scheduleReconnect`) |
| 设备令牌关闭后快速重试限制 | `250` ms | `client.ts` |
| `terminate()` 前强制停止宽限期 | `250` ms | `FORCE_STOP_TERMINATE_GRACE_MS` |
| `stopAndWait()` 默认超时 | `1_000` ms | `STOP_AND_WAIT_TIMEOUT_MS` |
| 默认 tick 间隔（hello-ok 前） | `30_000` ms | `client.ts` |
| tick 超时关闭 | 静默超过 `tickIntervalMs × 2` 时使用 code `4000` | `client.ts` |
| `MAX_PAYLOAD_BYTES` | `25 × 1024 × 1024` (25 MB) | `server-constants.ts` |
| Pre-handshake 帧大小上限 | `64 KiB` (65536 bytes) | 官方文档 - 传输层 |

> **对虾Hub 的意义**：
> - RPC 请求应设置 30 秒超时，超时后标记为失败
> - 连接质询等待 15 秒，超时视为连接失败
> - 重连退避从 1 秒起步，最大 30 秒（与 2.9 节的指数退避策略一致）
> - tick 超时为 `tickIntervalMs × 2`，若收到 `policy.tickIntervalMs: 15000` 则超时阈值为 30 秒

### A.8 设备认证迁移诊断码

当旧版客户端使用不兼容的签名方式连接时，`connect` 会在 `error.details.code` 下返回 `DEVICE_AUTH_*` 诊断码：

| 错误消息 | details.code | details.reason | 含义 |
|----------|-------------|---------------|------|
| `device nonce required` | `DEVICE_AUTH_NONCE_REQUIRED` | `device-nonce-missing` | 客户端省略了 `device.nonce` |
| `device nonce mismatch` | `DEVICE_AUTH_NONCE_MISMATCH` | `device-nonce-mismatch` | 客户端使用了过期/错误的 nonce |
| `device signature invalid` | `DEVICE_AUTH_SIGNATURE_INVALID` | `device-signature` | 签名载荷与 v2 载荷不匹配 |
| `device signature expired` | `DEVICE_AUTH_SIGNATURE_EXPIRED` | `device-signature-stale` | 签名时间戳超出允许偏移 |
| `device identity mismatch` | `DEVICE_AUTH_DEVICE_ID_MISMATCH` | `device-id-mismatch` | `device.id` 与公钥指纹不匹配 |
| `device public key invalid` | `DEVICE_AUTH_PUBLIC_KEY_INVALID` | `device-public-key` | 公钥格式/规范化失败 |

> **迁移建议**：始终等待 `connect.challenge` → 签名包含服务器 nonce 的 v3 载荷 → 在 `device.nonce` 中发送相同 nonce。旧版 `v2` 签名仍被接受，但推荐使用 `v3`（额外绑定 `platform` 和 `deviceFamily`）。

### A.9 认证失败恢复指引

认证失败时 `error.details` 中包含结构化恢复提示：

- `canRetryWithDeviceToken`（布尔值）：是否可以使用设备令牌重试
- `recommendedNextStep`：推荐操作，取值为：
  - `retry_with_device_token`：使用设备令牌重试
  - `update_auth_configuration`：更新认证配置
  - `update_auth_credentials`：更新认证凭据
  - `wait_then_retry`：等待后重试
  - `review_auth_configuration`：检查认证配置

**`AUTH_TOKEN_MISMATCH` 处理**：可信客户端（环回或带 `tlsFingerprint` 的 wss://）可尝试一次使用缓存设备令牌的重试。若仍失败，停止自动重连并提示用户。

**`AUTH_SCOPE_MISMATCH`**：设备令牌已被识别但不覆盖请求的角色/scope。不应呈现为错误令牌，应提示用户重新配对或批准更宽/更窄的 scope 契约。

**`UNAVAILABLE` + `startup-sidecars`**：Gateway 仍在完成启动时返回的可重试错误，`details.retryAfterMs` 指示等待时间。应在连接预算内重试，不要视为终止性握手失败。

### A.10 Exec 审批安全机制

当 exec 请求需要审批时：
- Gateway 广播 `exec.approval.requested`
- 操作员通过 `exec.approval.resolve` 处理（需 `operator.approvals` scope）
- 对于 `host=node` 的请求，`exec.approval.request` 必须包含 `systemRunPlan`（规范的 `argv`/`cwd`/`rawCommand`/会话元数据），缺少会被拒绝
- 审批后转发的 `node.invoke system.run` 调用复用该规范 `systemRunPlan` 作为权威上下文
- **防篡改**：如果调用方在准备和最终已审批的 `system.run` 转发之间篡改 `command`、`rawCommand`、`cwd`、`agentId` 或 `sessionKey`，Gateway 会拒绝运行

### A.11 节点角色与在线状态（官方文档补充）

**角色区分**：
- `operator`：控制平面客户端（CLI/UI/自动化），拥有 operator.* scope
- `node`：能力宿主（camera/screen/canvas/system.run），通过 caps/commands/permissions 声明能力

**节点能力声明**（connect 时声明）：
- `caps`：高级能力类别，如 `camera`、`canvas`、`screen`、`location`、`voice`、`talk`
- `commands`：可调用命令允许列表
- `permissions`：细粒度开关（如 `screen.record`、`camera.capture`）

**节点后台存活事件**：节点可调用 `node.event` 发送 `event: "node.presence.alive"`，记录后台唤醒期间的存活状态（不标记为已连接）。触发类型为封闭枚举：`background`、`silent_push`、`bg_app_refresh`、`significant_location`、`manual`、`connect`。

**在线状态**：`system-presence` 返回按设备身份键控的条目，包含 `deviceId`、`roles` 和 `scopes`，即使同一设备同时以 operator 和 node 身份连接也能分别显示。`node.list` 包含 `lastSeenAtMs` 和 `lastSeenReason` 字段。

### A.12 Agent 投递回退机制

`agent` 请求可包含 `deliver=true` 请求出站投递：
- `bestEffortDeliver=false`（默认）：无法解析的投递目标返回 `INVALID_REQUEST`
- `bestEffortDeliver=true`：无法解析外部路由时回退到仅会话执行
- 最终 `agent` 结果可能包含 `result.deliveryStatus`：`sent`、`suppressed`、`partial_failed`、`failed`

### A.13 与官方文档的差异清单

> 对比日期：2026-06-13，官方文档 URL：https://docs.openclaw.ai/zh-CN/gateway/protocol

以下为本次对比发现的主要差异，均已在本文档中补充：

| 差异点 | 原状态 | 补充位置 |
|--------|--------|---------|
| `hello-ok.policy` 字段（maxPayload / maxBufferedBytes / tickIntervalMs） | 缺失 | §2.2 握手流程图 |
| `hello-ok.auth` 字段（deviceToken / role / scopes） | 缺失 | §2.2 握手流程图 |
| `hello-ok.features.events` 数组 | 缺失 | §2.2 握手流程图 |
| Pre-handshake 64 KiB 帧大小限制 | 缺失 | §3.5 传输层载荷限制 |
| 幂等键（idempotencyKey） | 缺失 | §3.6 幂等键 |
| 帧序列号单调性 | 缺失 | §3.7 帧序列号 |
| 协议版本协商（minProtocol 3 / maxProtocol 4） | 不完整 | §3.4 协议版本 |
| tick 超时 = tickIntervalMs × 2, code 4000 | 不准确 | §2.8 心跳保活 |
| 广播事件作用域门控机制 | 缺失 | §4B 广播事件作用域门控 |
| 完整事件类型列表 | 不完整 | §4C 完整事件类型列表 |
| 会话高级控制方法（subscribe / abort / patch 等） | 缺失 | §4.15 |
| 节点管理方法（node.* 系列） | 缺失 | §4.16 |
| 定时自动化方法（cron.* 系列） | 缺失 | §4.17 |
| 其他补充方法（gateway.identity / secrets / update 等） | 缺失 | §4.18 |
| 设备令牌完整生命周期 | 不完整 | §4.11 设备配对管理 |
| Talk 方法完整列表 | 不完整 | §4.13 Talk 实时会话 |
| 客户端常量参考值 | 缺失 | §A.7 |
| 设备认证迁移诊断码 | 缺失 | §A.8 |
| 认证失败恢复指引 | 缺失 | §A.9 |
| Exec 审批安全机制 | 缺失 | §A.10 |
| 节点角色与在线状态 | 缺失 | §A.11 |
| Agent 投递回退机制 | 缺失 | §A.12 |
| `UNAVAILABLE` + `startup-sidecars` 可重试错误 | 缺失 | §A.9 |
| `pluginSurfaceUrls` 可选字段 | 缺失 | §2.2 握手流程图 |
| `chat.inject` 方法 | 缺失 | §4.15 |
| `chat.history` 显示规范化（移除指令标签等） | 缺失 | 已知悉，未单独列出 |
