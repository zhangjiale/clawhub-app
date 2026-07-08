import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/default_error_fallback.dart';

/// 可复用 fatal screen。
///
/// 既被 `main.dart` 的 `showFatal` runApp 路径使用（顶层 runApp，外层需要 MaterialApp），
/// 也被 `StartupGate` 的 inline 路径使用（runApp 之内，无外层 MaterialApp）。
///
/// 自带 `Material` + `Directionality` + `SafeArea` 兜底，让两边行为一致。
///
/// Retry 按钮 `_retrying` 守卫（board 修订）：慢设备上连点两次会让第二个
/// `main()` 在第一个 `ProviderScope` 半 teardown 时撞库（`main.dart:41-44`
/// 的 `onDispose` 只能兜一次）。
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
  bool _retrying = false;

  @override
  void didUpdateWidget(covariant FatalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // showFatal reuse path (ARB #4): on a persistent bootstrap failure
    // (e.g. the 2026-07-01 Workmanager PlatformException), `main.dart`'s
    // `showFatal` calls `runApp(MaterialApp(home: FatalScreen(e2)))` again.
    // The root element is reused (same runtimeType, no key) so Flutter
    // reconciles this State in place instead of recreating it - `_retrying`
    // would otherwise stay true from the first failed retry and lock the
    // user out of retrying the new failure until force-quit. A fresh throw
    // always produces a new StackTrace instance, so identity on [stackTrace]
    // is the reliable signal that a new failure replaced the old one.
    // Value-based `!=` on [error] fails for String-typed or value-equatable
    // errors thrown twice. The double-tap protection within one error display
    // is preserved: `_retrying` stays true between the first tap and the
    // re-render with a new failure.
    if (!identical(oldWidget.stackTrace, widget.stackTrace)) {
      _retrying = false;
    }
  }

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
            // 保留按钮在树里（`DefaultErrorFallback` 在 `onRetry == null`
            // 时会整棵移除 FilledButton，与本测试的
            // `find.text('重试', warnIfMissed: false)` 语义不符——后者
            // 对应 Flutter SDK「按钮仍在树里但忽略点击」的语义）。
            // 改用 closure 内部 gate：第一次点击 setState + 触发回调，
            // 后续点击命中 `if (_retrying) return;` 直接吞掉。
            onRetry: () {
              if (_retrying) return;
              setState(() => _retrying = true);
              widget.onRetry();
            },
          ),
        ),
      ),
    );
  }
}
