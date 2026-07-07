# 设计：API 请求/响应日志（App 内诊断页）

- **日期**：2026-07-07
- **关联**：排查 Gateway 连接/协议问题；无直接 US
- **状态**：设计已与用户确认（§1–§4 逐段通过），待写实现计划

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
| `lib/core/api_log_redactor.dart` | core | 纯函数 `redactAndTruncate(rawJson, maxBytes)` | 纯 Dart（`dart:convert`）|
| `lib/core/api_log_store.dart` | core | `ApiLogStore implements IApiLogger` — 环形缓冲 + 流 + 耗时匹配 | 纯 Dart |
| `lib/features/diagnostics/diagnostics_page.dart` | features | 诊断页 UI | Riverpod + ui_kit |
| `lib/features/diagnostics/providers/diagnostics_providers.dart` | features | 过滤状态 + 派生列表 provider | Riverpod |
| `test/core/api_log_redactor_test.dart` | test | 脱敏/截断单测（TDD 先行） | — |
| `test/core/api_log_store_test.dart` | test | 环形缓冲/耗时/清理单测（TDD 先行） | — |
| `test/core/acl/connection_manager_logging_test.dart` | test | 注入 fake logger，断言各采集点触发 | — |
| `test/features/diagnostics/diagnostics_page_test.dart` | test | widget 测试（Law 14 ≥2） | — |

### 2.2 修改文件

- `lib/core/acl/connection_manager.dart` — 加 `IApiLogger?` 构造参数 + ~13 个采集调用（纯观察，不改控制流）
- `lib/core/acl/ws_gateway_client.dart` — 加 `IApiLogger?` 参数，在 `connect()` 和 `testConnection()` 两处转发给 `ConnectionManager`
- `lib/app/di/providers.dart` — 加 `apiLogStoreProvider`（keepAlive singleton）+ `apiLoggerProvider`，注入 `wsGatewayClientProvider`
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
4. **诊断页在 release 也可见**。数据是用户自己的、纯内存、无导出风险（除非用户主动
   截图），对 bug 上报有用，与现有 settings 子页一致。

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

### 3.2 `redactAndTruncate`

纯函数：`String redactAndTruncate(String rawJson, {int maxBytes = 2048})`

1. `jsonDecode` 解析；解析失败走 regex 兜底（见第 5 步）。
2. 递归遍历 JSON 树，对**脱敏键集合**里的 key，把 value 替换成 `"<redacted>"`：
   `token, deviceToken, signature, signPayload, nonce, secret, password,
   accessToken, refreshToken`。
3. 紧凑重序列化（`jsonEncode`，无缩进）。
4. 若 ≤ `maxBytes`，原样返回；若超出，截到 `maxBytes` 并追加
   `…(truncated, N bytes total)`（N = 原始字节数）。
5. **regex 兜底**（解析失败）：对 `"key"\s*:\s*"[^"]*"` 模式按脱敏键集合替换，再按
   `maxBytes` 截断。保证畸形 JSON 不崩。

**用户消息内容不脱敏**：`chat.send` 的 `message`（用户文本）和 `chat.history` 返回的
历史消息不脱敏——这是用户自己的消息，排查时正是要看「发了什么/收到了什么」；base64
附件会被 2KB 截断自然吃掉，不会爆内存。

**调用位置**：脱敏在 `ApiLogStore` 内部完成（`logRequest`/`logResponse` 收到 rawJson
后调 `redactAndTruncate`）。ACL 采集点只传原始 JSON 字符串 + 元数据，不感知脱敏逻辑。

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
  payloadPreview=redactAndTruncate(rawJson)）；入缓冲；发流。
- `logResponse`：若 `_pendingReqTs[requestId]` 存在，算 `durationMs = now - sentAt` 并
  删条目；构造 entry（direction=in, kind=res）；入缓冲；发流。
- `logStateChange`：构造 entry（kind=state，`state` 可为 null 用于纯 message 诊断
  条目，无 payload）；入缓冲；发流。
