# Spec: ChatViewModel 拆分 — StreamingLifecycle + PreviewUpdater

**Date**: 2026-07-04
**Status**: Implemented (PR-A + PR-B landed) — 经 `architecture-reviewer` 审查修订(v1 → v2,4 补丁);实现期 v2 → v3 三处细化(见末「实现期修订」)
**Scope**: 从 `ChatViewModel`(1375 行)抽出 `StreamingLifecycle` + `PreviewUpdater` 两个纯 Dart 协作者,零行为变更。

## Context

ChatViewModel 是真"上帝 ViewModel":1375 行 / 11 state 字段 / 6 timer / 6 stream subscription。`_initStreamsAndHistory` 单方法 320 行(454-774)。streaming 文本累积+节流逻辑与 thinking 状态机耦合在同一个 `_startStreaming`(953-997)里,任何改 stall/flush 行为的 PR 都要重跑全套 streaming_guard case,且无法用 FakeAsync 隔离测 50KB buffer 上限和 stall timer 边界。

本 spec 把**流式文本累积+节流**抽成 `StreamingLifecycle`、**预览合并**抽成 `PreviewUpdater`,二者均为纯 Dart(不依赖 `StateNotifier`/Riverpod),沿用 `AgentReactiveState` mixin 的先例(`lib/features/_shared/agent_reactive_state.dart`)。VM 保留 thinking 状态机 + 全部编排职责。

**经审查校正**:原报告称拆完 1375 → ~900 行是高估。`_initStreamsAndHistory`(320 行,60+ 行注释,编排逻辑)不拆,真正搬走 ~150 行,实际结果 **~1230 行**。本次价值是**可独立单测 + 内聚**,不是行数。

## Goals

- `StreamingLifecycle` / `PreviewUpdater` 纯 Dart,可脱离 VM/Riverpod/repo 用 FakeAsync 单测。
- 零行为变更:`chat_view_model_streaming_guard_test.dart` 全 10 case + 其余 10 个 VM 测试文件零修改全过。
- 5 个 reset 位点(streaming 相关)1:1 镜像现状,review 可逐行对照。
- `chatViewModelProvider` 的公共契约(`isStreaming` / `reloadMessages` / `markTombstoneSuspectAndRefresh` / `init` / `dispose`)签名不变。

## Non-Goals

- 不拆 `_initStreamsAndHistory`(传 5 repo + 4 回调,收益为负)。
- 不动 thinking 状态机语义(`_timeoutTimer` 60s / `_overallTimeoutTimer` 120s 的 arm/cancel 时机不变)。
- 不改 `onReplyArrived` 不清 buffer 的预存行为(原始 stall timer 也不清,是既有契约)。
- 不引入 `StreamSubscriptionRegistry` 等长期架构升级(留作未来)。
- 不修 `_initStreamsAndHistory` 内的业务逻辑(仅搬走 streaming/preview 字段与方法)。

---

## 边界判定

报告原方案把 `_timeoutTimer` + `_overallTimeoutTimer` 都塞进 StreamingLifecycle,**本 spec 不采纳**——那会把 thinking 状态机切两半。`_timeoutTimer` 被 `_startThinking`(VM 入口)和 delta handler(SL 内部)双 arm,归 SL 会让 `_stopThinking` / connection-lost / teardown 都反向回调 SL 取消,timer 生命周期被 thinking 状态机驱动却归属 SL,是错配。

**改用:SL 只管流式文本累积+节流+stall,两个 timeout timer 留 VM。** SL 经 `onDeltaActivity()` callback 通知 VM 重 arm `_timeoutTimer`,VM 独占 timer 全生命周期,内聚更高。connection-lost 路径要调两次(`_streaming.onConnectionLost()` + VM 自己 cancel `_timeoutTimer`)是可接受成本,比双向耦合轻。

