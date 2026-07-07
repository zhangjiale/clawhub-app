# 设计：API 请求/响应日志（App 内诊断页）

- **日期**：2026-07-07
- **关联**：排查 Gateway 连接/协议问题；无直接 US
- **状态**：设计已与用户确认（§1–§4 逐段通过）；经架构评审委员会（Full，5 维度）评审，unanimously 推荐方案 A，已折入 4 项必修修订 + 短期发现；待写实现计划

---

## 1. 背景与目标

### 1.1 现状

- `ILogger`（`lib/core/i_logger.dart`）只有 `info()` / `error()` 两个方法，生产实现
  `DebugPrintLogger` 走 `debugPrint`——**release 模式被限流/截断，且 App 内不可见**。
- `ConnectionManager`（`lib/core/acl/connection_manager.dart`）散落 ~30 处 `debugPrint`，
  都是临时性的，重启即丢、用户看不到。
- **没有**结构化的 req/res 日志，**没有**持久化或可浏览的日志存储。
- 协议排查（auth 失败、pairing、deviceToken 轮换、image send-back、tick 超时等）目前
  只能靠连机看 console，无法在真机现场复现。

### 1.2 目标

加一个**结构化 API 日志**功能，记录 Gateway 的请求/响应 + 连接生命周期关键事件，
在 App 内提供诊断页浏览，方便排查问题。

### 1.3 用户确认的范围（brainstorming 结论）

| 维度 | 选定 |
|---|---|
| 日志消费方式 | **App 内诊断页**（不导出、不持久化） |
| 存储方式 | **内存环形缓冲**（固定条数，重启清空） |
| 采集范围 | **req/res + 连接生命周期**（不含流式 delta） |
| payload 细节 | **元数据 + 截断脱敏 payload**（≤2KB，敏感字段脱敏） |
| 采集架构 | **方案 A**：往 `ConnectionManager` 注入 `IApiLogger` |

### 1.4 非目标（明确不做）

- 流式 delta 事件（`chat`/`agent` 高频帧）记录
- `MockGatewayClient` 接入日志（离线 dev 路径，不走 `ConnectionManager`）
- 日志导出文件 / 系统分享
- 持久化到 SQLite
- 日志等级筛选（req/res/state 三类足够）

---

## 2. 分层与文件布局

核心约束：**ACL 是唯一碰协议的层**，采集点必须在 ACL；`IApiLogger` 抽象放 `core/`
（与 `i_logger.dart`、`i_avatar_storage_service.dart` 同级），ACL 依赖抽象不依赖实现；
具体实现（环形缓冲）纯 Dart 不碰 Flutter；Riverpod 接线和 UI 在 `app/di/` 与
`features/`。

### 2.1 新增文件

| 文件 | 层 | 职责 | 依赖 |
|---|---|---|---|
| `lib/core/i_api_logger.dart` | core | `IApiLogger` 接口 + `ApiLogEntry`/`ApiLogDirection`/`ApiLogKind` | 纯 Dart |
| `lib/core/api_log_redactor.dart` | core | 纯函数 `redactAndTruncate(rawJson, maxBytes, payloadSize)` — truncate-then-parse 脱敏截断 | 纯 Dart（`dart:convert`）|
| `lib/core/api_log_store.dart` | core | `ApiLogStore implements IApiLogger` — 环形缓冲 + 流 + 耗时匹配 | 纯 Dart |
| `lib/features/diagnostics/diagnostics_page.dart` | features | 诊断页 UI | Riverpod + ui_kit |
| `lib/features/diagnostics/providers/diagnostics_providers.dart` | features | 派生列表 provider（v1 无过滤，v2 加 filter） | Riverpod |
| `test/core/api_log_redactor_test.dart` | test | 脱敏/截断单测（TDD 先行） | — |
| `test/core/api_log_store_test.dart` | test | 环形缓冲/耗时/清理单测（TDD 先行） | — |
| `test/core/acl/connection_manager_logging_test.dart` | test | 注入 fake logger，断言各采集点触发 | — |
| `test/features/diagnostics/diagnostics_page_test.dart` | test | widget 测试（Law 14 ≥2） | — |