- **入缓冲**：`_entries.add(e)`；若 `length > maxEntries`，`removeAt(0)`（FIFO 淘汰
  最老）。500 条 × ≤2KB ≈ 1MB 上限，安全。
- **`_pendingReqTs` 防泄漏**：理论上每个 req 都有对应 res，但 res 永不到达（连接断开、
  超时）时条目会残留。**惰性清理**：当 `_pendingReqTs.length > 200` 时，删掉 30s 前的
  条目（按 sentAt 判断）。门槛宽松，因为正常在途请求数极少。
- **永不抛**：`logXxx` 全程 try/catch，内部异常吞掉并 `debugPrint` 面包屑（Law 8——
  非空 catch，有日志）。`redactAndTruncate` 已防御畸形 JSON。**采集日志绝不能影响
  协议路径。**

---

## 5. ConnectionManager 采集点

注入：构造函数加 `IApiLogger? apiLogger`（与 `_deviceTokenStore`、工厂同模式）。

### 5.1 req/res 采集（3 处）

1. **`sendRawRequest`**（L416 `_channel!.sink.add` 前）：
   ```dart
   _apiLogger?.logRequest(
     instanceId: _instanceId, requestId: id,
     method: _extractMethod(requestJson),  // jsonDecode 取 'method'
     byteSize: payloadSize, rawJson: requestJson,
   );
   ```
2. **`onConnectChallenge`**（L730 `_channel!.sink.add` 前）：同上，method =
   `Methods.connect`，byteSize = `utf8.encode(requestJson).length`。含
   `auth.token`/`signature` → redactor 脱敏。
3. **`_onIncomingData`**（L576 `parseFrame` 后）：
   - `ResponseFrame` → `logResponse(...)`。**覆盖所有 res，包括 connect 握手 res**
     （握手 res 也走这里）。
   - `EventFrame` → **不记录**。`tick`/`chat`/`agent` 高频会冲缓冲；lifecycle 相关的
     `shutdown`/`payload.large` 通过下面的 state 采集点带「原因」捕获。

### 5.2 状态/生命周期采集（~10 处，带人类可读原因；不在 `_setState` 里记，避免重复）

| 站点 | state | message |
|---|---|---|
| `_doConnect` 进入 | connecting | `Connecting to <url>` |
| hello-ok 成功（`_handleConnectResponse`） | connected | `Connected (protocol vN, maxPayload=…, tick=…ms)` |
| `_handleAuthFailure` | authFailed | `Auth failed: <reason> (code: X)` |
| `_handlePairingRequired` | pairingRequired | `Pairing required — waiting for approval` |
| `_handleDeviceIdMismatch` | recovering | `Device ID mismatch — transient race, retry 2s` |
| `_handleAuthTokenMismatchRetry` | —(注) | `AUTH_TOKEN_MISMATCH — retrying with cached deviceToken` |
| `_handleGracefulShutdown` | —(注) | `Gateway graceful shutdown — reconnecting` |
| tick 超时回调（`_resetTickTimeout`） | recovering | `Tick timeout — connection lost` |
| `_onConnectionError` | recovering | `WebSocket error: <error>` |
| `_onConnectionDone` | recovering/disconnected | `WebSocket closed` |
| `_scheduleReconnect` 耗尽 | reconnectExhausted | `Reconnect exhausted after N failures` |
| `sendRawRequest` buffer overflow | — | `Buffer overflow: buffered=X attempted=Y max=Z` |
| `sendRawRequest` payload too large | — | `Payload too large: X > maxPayload Y` |

（注：`_handleAuthTokenMismatchRetry`/`_handleGracefulShutdown` 走 `_immediateReconnect`
→ `_setState(disconnected)` 再 reconnect。这两条以 **message-only** 条目记录（`state` 传
null），不重复记 state——紧随其后的 disconnected/recovering 由 `_onConnectionDone` 等
站点覆盖，避免重复。）

**共 ~13 个采集点，全是单行 `_apiLogger?.logXxx(...)`，不改任何控制流。**

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

### 7.1 `diagnostics_page.dart`

