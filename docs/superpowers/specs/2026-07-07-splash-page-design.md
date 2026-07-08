# 设计：开屏页（Splash Page）

- **日期**：2026-07-07
- **状态**：v2 — brainstorming 6 节 + 架构评审委员会（5 维度 + challenge）双重确认；5 项必修已应用；待用户 review 后进入 planning
- **来源**：用户请求 "我想设计一个开屏页 也就是启动页"
- **关联**：[`background-sync-limitations.md` §Workmanager Plugin Upgrade Trap](../technical/background-sync-limitations.md) — 2026-07-01 启动死锁事件是本次设计的直接触发点

---

## 1. 背景与目标

### 1.1 现状

- **平台开屏半坏**：
  - `android/app/src/main/res/drawable/launch_background.xml` 引用 `@drawable/background`（存在）和 `@drawable/splash`（**不存在**）—— 中心 Logo 永远 inflate 失败，运行时回退到裸背景。
  - `flutter_native_splash: ^2.4.4` 已在 `pubspec.yaml` 配好 `image: "docs/design/assets/xiahub-splash-v3.png"`，**但从未跑过 `flutter_native_splash:create`** → 没有生成任何 drawable / storyboard。
  - iOS 端 `LaunchScreen.storyboard` 是默认纯白 `Theme.Light` storyboard。
  - `values-v31/styles.xml` 和 `values-night-v31/styles.xml` 缺 `windowBackground`，Android 12+ 上平台开屏会显示全白。
- **没有 Flutter 层开屏**：
  - `lib/main.dart` 的 `_ConnectionInitializer` 在 init 期间让 `MaterialApp.router` 同步渲染主页 shell —— init 还没完成时用户看到的是 3-Tab 导航骨架（无 instance 时会立即空状态，无品牌露出）。
  - `lib/main.dart` 没有 `splash` / `splash_screen` / `startup` 相关文件（grep `splash` 全仓只有 `lib/data/services/local_notification_service.dart` 一次命中，跟"系统通知 Splash"无关）。
- **冷启动可感知时间窗**：
  - Pre-runApp：`Workmanager().initialize()` + `createAppDatabase()` ≈ 200–500ms。
  - Post-runApp：`NotificationBootstrap.init()` + `ConnectionOrchestrator.initialize()`（自动连接所有已配 instance）≈ 1–3s。
  - 用户当前体验：先看到坏掉的平台开屏 → 突然跳到 3-Tab shell（无 instance 时是空状态）→ 1–3s 后 instance 连接完成、空状态刷新。
- **2026-07-01 启动死锁事件**：`docs/technical/background-sync-limitations.md` 详述——`runApp` 永不调用时平台开屏成为唯一可见表面，且**没有可观察的失败信号**。该事件催生了 `bootstrapApp` 失败转 `DefaultErrorFallback` 的 guardrail；本次设计让 guardrail 的 fatal screen 在 post-runApp 路径上也得到一致行为（见 §5）。

### 1.2 目标

加一个**跨平台一致的开屏**（Android + iOS + Flutter），让用户从点图标到看到 3-Tab 主页之间有 ≥ 800ms 的稳定品牌露出，覆盖 cold start 全部时间窗；平台开屏和 Flutter 开屏复用同一张品牌素材，主题与 App 暗色主题一致。

### 1.3 用户确认的范围（brainstorming 结论）

| 维度 | 选定 |
|---|---|
| 范围 | 平台开屏 + Flutter 侧开屏页面（都做） |
| 启动过渡 | 最短展示时间 + 初始化完了才走（≥ 800ms + wait-for-init） |
| 页面元素 | 品牌 Logo + App 名称 + 版本号（无加载动画、无动态背景） |
| 底部文案 | App 版本号（`v0.1.0+1` 格式，从 `PackageInfo` 读） |
| 素材构成 | 两侧用同一张图（`xiahub-splash-v3.png`） |
| 明暗主题 | 强制暗色，生成单一 drawable（不提供 OS 暗色专用变体） |
| iOS 启动屏 | 也品牌化（替换默认 storyboard） |
| 最短时间 | 800ms |
| Flutter 接入架构 | **方案 A：作为启动闸门**（重构 `_ConnectionInitializer` → `_StartupGate`，状态机 `splash` ↔ `app`） |
| 错误处理 | **Tier-gate 捕获**（board 评审后采纳）：`NotificationBootstrap.init()` 失败 → `FatalScreen`（fatal，gates 通知权限和 platform bindings）；`ConnectionOrchestrator.initialize()` 失败 → 局部 catch，**恢复** in-app banner（保留旧 SnackBar 行为），app shell 正常 mount。**有意行为变更**：原 `ConnectionOrchestrator` 失败的 fatal 升屏被取消，flaky-network 用户恢复离线可用 |

### 1.4 非目标（明确不做）

- 开屏期间加载动画 / 进度条 / Shimmer
- 动态背景（呼吸/缩放/渐入）
- 品牌 Slogan（仅版本号）
- App 内 logo 与背景图解耦（V3 合成图整体复用）
- iOS 状态栏保留（iOS 也走全屏）
- Android 12+ 单独 icon 资源（V3 共用先跑，视觉验证后再决定是否拆）
- "原地重试 init"（Retry 走全量重启 `main()`，复用现有 fatal screen 语义）
- **board 修订后撤销的非目标**：原 v1 列了"所有 init 失败 → `FatalScreen`"作为有意行为变更（移除非 fatal 路径的 SnackBar）。v2 改为 **tier-gate 捕获**：ConnectionOrchestrator 软失败**保留** in-app banner（不删除 SnackBar 路径）。这条非目标被 v2 撤销。