### 2.2 修改文件

- `lib/core/acl/connection_manager.dart` — 加 `IApiLogger?` 构造参数 + 15 个采集调用（3 req/res + 12 state，纯观察，不改控制流）
- `lib/core/acl/ws_gateway_client.dart` — 加 `IApiLogger?` 参数，在 `connect()` 和 `testConnection()` 两处转发给 `ConnectionManager`
- `lib/app/di/providers.dart` — 加 `apiLogStoreProvider`（普通 `Provider` singleton）+ `apiLoggerProvider`，注入 `wsGatewayClientProvider`
- `lib/features/settings/settings_page.dart` — 加「诊断」导航入口
- `lib/app/router/` — 加 `/settings/diagnostics` 路由

### 2.3 关键分层决策

1. **`ApiLogEntry` 用普通不可变类，不用 freezed**。它是基础设施诊断记录、不是业务
   domain 模型；UI 监听「列表本身的变化」（Notifier 发新 list），不依赖单条 entry 的
   `==`。避免为一个 infra 类型引入 build_runner。
2. **`ApiLogStore` 纯 Dart，不碰 Flutter/Riverpod**。能被 ACL 注入、能单测；Riverpod
   在 `app/di/` 包一层 provider 暴露给 UI。同一 store 实例既被 `ConnectionManager`
   当 logger 用、又被 UI provider 当数据源读——保证 SSOT。
3. **`MockGatewayClient` 不接入日志**（非目标）。
4. **诊断页在 release 可见，但用现有 biometric 设置门禁**。页面会展示 500 条最近协议
   帧含原始用户文本（可能含粘贴的 API key/密码/2FA/他人 PII），物理访问/屏幕共享下是
   真实泄露面。复用现有 `lib/features/settings/biometric_settings_page.dart` 基础设施，
   进入诊断页前要求生物识别解锁——既保留 release 自诊断/截图上报的 ROI，又 bound 泄露面。
5. **`IApiLogger` 补充（不替换）现有 `ILogger`/`debugPrint`**。`ConnectionManager` 现有
   ~30 处 `debugPrint` 服务 console/dev 路径，**本设计不移除**；`IApiLogger` 服务 App 内
   结构化路径（带 req↔res 链接/durationMs/instanceId）。两者受众不同，v1 共存。未来统一
   debugPrint 是独立任务，不在本 spec 范围。

---

## 3. 数据模型与脱敏

### 3.1 `ApiLogEntry`

```dart
class ApiLogEntry {
  final String id;              // 条目自身 uuid
  final int timestampMs;        // 发生时间
  final String instanceId;      // 哪个实例
  final ApiLogDirection direction;  // out / in
  final ApiLogKind kind;        // req / res / state
  final String? methodOrEvent;  // "chat.send" / "connect"；state 为 null
  final String? requestId;      // 帧 id，链接 req↔res（state 为 null）
  final bool? ok;               // res 用
  final String? errorCode;      // res 错误码，如 "NOT_PAIRED"
  final String? state;          // state 用，如 "authFailed" / "recovering"
  final int? byteSize;          // req/res 帧字节数
  final int? durationMs;        // res 用，由 store 匹配 req 算出
  final String? payloadPreview; // 截断+脱敏后的 JSON（≤2KB）；state 为 null
  final String? message;        // state 用的人类可读说明
}

enum ApiLogDirection { out, in }
enum ApiLogKind { req, res, state }
```

### 3.2 `redactAndTruncate`（truncate-then-parse，保护热路径）

纯函数：`String redactAndTruncate(String rawJson, {int maxBytes = 2048, int? payloadSize})`

