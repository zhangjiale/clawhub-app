import '../models/conversation.dart';
import '../models/enums.dart';

/// 会话仓库接口
/// 对齐: 架构 vFinal 5.2 (消息中心聚合与预览生成引擎)
abstract class IConversationRepo {
  /// 获取或创建会话（幂等操作）
  Future<Conversation> getOrCreate(String instanceId, String agentId);

  /// 获取所有有消息的会话（按最后消息时间降序）
  Future<List<Conversation>> getAllWithMessages();

  /// 根据 ID 获取会话
  Future<Conversation?> getById(String id);

  /// 更新最后消息预览（由 Repository 在事务中完成）
  Future<Conversation> updateLastMessage({
    required String conversationId,
    required String messageId,
    required String preview,
    required int timestamp,
    required MessageRole role,
  });

  /// 增量未读数
  Future<Conversation> incrementUnread(String conversationId, {int count = 1});

  /// 清零未读数
  Future<Conversation> clearUnread(String conversationId);

  /// 切换免打扰
  Future<Conversation> toggleMute(String conversationId);

  /// 删除实例下所有会话
  Future<void> deleteByInstanceId(String instanceId);
}
