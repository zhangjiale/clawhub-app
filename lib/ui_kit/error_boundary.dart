import 'package:flutter/material.dart';

/// 错误边界组件（当前为 no-op 透传）。
/// 对齐: 架构 vFinal 5.5 (OOM 熔断), 11 (Markdown 渲染陷阱)
///
/// ⚠️ 死代码提示（2026-07-01 审计）：本组件当前实现为 `return child` 纯透传，
/// 生产 widget 树中**零引用**（仅本文件及自身测试引用）。全局错误 UI 由
/// `bootstrap.dart` 中的 `ErrorWidget.builder` 统一设置，实际渲染由
/// `DefaultErrorFallback` 承担，本组件不参与。
///
/// 保留为可选的声明式 seam：若未来需要在子树边界挂差异化降级 UI，可在此
/// 扩展。在此之前，新代码不应使用本组件 —— 直接渲染子组件即可。
@Deprecated(
  'No-op passthrough with zero production usages. Global error UI '
  'is set via ErrorWidget.builder in bootstrap.dart. Do not add new '
  'usages; render children directly.',
)
class ErrorBoundary extends StatelessWidget {
  final Widget child;

  const ErrorBoundary({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