**核心约束**：`chat.send` 的 `requestJson` 可达 25MB（`defaultMaxPayloadBytes`），而
`ws_gateway_client.dart` L267-287 刻意把 base64 序列化放进 worker isolate「避免大 base64
在主 isolate 上 jsonEncode 造成 jank」。若脱敏器对整帧 `jsonDecode`+`jsonEncode`，会在
主 isolate 重新引入这个 jank——违反本 spec「采集日志绝不能影响协议路径」不变量。故采用
**truncate-then-parse**：解析成本 O(阈值) 而非 O(payloadSize)。

1. **大帧跳过解析**：若 `payloadSize > largeFrameThresholdBytes`（64KB），**不 `jsonDecode`**，
   直接在前 `regexFallbackScanBytes`（8KB）子串上跑 regex 脱敏（第 5 步），再按 `maxBytes`
   截断。大帧几乎都是 `chat.send`（带 base64 附件）/ `chat.history`（多条消息），不含
   `auth`/`signature`（那些只在小的 `connect` 帧里），故 regex 兜底够用。
2. **小帧结构化脱敏**：`payloadSize ≤ 64KB` 时 `jsonDecode`（≤64KB 解析 <1ms，可接受）；
   解析失败走 regex 兜底（第 5 步）。
3. 递归遍历 JSON 树，对**脱敏键集合**里的 key，把 value 替换成 `"<redacted>"`（见 §9
   集合，已防御性加入 `authToken`/`sessionToken`/`bearerToken`）。
4. 紧凑重序列化（`jsonEncode`，无缩进）。若 ≤ `maxBytes` 原样返回；若超出，截到
   `maxBytes` 并追加 `…(truncated, N bytes total)`（N = 原始字节数）。
5. **regex 兜底**（解析失败 / 大帧）：对 `"key"\s*:\s*"[^"]*"` 模式按脱敏键集合替换（仅扫
   前 8KB），再按 `maxBytes` 截断。保证畸形 JSON 不崩。

**用户消息内容不脱敏**：`chat.send` 的 `message`（用户文本）和 `chat.history` 返回的
历史消息不脱敏——这是用户自己的消息，排查时正是要看「发了什么/收到了什么」；base64
附件会被 2KB 截断自然吃掉，不会爆内存。其 release 可见性靠 §2.3 决策 4 的 biometric
门禁 bound，而非改脱敏策略。

**调用位置**：脱敏在 `ApiLogStore` 内部完成（`logRequest`/`logResponse` 收到 rawJson +
byteSize 后调 `redactAndTruncate(rawJson, payloadSize: byteSize)`）。ACL 采集点只传原始
JSON 字符串 + 元数据，不感知脱敏逻辑。

**协议升级审计**：`api_log_redactor.dart` 顶部须带 `// RE-AUDIT WHEN` 注释，绑
`gateway_protocol.dart` 的方法/字段新增——协议加新凭据字段（如 `sessionToken`）时必须
重新审计 `redactedKeys`。纳入 protocol-bump checklist。

### 3.3 样本

出站 `chat.send`：
```
[out] req  chat.send  id=9f3a…  2.1KB
{"method":"chat.send","params":{"sessionKey":"agent:7:main","message":"你好","attachments":…(truncated, 48213 bytes total)}}
```

入站 `connect` 失败响应：
```
[in]  res  connect  id=…  ok=false  code=NOT_PAIRED  340B  +1280ms
{"ok":false,"error":{"code":"NOT_PAIRED","details":{"requestId":"…","deviceId":"…"}}}
```

状态变更：
```
[—]  state  authFailed  "Auth failed: Bad gateway URL: …"
```

---

## 4. 环形缓冲 Store

### 4.1 `ApiLogStore implements IApiLogger`

