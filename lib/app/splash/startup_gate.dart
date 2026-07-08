import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/splash/min_display_timer.dart';
import 'package:claw_hub/app/splash/splash_screen.dart';
import 'package:claw_hub/ui_kit/fatal_screen.dart';

enum StartupPhase { splash, app }

/// 启动闸门：splash ↔ app 状态机。
///
/// 在 runApp 之后、`MaterialApp.router` 之前挂载。
/// - splash 阶段：渲染 `SplashScreen`，等 init 完成 + 800ms
/// - app 阶段：渲染 `child`（= `MaterialApp.router`）
/// - 错误（board 修订 tier-gate）：
///   - Tier 1 (Notification fatal) → `FatalScreen`
///   - Tier 2 (Connection soft-fail) → app shell mount，写 connectionInitStateProvider
class StartupGate extends ConsumerStatefulWidget {
  const StartupGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<StartupGate> createState() => StartupGateState();
}

class StartupGateState extends ConsumerState<StartupGate> {
  StartupPhase _phase = StartupPhase.splash;
  String _version = '';
  Object? _initError;
  StackTrace? _initStackTrace;

  @override
  void initState() {
    super.initState();
    // 把 splash 资产 decode 提前到 init 等待期内（board 修订：frameBuilder 不是
    // 首帧防御，必须 precacheImage）。postFrameCallback 拿到合法 BuildContext。
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
      // 1. 读版本号（与 init 并行启动）
      final pkgFuture = PackageInfo.fromPlatform();

      // 2. 启动 init 任务 + 最短展示计时器
      await Future.wait<Object?>([
        _runInitialization(),
        MinDisplayTimer.wait(const Duration(milliseconds: 800)),
      ]);

      // 3. 都满足 → 切到 app 阶段
      final pkg = await pkgFuture;
      if (!mounted) return;
      setState(() {
        _version = 'v${pkg.version}+${pkg.buildNumber}';
        _phase = StartupPhase.app;
      });
    } catch (e, st) {
      // 仅 NotificationBootstrap.init() 抛错会逃逸到这里
      // （_runInitialization 里 ConnectionOrchestrator 失败被局部吞掉）
      //
      // 时序注记：Future.wait 默认 eagerError:false —— 即使 _runInitialization
      // 已 reject，也要等 MinDisplayTimer(800ms) settle 后才把错误抛到这里。
      // 所以 FatalScreen 最迟在 init 抛错后 800ms 才出现（与最小展示时间对齐，
      // 不会更早）。这是预期行为，不是 bug。
      if (mounted) {
        setState(() {
          _initError = e;
          _initStackTrace = st;
        });
      }
    }
  }

  Future<void> _runInitialization() async {
    // Tier 1 (fatal) — 失败时不应进 app shell
    final bootstrap = ref.read(notificationBootstrapProvider);
    await bootstrap.init();

    // Tier 2 (soft-fail) — 失败时记日志 + 写 connectionInitStateProvider
    try {
      final orchestrator = ref.read(connectionOrchestratorProvider);
      await orchestrator.initialize();
      // 成功信号：与旧 _ConnectionInitializer 行为对齐 —— 让 in-app banner
      // 等消费者能区分「init 完成」与「未跑完」。放 try 内、orchestrator 之后：
      // orchestrator 抛错时这行不执行，直接进 catch 写 error，不会覆盖。
      ref.read(connectionInitStateProvider.notifier).state =
          const AsyncValue.data(null);
    } catch (e, st) {
      ref
          .read(loggerProvider)
          .error('[startup] orchestrator init soft-failed: $e', st);
      ref.read(connectionInitStateProvider.notifier).state = AsyncValue.error(
        e,
        st,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return FatalScreen(
        error: _initError!,
        stackTrace: _initStackTrace!,
        // Retry 重入 _runStartup 而不是调 main()：
        // 1. 避免 startup_gate.dart → main.dart 循环 import
        //    （main.dart 自身就要 import StartupGate）
        // 2. 跳过 bootstrapApp 里的 Workmanager().initialize() 第二次调用
        //    （review #4 风险点：workmanager 0.9.0+3 二次 init 行为不确定）
        onRetry: () {
          setState(() {
            _initError = null;
            _initStackTrace = null;
            _phase = StartupPhase.splash;
            _version = '';
          });
          _runStartup();
        },
      );
    }
    return switch (_phase) {
      StartupPhase.splash => SplashScreen(version: _version),
      StartupPhase.app => widget.child,
    };
  }
}

// 注：StartupGate 设计为 public（class StartupGate，非 _StartupGate）——
// Task 8 的 main.dart 需要跨文件引用它。如果保留下划线前缀，
// Dart 编译器会判为 library-private 而 break build（参考 review #1）。
