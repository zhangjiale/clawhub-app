import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Message status icon — shows delivery/failure state.
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
        return Icon(Icons.edit, size: size, color: XiaColors.text3);
      case MessageStatus.pending:
        return Icon(Icons.access_time, size: size, color: XiaColors.text3);
      case MessageStatus.sending:
        return SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(XiaColors.text3),
          ),
        );
      case MessageStatus.sent:
        return Icon(Icons.check, size: size, color: XiaColors.text3);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: size, color: XiaColors.accent);
      case MessageStatus.failed:
        return Icon(Icons.error, size: size, color: XiaColors.red);
      case MessageStatus.expired:
        return Icon(Icons.schedule, size: size, color: XiaColors.text3);
    }
  }
}