---

## 2. 架构与文件布局

### 2.1 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│ main()                                                      │
│   └── bootstrapApp(...)                                     │
│         ├─ Workmanager.initialize(...)         (预 runApp)  │
│         ├─ createAppDatabase()                  (预 runApp)  │
│         └─ runApp(ProviderScope(                (runApp)     │
│                child: ClawHubApp                              │
│              ))                                              │
│                                                              │
│ ClawHubApp                                                   │
│   └── _StartupGate                       ← 本设计新增        │
│         ├─ phase = splash                                    │
│         │     ├─ 触发 NotificationBootstrap +                │
│         │     │  ConnectionOrchestrator.initialize()        │
│         │     ├─ Future.wait([init, 800ms timer])           │
│         │     └─ 渲染 SplashScreen                           │
│         │           (独立 Material · 深色主题)              │
│         │                                                   │
│         ├─ phase = splash + init error → FatalScreen         │
│         │                                                   │
│         └─ phase = app                                       │
│               └─ 渲染 MaterialApp.router                    │
└─────────────────────────────────────────────────────────────┘
```

核心思想：把现在的 `_ConnectionInitializer` 升级成 `_StartupGate`，引入 `StartupPhase` 状态机（`splash` / `app`），让开屏页面在 `runApp` 之后、`MaterialApp.router` 渲染之前占据画面。`init` 完成 + 800ms 两个条件都满足才切到 `app` 阶段、挂载真正的 router。

### 2.2 新增文件

| 文件 | 层 | 职责 | 依赖 |
|---|---|---|---|
| `lib/app/splash/startup_gate.dart` | app | `_StartupGate` widget + `StartupPhase` enum + `_StartupGateState` | flutter_riverpod, package_info_plus, 现有 `NotificationBootstrap` / `connectionOrchestratorProvider` |
| `lib/app/splash/splash_screen.dart` | app | `SplashScreen` widget（全屏品牌图 + 版本号） | flutter, `XiaColors` / `XiaSpacing` tokens |
| `lib/app/splash/min_display_timer.dart` | app | `MinDisplayTimer.wait(Duration)` 纯函数 | dart:async |
| `lib/ui_kit/fatal_screen.dart` | ui_kit | `FatalScreen` widget（可复用 fatal UI） | flutter, `DefaultErrorFallback`, `XiaColors` |
| `test/app/splash/min_display_timer_test.dart` | test | 单测：计时器不早于 duration 完成（Law 17 TDD 先行） | fake_async |
| `test/app/splash/splash_screen_test.dart` | test | widget 测试：渲染品牌图 + 版本号（Law 14 ≥2） | flutter_test |
| `test/app/splash/startup_gate_test.dart` | test | widget 测试：splash→app 切换、错误路径、800ms 计时（Law 14 ≥2） | flutter_test, fake_async, mocktail |
| `test/ui_kit/fatal_screen_test.dart` | test | widget 测试：渲染错误、Retry 触发回调（Law 14 ≥2） | flutter_test |

### 2.3 修改文件

| 文件 | 改动 |
|---|---|
| `lib/main.dart` | `_ConnectionInitializer` → `_StartupGate`；`showFatal` 内联的 `runApp(MaterialApp(...DefaultErrorFallback...))` 重构为 `runApp(MaterialApp(...FatalScreen...))` |
| `pubspec.yaml` | (1) `flutter.assets:` 块加 `- docs/design/assets/xiahub-splash-v3.png`（**当前未列出**，SplashScreen 的 `Image.asset` 引用会运行时崩溃）；(2) `flutter_native_splash` 块补全 `color_dark` / `android_12` / `ios_content_mode` / `fullscreen` 字段（现有 `color: "#111110"` ≠ V2 暗色 bg `#08090D`，需要同步更新）；(3) 加 `package_info_plus` 依赖（若未在） |
| `android/app/src/main/res/{values,values-night,values-v31,values-night-v31}/styles.xml` | 由 `flutter_native_splash:create` 自动重写（commit 进版本控制） |
| `android/app/src/main/res/drawable*/launch_background.xml` | 同上 |
| `ios/Runner/Base.lproj/LaunchScreen.storyboard` | 由 `flutter_native_splash:create` 自动重写（commit 进版本控制） |
| `ios/Runner/Info.plist` | 由插件按需补字段（如 `UILaunchStoryboardName`） |

### 2.4 关键分层决策

1. **`SplashScreen` 独立 widget，不嵌入 ui_kit 之外的现成组件**：因为它**渲染在 `MaterialApp` 之外**（见 §3.1），需要自带 `Material` + `Directionality` 兜底，所以不依赖 `ui_kit` 中假设有 `Theme`/`MediaQuery` 继承的组件。

2. **`FatalScreen` 放 `lib/ui_kit/`**：因为它**既被 main.dart 的 `runApp` 路径使用（顶层 runApp，需要外层 MaterialApp），也被 `_StartupGate` 的 inline 路径使用（在 runApp 之内）**。放 ui_kit 让两边都能用，不与 splash 耦合。

3. **`MinDisplayTimer` 抽成纯函数**：测试时用 `fake_async` 验证计时准确性，避免 widget 测试里真实 `Future.delayed` 拖慢 CI。**Law 17：domain 抽出来后必须先写测试再写实现**。