```dart
class ApiLogStore implements IApiLogger {
  ApiLogStore({this.maxEntries = defaultMaxEntries});
  final int maxEntries;

  final List<ApiLogEntry> _entries = [];
  final Map<String, int> _pendingReqTs = {};  // requestId → sentAt ms
  final StreamController<ApiLogEntry> _ctrl = StreamController.broadcast();

  List<ApiLogEntry> snapshot();            // UnmodifiableListView
  Stream<ApiLogEntry> get onEntry => _ctrl.stream;
  void clear();

  @override
  void logRequest({required String instanceId, required String requestId,
                   required String method, required int byteSize,
                   required String rawJson});
  @override
  void logResponse({required String instanceId, required String requestId,
                    required bool ok, String? errorCode, required int byteSize,
                    String? rawJson});
  @override
  void logStateChange({required String instanceId, String? state,
                       required String message});
}
```

### 4.2 行为

- `logRequest`：记 sentAt 进 `_pendingReqTs`；构造 entry（direction=out, kind=req,
  payloadPreview=redactAndTruncate(rawJson, payloadSize: byteSize)）；入缓冲；发流。
- `logResponse`：若 `_pendingReqTs[requestId]` 存在，算 `durationMs = now - sentAt` 并
  删条目；构造 entry（direction=in, kind=res）；入缓冲；发流。
- `logStateChange`：构造 entry（kind=state，`state` 可为 null 用于纯 message 诊断
  条目，无 payload）；入缓冲；发流。
- **入缓冲**：`_entries.add(e)`；若 `length > maxEntries`，`removeAt(0)`（FIFO 淘汰
  最老）。500 条 × ≤2KB ≈ 1MB 上限，安全。
- **`_pendingReqTs` 防泄漏**：理论上每个 req 都有对应 res，但 res 永不到达（连接断开、
  超时）时条目会残留。**惰性清理**：当 `_pendingReqTs.length > 200` 时，删掉 30s 前的
  条目（按 sentAt 判断），**并 `logStateChange(state: null, message: "evicted N pending
  req entries older than 30s")`**——清理不静默，留下诊断痕迹。门槛宽松，因为正常在途
  请求数极少。
- **永不抛**：`logXxx` 全程 try/catch，内部异常吞掉并 `debugPrint` 面包屑（Law 8——
  非空 catch，有日志）。`redactAndTruncate` 已防御畸形 JSON。**采集日志绝不能影响
  协议路径。**

---

## 5. ConnectionManager 采集点

注入：构造函数加 `IApiLogger? apiLogger`（与 `_deviceTokenStore`、工厂同模式）。

### 5.1 req/res 采集（3 处）

1. **`sendRawRequest`**（L416 `_channel!.sink.add` 前）：
   `method` 由调用方透传——`sendRequest` 已知 method，`WsGatewayClient.sendMessage` 传
   `Methods.chatSend`。`sendRawRequest` 签名加可选 `String? method` 参数（避免二次
   `jsonDecode` 解析，消除 `_extractMethod`）：
   ```dart
   _apiLogger?.logRequest(
     instanceId: _instanceId, requestId: id,
     method: method, byteSize: payloadSize, rawJson: requestJson,
   );
   ```
2. **`onConnectChallenge`**（L730 `_channel!.sink.add` 前）：同上，method =
   `Methods.connect`，byteSize = `utf8.encode(requestJson).length`。含
   `auth.token`/`signature` → redactor 脱敏。
3. **`_onIncomingData`**（L576 `parseFrame` 后）：
   - `ResponseFrame` → `logResponse(...)`，且**必须在 `completer.complete(frame)` 之后
     调**——确保日志路径失败（即便 store 内部已 try/catch）绝不阻塞响应交付、不让
     `sendRequest` 卡 15-30s 超时。**覆盖所有 res，包括 connect 握手 res**。
   - `EventFrame` → **不记录**。`tick`/`chat`/`agent` 高频会冲缓冲；lifecycle 相关的
     `shutdown`/`payload.large` 通过下面的 state 采集点带「原因」捕获。

### 5.2 状态/生命周期采集（12 处，带人类可读原因；不在 `_setState` 里记，避免重复）

