# 推送通知声音与震动 — 设计文档

**Date**: 2026-06-22
**Status**: Approved
**Related**: US-018（推送通知 Tier1+Tier2，已实现）
**Owner**: NING MEI

---

## 问题概述

当前 `LocalNotificationService` 在创建 Android 通知通道（`clawhub_reply` / `clawhub_error` / `clawhub_connection`）时**未显式传 `playSound` / `enableVibration`** 参数，`AndroidNotificationDetails` 和 `DarwinNotificationDetails()` 同样未显式带声音字段。结果：推送通知到达时没有声音（用户反馈），用户体验缺失。

需要让前台/近前台收到的本地通知（回复 / 出错 / 连接变化）在 iOS 和 Android 上都能播放**系统默认提示音**并触发**默认震动**，且对已升级用户立即生效。

---

## 目标与非目标

### 目标

- 三类通知（reply / error / connection）在 iOS 和 Android 都能播放系统默认提示音 + 默认震动
- 升级用户首次启动即生效，不需重装、不需清数据
- 对 ACL 之上的 `NotificationDispatcher` / `EvaluateNotificationUseCase` / domain 模型零侵入

### 非目标（明确不做）

- 自定义品牌音效（没有资源文件，需求确认系统默认即可）
- 在《通知设置》页里加"声音"开关（用户确认依赖系统设置）
- 修改 DND 静默队列逻辑（DND 内本来就静默入队，flush 时汇总通知自然有声）
- iOS / Android 后台进程被杀时的推送（仍属于 US-018 已知限制，需 Gateway+APNs/FCM）
- 用户级"音量"或"自选铃声"

---

## 设计

### 架构与变更面

ACL 边界保持不变：

```
domain/usecases/evaluate_notification ─┐
                                       ├──► ILocalNotificationService（接口不变）
data/services/notification_dispatcher ─┘                │
                                                        ▼
                                       data/services/local_notification_service
                                                        │
                                                        ▼ （唯一触碰平台插件之处）
                                       flutter_local_notifications 18.x
```

**改动范围 = 一个实现文件 + 它的测试**：

| 文件 | 类型 | 改动 |
|---|---|---|
| `lib/data/services/local_notification_service.dart` | 修改 | channel id 升 v2、`_ChannelConfig` 加 `playSound`/`enableVibration` 字段、注册前删旧 channel、details 显式带声音参数 |
| `test/data/services/local_notification_service_test.dart` | **扩展** | 已存在 9 个 case（payload 透传 / tap 回调 / 冷启动补投 / initialize 幂等 / dispose），本次**新增 4 条**覆盖 v2 channel 配置与迁移行为，现有 case 保留不动 |

**不动的文件**：

- `lib/core/i_local_notification_service.dart` —— 接口零变化
- `lib/domain/**` —— 完全零依赖
- `lib/data/services/notification_dispatcher.dart` —— 完全零依赖
- `lib/app/notifications/notification_coordinator.dart` / `notification_bootstrap.dart` —— 完全零依赖
- `lib/features/settings/notification_settings_page.dart` —— UI 不加开关
- `pubspec.yaml` —— `flutter_local_notifications: ^18.0.1` 已支持所需 API，不升级

### 实现：Channel v2 + 一次性迁移

Android 8+ 的 channel `playSound` / `enableVibration` 字段一旦创建后**不可变**。对已经装了 App 的老用户，他们设备上的 v1 channel 是无声配置，要让他们立即生效，必须用新的 channel id 并删除旧的。

**步骤 1：扩 `_ChannelConfig`**

```dart
class _ChannelConfig {
  final String id;
  final String name;
  final Importance importance;
  final Priority priority;
  final bool playSound;        // ← 新增
  final bool enableVibration;  // ← 新增

  const _ChannelConfig(
    this.id, this.name, this.importance, this.priority,
    {this.playSound = true, this.enableVibration = true},
  );
}
```

**步骤 2：channel 配置升 v2**

```dart
static const _channelConfigs = <NotificationChannelId, _ChannelConfig>{
  NotificationChannelId.reply: _ChannelConfig(
    'clawhub_reply_v2',
    '虾回复',
    Importance.high,
    Priority.high,
  ),
  NotificationChannelId.error: _ChannelConfig(
    'clawhub_error_v2',
    '虾出错',
    Importance.high,
    Priority.high,
  ),
  NotificationChannelId.connection: _ChannelConfig(
    'clawhub_connection_v2',
    '连接变化',
    Importance.defaultImportance,
    Priority.defaultPriority,
  ),
};
```

> `defaultImportance` 通道在 Android 上默认就有声音（无 heads-up 横幅），所以"连接变化"通道开声音是合理默认。若未来嫌吵，可单独把它的 `playSound` 设为 `false`，接口已留好。

**步骤 3：注册时显式传 sound/vibration**