4. **不开新依赖**：`flutter_native_splash` 已在 `pubspec.yaml`；`package_info_plus` 是 Flutter 官方包、加进来读取版本号。`fake_async` / `mocktail` 已在测试依赖里（现有 `bootstrap_test.dart` 用了 `mocktail`）。

5. **`StartupPhase` enum 不入 DI**：状态机是 `_StartupGate` 的内部状态，外部不需要观察。注入 SplashScreen 看到的应该是 widget props（`version`），不是 phase。

---

## 3. 组件结构

### 3.1 `SplashScreen`

```dart
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.canvas,
      color: XiaColors.bg, // 兜底色：背景图加载未完成时显示深色
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. 全屏背景图：复用平台开屏同一张素材
            Image.asset(
              'docs/design/assets/xiahub-splash-v3.png',
              fit: BoxFit.cover,
              frameBuilder: (_, child, frame, sync) =>
                  frame == null
                      ? const ColoredBox(color: XiaColors.bg)
                      : child,
            ),
            // 2. 底部版本号（弱化文案，不抢主体）
            Positioned(
              left: 0,
              right: 0,
              bottom: XiaSpacing.s8, // V2: 32px
              child: Center(
                child: Text(
                  version,
                  style: AppTheme.darkTheme.textTheme.bodySmall?.copyWith(
                    color: XiaColors.text3, // 30% alpha —— V2 弱化文案
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

设计要点：

1. **自带 `Material` + `Directionality`**：Splash 阶段还没进 `MaterialApp.router`，没有 `Theme`/`Directionality`/`MediaQuery` 继承。这一层是"独立运行时"，跟 fatal screen 的 `MaterialApp(... DefaultErrorFallback ...)` 是同类设计。

2. **`Stack.fit: StackFit.expand`**：背景图 + 版本号都需要全屏坐标系，expand 让子节点自动拿到 Stack 的尺寸约束。

3. **`frameBuilder` 不作为首帧防御**（board 评审修订）：`Image.frameBuilder` 只在 build 期间触发，**首帧没有前一帧可参考**——Performance 评审正确反驳了 Architect 的原始 claim。`Material` 自带 `XiaColors.bg` 是 paint 兜底（不依赖 `frameBuilder`），但**首帧 decode 防御**由 `_StartupGate` 在 `initState` 的 postFrameCallback 里调 `precacheImage(AssetImage('docs/design/assets/xiahub-splash-v3.png'), context)` 完成——把 decode 提前到 init 等待期内，与 `Future.wait([init, 800ms])` 并行消化。

4. **Logo + App 名称已在背景图里**：`xiahub-splash-v3.png` 是已合成素材（含 Logo + 名称），Flutter 层只额外加版本号，不重复渲染 Logo。

5. **无 SafeArea**：跟 Android `LaunchTheme` 的 `windowFullscreen=true` + `windowLayoutInDisplayCutoutMode=shortEdges` 一致，开屏期间吃满整屏（含刘海区）。iOS 同理。

6. **状态无关**：`StatelessWidget`，版本号通过参数注入（由 `_StartupGate` 在 `initState` 里读 `PackageInfo` 后传入）。这让 SplashScreen 可以脱离启动流程独立测试。

### 3.2 `MinDisplayTimer`

```dart
class MinDisplayTimer {
  /// Wait at least [duration] before completing.
  /// Pure function — extracted to a static so tests can use `fake_async`
  /// to advance the virtual clock without real wall-clock delays.
  static Future<void> wait(Duration duration) =>
      Future<void>.delayed(duration);
}
```

设计要点：

1. **纯函数 = 可单测**：测试用 `FakeAsync().run((async) { ... async.elapse(799ms); expect(done, false); async.elapse(1ms); expect(done, true); })` 验证"不早于 duration 完成"。

2. **不需要返回 `Completer`**：上游用 `Future.wait([init, MinDisplayTimer.wait(800ms)])` 已经能同时等待两件事。`MinDisplayTimer` 只暴露"等够 N ms"这一件事。

### 3.3 `_StartupGate` 状态机

```dart
enum StartupPhase { splash, app }