| 站点 | state | message |
|---|---|---|
| `_doConnect` 进入 | connecting | `Connecting to <url>` |
| hello-ok 成功（`_handleConnectResponse`） | connected | `Connected (protocol vN, maxPayload=…, tick=…ms)` |
| `_handleAuthFailure` | authFailed | `Auth failed: <reason> (code: X)` |
| `_handlePairingRequired` | pairingRequired | `Pairing required — waiting for approval` |
| `_handleDeviceIdMismatch` | recovering | `Device ID mismatch — transient race, retry 2s` |
| `_immediateReconnect`（gracefulShutdown / authTokenMismatch 入口） | disconnected | `<pendingFailReason>`（如 `Gateway graceful shutdown` / `AUTH_TOKEN_MISMATCH (retrying)`） |
| tick 超时回调（`_resetTickTimeout`） | recovering | `Tick timeout — connection lost` |
| `_onConnectionError` | recovering | `WebSocket error: <error>` |
| `_onConnectionDone` | recovering/disconnected | `WebSocket closed`（注：`_closeWebSocket` 显式 cancel 订阅时**不触发**，故 `_immediateReconnect` 路径的 disconnected 由上条覆盖） |
| `_scheduleReconnect` 耗尽 | reconnectExhausted | `Reconnect exhausted after N failures` |
| `sendRawRequest` buffer overflow | —(null) | `Buffer overflow: buffered=X attempted=Y max=Z` |
| `sendRawRequest` payload too large | —(null) | `Payload too large: X > maxPayload Y` |

`_handleGracefulShutdown` / `_handleAuthTokenMismatchRetry` 自身**不再单独记** message-only
条目——它们的 reason 已由 `_immediateReconnect(state: disconnected, message:
pendingFailReason)` 一条覆盖（state + reason 都在），避免重复。buffer overflow /
payload too large 是诊断事件非状态转换，`state` 传 null。

**共 15 个采集点（3 req/res + 12 state），全是单行 `_apiLogger?.logXxx(...)`，不改任何
控制流。每个采集点附一行 `// observation-only — do not add control flow` 注释，防未来
漂移。`ConnectionManager` 类 docstring 交叉引用本 spec §5.2。**

### 5.3 `WsGatewayClient` 转发

构造函数加 `IApiLogger? apiLogger`，在 `connect()`（L195）和 `testConnection()`（L447）
两处构造 `ConnectionManager` 时传 `apiLogger: _apiLogger`。`testConnection` 的临时连接
也记日志（tagged `__test_<id>`，UI 可按实例过滤或保留——保留，因为测试连接失败正是
排查点）。

---

## 6. DI 接线

```dart
// lib/app/di/providers.dart
final apiLogStoreProvider = Provider<ApiLogStore>(
  (ref) => ApiLogStore(maxEntries: ApiLogStore.defaultMaxEntries),
);

final apiLoggerProvider = Provider<IApiLogger>(
  (ref) => ref.watch(apiLogStoreProvider),
);

// wsGatewayClientProvider 加：apiLogger: ref.watch(apiLoggerProvider)
```

`apiLogStoreProvider` 用**普通 `Provider`**（非 `.autoDispose`），即 app 生命周期单例——
离开诊断页不会被释放，缓冲常驻。**不可用 `.autoDispose`**，否则离开诊断页缓冲清空、且
`ConnectionManager` 持有的引用失效。本仓库 `providers.dart` 全用 manual provider 风格
（非 riverpod_generator），照此对齐。

---

## 7. UI：诊断页

### 7.1 `diagnostics_page.dart`（v1 简化版）

CTO 评审建议 v1 砍掉过滤行，扁平逆序列表先上——约砍一半 UI 成本和测试面（Law 14）。
过滤 chip / 实例下拉延到 v2。

- **进入门禁**：进入页面前要求 biometric 解锁（复用 `biometric_settings_page.dart`
  基础设施，§2.3 决策 4）。