- AppBar：「诊断」+ 右上角「清空」按钮（带确认 dialog）+ 副标题 `N / 500`。
- 过滤行（顶部 sticky）：
  - 实例下拉：`全部` + 各已连接实例（按 instanceId 显示实例名）
  - 类型 chips：`全部` / `请求` / `响应` / `状态`（多选 toggle）
- 列表：`ListView.builder`（Law 11），**最新在最上**。每个 tile 一行紧凑布局：
  - 方向图标：`↑`(out, 蓝) / `↓`(in, 绿) / `⊙`(state, 灰)
  - 主标题：`method` 或 `state`
  - 副信息：时间戳(HH:mm:ss.SSS) + 状态 chip（`ok`/`code`/`+durationMs`）+ `字节数`
  - tap → 展开 payload preview（等宽字体，可横向滚动）+「复制」按钮
- 空状态：`还没有日志 — 连接 Gateway 并发条消息试试`。

### 7.2 `providers/diagnostics_providers.dart`

```dart
final diagnosticsFilterProvider =
    NotifierProvider<DiagnosticsFilterNotifier, DiagnosticsFilter>(...);
// DiagnosticsFilter { String? instanceId; Set<ApiLogKind> kinds; }

final diagnosticsEntriesProvider = StreamProvider<List<ApiLogEntry>>((ref) {
  final store = ref.watch(apiLogStoreProvider);
  final filter = ref.watch(diagnosticsFilterProvider);
  // 用 store.snapshot() 做 seed，store.onEntry 增量更新
  // 输出按 filter 过滤后的列表（最新在最上）
});
```

SSOT：UI 只 watch `diagnosticsEntriesProvider`，不自己维护 ephemeral flag（Law 4）。

### 7.3 路由 + 入口

- `lib/app/router/` 加 `/settings/diagnostics` 路由（从 settings tab push）。
- `settings_page.dart` 加一行「诊断」→ 跳转。

---

## 8. 测试计划（Law 17 — TDD 顺序）

**先写测试，再写实现（per-file）：**

1. `test/core/api_log_redactor_test.dart` → `lib/core/api_log_redactor.dart`
   - 脱敏 `token`/`deviceToken`/`signature`/`nonce`/`signPayload`
   - ≤maxBytes 原样保留
   - >maxBytes 截断 + marker（含原始字节数）
   - 畸形 JSON 走 regex 兜底不崩
   - 嵌套对象里的敏感键也脱敏（`auth.token`）

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
   - 断言：`sendRequest(chat.history)` → `logRequest` 被调（method 正确）+ 对应 res →
     `logResponse` 被调 + `durationMs` 非负
   - 断言：握手 `connect.challenge` → `logRequest(method=connect)` + hello-ok →
     `logStateChange(connected)`
   - 断言：tick 超时 → `logStateChange(recovering, "Tick timeout…")`
   - 断言：buffer overflow / payload too large → 对应 `logStateChange` 触发
   - 断言：`EventFrame`（chat delta）→ **不**触发任何 log（验证过滤）

4. `test/features/diagnostics/diagnostics_page_test.dart` → 页面
   - 注入带假数据的 `apiLogStoreProvider`，渲染列表
   - 切换类型 chip → 列表过滤生效
   - tap「清空」→ 调 `store.clear()`、列表变空

**`WsGatewayClient` 转发**：现有 `ws_gateway_client_test.dart` 加 1-2 个用例验证
`apiLogger` 被转发到 `ConnectionManager`。

---

## 9. 配置常量

集中在 `api_log_store.dart` / `api_log_redactor.dart` 顶部：

```dart
// api_log_store.dart
static const int defaultMaxEntries = 500;
static const int pendingReqSweepThreshold = 200;
static const int pendingReqTtlMs = 30000;

// api_log_redactor.dart
static const int defaultMaxPayloadPreviewBytes = 2048;
static const Set<String> redactedKeys = {
  'token', 'deviceToken', 'signature', 'signPayload',
  'nonce', 'secret', 'password', 'accessToken', 'refreshToken',
};
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
