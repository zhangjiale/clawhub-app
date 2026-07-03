import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// 附件类型(用户在 "+" 菜单里选的来源)。
///
/// widget 只负责把这个选择回调出去(Law 2:不调平台 API);实际 image_picker /
/// file_picker 调用由 ChatRoomPage 处理。
enum AttachmentKind { gallery, camera, file }

/// 附件选择底部 sheet —— 纯 UI,三个选项:相册 / 拍照 / 文件。
///
/// 反转 V2 component-spec §4.5.1("移除 Plus Button 简化输入栏")的决策:
/// PRD 3.3 规则 2/8 要求图片/文件消息能力,"+" 入口是必要的。spec 的"简化"
/// 在 V1.x 文本-only 阶段成立,进入图片/文件消息阶段后需恢复。
class AttachmentSheet extends StatelessWidget {
  final ValueChanged<AttachmentKind> onPick;

  const AttachmentSheet({super.key, required this.onPick});

  /// 便捷入口:以 modal bottom sheet 形式弹出。
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<AttachmentKind> onPick,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: XiaColors.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(XiaRadius.xl)),
      ),
      builder: (_) => AttachmentSheet(onPick: onPick),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Option(
            icon: Icons.photo_outlined,
            label: '相册',
            onTap: () => _select(context, AttachmentKind.gallery),
          ),
          _Option(
            icon: Icons.camera_alt_outlined,
            label: '拍照',
            onTap: () => _select(context, AttachmentKind.camera),
          ),
          _Option(
            icon: Icons.insert_drive_file_outlined,
            label: '文件',
            onTap: () => _select(context, AttachmentKind.file),
          ),
          const SizedBox(height: XiaSpacing.s2),
        ],
      ),
    );
  }

  void _select(BuildContext context, AttachmentKind kind) {
    Navigator.of(context).pop();
    onPick(kind);
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Option({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: XiaColors.accent),
      title: Text(
        label,
        style: const TextStyle(color: XiaColors.text1, fontSize: 15),
      ),
      onTap: onTap,
    );
  }
}