class _StartupGate extends ConsumerStatefulWidget {
  const _StartupGate({required this.child});
  final Widget child; // child = MaterialApp.router
  @override
  ConsumerState<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<_StartupGate> {
  StartupPhase _phase = StartupPhase.splash;
  String _version = '';
  Object? _initError;
  StackTrace? _initStackTrace;

  @override
  void initState() {
    super.initState();
    // 把 splash 资产 decode 提前到 init 等待期内，避免首帧 decode lag 闪烁。
    // postFrameCallback 拿到合法的 BuildContext；与 _runStartup 并行执行。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(
        const AssetImage('docs/design/assets/xiahub-splash-v3.png'),
        context,
      );
    });
    _runStartup();
  }

  Future<void> _runStartup() async {
    try {
      // 1. 读版本号（PackageInfo 异步但通常 <50ms；与 init 并行启动）
      final pkgFuture = PackageInfo.fromPlatform();

      // 2. 启动 init 任务 + 最短展示计时器
      await Future.wait<Object?>([
        _runInitialization(),
        MinDisplayTimer.wait(const Duration(milliseconds: 800)),
      ]);

      // 3. 等到 init 完成 + 800ms 都满足 → 切到 app 阶段
      final pkg = await pkgFuture;
      if (!mounted) return;
      setState(() {
        _version = 'v${pkg.version}+${pkg.buildNumber}';
        _phase = StartupPhase.app;
      });
    } catch (e, st) {
      // 仅 NotificationBootstrap.init() 抛错会逃逸到这里（见 _runInitialization
      // 的 tier-gating 注释）；ConnectionOrchestrator 失败被局部吞掉，转 soft-fail。
      if (mounted) {
        setState(() {
          _initError = e;
          _initStackTrace = st;
        });
      }
    }
  }

  Future<void> _runInitialization() async {
    // Tier 1 (fatal) — NotificationBootstrap gates 通知权限和 platform bindings，
    // 失败时不应进入 app shell。抛错会被 _runStartup 的外层 catch 捕获。
    final bootstrap = NotificationBootstrap(ref);
    await bootstrap.init();

    // Tier 2 (soft-fail) — ConnectionOrchestrator 失败 = 网络/transport 失败，
    // 是移动 App 最常见失败模式。失败时记日志 + 写入 connectionInitStateProvider，
    // 让 app shell 的现有 ref.listen 触发 in-app banner。app shell 正常 mount，
    // 用户可继续浏览本地缓存内容。
    try {
      final orchestrator = ref.read(connectionOrchestratorProvider);
      await orchestrator.initialize();
    } catch (e, st) {
      ref.read(loggerProvider).error(
        '[startup] orchestrator init soft-failed: $e', st);
      // 触发与原 _ConnectionInitializer 相同的 SnackBar 路径
      ref.read(connectionInitStateProvider.notifier).state =
          AsyncValue.error(e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return FatalScreen(
        error: _initError!,
        stackTrace: _initStackTrace!,
        onRetry: () => main(),
      );
    }
    return switch (_phase) {
      StartupPhase.splash => SplashScreen(version: _version),
      StartupPhase.app => widget.child,
    };
  }
}
```

设计要点：

1. **`Future.wait` 同时等待 init + 计时器**：保证两者都满足才切到 app。这是"最短展示时间 + 初始化完成"语义的标准实现，比 `if (initDone && elapsed >= 800) transition` 轮询干净。

2. **版本号并行读**：`PackageInfo.fromPlatform()` 与 init 并行启动，最后 `await pkgFuture` 拿结果。即使 init 极慢，版本号也不会额外拖时间。

3. **`precacheImage` 提前首帧 decode**（board 修订）：`frameBuilder` 不是首帧防御；改用 `precacheImage` 把 splash 资产 decode 提前到 `initState` 的 postFrameCallback 内执行。decode 与 `Future.wait([init, 800ms])` 并行消化，不阻塞 splash→app 切换。

4. **错误语义：Tier-gate 捕获**（board 修订）：
   - **Tier 1 (fatal)** — `NotificationBootstrap.init()` 抛错：gates 通知权限和 platform bindings，结构性失败不能进 app shell → 走 `FatalScreen`。
   - **Tier 2 (soft-fail)** — `ConnectionOrchestrator.initialize()` 抛错：网络/transport 失败是移动 App 最常见失败模式 → 局部 catch，写入 `connectionInitStateProvider`，app shell 正常 mount，由 `ClawHubApp` 的现有 `ref.listen` 触发 in-app banner。
   - **理由**（board 评审）：把所有 init 失败都升为 `FatalScreen` 对 flaky-network 用户是可用性回归——他们当前是 5s SnackBar + 仍可离线用，新方案是硬锁屏 + Retry 重跑 bootstrap 2-5s 几乎必然再失败。Tier-gate 保留 defense-in-depth（notification 失败仍致命）的同时恢复 degraded-but-usable UX。

5. **`mounted` 检查**：init 是 async，gate widget 可能被 unmount（hot-restart、测试 teardown），写 state 前必须 `mounted` 守卫。

6. **`main()` Retry**：与现有 fatal screen 一致——Retry 直接重跑整个 `main()`，包括 bootstrap（workmanager + DB），不会复用已 dispose 的 ProviderScope。Retry 仅用于 Tier 1（fatal）路径；Tier 2（soft-fail）走 in-app banner，不显示 Retry。

7. **`connectionInitStateProvider` 复用**：原 `_ConnectionInitializer` 写入它、`ClawHubApp` SnackBar 监听它。新设计 tier-gate 后 provider **保留**——Tier 2 失败仍写入 provider，复用现有 SnackBar 路径，不引入新机制（详见 §5.3）。

---

## 4. 平台开屏配置

### 4.1 `pubspec.yaml` 中 `flutter_native_splash` 配置

```yaml
flutter_native_splash:
  # 强制暗色 —— App 本身只暗色（ThemeMode.dark），平台开屏保持一致。
  # color_dark 覆盖 OS 在暗色模式下的 drawable；不设 color_light 让插件不生成明色 drawable。
  color: "#08090D"        # = XiaColors.bg （V2 暗色 bg）
  color_dark: "#08090D"   # 跟 color 相同 → OS 明色时也是暗色
  
  # 同一张品牌素材在两侧复用
  image: "docs/design/assets/xiahub-splash-v3.png"
  
  # Android 12+ 用 SplashScreen API（windowSplashScreen*）。
  # 这里跟 color/image 保持一致，避免 Android 12+ 设备出现"短暂白屏 → 图"闪烁。
  android_12:
    color: "#08090D"
    image: "docs/design/assets/xiahub-splash-v3.png"
    icon_background_color: "#08090D"
  
  # iOS：图居中显示（LaunchScreen.storyboard 自动生成）
  ios_content_mode: "center"
  fullscreen: true  # 跟 Android LaunchTheme 的 windowFullscreen=true 对齐