| 字段 / 方法 | 去向 |
|---|---|
| `_streamingSubscription` / `_streamBuffer` / `_lastPublishedLength` / `_flushTimer` / `_stallTimer` / `_isStreaming` + `vm.isStreaming` getter | **StreamingLifecycle** |
| `_startStreaming` / `_scheduleFlush` / `_flushToState` / `_flushImmediately` | **StreamingLifecycle** |
| `_timeoutTimer`(60s 活动) / `_overallTimeoutTimer`(120s 硬顶) | **VM**(thinking 状态机) |
| `_pendingPreviewMessage` / `_previewCoalesceTimer` / `_scheduleConversationPreviewUpdate` | **PreviewUpdater** |
| `_updateConversationPreview`(35 行,含 guard + 写库) | **VM**(作为 `onFlush` 回调体) |
| `_messageReloadCoalesceTimer` + `_scheduleMessagesReload` | **VM**(reload 不是 preview,别混进 PreviewUpdater) |
| 5 个非流式 subscription / `_awaitingReply` / `_tombstoneSuspect` / `_streamsInitialized` / `_highlightActive` | **VM** |

---

## StreamingLifecycle 契约

`lib/features/chat_room/viewmodels/streaming_lifecycle.dart`,纯 Dart,不依赖 `StateNotifier`/Riverpod。

```dart
class StreamingLifecycle {
  StreamingLifecycle({
    required this.flushDelay,
    required this.onStreamingTextChanged, // 推 state.streamingText
    required this.onDeltaActivity,        // VM 重新 arm 60s _timeoutTimer
    required this.logger,
  });

  final Duration flushDelay;
  final void Function(String text) onStreamingTextChanged;
  final void Function() onDeltaActivity;
  final ILogger logger;

  StreamSubscription<StreamingEvent>? _subscription;
  String _agentRemoteId = '';          // start() 传入存字段,_onEvent 对比用
  final StringBuffer _buffer = StringBuffer();
  int _lastPublishedLength = 0;
  Timer? _flushTimer;
  Timer? _stallTimer;
  bool _isStreaming = false;

  bool get isStreaming => _isStreaming;
}
```

**构造函数必须纯存参、无副作用**(`vm.isStreaming` getter 首次访问会触发 `late final` 构造,副作用会污染 getter 语义)。

### 5 个公共方法(1:1 镜像现状,刻意不合并)

> 不合并成带 flag 的 `_reset()`——5 个位点行为略不同(是否取消 sub、是否清 buffer、是否归零 `_lastPublishedLength`、是否推 state),合并会改行为。每个方法 1:1 镜像现状,review 可逐行对照。

| 方法 | 镜像位点 | 取消 sub | 清 buffer | 归零 lastPublished | 取消 flush/stall | isStreaming=false | 推 state |
|---|---|---|---|---|---|---|---|
| `resetForSend()` | `_sendCore` 833-843 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ '' |
| `onConnectionLost()` | connection-lost 508-520 | ❌ | ✅ | ✅ | stall ✅ / flush ❌ | ✅ | ✅ '' |
| `onReplyArrived()` | agent-arrival 617-624 | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ '' |
| `cancel()` | teardown 1351-1365 + retry 1320-1322 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| `start(...)` | `_startStreaming` 953-997 | (重订) | — | — | — | (delta 翻转) | (flush 推) |

**`cancel()` 契约说明**(v2 补丁):取消 sub+flush+stall,**清 buffer + 归零 `_lastPublishedLength`**,isStreaming=false,**不推 state**。原 teardown 不清 buffer,但 buffer 随后 GC / `retry()` 本就在 teardown 后手动清——合并到 `cancel()` 后 `retry()` 1320-1322 三行可删,两个调用点(dispose / retry)行为等价、无外部可观测差异。

**`onConnectionLost()` 契约说明**(v2 补丁):必须**显式归零 `_lastPublishedLength`**(原 513-514 同时 `clear()` + `= 0`)。漏掉会让 `_flushToState` 的 `full.length == _lastPublishedLength` 守卫在低概率下错误跳过 publish。

**`onReplyArrived()` 不清 buffer 是有意的**——原始 stall timer(974-976)也不清 buffer 只推 `''`,stall-后-delta 回填是既有契约,拆分保留之不引入新 bug。**禁止顺手优化**成清 buffer,若要改单开 PR 带测试。

