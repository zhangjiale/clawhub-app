import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/status_banner.dart';

/// 离线消息队列警告横幅（US-015 AC3）。
///
/// 当指定实例的待发送消息数量 ≥20 时显示，提示用户检查网络连接。
/// 否则收起为零高度。
///
/// 样式：黄色警告色（[XiaColors.yellow] / [XiaColors.yellowMuted]），
/// 与 [ConnectionBanner] 的"网络异常"分支一致。
class OutboxWarningBanner extends StatelessWidget {
  final int outboxCount;

  /// US-015 AC3 阈值：≥20 条触发警告。
  static const int warningThreshold = 20;

  const OutboxWarningBanner({super.key, required this.outboxCount});

  @override
  Widget build(BuildContext context) {
    if (outboxCount < warningThreshold) {
      return const SizedBox.shrink();
    }
    return StatusBanner(
      message: '有$outboxCount条消息等待发送，请检查网络连接',
      foregroundColor: XiaColors.yellow,
      backgroundColor: XiaColors.yellowMuted,
      icon: Icons.warning_amber,
    );
  }
}