```

### 4.2 跑 `flutter pub run flutter_native_splash:create` 自动生成

执行后插件会：

| 平台 | 生成/修改文件 | 行为 |
|---|---|---|
| **Android (legacy)** | `res/drawable/launch_background.xml`、`values/styles.xml`、`values-night/styles.xml` | 重写为 `@drawable/launch_background` 引用 image+color |
| **Android 12+** | `res/values-v31/styles.xml`、`res/values-night-v31/styles.xml` | 注入 `windowSplashScreenBackground` + `windowSplashScreenAnimatedIcon` |
| **iOS** | `ios/Runner/Base.lproj/LaunchScreen.storyboard`、`Info.plist` | 在 storyboard 加 `LaunchBackground`（色块）+ `LaunchImage`（品牌图） |

### 4.3 关键决策

1. **强制暗色通过 `color_dark` 而非 Theme 父类切换**：现状 `values/styles.xml` parent 是 `Theme.Light.NoTitleBar`，`values-night` parent 是 `Theme.Black.NoTitleBar`——依赖 OS 明暗模式。新方案改用 `color` + `color_dark` 两套 drawable，但**两套都用同一深色**。brainstorming 中用户已确认。

2. **不用 `color_light`**：插件把 `color` 当 light、`color_dark` 当 dark；两者相同 = "只深色"。

3. **Android 12+ SplashScreen API 的图片处理**：
   - Android 12 SplashScreen API 要求 `windowSplashScreenAnimatedIcon` 是带透明通道的 foreground icon（OS 自动加圆形遮罩）。
   - `xiahub-splash-v3.png` 是合成素材（带背景图），不是 icon。`icon_background_color` 用来遮丑——把 `icon_background_color` 设成跟 `color` 同色，相当于在 icon 后面再垫一层同色背景。
   - V3 共用先跑一次，Android 12+ 视觉验证后再决定是否拆 icon（不在本 spec 范围）。brainstorming 中用户已确认。

4. **iOS 全屏 vs 留状态栏**：`fullscreen: true` 让 iOS 也走全屏，跟 Android 对齐。brainstorming 中用户已确认。

5. **不引入新依赖**：`flutter_native_splash` 已在 `pubspec.yaml`；本次新增的 `package_info_plus` 是 Flutter 官方包。

6. **生成产物入版本控制**：插件生成的文件（drawable XML、storyboard、Info.plist 改动）commit 进 repo，不加 `.gitignore`。

---

## 5. 错误处理

### 5.1 `FatalScreen` 抽取

```dart
class FatalScreen extends StatefulWidget {
  const FatalScreen({
    super.key,
    required this.error,
    required this.stackTrace,
    required this.onRetry,
  });

  final Object error;
  final StackTrace stackTrace;
  final VoidCallback onRetry;

  @override
  State<FatalScreen> createState() => _FatalScreenState();
}

