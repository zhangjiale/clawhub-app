# US-018 Background Sync — Design Doc

**Date**: 2026-06-29
**Status**: Draft — pending user review
**Source**: User request "US-018 后台保活"; existing notification chain complete but background lifecycle missing
**Parent PRD**: [PRD §3.8 推送通知与状态提醒](../product/prd.md#38-推送通知与状态提醒)
**Parent UserStory**: [UserStory US-018](../product/user-stories.md#us-018推送通知任务完成提醒)

## Problem Summary

US-018 Tier 1/2 已实现（[memory: us018-notification-status]），但有已知限制：

> 当前推送依赖 App 在前台或短期后台时 WebSocket 连接仍存活；冷启动 / 系统回收后到达的消息不会主动推送。

根本原因：

| 缺失 | 现状 |
|---|---|
| `WidgetsBindingObserver` 生命周期处理 | lib 下零引用 |
| Android Foreground Service / WorkManager | 零依赖、零代码 |
| iOS BGTaskScheduler 注册 | Info.plist 无 `UIBackgroundModes`、`AppDelegate.swift` 不存在（ios 目录几乎空） |
| 后台 isolate 入口 | 无 |

导致：App 被系统挂起 → Dart isolate 冻结 → WebSocket 被 OS 杀 → `messageStream` 沉默 → 通知链路无事件可消费。

## Design Constraints（用户决策）

1. **不实现 Foreground Service**（用户明确拒绝）。不接受持续通知栏图标
2. 接受 **WorkManager（Android）+ BGTaskScheduler（iOS）周期拉取**（无持续通知）
3. **增量拉取**自从上次同步以来的消息（per-instance last_sync_at）
4. **15 min 跨平台对齐**调度间隔
5. **提供"后台同步"开关**给用户，默认启用
6. **检测主 isolate 仍在运行 → 跳过**后台拉取

## Architecture Overview

### 新增组件

| 组件 | 职责 | 位置 |
|---|---|---|
| `BackgroundSyncScheduler` | 平台抽象：注册/取消/触发后台任务 | `lib/core/lifecycle/background_sync_scheduler.dart` |
| `BackgroundSyncRunner` | 后台任务入口：执行一次完整拉取 | `lib/core/lifecycle/background_sync_runner.dart` |
| `BackgroundSyncGate` | 跨 isolate 通信：主 isolate active 标记 | `lib/core/lifecycle/background_sync_gate.dart` |
| `LastSyncAtRepository` | per-instance 持久化 `last_background_sync_at` | `lib/data/repositories/drift_last_sync_repo.dart` |
| `BackgroundSyncToggleNotifier` | Riverpod notifier：监听 prefs → schedule/cancel | `lib/features/settings/providers/background_sync_providers.dart` |
| `DriftSyncStateTable` | Drift schema 新表 `sync_state`（schemaVersion 7 → 8） | `lib/data/local/database/schema.drift`（仅 schema 定义） |

### 复用组件（不重写）

- `WsGatewayClient`（`lib/core/acl/ws_gateway_client.dart`）：OpenClaw v4 协议
- `MessageRepository`（`lib/data/repositories/drift_message_repo.dart`）：写入 + dedup
- `NotificationDispatcher`（`lib/data/services/notification_dispatcher.dart`）：**新增 public 方法** `handlePulledMessages(List<Message>)`（仅在后台拉取路径调用，不订阅流）。复用现有 `evaluateNotification` use case + `flushDndSummary` 路径
- `flutter_secure_storage`：跨 isolate 共享（keychain/keystore）
- `LocalNotificationService`（`lib/data/services/local_notification_service.dart`）：跨 isolate 需重新 init

### 数据流

```
┌────────────────────────────────────────────────────────────┐
│ Main Isolate (UI)                                           │
│                                                              │
│  NotificationBootstrap.init()                               │
│   └─ BackgroundSyncToggleNotifier.init()                    │
│       └─ watch settings.backgroundSyncEnabled              │
│           └─ BackgroundSyncScheduler.schedule() / cancel()  │
│                                                              │
│  WidgetsBindingObserver.didChangeAppLifecycleState          │
│   └─ BackgroundSyncGate.notifyForegrounded()               │
└────────────────────────────────────────────────────────────┘
                │ workmanager (Android) / BGTaskScheduler (iOS)
                │ 15 min 间隔，系统调度
                ▼
┌────────────────────────────────────────────────────────────┐
│ 后台执行上下文（平台差异）                                     │
│  • Android: workmanager 启动 background isolate（独立进程）  │
│  • iOS:     BGTaskScheduler 唤醒主 isolate 约 30 秒         │
│                                                              │
│  BackgroundSyncRunner.executeOnce()                         │
│   1. BackgroundSyncGate.shouldSkip() → 主 isolate 跑则返回 │
│   2. 加载 Settings (backgroundSyncEnabled + 实例列表)        │
│   3. settings.enabled=false → return                       │
│   4. 加载 last_background_sync_at per-instance              │
│   5. 对每个 enabled instance:                                │
│      - 从 secure storage 取 URL + Token                     │
│      - WsGatewayClient.connect (10s 超时)                   │
│      - fetchRecentMessages(since=last_sync_at) (15s 超时)   │
│      - MessageRepo.saveBatch (事务批量插入)                 │
│      - NotificationDispatcher.handlePulledMessages(list)   │
│      - WsGatewayClient.disconnect                            │
│   6. 更新 last_background_sync_at = max(message.serverTs)  │
│      - 无消息 → 用 DateTime.now()                            │
│      - 失败 → 不更新，下次重试（依赖 dedup 兜底）           │
└────────────────────────────────────────────────────────────┘
```

## Background Sync Lifecycle

### 触发源

| 触发条件 | 处理 |
|---|---|
| 用户在设置页切换"后台同步"开关 | `BackgroundSyncToggleNotifier` 监听 prefs stream，立即 `schedule()` 或 `cancel()` |
| App 启动完成 | `NotificationBootstrap.init()` 末尾调用 `ensureScheduled()` |
| 用户开启新 Instance | `ConnectionOrchestrator.onInstanceSaved()` 末尾调用 `BackgroundSyncScheduler.notifyInstancesChanged()` |
| 系统调度（15 min 后） | `BackgroundSyncRunner.executeOnce()` 被平台层调用 |

### 执行时序（`executeOnce`）

```
T+0s    Android: 进入后台 isolate / iOS: 主 isolate 被唤醒
T+0.1s  BackgroundSyncGate.shouldSkip()
T+0.2s  Android: Drift DB reopen（iOS 主 isolate 已持有连接，跳过）
T+0.5s  读 Settings (backgroundSyncEnabled + List<Instance>)
T+1s    读 last_background_sync_at per-instance
T+1.5s  对每个 instance:
        ├─ WsGatewayClient.connect (10s 超时)
        ├─ fetchRecentMessages (15s 超时)
        ├─ MessageRepo.saveBatch
        ├─ NotificationDispatcher.handlePulledMessages
        └─ WsGatewayClient.disconnect
        单 instance 预算 ≤ 25s（iOS 30s 唤醒窗口）
T+25s   全部完成 / 任一超时 → 跳出循环
T+25.5s 更新 last_background_sync_at per-instance
T+26s   exit(0)
```

### 状态持久化

| 字段 | 位置 | 用途 |
|---|---|---|
| `background_sync_enabled` | `UserPreferences` freezed 字段（Drift `settings` 表加列） | 主 isolate + 后台 isolate 都读 |
| `last_background_sync_at` | 新表 `sync_state(instance_id PRIMARY KEY, last_sync_at INTEGER)` | 后台 isolate 写，主 isolate 只读 |
| `main_isolate_active` | 内存 flag + SharedPreferences atomic flag | 主 isolate 启动 → true；dispose → false |

## Error Handling

| 错误类别 | 例子 | 处理 | 是否更新 last_sync_at |
|---|---|---|---|
| **平台层错误** | workmanager 未注册 / BGTaskScheduler 拒绝 | log，UI 设置页可显示"后台同步不可用" | — |
| **主 isolate 仍在前台** | `BackgroundSyncGate.shouldSkip()=true` | 静默退出 | ❌ |
| **后台同步开关关闭** | `backgroundSyncEnabled=false` | 静默退出 | ❌ |
| **Drift DB 打开失败** | DB 损坏 / schema 不兼容 | 静默退出 | ❌ |
| **secure storage 读取失败** | Token 缺失 | 跳过该 instance | ❌ |
| **WebSocket 连接超时** | Gateway 不可达 | 跳过该 instance | ❌ |
| **认证失败** | Token 过期 | 跳过该 instance，不降级，下次仍尝试 | ❌ |
| **协议错误** | OpenClaw v4 不兼容 | 跳过该 instance | ❌ |
| **拉取成功 0 条** | 正常 | 更新 last_sync_at = now() | ✅ |
| **拉取成功且有消息** | 正常 | 更新 last_sync_at = max(serverTs) | ✅ |
| **保存消息失败** | Drift 事务失败 | 不更新 last_sync_at | ❌ |
| **本地通知触发异常** | NotificationService 失败 | log，不影响 last_sync_at | ✅ |
| **多 instance 部分失败** | A 成功 B 失败 | 各自独立更新 | 各自处理 |

### per-instance last_sync_at

**不用全局 last_sync_at**：

- A Gateway 离线 1h 后恢复，不应把"1h 离线"消息回放给 B 实例
- 每 instance 独立追踪同步窗口

### 错误暴露

| 层级 | 行为 |
|---|---|
| 后台 isolate 内 | log + 内部 `lastSyncStatus` 字段更新 |
| UI 层 | 不主动展示。设置页可显示"上次同步：5 min 前 / 失败：Gateway X 离线" |
| 推送 | 失败时**不发**通知 |

### 重试策略

- **不重试**：单次 `executeOnce` 内失败即跳过
- **依赖系统调度**：15 min 后再次唤醒，尝试相同区间（依赖 Message dedup 兜底）

## Native Layer Changes

### Android `AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>  <!-- 新增 -->

<application ...>
    <activity ...>...</activity>

    <provider
        android:name="androidx.startup.InitializationProvider"
        android:authorities="${applicationId}.androidx-startup"
        android:exported="false"
        tools:node="merge">
        <meta-data
            android:name="androidx.work.WorkManagerInitializer"
            android:value="androidx.startup"
            tools:node="remove" />
    </provider>
</application>
```

### Flutter 侧（关键）

- 用 `workmanager` 包 `Workmanager().initialize(callbackDispatcher, ...)` 在 App 启动时注册
- callback 函数必须是 **top-level / static**（`@pragma('vm:entry-point')` 防止 tree-shaking）
- 在 background isolate 中运行 → 需重新初始化 Drift / secure storage / notification service

### iOS `Info.plist`

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.clawhub.background-sync</string>
</array>
```

### iOS `AppDelegate.swift`（新建）

```swift
import UIKit
import Flutter
import background_fetch

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        WorkmanagerPlugin.registerTask(withIdentifier: "com.clawhub.background-sync")
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

### 跨平台差异

| 维度 | Android (WorkManager) | iOS (BGTaskScheduler) |
|---|---|---|
| 最短调度间隔 | 15 min | ~15 min（系统决定） |
| 唤醒窗口 | 无硬限制（Doze 限制网络） | ~30 秒 |
| 是否需要特定权限 | `RECEIVE_BOOT_COMPLETED` | 无 |
| 用户禁用路径 | 系统设置 → 应用 → 后台活动 → 关 | 设置 → 通用 → 后台 App 刷新 → 关 |
| 跨重启调度保持 | ✅ 需 RECEIVE_BOOT_COMPLETED | ✅ 系统保持 |
| 厂商限制 | 华为/小米/OPPO 需用户加白名单 | 无 |

## Testing Strategy

### Domain 单元测试（铁律 17 强制 TDD）

| 文件 | 关键用例 |
|---|---|
| `test/core/lifecycle/background_sync_gate_test.dart` | main active → skip=true；inactive → false |
| `test/data/repositories/drift_last_sync_repo_test.dart` | get / upsert / 不存在返回 null |
| `test/core/lifecycle/background_sync_runner_test.dart` | 见下 |

### `BackgroundSyncRunner` 详细用例

```
✓ executeOnce_skipWhenMainIsolateActive     — 主 isolate active → 跳过，0 次 connect
✓ executeOnce_skipWhenToggleDisabled        — 开关关闭 → 跳过
✓ executeOnce_pullAllInstances              — 2 instance → 都 connect → 都 fetch → 都 disconnect
✓ executeOnce_partialFailure_continues      — A 成功 B 失败 → A 更新 last_sync_at，B 不更新
✓ executeOnce_perInstanceLastSync           — per-instance 时间戳，不用全局
✓ executeOnce_zeroMessages_updatesLastSync  — 0 条 → 用 now() 更新
✓ executeOnce_notifyViaDispatcher           — 拉到的 agent 回复 → LocalNotificationService.show 被调用
✓ executeOnce_tombstoneAgentSuppressed      — tombstoned agent 回复 → 不通知（与现有 AC 对齐）
✓ executeOnce_timeoutDoesNotUpdateSync      — 25s 超时 → 不更新，下次重试同区间
✓ executeOnce_dndRespected                 — DND 时段 → 不立即通知，存入 pending（DND 到期 flush）
```

### Widget 测试

- 设置页"后台同步"开关 UI 切换 → Riverpod state 正确变更 → `BackgroundSyncScheduler.schedule/cancel` 被调用

### 平台集成测试

- **Android**：手动验证 logcat `WM-WorkerWrapper` 中 `BackgroundSyncRunner.executeOnce` 被执行
- **iOS**：Xcode Debug → Simulate Background Fetch → 验证执行

### 自动化测试覆盖不到的边界（文档化到 spec "已知限制"）

- 系统调度延迟真实分布（15min ~ 数小时）
- 厂商省电策略对 WorkManager 的影响
- Doze 模式下 WorkManager 被延后
- iOS 后台唤醒窗口 30 秒限制

## Migration

| 改动 | 策略 | 风险 |
|---|---|---|
| `sync_state` 新表 | Drift schemaVersion 7 → 8，仅增表 | 低 |
| `UserPreferences.backgroundSyncEnabled` | freezed default=true；Drift ALTER TABLE 加列 | 低 |
| 旧用户无 `last_background_sync_at` | 首次后台同步用 `DateTime.now() - 24h` 起点 | 中：可能一次性拉 24h 消息 |

## Out of Scope

| 不做 | 原因 |
|---|---|
| Foreground Service | 用户明确拒绝 |
| APNs / FCM 远程推送 | 需 Gateway 协议改造 |
| 持续 WebSocket 保活（任何形式） | 用户明确拒绝 |
| 后台调度间隔可配置 | 默认 15 min 跨平台对齐已足够 |
| 后台拉取失败时弹通知 | 失败是常态，弹通知刷屏 |
| Android 厂商白名单引导 | 属于另一个 Story |
| 离线缓存清理 | 已在另一 Story 范围 |

## Acceptance Criteria（更新版）

### 保留

- **AC-16**（推送通知）：前台 + 短期后台场景下通知仍实时

### 改写

- **AC-16 隐含的"实时推送"语义**：spec 文档化为"已知限制"——通知延迟 15min ~ 数小时 best-effort

### 新增

- **AC-21**：用户开启后台同步开关后，杀掉 App 进程 30 min 以上再打开，应能看到杀进程期间到达的消息通知（best-effort）

### Manual Verification Checklist

```
□ Android 真机：打开 App → 设置 → 后台同步开启 → 杀掉进程 → 等待 30 min → 重新打开 → 验证杀掉期间的通知是否到达
□ Android 真机：设置 → 后台同步关闭 → 杀掉进程 → 等待 30 min → 验证无后台拉取（logcat 无 BackgroundSyncRunner 调用）
□ Android 真机：关闭网络 → 后台拉取应静默失败，不弹通知
□ iOS 真机：Debug → Simulate Background Fetch → 验证后台任务执行
□ iOS 真机：杀掉 App → 锁屏 → 等待 30 min → 解锁 → 验证通知
□ 跨重启：重启手机 → 验证后台同步仍被调度
□ DND 时段：开启 DND → 后台拉取到消息 → 验证不立即通知，存入 pending
□ DND 结束：到点后 → 验证汇总通知
□ Tombstoned agent：被 tombstone 的 agent 在后台拉取到消息 → 验证不通知
□ 多 instance：A 在线 B 离线 → 后台同步 → A 拉到消息，B 失败不影响 A 的 last_sync_at
□ 设置页：切换后台同步开关 → 验证 workmanager 立即 schedule / cancel
```

## Known Risks（必须文档化）

| 风险 | 触发 | 缓解 |
|---|---|---|
| iOS App Store 拒审 | 声明 UIBackgroundModes 但实际未使用 | 每次 fetch 都执行真实拉取 |
| Android 厂商杀进程 | 华为/小米/OPPO 省电模式 | 文档化为已知限制，不在本 Story 修复 |
| WorkManager Doze 模式 | 屏幕关闭后网络受限 | 文档化为已知限制 |
| iOS 系统调度延迟 | 用户使用频率低 | 文档化为已知限制 |
| 后台拉取超过 30s（iOS） | 单 instance 拉取慢 | 单 instance 预算 25s；超时即退出 |

## Implementation Effort Estimate

| 模块 | Points（Fibonacci） |
|---|---|
| `BackgroundSyncGate` + test | 2 |
| `LastSyncAtRepository` + test | 2 |
| `UserPreferences` 字段 + Drift migration | 1 |
| `BackgroundSyncRunner` + 10 个测试用例 | 8 |
| `BackgroundSyncScheduler` 平台抽象 | 3 |
| `BackgroundSyncToggleNotifier` + 设置页 UI | 2 |
| `NotificationDispatcher.handlePulledMessages` 新 entry | 2 |
| Android Manifest + workmanager 集成 | 2 |
| iOS Info.plist + AppDelegate.swift + workmanager 集成 | 3 |
| 手动验证 + 文档 | 2 |
| **合计** | **27 Points** |

超出 PRD 估算（US-018 原 5 Points）。原因：原估算假设使用 Foreground Service（单点改动），但用户决策后方案转向"平台工作调度器 + 后台 isolate"路径，工程量翻倍。