- AppBar：「诊断」+ 右上角「清空」按钮（带确认 dialog）+ 副标题 `N / 500`。
- 列表：`ListView.builder`（Law 11），**最新在最上**，扁平逆序，无过滤行。每个 tile
  一行紧凑布局：
  - 方向图标：`↑`(out, 蓝) / `↓`(in, 绿) / `⊙`(state, 灰)
  - 主标题：`method` 或 `state`
  - 副信息：时间戳(HH:mm:ss.SSS) + 实例名 + 状态 chip（`ok`/`code`/`+durationMs`）+ `字节数`
  - tap → 展开 payload preview（等宽字体，可横向滚动）+「复制」按钮；payload 默认折叠
    （tap-to-reveal），降低一眼泄露面
- 空状态：`还没有日志 — 连接 Gateway 并发条消息试试`。

### 7.2 `providers/diagnostics_providers.dart`（v1 无过滤）

```dart
// v1：无过滤，直接逆序输出全量
final diagnosticsEntriesProvider = StreamProvider<List<ApiLogEntry>>((ref) {
  final store = ref.watch(apiLogStoreProvider);
  // 用 store.snapshot() 做 seed，store.onEntry 增量更新
  // 输出最新在最上的逆序列表
});
// v2 再加 diagnosticsFilterProvider（instanceId / kinds）
```

SSOT：UI 只 watch `diagnosticsEntriesProvider`，不自己维护 ephemeral flag（Law 4）。
重建成本：每次 onEntry 发射产出新 `List`（500 条 O(500) 拷贝，可接受）；v2 可优化为
增量 diff。

### 7.3 路由 + 入口

- `lib/app/router/` 加 `/settings/diagnostics` 路由（从 settings tab push），进入时
  触发 biometric 门禁（§7.1）。
- `settings_page.dart` 加一行「诊断」→ 跳转。

---

## 8. 测试计划（Law 17 — TDD 顺序）

**先写测试，再写实现（per-file）：**

1. `test/core/api_log_redactor_test.dart` → `lib/core/api_log_redactor.dart`
   - 脱敏 `token`/`deviceToken`/`signature`/`nonce`/`signPayload`/`authToken`
   - ≤maxBytes 原样保留
   - >maxBytes 截断 + marker（含原始字节数）
   - **大帧（payloadSize > 64KB）跳过 jsonDecode，走 regex 兜底**——验证不解析整帧
   - 畸形 JSON 走 regex 兜底不崩
   - **畸形 JSON 含嵌套 `auth.token` → regex 兜底仍脱敏**（防 jsonDecode 与 parseFrame 分歧）
   - 嵌套对象里的敏感键也脱敏（`auth.token`，结构化路径）

2. `test/core/api_log_store_test.dart` → `lib/core/api_log_store.dart`
   - 超容量 FIFO 淘汰最老
   - `snapshot()` 返回不可修改视图
   - res 匹配 req 算出 `durationMs`
   - res 无匹配 req 时 `durationMs` 为 null（不崩）
   - `clear()` 清空
   - `onEntry` 流每次 add 都发
   - `_pendingReqTs` 惰性清理（构造 >200 个孤儿 req 后，旧的被清）

3. `test/core/acl/connection_manager_logging_test.dart` → `connection_manager.dart` 改动
   - 注入 fake `IApiLogger`，fake WS 注入帧
   - 断言：`sendRequest(chat.history)` → `logRequest` 被调（method 透传正确，无 _extractMethod）
     + 对应 res → `logResponse` 被调 + `durationMs` 非负
   - 断言：`logResponse` 在 `completer.complete(frame)` **之后**调——fake logger 抛异常时
     响应仍正常交付、sendRequest 不卡超时
   - 断言：握手 `connect.challenge` → `logRequest(method=connect)` + hello-ok →
     `logStateChange(connected)`
   - 断言：tick 超时 → `logStateChange(recovering, "Tick timeout…")`
   - 断言：`_immediateReconnect`（gracefulShutdown / authTokenMismatch 入口）→
     `logStateChange(disconnected, <pendingFailReason>)` 触发
   - 断言：buffer overflow / payload too large → 对应 `logStateChange(state: null, …)` 触发
   - 断言：`EventFrame`（chat delta）→ **不**触发任何 log（验证过滤）
   - **throwing-logger 契约测试**：fake logger 每个 `logXxx` 都抛异常，断言状态机照常
     完成（connect 成功 / 重连调度 / auth 失败转换正常）——直接测「采集日志绝不能影响
     协议路径」不变量