class _FatalScreenState extends State<FatalScreen> {
  // 防 Retry 按钮双击：慢设备上连点两次会让第二个 main() 在第一个 ProviderScope
  // 半 teardown 时撞库（main.dart:41-44 的 onDispose 只能兜一次）。
  bool _retrying = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.canvas,
      color: XiaColors.bg,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SafeArea(
          child: DefaultErrorFallback(
            error: widget.error,
            stackTrace: widget.stackTrace,
            onRetry: _retrying
                ? null
                : () {
                    setState(() => _retrying = true);
                    widget.onRetry();
                  },
          ),
        ),
      ),
    );
  }
}
```

### 5.2 `main.dart` 重构：用 `FatalScreen` 替换内联实现

```dart
showFatal: (error, stackTrace) => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: ThemeMode.dark,
    home: FatalScreen(
      error: error,
      stackTrace: stackTrace,
      onRetry: () => main(),
    ),
  ),
),
```

### 5.3 设计要点

1. **为什么不让 FatalScreen 嵌 MaterialApp**：`_StartupGate` 已经在 ProviderScope 内运行，再嵌 MaterialApp 会建第二套 Navigator 浪费 widget tree。直接渲染 `Material + Directionality` 是更轻的方案。`main.dart` 那边因为是 `runApp` 顶层，保留外层 `MaterialApp` 是必要的（提供 `WidgetsApp` 的 navigator / route 基础设施）。

2. **`SafeArea` 移到 widget 内**：当前 `main.dart` 在 `Scaffold` 里包了 `SafeArea`。抽到 `FatalScreen` 后，无论上层有没有 `Scaffold` 都自带安全区，行为一致。

3. **Retry 语义 = `() => main()`**：与现有 fatal screen 完全一致。重跑 `main()` 会：
   - 重新 `WidgetsFlutterBinding.ensureInitialized()`
   - 重新跑 `bootstrapApp`（workmanager + DB）
   - 重新 `runApp(ProviderScope(...))` —— 整个 ProviderScope 重新建立
   
   含义："点 Retry → 看到开屏 → 看到主页" 全量重启。

4. **Retry 防双击（`_retrying` flag，board 修订）**：慢设备上连点 Retry 两次会让第二个 `main()` 在第一个 `ProviderScope` 半 teardown 时撞库（`main.dart:41-44` 的 `onDispose` 只能兜一次）。`_FatalScreenState._retrying` 标记后即把 `onRetry` 设为 `null`，Retry 按钮 disable。

5. **错误来源 + Tier-gate 处置**（board 修订）：
   - **Tier 1（fatal → `FatalScreen`）**：
     - `NotificationBootstrap.init()`（platform 通道调用）—— 极少见但结构性
   - **Tier 2（soft-fail → in-app banner）**：
     - `ConnectionOrchestrator.initialize()`（网络连接）—— 较常见（无网络/无 instance）
   - **不影响 fatal / soft-fail 分流**：
     - `PackageInfo.fromPlatform()` —— 几乎不会失败

6. **`connectionInitStateProvider` 决策**（board 修订，与 §8 #3 一致）：
   - **保留** provider。原 §5.3 旧版"清理 SnackBar listener 移除"的说法作废。
   - Tier 2（soft-fail）路径继续写入 `connectionInitStateProvider`，由 `ClawHubApp` 的现有 `ref.listen` 触发 SnackBar。**复用现有机制，不引入新 banner 通道**。
   - Tier 1（fatal）路径绕开 provider，直接进 `FatalScreen`。
   - 实施前 `grep -rn "connectionInitStateProvider" lib/` 确认没有非 SnackBar 消费方；如有非 SnackBar 消费方，本设计仍兼容（它们仍可正常 watch）。

---

## 6. 测试策略

### 6.1 测试覆盖矩阵

| 组件 | 难度 | Iron Law | 测试类型 | 必跑场景 |
|---|---|---|---|---|
| `SplashScreen` | 易 | Law 14 (≥2 tests) | Widget test | 渲染品牌图、渲染版本号 |
| `FatalScreen` | 易 | Law 14 (≥2 tests) | Widget test | 渲染错误、Retry 触发回调、**Retry 防双击（board 修订）** |
| `_StartupGate` 状态机 | 中 | Law 2 (无业务逻辑) | Widget + tester.pump | splash→app 切换、**800ms 不早切**（board 修订）、**precacheImage 触发**（board 修订） |
| `_StartupGate` 错误路径 | 中 | Law 2 | Widget | **Tier 1 致命：NotificationBootstrap 抛错 → FatalScreen**（board 修订） |
| `_StartupGate` 软失败路径 | 中 | Law 2 | Widget | **Tier 2 软失败：ConnectionOrchestrator 抛错 → app shell mount**（board 修订） |
| `MinDisplayTimer` | 易 | Law 17 (Domain TDD) | Unit + fake_async | 不早于 duration 完成 |
| `flutter_native_splash` 生成结果 | N/A | N/A | 手动 | 视觉验证 V3 合成图 |

### 6.2 各组件测试设计

#### `SplashScreen` (2 tests)

```dart
testWidgets('renders brand image asset', (tester) async {
  await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
  expect(find.byType(Image), findsOneWidget);
  expect(
    (tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName,
    'docs/design/assets/xiahub-splash-v3.png',
  );
});

testWidgets('renders version text at bottom center', (tester) async {
  await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
  expect(find.text('v0.1.0+1'), findsOneWidget);
  final positioned = tester.widget<Positioned>(
    find.ancestor(of: find.text('v0.1.0+1'), matching: find.byType(Positioned)),
  );
  expect(positioned.bottom, XiaSpacing.s8);
});
```

#### `FatalScreen` (3 tests, board 修订后加 _retrying 测试)

```dart
testWidgets('renders error message', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: FatalScreen(
      error: 'boom',
      stackTrace: StackTrace.current,
      onRetry: () {},
    ),
  ));
  expect(find.text('boom'), findsOneWidget);
});

testWidgets('Retry button triggers callback on first tap', (tester) async {
  var retries = 0;
  await tester.pumpWidget(MaterialApp(
    home: FatalScreen(
      error: 'boom',
      stackTrace: StackTrace.current,
      onRetry: () => retries++,
    ),
  ));
  await tester.tap(find.text('重试'));
  expect(retries, 1);
});

testWidgets('Retry button disables after first tap (防双击, board 修订)', (tester) async {
  var retries = 0;
  await tester.pumpWidget(MaterialApp(
    home: FatalScreen(
      error: 'boom',
      stackTrace: StackTrace.current,
      onRetry: () => retries++,
    ),
  ));
  // 第一次点击：触发 callback，按钮 disable
  await tester.tap(find.text('重试'));
  expect(retries, 1);
  await tester.pump();
  // 第二次点击：button 已经 disabled，retries 不应再增加
  await tester.tap(find.text('重试'), warnIfMissed: false);
  expect(retries, 1, reason: 'Retry should be disabled after first tap');
});
```

#### `_StartupGate` 状态机（5 tests，含 board 修订后的 tier-gate + precacheImage + 软失败）

```dart
testWidgets('initial phase shows SplashScreen', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      connectionOrchestratorProvider.overrideWith((ref) =>
        FakeOrchestrator(completesAfter: const Duration(seconds: 10))),
    ],
    child: const _StartupGate(child: Text('APP')),
  ));
  await tester.pump();
  expect(find.byType(SplashScreen), findsOneWidget);
  expect(find.text('APP'), findsNothing);
});

testWidgets('does not transition before 800ms even if init is instant', (tester) async {
  // 用 tester.pump 推进虚拟时钟（不是 FakeAsync().run —— 后者没有 widget tree）
  await tester.pumpWidget(ProviderScope(
    overrides: [
      connectionOrchestratorProvider.overrideWith((ref) =>
        FakeOrchestrator(completesAfter: Duration.zero)),
    ],
    child: const _StartupGate(child: Text('APP')),
  ));
  await tester.pump(); // init resolves
  await tester.pump(const Duration(milliseconds: 799));
  expect(find.byType(SplashScreen), findsOneWidget,
      reason: 'min display time not yet met');
  await tester.pump(const Duration(milliseconds: 1));
  expect(find.text('APP'), findsOneWidget);
  expect(find.byType(SplashScreen), findsNothing);
});

