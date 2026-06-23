import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 成长面板空状态卡片 (US-019 AC-3)。
///
/// 当虾详情页的 `messageCount == 0` 时取代 StatsGrid / Timeline，
/// 引导用户去对话。
///
/// 设计取舍：选用 ListView 之外的居中 Column 而非占位卡片——空状态
/// 是"主动引导"语义，应占据视觉中心，而非降级到一行 `--`。
///
/// 与父页面解耦：按钮通过 [onStartChat] 回调触发，不直接 import 路由 /
/// Riverpod。便于 widget 测试断言"按钮点击触发了回调"而无需搭建
/// Provider / Router 环境。
class EmptyGrowthView extends StatelessWidget {
  /// 点击「去对话」按钮时调用。通常由父页面 `Navigator.push` 到对应 chat
  /// 路由。null 时按钮仍可见但不响应点击（用于演示 / 测试）。
  final VoidCallback? onStartChat;

  const EmptyGrowthView({super.key, this.onStartChat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.pagePaddingH,
          vertical: XiaSpacing.s8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🦐', style: TextStyle(fontSize: 64)),
            const SizedBox(height: XiaSpacing.s5),
            Text(
              '刚开始养虾',
              style: theme.textTheme.titleMedium?.copyWith(
                color: XiaColors.text1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: XiaSpacing.s2),
            Text(
              '快去对话吧！',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: XiaColors.text3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: XiaSpacing.s7),
            // PrimaryButton 内部宽度为 double.infinity；通过外层 SizedBox
            // 约束最大宽度，避免在大屏上拉得过宽，同时让按钮在 Column 内
            // 不至于把整个面板撑满。
            SizedBox(
              width: 200,
              child: PrimaryButton(label: '💬 去对话', onPressed: onStartChat),
            ),
          ],
        ),
      ),
    );
  }
}