```dart
static List<AndroidNotificationChannel> get _channels => [
  for (final entry in _channelConfigs.entries)
    AndroidNotificationChannel(
      entry.value.id,
      entry.value.name,
      groupId: _channelGroupId,
      importance: entry.value.importance,
      playSound: entry.value.playSound,          // ← 新增
      // sound: null  ==> 系统默认提示音
      enableVibration: entry.value.enableVibration,  // ← 新增
    ),
];
```

**步骤 4：`initialize()` 内增加一次性迁移**

在创建 channel group 之后、循环创建新 channel 之前，best-effort 删除三条历史 channel。

先在 `LocalNotificationService` 类里加一个静态常量（与 `_channelConfigs` 并排）：

```dart
// 类静态字段：历史 v1 channel id，仅供 initialize() 迁移使用
static const _legacyChannelIds = [
  'clawhub_reply',
  'clawhub_error',
  'clawhub_connection',
];
```

然后修改 `initialize()` 的 Android 分支。**迁移必须用 try/catch 包住**——若某条 `deleteNotificationChannel` 在定制 ROM 抛异常，绝不能让下面的 `createNotificationChannel` 没执行（否则 v2 channel 创建不出来，通知功能完全瘫痪，比无声严重得多）：

```dart
if (defaultTargetPlatform == TargetPlatform.android) {
  final android = _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannelGroup(_channelGroup);

  // ── 一次性迁移：删除 v1 历史 channel（不存在时 no-op，失败也要继续创建 v2） ─
  try {
    for (final legacyId in _legacyChannelIds) {
      await android?.deleteNotificationChannel(legacyId);
    }
  } catch (e, st) {
    // best-effort：删除失败仅留下"v1 残留"无功能影响（v2 已是默认），
    // 下次启动会自动重试。绝不让此错误阻断 v2 channel 创建。
    // 注：此处 swallow 已加 iron-law-allow: Law8 -- migration best-effort
  }

  for (final channel in _channels) {
    await android?.createNotificationChannel(channel);
  }
}
```

`deleteNotificationChannel` 对不存在 id 是幂等 no-op，所以全新用户和升级用户走同一段代码，无需额外分支。`initialize()` 现有 `_initialized` 卫兵保证只执行一次。

**步骤 5：`AndroidNotificationDetails` 显式带声音参数**

虽然 Android 8+ 由 channel 覆盖，但显式写上为 Android 7 及以下兜底：

```dart
AndroidNotificationDetails _androidDetailsFor(NotificationChannelId channel) {
  final c = _channelConfigs[channel]!;
  return AndroidNotificationDetails(
    c.id, c.name,
    groupKey: _channelGroupId,
    importance: c.importance,
    priority: c.priority,
    playSound: c.playSound,             // ← 新增
    enableVibration: c.enableVibration, // ← 新增
  );
}
```

**步骤 6：iOS `DarwinNotificationDetails` 改为显式带 `presentSound`**

`show()` 内的 iOS details 从 `const DarwinNotificationDetails()` 改为：

```dart
iOS: const DarwinNotificationDetails(
  presentSound: true,
  // sound: null  ==> 系统默认提示音
),
```

`presentSound: true` 在 v18 是默认值，显式写出来纯粹是表达意图。

---

## 跨平台行为矩阵

| 场景 | Android 8+ | Android 7 及以下 | iOS |
|---|---|---|---|
| 回复通知 | `clawhub_reply_v2` channel：系统默认音 + 默认震动 + heads-up | details `playSound:true`，系统默认音 + 默认震动 | `presentSound:true`，系统默认音 |
| 出错通知 | `clawhub_error_v2`：同上 | 同上 | 同上 |
| 连接变化通知 | `clawhub_connection_v2`：默认 importance，有声无 heads-up | 同上 | 同上 |
| DND 时段内回复 | dispatcher 入 `pending_notifications` 静默不弹 | 同左 | 同左 |
| DND 结束 flush 汇总 | "N 条新消息" 走 reply channel，**自动有声** | 同左 | 同左 |
| 系统勿扰 / 静音模式 | 由 OS 决定，应用层不绕过 | 同左 | 同左 |
| 用户在系统设置里关了通道声音 | 静音 —— OS 覆盖应用，应用层不还击 | n/a | n/a |
| 升级用户首次启动 | v1 删除，v2 即时生效 | 一直走 details，无迁移 | 一直走 details，无迁移 |

---

## 测试计划

`test/data/services/local_notification_service_test.dart` **已存在**，使用 `mocktail` 注入 mock 的 `FlutterLocalNotificationsPlugin`，覆盖 9 个 case：

| 现有 case（保留不动） |
|---|
| `handleNotificationTap` null routePath 是 no-op |
| `handleNotificationTap` 空 routePath 是 no-op |
| `show` 透传 routePath 为 payload |
| `show` routePath 缺省时 payload 为 null |
| 注册 tap 回调后收到 payload |
| 冷启动 payload 缓存后由 setupOnTap 补投 |
| tap 在 setupOnTap 之前到达时缓冲并补投 |
| `initialize` 幂等（重复调用 plugin.initialize 只调一次） |
| `dispose` 清除 tap 回调 |

