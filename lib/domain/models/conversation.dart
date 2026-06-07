import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 会话聚合根
/// 对齐: 架构 vFinal 4.0 (Conversation 聚合根), 5.2 (预览生成引擎)
///
/// id 生成规则: hash(instanceId + agentId)，确保全局唯一
class Conversation {
  final String id; // 复合键: hash(instanceId + agentId)
  final String agentId; // 关联 agents.localId
  final String instanceId; // 冗余: 用于路由和统计
  final String? lastMessageId; // 关联 messages.clientId
  final String? lastMessagePreview; // 预览引擎生成的40字预览
  final int lastMessageTime; // 用于消息页时间降序排列(毫秒)
  final int unreadCount; // 未读角标
  final bool isMuted; // 是否免打扰

  Conversation({
    String? id,
    required this.agentId,
    required this.instanceId,
    this.lastMessageId,
    this.lastMessagePreview,
    this.lastMessageTime = 0,
    this.unreadCount = 0,
    this.isMuted = false,
  }) : id = id ?? generateId(instanceId, agentId);

  /// 生成复合键 ID
  static String generateId(String instanceId, String agentId) {
    final bytes = utf8.encode('$instanceId:$agentId');
    return sha256.convert(bytes).toString();
  }

  /// 增量未读数
  Conversation incrementUnread() {
    return copyWith(unreadCount: unreadCount + 1);
  }

  /// 清零未读数
  Conversation clearUnread() {
    return copyWith(unreadCount: 0);
  }

  /// 更新最后消息信息
  Conversation updateLastMessage({
    required String messageId,
    required String preview,
    required int timestamp,
  }) {
    return copyWith(
      lastMessageId: messageId,
      lastMessagePreview: preview,
      lastMessageTime: timestamp,
    );
  }

  Conversation copyWith({
    String? id,
    String? agentId,
    String? instanceId,
    String? lastMessageId,
    String? lastMessagePreview,
    int? lastMessageTime,
    int? unreadCount,
    bool? isMuted,
  }) {
    return Conversation(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      instanceId: instanceId ?? this.instanceId,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Conversation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Conversation(id: $id, agentId: $agentId, unread: $unreadCount)';
}
