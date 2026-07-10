import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/splash/min_display_timer.dart';
import 'package:claw_hub/ui_kit/fatal_screen.dart';

/// Native-only splash 占位背景色（与 Android values/colors.xml 的 splash_bg +
/// values-v31/styles.xml 的 windowSplashScreenBackground + iOS LaunchScreen +
/// pubspec.yaml flutter_native_splash.color 同色 #FDD3BC）。
///
/// Flutter 侧不再渲染 splash 插画，StartupGate 在 splash 阶段挂一个全屏
/// ColoredBox 保持背景色一致，避免 Flutter 接管首帧时背景跳变到 #08090D。
const Color _splashBgColor = Color(0xFFFDD3BC);

enum StartupPhase { splash, app }

/// 启动闸门：splash ↔ app 状态机（plan 2026-07-10 native-only）。
///
/// 在 runApp 之后、`MaterialApp.router` 之前挂载。
/// - splash 阶段：渲染纯色 #FDD3BC 占位 + native splash 由 FlutterNativeSplash
///   .preserve() 维持显示
/// - app 阶段：渲染 `child`（= `MaterialApp.router`），postFrameCallback 调
///   FlutterNativeSplash.remove() 让 native 退出
/// - 错误（board 修订 tier-gate）：
///   - Tier 1 (Notification fatal) → `FatalScreen` + 调 onReady 退出 native
///   - Tier 2 (Connection soft-fail) → app shell mount，写 connectionInitStateProvider
///
/// native-only 形态后 Flutter 侧不再渲染 splash 插画 / "虾Hub" / 版本号——
/// 这些视觉信息全部由 native 层（Android system splash + iOS LaunchScreen）
/// 提供。冷启动用户只看到 native 一层。
class StartupGate extends ConsumerStatefulWidget {
  const StartupGate({super.key, required this.child, required this.onAppReady});

  final Widget child;

  /// native splash 退出回调。生产由 `ClawHubApp.build` 注入
  /// `FlutterNativeSplash.remove()`（try/catch + logger 兜底）；测试注入
  /// no-op 计数器，避免 `MissingPluginException`。
  ///
  /// 在以下两种状态机终态触发：
  /// 1. splash → app 切换（init 成功 + 800ms MinDisplayTimer 到期）
  /// 2. _initError 写入（Tier 1 fatal，渲染 FatalScreen）
  ///
  /// 关键不变量：必须保证只触发一次（避免重复 remove() 行为未定义）。用
  /// [_StartupGateState._onReadyFired] 守卫。
  final VoidCallback onAppReady;

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<StartupGate> {
  StartupPhase _phase = StartupPhase.splash;
  Object? _initError;
  StackTrace? _initStackTrace;
  bool _onReadyFired = false;

  @override
  void initState() {
    super.initState();
    _runStartup();
  }

  Future<void> _runStartup() async {
    try {
      // 启动 init 任务 + 最短展示计时器
      await Future.wait<Object?>([
        _runInitialization(),
        MinDisplayTimer.wait(const Duration(milliseconds: 800)),
      ]);

      // 都满足 -> 切到 app 阶段
      if (!mounted) return;
      setState(() => _phase = StartupPhase.app);
      _fireOnReady();
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
      _fireOnReady();
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

  /// 调 onAppReady 一次（splash→app 切换成功 或 fatal 都触发）。
  ///
  /// postFrameCallback 包一层：让首帧（app child 或 FatalScreen）layout 完
  /// 再 remove native，避免「Flutter 黑屏 + native 消失」中间空窗。
  void _fireOnReady() {
    if (_onReadyFired) return;
    _onReadyFired = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onAppReady();
    });
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
            _onReadyFired = false;
          });
          _runStartup();
        },
      );
    }
    return switch (_phase) {
      StartupPhase.splash => ColoredBox(color: _splashBgColor),
      StartupPhase.app => widget.child,
    };
  }
}