**本次新增 4 条**：

1. **`show` details 携带 sound/vibration 参数**：扩展现有 `show forwards routePath` 测试或新建一条，捕获 `plugin.show` 的第 4 个位置参数（`NotificationDetails`），断言其 `android.playSound == true && android.enableVibration == true`，`iOS.presentSound == true`
2. **Android channel 迁移调用顺序**：通过额外 mock `AndroidFlutterLocalNotificationsPlugin`（让 `resolvePlatformSpecificImplementation<...>()` 返回 mock 而非 null），用 `verifyInOrder` 校验调用序列：`createNotificationChannelGroup` → 3 次 `deleteNotificationChannel('clawhub_*')` → 3 次 `createNotificationChannel('clawhub_*_v2')`
3. **v2 channel 配置正确性**：捕获每次 `createNotificationChannel` 的参数，断言 `playSound == true && enableVibration == true && id == 'clawhub_*_v2' && importance` 与 `_channelConfigs` 匹配
4. **迁移失败的稳健性**：让某条 `deleteNotificationChannel` `thenThrow`，验证后续的 `createNotificationChannel` 仍被调用（即 try/catch 兜底生效）

> **测试环境约束**：Flutter test 默认 `defaultTargetPlatform == TargetPlatform.android`，所以 `initialize()` 的 Android 分支可达。如默认值未来改变，需在新增 case 顶部加 `debugDefaultTargetPlatformOverride = TargetPlatform.android;`（`tearDown` 重置）。

**不需改动的测试**（接口未变）：

- `test/data/services/notification_dispatcher_test.dart`
- `test/app/notifications/notification_coordinator_test.dart`
- `test/features/settings/notification_settings_page_test.dart`

---

## 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 用户曾在系统设置里手动关掉 v1 channel sound | 升级后 v1 删除，v2 重新默认有声，可能违反用户意图 | CHANGELOG / release note 写明"通知通道已升级，如需静音请重新关闭"。Android channel 模型固有约束 |
| 已显示但未点掉的 v1 通知，在 channel 被删后的行为 | flutter_local_notifications 18 删除 channel 时不撤销已显示通知，但其 sound URI 解析通常会失败 → **静音残留**。再次点击是否仍走 payload 路由也需验证 | 通过 DoD 手测项验证：v1 时段发出未点击的通知，升级后行为如何（点击仍能跳转；再次发声不应触发） |
| Android 13+ POST_NOTIFICATIONS 权限被拒 | 通道创建成功但 `show` 静默失败 | 已有 `requestPermissions()` 流程，不变 |
| `deleteNotificationChannel` 在某些定制 ROM 抛异常 | 若不兜底会让 `createNotificationChannel` 没执行→**通知功能完全瘫痪**（远比无声严重） | **必须** 在迁移循环外加 try/catch，catch 后继续 create 循环。已在 §3 步骤 4 落实 |
| `flutter_local_notifications` 18.x 与目标 OS 版本兼容 | 应无问题，已在使用 | 不变更版本 |

---

## 验收标准（DoD）

- [ ] `flutter analyze` 零警告
- [ ] `flutter test test/data/services/local_notification_service_test.dart` 全绿（现有 9 + 新增 4 = 13 case）
- [ ] `flutter test` 整套全绿（无回归）
- [ ] 真机/模拟器手测：iOS + Android 各发一条 reply 通知，听到系统默认音 + 感到震动
- [ ] 真机手测升级路径：先 checkout 当前 master 生成 v1 channel，再切到本次 PR 重启 App，第一次收通知就有声
- [ ] **真机手测 v1 残留通知行为**：在 v1 上发 1 条 reply 通知不点掉 → 升级到 v2 重启 → 验证残留通知点击路由仍可跳转、且不应在 v2 启动瞬间再次发声
- [ ] iron-law pre-commit hook 通过（迁移 try/catch 块需带 `iron-law-allow: Law8` 注释）
- [ ] CHANGELOG 加一行 "feat(notification): 推送通知加入系统默认提示音和震动"
- [ ] 在 `~/.claude/projects/.../memory/us018-notification-status.md` 追加一行："v18 channel 升级（clawhub_*_v2）修复无声问题"

---

## Iron Laws 合规

| Law | 是否触发 | 说明 |
|---|---|---|
| 1（domain 纯净） | ✅ 不动 domain |
| 2（widget 只渲染） | ✅ 不动 UI |
| 4（StateNotifier vs ValueNotifier） | ✅ 不涉及 |
| 6（批量查询） | ✅ 不涉及 DB |
| 11（ListView.builder） | ✅ 不涉及列表 |
| 14（widget 至少 2 测试） | ✅ 不动 widget |
| 17（TDD 分层） | ✅ Service 测试与代码同 commit；非 domain 文件不强制 RED-first |