testWidgets('NotificationBootstrap failure → FatalScreen (Tier 1 fatal)', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      // 注入一个永远抛错的 NotificationBootstrap fake
      notificationBootstrapProvider.overrideWith((ref) =>
        FakeNotificationBootstrap(throwsOnInit: StateError('notif boom'))),
    ],
    child: const _StartupGate(child: Text('APP')),
  ));
  await tester.pump();
  await tester.pumpAndSettle();
  expect(find.byType(FatalScreen), findsOneWidget);
  expect(find.text('APP'), findsNothing);
});

testWidgets('ConnectionOrchestrator failure → app shell mounts (Tier 2 soft-fail)', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      connectionOrchestratorProvider.overrideWith((ref) =>
        FakeOrchestrator(throwsOnInit: StateError('net boom'))),
    ],
    child: const _StartupGate(child: Text('APP')),
  ));
  await tester.pump();
  await tester.pumpAndSettle();
  // 软失败：app shell 正常 mount，连接失败由 connectionInitStateProvider 触发的
  // SnackBar 显示（不归本测试断言范围）
  expect(find.text('APP'), findsOneWidget);
  expect(find.byType(FatalScreen), findsNothing);
  expect(find.byType(SplashScreen), findsNothing);
});

testWidgets('precacheImage fires once in initState (avoids first-frame decode lag)', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      connectionOrchestratorProvider.overrideWith((ref) =>
        FakeOrchestrator(completesAfter: const Duration(seconds: 10))),
    ],
    child: const _StartupGate(child: Text('APP')),
  ));
  await tester.pump();
  // 验证 image cache 里有 splash asset
  final assetImage = const AssetImage('docs/design/assets/xiahub-splash-v3.png');
  expect(imageCache.containsKey(assetImage), isTrue);
  // 清掉 image cache 避免污染后续 test
  imageCache.clear();
});
```

#### `MinDisplayTimer` (1 test, Law 17)

```dart
test('does not complete before duration elapses', () {
  FakeAsync().run((async) {
    var done = false;
    MinDisplayTimer.wait(const Duration(milliseconds: 800))
        .then((_) => done = true);
    async.elapse(const Duration(milliseconds: 799));
    expect(done, isFalse);
    async.elapse(const Duration(milliseconds: 1));
    expect(done, isTrue);
  });
});
```

### 6.3 关键测试决策

1. **`fake_async` 跑计时器**：`Future.delayed(800ms)` 在 widget test 里是真实时间，会拖慢测试。`fake_async` 让 `pumpAndSettle` 在 0 真实时间内推进虚拟时钟。

2. **Fake `ConnectionOrchestrator`**：用 Riverpod `overrideWith` 注入 fake，**不要** mock 网络层。Fake 实现 `ConnectionOrchestrator` 接口（已有契约），只控制"何时完成/是否抛错"。

3. **不测 `flutter_native_splash` 生成结果**：build-time 工具，**视觉验证靠真机/模拟器**。

4. **`bootstrap_test.dart` 回归保护**：现有 `test/app/bootstrap_test.dart` 测 `bootstrapApp` 行为。本次设计**不修改 `bootstrapApp` 签名**，该测试保持绿色。

### 6.4 TDD 顺序（Law 17）

按这个顺序写——先 RED 后 GREEN：

1. `test/app/splash/min_display_timer_test.dart` → RED → `lib/app/splash/min_display_timer.dart` → GREEN
2. `test/app/splash/splash_screen_test.dart` → RED → `lib/app/splash/splash_screen.dart` → GREEN
3. `test/ui_kit/fatal_screen_test.dart` → RED → `lib/ui_kit/fatal_screen.dart` → GREEN
4. `test/app/splash/startup_gate_test.dart` → RED → `lib/app/splash/startup_gate.dart` → GREEN
5. `lib/main.dart` 重构（接入 `_StartupGate` + `FatalScreen`）→ 跑现有 `test/app/bootstrap_test.dart` 确保不破坏

### 6.5 手动验证 Checklist（不进 CI）

- [ ] Android 冷启动：深色品牌图，无白闪，无 Logo 跳变
- [ ] Android 12+：品牌图作为 SplashScreen icon 显示正常
- [ ] iOS 冷启动：深色品牌图
- [ ] iOS 全屏（无状态栏）
- [ ] Flutter splash：800ms 内不切走（即使 init 极快）
- [ ] Flutter splash：版本号正确显示（debug/release）
- [ ] Flutter splash：模拟 NotificationBootstrap 失败 → 看到 FatalScreen（**Tier 1 致命，board 修订**）
- [ ] Flutter splash：模拟 ConnectionOrchestrator 失败 → 看到 in-app banner + app shell 正常 mount（**Tier 2 软失败，board 修订**）
- [ ] FatalScreen：Retry 按钮能正常重跑
- [ ] FatalScreen：双击 Retry → 只触发一次 `main()`（**board 修订：`_retrying` 防双击**）
- [ ] iOS + Android 真机：连续冷启动 5 次，每次都看到完整品牌图
- [ ] **board 修订** CI 加 `dart run flutter_native_splash:create` + `git diff --exit-code` 兜底 broken-drawable 类 bug（详见 §8）

---

## 7. Iron Law 合规检查

| Law | 合规 | 说明 |
|---|---|---|
| Law 1: domain/ 零外部依赖 | N/A | 本设计不修改 `lib/domain/` |
| Law 2: widget 只渲染 UI | ✅ | `SplashScreen` / `FatalScreen` 无业务逻辑；`_StartupGate` 只做 init 编排 |
| Law 3: 依赖抽象不依赖实现 | ✅ | `NotificationBootstrap` / `ConnectionOrchestrator` 已有抽象边界 |
| Law 4: ValueNotifier+addListener+setState 禁用 | ✅ | 状态机用 `setState`（state 内部），不跨 widget 桥接 |
| Law 6: 批量查询无 N+1 | N/A | 不涉及数据查询 |
| Law 8: 空 catch 块禁用 | ✅ | `_runStartup` 的 `catch (e, st)` 显式处理并 setState |
| Law 11: >20 项列表用 ListView.builder | N/A | SplashScreen 只 2 个子节点 |
| Law 14: 新 widget ≥2 tests | ✅ | SplashScreen 2 tests、FatalScreen 2 tests、_StartupGate 3 tests |
| Law 17: domain TDD | ✅ | `MinDisplayTimer` 先写测试 |
| Law 18: keyed-lookup nulls 显式 | ✅ | `connectionOrchestratorProvider` 经 `ref.read` 拿到非空实例 |

---

## 8. Open Questions / Future Work

- **Android 12+ 视觉验证**：V3 共用先跑一次。若 SplashScreen API 上 V3 看起来被裁切/比例怪，再单独导出一张 `splash-android12-icon.png`（透明通道 icon）作为 `android_12.image`。
- **Retry 升级为"原地重试 init"**：当前 Retry 走全量重启 `main()`。如果未来发现用户高频遇到 init 失败，可以把 `_runStartup` 抽成可重入函数 + 处理 ProviderScope 复用问题。
- **`connectionInitStateProvider` 的归宿**（board 修订，已定）：**保留** provider。tier-gate 后 Tier 2 软失败路径继续写入 provider，由 `ClawHubApp` 的现有 `ref.listen` 触发 SnackBar。**结论与原 §5.3 旧版"清理 SnackBar listener"相反，以本条为准**。实施前 `grep -rn "connectionInitStateProvider" lib/` 确认无其他非 SnackBar 消费方。
- **CI 加 `flutter_native_splash:create` 兜底**（board 建议，非阻塞）：当前 broken-drawable 状态正是这类 bug；CI 跑 `dart run flutter_native_splash:create` + `git diff --exit-code`，能 PR-time 拦住未来类似的 platform splash 漂移。可与现有 `pre-commit` hook（CLAUDE.md 提到）合并到 `scripts/`。
- **Splash 资产路径 ADR**（board 建议，非阻塞）：当前 spec 用 `docs/design/assets/xiahub-splash-v3.png` 作为 `Image.asset` 路径 + `flutter.assets` 条目，与现有 `assets/mock/` 约定不一致。两条路：(a) 把 png 移到 `assets/splash/xiahub-splash-v3.png`，对齐 `flutter.assets` 约定；(b) 写一段 ADR 解释 `docs/design/assets/` carve-out。V3 暂时不推荐 (a)（可能影响其他文档/品牌资产引用），优先 (b)。
- **`Workmanager().initialize()` 幂等**（board 风险条目，非阻塞）：Retry 走 `() => main()` 会重新调 `Workmanager().initialize()`。如果 workmanager 0.9.0+3 的 `initialize()` 不是幂等的（文档没明说），第二次调可能抛 `PlatformException` → 走 fatal screen。`bootstrapApp` 里加个 `bool _workmanagerInitialized = false` 守卫。**实施前查 workmanager 0.9.0+3 文档/源码确认**。
- **图标 v3→v4 进度**：观察到工作树中 `xiahub-icon-v3.png` 已删、`xiahub-icon-v4.png` 已添加（`flutter_launcher_icons` 块已配 v4），但 `xiahub-splash-v3.png` 仍存在（无 v4 splash）。本次 spec 引用 v3 splash——splash 是合成素材（带背景），与 icon 是独立轨道。实施阶段如果出现 v4 splash 资源，单点修改 `Image.asset` 路径 + `flutter_native_splash.image` 字段即可。

---

## 9. 修订历史

- v1（2026-07-07）：初始设计。brainstorming 6 节全部经用户确认通过。
- v2（2026-07-07）：架构评审委员会（5 维度 + challenge）后修订。5 项必修：
  1. 修 spec §6.2 自带坏测试（`MinDisplayTimer.wait` 签名对齐、`tester.pump` 替代 `FakeAsync().run` 内的 `find.text`）
  2. **Tier-gate 捕获**：NotificationBootstrap fatal / ConnectionOrchestrator soft-fail
  3. 解 §5.3 vs §8 #3 `connectionInitStateProvider` 矛盾（保留 provider，Tier 2 复用 SnackBar 路径）
  4. 弃 `frameBuilder` 防御，换 `precacheImage` 在 `initState` 的 postFrameCallback
  5. `FatalScreen` 加 `_retrying` flag 防双击 Retry
  
  + 4 项非阻塞建议（§8）：CI `flutter_native_splash:create` 兜底、Splash 资产路径 ADR、`Workmanager.initialize()` 幂等守卫、TalkBack/VoiceOver a11y 标签。
  
  整体风险 🟡 MEDIUM → 🟢 LOW（修完后）。
