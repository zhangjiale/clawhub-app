import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// A slim, full-width status banner for one-line messages with an icon.
///
/// Three concrete usages in the app:
/// - [ConnectionBanner] — connection-state alerts (disconnected / connecting)
/// - Agent-list stale-data warning (cloud-off icon, yellow tint)
///
/// Any page needing a one-line status bar with an icon should reuse this
/// component rather than inlining its layout.
class StatusBanner extends StatelessWidget {
  final String message;
  final Color foregroundColor;
  final Color backgroundColor;
  final IconData icon;

  /// 可选点击回调。非 null 时整个 banner 可点击（包一层 [GestureDetector]）。
  ///
  /// 用于可交互状态横幅，如重连耗尽时的"点击重试"。null 时退化为纯展示横幅，
  /// 保持与历史调用方（`const StatusBanner(...)`）的兼容。
  final VoidCallback? onTap;

  const StatusBanner({
    super.key,
    required this.message,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final banner = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.pagePaddingH,
        vertical: XiaSpacing.s2,
      ),
      color: backgroundColor,
      child: Row(
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: XiaSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(
                color: foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
    // 仅在提供回调时才包手势层 —— 避免 const 横幅引入不必要的 widget 树层级。
    final callback = onTap;
    if (callback == null) return banner;
    return GestureDetector(onTap: callback, child: banner);
  }
}