### 私有方法

- `start(client, instanceId, agentRemoteId)`:`_subscription?.cancel()` 后重订;listen 体含 50KB buffer 上限(`if (_buffer.length < 50*1024) { _buffer.write(text); _scheduleFlush(); }`,**注意:delta 仍翻转 isStreaming + 调 onDeltaActivity,在 if 之外**)、stall timer(30s → `onStreamingTextChanged('')`,buffer 不动)、StreamingDone(立即 `_flushImmediately` + 取消 stall + 推 `''`)、onError(flush + 取消 stall + log)。
- `_scheduleFlush()` / `_flushToState()`(经 `onStreamingTextChanged` 推,`full.length == _lastPublishedLength` 则跳过)/ `_flushImmediately()`。
- `_onEvent(StreamingEvent)`:对比 `event.agentId == _agentRemoteId` 分发 StreamingDelta / StreamingDone。

---

## PreviewUpdater 契约

`lib/features/chat_room/viewmodels/preview_updater.dart`,~50 行,纯 Dart。

```dart
class PreviewUpdater {
  PreviewUpdater({required this.onFlush, required this.isMounted});
  final Future<void> Function(Message) onFlush; // VM 的 _updateConversationPreview 体
  final bool Function() isMounted;

  Message? _pending;
  Timer? _timer;

  void schedule(Message message) {
    if (message.type == MessageType.toolCall) return;       // 护栏 1
    if (_pending == null || message.timestamp >= _pending!.timestamp) {
      _pending = message;
    }
    _timer?.cancel();
    _timer = Timer(Duration.zero, () {                       // 同窗口合并,与现状一致
      final pending = _pending;
      _pending = null;
      if (pending == null || !isMounted()) return;
      onFlush(pending);
    });
  }

  void dispose() { _timer?.cancel(); _timer = null; _pending = null; }
}
```

`_updateConversationPreview`(35 行:护栏 2 时间戳 guard + `generatePreview` + `updateLastMessage` + try/catch)作为 VM 私有方法保留,绑成 `onFlush` 传给 PreviewUpdater。PreviewUpdater 只负责"留 timestamp 最大那条 + 同事件循环合并"。

---

## VM 改造点(`chat_view_model.dart`)

### 字段 diff

```diff
- StreamSubscription<StreamingEvent>? _streamingSubscription;
- final StringBuffer _streamBuffer = StringBuffer();
- int _lastPublishedLength = 0;
- Timer? _flushTimer;
- Timer? _stallTimer;
- Message? _pendingPreviewMessage;
- Timer? _previewCoalesceTimer;
+ late final StreamingLifecycle _streaming = StreamingLifecycle(
+   flushDelay: flushDelay,
+   onStreamingTextChanged: (t) => _updateState((s) => s.copyWith(streamingText: t)),
+   onDeltaActivity: _onDeltaActivity,
+   logger: _logger,
+ );
+ late final PreviewUpdater _preview = PreviewUpdater(
+   onFlush: _updateConversationPreview,
+   isMounted: () => mounted,
+ );
```

保留:`_timeoutTimer` / `_overallTimeoutTimer` / `_messageReloadCoalesceTimer` / 5 个非流式 subscription / 其余 flag。

`late final` 闭包引用 `this._updateState` 的写法有 `_mergeUseCase` 先例(@ 201,Dart 语义:`late final` 惰性求值,构造完成后才首次访问,`this` 完全可用;无环形引用——`_updateState` 不引用 `_streaming`,SL 构造只存回调不反向访问 VM)。

### 新增私有方法

```dart
void _onDeltaActivity() {
  _timeoutTimer?.cancel();
  _timeoutTimer = Timer(const Duration(seconds: 60),
      () => _updateState((s) => s.copyWith(thinkingState: ThinkingState.timeout)));
}
```

`_startThinking`(1019-1025)里 arm `_timeoutTimer` 的 3 行也改成调 `_onDeltaActivity()`,统一入口,避免两处 60s 值漂移。