4. `test/features/diagnostics/diagnostics_page_test.dart` → 页面
   - 注入带假数据的 `apiLogStoreProvider`，渲染逆序列表
   - tap「清空」→ 调 `store.clear()`、列表变空
   - tap 条目 → 展开 payload preview；「复制」按钮可拷贝
   - （v2 加过滤 chip 测试）

**`WsGatewayClient` 转发**：现有 `ws_gateway_client_test.dart` 加 1-2 个用例验证
`apiLogger` 被转发到 `ConnectionManager`。

**性能回归测试**（防热路径 jank 回归）：`test/core/api_log_store_perf_test.dart`——
注入 fake logger whose `logRequest` 测耗时，发一个 5MB `chat.send` 帧断言 `logRequest`
调用 < 5ms（验证 truncate-then-parse 生效，未退回全量解析）。

---

## 9. 配置常量

集中在 `api_log_store.dart` / `api_log_redactor.dart` 顶部：

```dart
// api_log_store.dart
static const int defaultMaxEntries = 500;
static const int pendingReqSweepThreshold = 200;
static const int pendingReqTtlMs = 30000;

// api_log_redactor.dart
static const int defaultMaxPayloadPreviewBytes = 2048;   // 最终 preview 截断
static const int largeFrameThresholdBytes = 65536;       // >此值跳过 jsonDecode 走 regex
static const int regexFallbackScanBytes = 8192;          // regex 兜底只扫前 N 字节
static const Set<String> redactedKeys = {
  'token', 'deviceToken', 'signature', 'signPayload',
  'nonce', 'secret', 'password', 'accessToken', 'refreshToken',
  // 防御性：协议若新增这些字段名也覆盖（见 // RE-AUDIT WHEN 注释）
  'authToken', 'sessionToken', 'bearerToken',
};
// 顶部必带：// RE-AUDIT WHEN gateway_protocol.dart 加新方法/凭据字段 → 审计 redactedKeys
```

---

## 10. Iron Laws 合规自检

- **Law 1**（domain 纯净）：本设计不改 `domain/`，新增类型全在 `core/`，无 Flutter 依赖。
- **Law 2**（widget 只渲染）：诊断页只 watch provider 渲染，无业务逻辑/直接 API。
- **Law 3**（依赖抽象）：ACL 依赖 `IApiLogger`（core 抽象），不依赖 `ApiLogStore` 具体
  实现；UI 依赖 provider 暴露的抽象。
- **Law 4**（不用 ValueNotifier+setState）：用 `Notifier`/`StreamProvider`，UI 用
  `ref.watch`。
- **Law 8**（无空 catch）：`logXxx` 的 catch 带 `debugPrint` 面包屑。
- **Law 11**（>20 项用 builder）：诊断页用 `ListView.builder`。
- **Law 14**（新 widget ≥2 测试）：诊断页有 widget 测试。
- **Law 17**（TDD）：redactor / store / connection_manager 改动均测试先行。
- **Law 18**（keyed-lookup nulls 显式）：`logResponse` 无匹配 req 时 `durationMs` 显式
  为 null（非静默默认值），符合「res 无对应 req」的合法并发场景。

**「采集日志绝不能影响协议路径」不变量**（评审委员会首要关注）由三重保障：
(1) `redactAndTruncate` truncate-then-parse 使解析成本 O(阈值) 而非 O(payloadSize)，
不重新引入 worker-isolate 规避的 jank；(2) `logResponse` 钉在 `completer.complete` 之后；
(3) throwing-logger 契约测试 + store 内部 try/catch。三者缺一则该不变量不成立。
