import '../../domain/models/enums.dart';
import '../../domain/models/message.dart';

/// Gateway `chat.send` 出站消息负载构造器。
///
/// 职责：把领域 [Message] 转换为 Gateway `chat.send` 所需的 `message` 字符串
/// 与可选的 `attachments` 数组。不包含任何文件 I/O —— 附件 base64 由调用方
/// 通过 [AttachmentEncoder] 提供。
class OutboundMessageSerializer {
  const OutboundMessageSerializer();

  /// PROTOCOL-VERIFY (appendix F, 2026-07-03): chat.send 的 `message` 必须是字符串,
  /// 多模态走顶层 `attachments` 数组。Gateway 拒绝 content-blocks 形态的 `message`
  /// (实测 "at /message: must be string")与顶层 `metadata`("unexpected property")。
  ///
  /// 返回 record:`(message, attachments?)`。
  /// - text/toolCall → message=content, attachments=null
  /// - image → message=caption(可空), attachments=[{mimeType, content: base64, filename?}]
  ///   无 base64(读文件失败)→ 降级 message="[图片]", attachments=null
  /// - file → message=""(空), attachments=[{mimeType, content: base64, filename?}]
  ///   无 base64 → 降级 message="[文件] name", attachments=null
  ///
  /// ⚠️ attachment 元素字段名 `mimeType` vs `mime` 有歧义(appendix F.2 两处来源不一),
  /// 当前用 `mimeType`(testing-live.md 示例)。生产前需 capture 确认 —— 只改本方法。
  ({String message, List<Map<String, dynamic>>? attachments}) serialize(
    Message message, {
    String? base64Data,
  }) {
    switch (message.type) {
      case MessageType.text:
      case MessageType.toolCall:
        return (message: message.content ?? '', attachments: null);
      case MessageType.image:
        final caption = message.caption ?? '';
        if (base64Data == null) {
          return (
            message: caption.isNotEmpty ? caption : '[图片]',
            attachments: null,
          );
        }
        return (
          message: caption,
          attachments: [_buildAttachment(message, base64Data)],
        );
      case MessageType.file:
        if (base64Data == null) {
          return (
            message: '[文件] ${message.fileName ?? '文件'}',
            attachments: null,
          );
        }
        return (
          message: '',
          attachments: [_buildAttachment(message, base64Data)],
        );
    }
  }

  /// 构造单个 attachment 元素:{mimeType, content: base64, filename?}。
  Map<String, dynamic> _buildAttachment(Message message, String base64Data) {
    final att = <String, dynamic>{
      'mimeType':
          message.mimeType ??
          (message.isImage ? 'image/jpeg' : 'application/octet-stream'),
      'content': base64Data,
    };
    if (message.fileName != null) att['filename'] = message.fileName;
    return att;
  }
}