### 5 个 reset 位点改写

| # | 位点(原行号) | 改后 |
|---|---|---|
| 1 | `_sendCore` 开头(833-843) | `_streaming.resetForSend(); _timeoutTimer?.cancel(); _timeoutTimer = null;` |
| 2 | connection-lost(508-520) | `if (state != connected/connecting/auth && _streaming.isStreaming) { _streaming.onConnectionLost(); _timeoutTimer?.cancel(); _timeoutTimer = null; }` |
| 3 | message 监听 agent 到达(617-624) | `_streaming.onReplyArrived(); _stopThinking();`(`_awaitingReply=false` 留 VM) |
| 4 | `_sendCore` 调 `_startStreaming()`(896) | `_streaming.start(_gatewayClient, instanceId, agent!.remoteId);` |
| 5 | `retry()`(1320-1322) | **删除三行**(`_flushTimer?.cancel(); _streamBuffer.clear(); _lastPublishedLength = 0;`),由 `_teardownSubscriptions()` 内的 `_streaming.cancel()` 承担 |

### `_teardownSubscriptions` 改写

```dart
void _teardownSubscriptions() {
  _messageSubscription?.cancel();       _messageSubscription = null;
  _connectionSubscription?.cancel();    _connectionSubscription = null;
  _toolCallSubscription?.cancel();      _toolCallSubscription = null;
  _streaming.cancel();                  // 原 step4(sub) + step8/10(flush/stall) 打包
  _outboxCountSubscription?.cancel();   _outboxCountSubscription = null;
  _agentSubscription?.cancel();         _agentSubscription = null;
  _timeoutTimer?.cancel();              _timeoutTimer = null;
  _overallTimeoutTimer?.cancel();       _overallTimeoutTimer = null;
  _preview.dispose();                   // 原 pending + previewCoalesceTimer
  _messageReloadCoalesceTimer?.cancel(); _messageReloadCoalesceTimer = null;
  _streamsInitialized = false;
}
```

**顺序声明(v2 补丁,诚实措辞)**:`_streaming.cancel()` 放原 `_streamingSubscription` cancel 位(step4,toolCall 之后、outbox 之前),但 `cancel()` 内部打包取消 sub+flush+stall——即 flush/stall 的**物理取消时机从原 step8/10 提前到 step4**。行为等价(`Timer.cancel` 幂等、中间无 `await`),但非"严格 1:1 保序"。`_preview.dispose()` 放原 preview 字段清理位。

### `vm.isStreaming` 公共 getter(312)

```dart
bool get isStreaming => _streaming.isStreaming;
```

公共契约不变(`streaming_guard_test` 直接读)。

---

## 测试矩阵

### 必须保持 green(零修改)— 11 个 VM 测试文件

`chat_view_model_streaming_guard_test.dart`(10 case,最关键)、`_send_test` / `_retry_test` / `_refresh_agent_test` / `_watch_by_id_test` / `_highlight_test` / `_close_requested_test` / `_history_no_n_plus_1_test` / `_large_payload_test` / `_init_fail_tombstone_test` / `_send_no_redundant_getbyid_test`。

**前提**:编译通过(即 `retry()` 第 5 位点已按上表修复)。全 `test/` 扫描确认无任何测试直接引用被搬走的私有字段/方法——全走公共 API(`vm.isStreaming` / `vm.state` / `vm.reloadMessages` / `vm.init` / `vm.dispose` / `gateway.emit*`),故"零修改"成立。

### 新增单测(Law 17:ViewModel 层 should 测试先行,本项目文化要求 RED-first)

