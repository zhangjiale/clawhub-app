import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/message_status.dart';

/// 消息状态图标组件
/// 对齐: 架构 vFinal 5.3 (消息生命周期), UI 渲染对照表
///
/// | 状态 | 图标 |
/// |:---|:---|
/// | DRAFT | 编辑图标 (灰色) |
/// | PENDING | 时钟图标 (灰色) |
/// | SENDING | 加载转圈 |
/// | SENT | 单勾 ✓ |
/// | DELIVERED | 双勾 ✓✓ |
/// | FAILED | 红色叹号 |
/// | EXPIRED | 灰色过期标记 |
class StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final double size;

  const StatusIcon({
    super.key,
    required this.status,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.draft:
        return Icon(Icons.edit, size: size, color: Colors.grey);
      case MessageStatus.pending:
        return Icon(Icons.access_time, size: size, color: Colors.grey);
      case MessageStatus.sending:
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.grey),
          ),
        );
      case MessageStatus.sent:
        return Icon(Icons.check, size: size, color: Colors.grey);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: size, color: const Color(0xFF007AFF));
      case MessageStatus.failed:
        return Icon(Icons.error, size: size, color: Colors.red);
      case MessageStatus.expired:
        return Icon(Icons.schedule, size: size, color: Colors.grey);
    }
  }
}
