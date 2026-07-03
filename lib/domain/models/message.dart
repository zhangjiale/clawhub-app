import 'message_status.dart';
import 'enums.dart';

/// 消息实体
/// 对齐: 架构 vFinal 5.3 (7状态消息生命周期), 5.12 (大文件分片)
///
/// 双 ID 机制:
/// - clientId: 本地 UUID，用于发送和去重兜底
/// - serverId: Gateway 返回 ID，用于全局去重
/// - 逻辑时钟 (logicalClock) 解决同毫秒消息排序
class Message {
  final String clientId; // 本地 UUID (发送与去重兜底)
  final String? serverId; // Gateway 返回 ID (全局去重)
  final String conversationId; // 关联 conversations.id
  final String agentId; // 冗余: 用于统计和清理
  final MessageRole role; // 角色枚举
  final String? content; // 文本内容或文件路径
  final MessageType type; // 消息类型枚举
  final MessageStatus status; // 7状态生命周期枚举
  final int logicalClock; // 逻辑时钟
  final int timestamp; // 消息时间(毫秒)
  final Map<String, dynamic>? metadata; // 扩展元数据

  Message({
    required this.clientId,
    this.serverId,
    required this.conversationId,
    required this.agentId,
    required this.role,
    this.content,
    required this.type,
    this.status = MessageStatus.pending,
    required this.logicalClock,
    int? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  /// 绑定 Gateway 返回的 serverId，同时状态从 SENDING -> SENT
  Message bindServerId(String id) {
    if (status != MessageStatus.sending) {
      throw StateError('只能在 SENDING 状态下绑定 serverId，当前状态: $status');
    }
    return copyWith(serverId: id, status: MessageStatus.sent);
  }

  /// 状态流转（遵循状态机规则）
  Message transitionTo(MessageStatus target) {
    if (!status.canTransitionTo(target)) {
      throw StateError('无效的状态转换: $status -> $target');
    }
    return copyWith(status: target);
  }

  /// 身份判断：同 clientId 或同 serverId（且非 null）均视为相同消息
  bool hasSameIdentity(Message other) {
    if (clientId == other.clientId) return true;
    if (serverId != null &&
        other.serverId != null &&
        serverId == other.serverId) {
      return true;
    }
    return false;
  }

  /// 是否为发送失败可重试状态
  bool get isRetryable => status.isRetryable;

  // --- 图片/文件消息便捷 getter（US-007 扩展：图片/文件消息）---
  //
  // 存储约定（无 schema 迁移，复用 content + metadata）：
  // - 用户发图: type=image, content=本地文件路径,
  //   metadata={fileName, mimeType, size, caption?}
  // - 用户发文件: type=file, content=本地文件路径,
  //   metadata={fileName, mimeType, size}
  // - Agent 回图(响应侧): type=image, content=null/caption,
  //   metadata={imageUrl, mimeType}
  //
  // 这些 getter 仅做类型判断 + metadata 读取，不含业务逻辑。

  bool get isImage => type == MessageType.image;
  bool get isFile => type == MessageType.file;

  /// 用户发送图片/文件的本地路径。
  /// 仅 image/file 类型、**无** imageUrl(即用户本地附件,非 Agent 回图)、
  /// 且 content 非空时返回。Agent 回图(imageUrl 非空)或空 content 返回 null。
  String? get imagePath =>
      isImage && imageUrl == null && content != null && content!.isNotEmpty
      ? content
      : null;
  String? get filePath =>
      isFile && content != null && content!.isNotEmpty ? content : null;

  /// 附件文件名 / MIME 类型 / 字节数 / 图片说明（均从 metadata 读取）。
  String? get fileName => metadata?['fileName'] as String?;
  String? get mimeType => metadata?['mimeType'] as String?;
  int? get fileSize => metadata?['size'] as int?;
  String? get caption => metadata?['caption'] as String?;

  /// Agent 回图的图片 URL（data: URL 或 https URL，响应侧）。
  String? get imageUrl => metadata?['imageUrl'] as String?;

  Message copyWith({
    String? clientId,
    String? serverId,
    String? conversationId,
    String? agentId,
    MessageRole? role,
    String? content,
    MessageType? type,
    MessageStatus? status,
    int? logicalClock,
    int? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return Message(
      clientId: clientId ?? this.clientId,
      serverId: serverId ?? this.serverId,
      conversationId: conversationId ?? this.conversationId,
      agentId: agentId ?? this.agentId,
      role: role ?? this.role,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      logicalClock: logicalClock ?? this.logicalClock,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() =>
      'Message(clientId: $clientId, serverId: $serverId, status: $status, type: $type)';
}