**`test/features/chat_room/streaming_lifecycle_test.dart`**(FakeAsync 隔离,不需 VM/repo/Riverpod):
1. 初始 `isStreaming == false`
2. `start()` 后 StreamingDelta → `isStreaming=true` + `onStreamingTextChanged` 收累积文本
3. 连续 delta 在 `flushDelay` 窗口内 → 只触发一次 `onStreamingTextChanged`(节流)
4. buffer ≥ 50KB 后停止 append,但 `isStreaming` 仍 true、`onDeltaActivity` 仍触发
5. StreamingDone → `isStreaming=false` + 立即 flush + `onStreamingTextChanged('')`
6. `onError` → `isStreaming=false` + flush + stall 取消 + logger 收 error
7. `resetForSend` → 取消 sub、清 buffer、归零 lastPublished、`isStreaming=false`、推 `''`
8. `onConnectionLost` → 清 buffer、归零 lastPublished、取消 stall、`isStreaming=false`、推 `''`,**不**取消 sub、**不**取消 flushTimer
9. `onReplyArrived` → `isStreaming=false` + 推 `''`,**不**清 buffer、**不**归零 lastPublished
10. `cancel` → 取消 sub+timers、清 buffer、归零 lastPublished、`isStreaming=false`、**不**推 state
11. stall timer(30s)触发 → `onStreamingTextChanged('')`,buffer 不动
12. `dispose` 幂等

**`test/features/chat_room/preview_updater_test.dart`**:
1. `schedule(toolCall)` → no-op
2. 同窗口 3 条消息 → 只 `onFlush` 一次,且是 timestamp 最大那条
3. 旧消息在最新消息之后 schedule → 不覆盖最新
4. `dispose` → 取消 timer,不再 flush
5. `isMounted()==false` 时不调 `onFlush`

**`chat_view_model_retry_test.dart` 补一个 case**(审查发现 `retry()` 当前无直接测试覆盖,`chat_room_page:507` 调它但 `test/` 下零 `vm.retry()` 调用):验证 retry 后 `_streaming.isStreaming == false` 且 state 重置为 `LoadInProgress`。

---

## 迁移步骤(2 个独立 PR,各自 RED→GREEN)

### PR-A:抽 PreviewUpdater(小、低风险,先做)

1. **RED**:写 `preview_updater_test.dart`(5 case)
2. **GREEN**:写 `preview_updater.dart`
3. VM 接线:删 2 字段 + `_scheduleConversationPreviewUpdate`;`_updateConversationPreview` 改绑 `onFlush`
4. 跑 `streaming_guard_test` 的 "rapid incoming messages coalesce" case(@ 494)+ 全 VM 测试 + `flutter analyze`

### PR-B:抽 StreamingLifecycle

1. **RED**:写 `streaming_lifecycle_test.dart`(12 case)
2. **GREEN**:写 `streaming_lifecycle.dart`
3. VM 接线:删 5 字段 + `_startStreaming`/`_scheduleFlush`/`_flushToState`/`_flushImmediately` + 5 个 reset 位点(含 `retry()` 删 3 行)+ `_teardownSubscriptions` + `isStreaming` getter + 新增 `_onDeltaActivity`;`_startThinking` 改调 `_onDeltaActivity`
4. 补 `chat_view_model_retry_test.dart` 的 retry case
5. 跑 `streaming_guard_test` 全 10 case + 全 VM 测试 + `flutter analyze`

拆两个 PR 的理由:PR-A 是 14 行逻辑、零行为风险,先建立 `late final` 注入 + callback 模式;PR-B 复用同模式,review 时只需盯 5 个 reset 位点的 1:1 对照表。

---

## 风险与边界

