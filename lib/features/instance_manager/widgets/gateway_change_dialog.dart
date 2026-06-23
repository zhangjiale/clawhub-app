import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/usecases/gateway_change_resolution.dart';

/// 编辑实例时检测到 Gateway host 变化，询问用户如何处理本地 agents。
///
/// 返回值：
/// - `null` —— 用户取消保存
/// - [GatewayChangeResolution.keepLocal] —— 保留旧数据，与新 Gateway 合并
/// - [GatewayChangeResolution.purgeLocal] —— 清除本实例下所有 agents 及历史会话
class GatewayChangeDialog extends StatelessWidget {
  /// 本实例下当前本地 agents 的数量（用于文案）。
  final int localAgentCount;

  const GatewayChangeDialog._({required this.localAgentCount});

  /// 展示 dialog。`barrierDismissible: false` 避免误点关闭丢失关键决策。
  static Future<GatewayChangeResolution?> show(
    BuildContext context, {
    required int localAgentCount,
  }) {
    return showDialog<GatewayChangeResolution>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GatewayChangeDialog._(localAgentCount: localAgentCount),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gateway 地址已变更'),
      content: Text(
        '检测到你修改了 Gateway 地址。\n\n'
        '如果切换到不同的 Gateway，本地的 $localAgentCount 个 Agent '
        '可能在新 Gateway 上不存在。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(GatewayChangeResolution.keepLocal),
          child: const Text('保留旧数据'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: XiaColors.red),
          onPressed: () =>
              Navigator.of(context).pop(GatewayChangeResolution.purgeLocal),
          child: const Text('清除并切换'),
        ),
      ],
    );
  }
}
