import 'package:flutter/material.dart';

/// 错误边界组件
/// 对齐: 架构 vFinal 5.5 (OOM 熔断), 11 (Markdown 渲染陷阱)
///
/// 全局错误 UI 由 `bootstrap.dart` 中的 `ErrorWidget.builder` 统一设置，
/// 实际渲染由 `DefaultErrorFallback`（见 `default_error_fallback.dart`）
/// 承担。`ErrorBoundary` 作为声明式占位符嵌入组件树，自身不操作全局状态
/// (避免多实例场景下的 builder 冲突)。
///
/// 如需差异化降级 UI，请在子组件树中自行 catch 错误并渲染备用组件。
class ErrorBoundary extends StatelessWidget {
  final Widget child;

  const ErrorBoundary({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