1. **`vm.isStreaming` 是公共契约**——`streaming_guard_test` 直接读(@ 244/258)。getter 必须委托 `_streaming.isStreaming`,别漏。
2. **`_onEvent` 里的 `_agentRemoteId`**——必须 `start()` 传入存字段,否则 `event.agentId == _agentRemoteId` 对比编译错。原 VM 闭包直接捕 `agent!.remoteId`,搬进 SL 后改参数。
3. **`_timeoutTimer` 双 arm 点**——`_startThinking` 和 `_onDeltaActivity` 都 arm 同一字段,改后必须都走 `_onDeltaActivity()` 统一入口,否则两处 60s 值漂移埋雷。
4. **`late final` 初始化**——`_streaming` 闭包引用 `_updateState`/`_logger`/`flushDelay`,三者在构造体就绪。`_mergeUseCase` 已验证此模式。PR-B 接线后跑一次 `flutter analyze` 确认无 `late` 环形引用。
5. **`retry()` 第 5 位点**(v2 补丁)——原方案漏列,照 v1 直接拆会编译失败。必须按"5 个 reset 位点"表 #5 删除三行,由 `cancel()` 承担。
6. **`onConnectionLost` 归零 lastPublished**(v2 补丁)——契约必须显式写,漏掉低概率跳过 publish。
7. **不拆 `_initStreamsAndHistory`**——320 行里 60+ 行注释,纯代码 ~260 行是 5 订阅 + history fetch 编排,拆出要传 5 repo + 4 回调,收益为负。
8. **`cancel()` 清 buffer 的语义偏离**(v2 补丁)——原 teardown 不清 buffer,`cancel()` 清了。但 dispose 路径 buffer 随后 GC、retry 路径本就手动清,两处行为等价、无外部可观测差异。review 时需知此偏离是**有意的合并**,不是疏漏。

---

## 修订记录

**v1 → v2(经 `architecture-reviewer` 审查,4 补丁)**:

| # | 补丁 | 触发问题 |
|---|---|---|
| 1 | 补 `retry()` 第 5 reset 位点(删 1320-1322 三行,由 `cancel()` 承担) | 🔴 阻塞:v1 漏列,照拆直接编译失败,11 个 VM 测试全挂 |
| 2 | `onConnectionLost` 契约显式归零 `_lastPublishedLength` | 🟠 严重:v1 只写"清 buffer",漏 `= 0`,低概率跳过 publish |
| 3 | `_teardownSubscriptions` "不重排顺序" 改为"cancel() 打包,物理提前但语义等价" | 🟡 警告:v1 措辞误导 reviewer 以为 cancel() 只取消 sub |
| 4 | SL 构造函数 purity 写进契约 | 🟡 警告:`vm.isStreaming` 首次访问触发构造,副作用污染 getter |

**审查同时验证成立的判断**:
- 边界选 A(SL 排除两个 timeout timer)比报告原方案 B 更合理 ✅
- `late final` 闭包引用 `this._updateState` Dart 语义成立,`_mergeUseCase` 先例 ✅
- "10 case 零修改全过"成立(前提:retry() 已修);全 `test/` 扫描确认无测试直接读被搬走的私有字段 ✅
- `onReplyArrived` 不清 buffer 是正确的(对齐原始 stall timer 行为)✅

---

## 实现期修订 (v2 → v3)

PR-B 落地时发现 3 处 spec 欠指定/可优化,在实现中补全(边界判定不变):

| # | 细化 | 原因 |
|---|---|---|
| 1 | `start(Stream<StreamingEvent> stream, String agentRemoteId)` 替代 `start(IGatewayClient, instanceId, agentRemoteId)` | ISP:SL 只需流,不需整个 fat ACL 接口;VM 调用方 `_gatewayClient.streamingDeltaStream(id)` 取流后传入;测试直接传 controller.stream,免 mock client |
| 2 | 新增 `stallDelay` 构造参数(默认 30s) | 与 `flushDelay` 平行,生产默认 30s 不变;测试注入小值(30ms)免 FakeAsync 测 stall timer |
| 3 | SL 契约新增 `onStreamError` 回调 | 原 `_startStreaming` 的 onError 取消了 VM 持有的 `_timeoutTimer`,Option A 下 SL 无法直接取消;`onStreamError` 通知 VM 取消之,1:1 保行为(spec v2 的 SL 契约只列了 `onStreamingTextChanged`/`onDeltaActivity`/`logger`,漏了这个) |

**落地验证**:全项目 `flutter analyze` 零 issue;完整测试套件 1738 passed(含新增 `streaming_lifecycle_test.dart` 12 case + `preview_updater_test.dart` 5 case + `retry()` 黑盒 1 case);原 11 个 VM 测试文件零修改全过。
