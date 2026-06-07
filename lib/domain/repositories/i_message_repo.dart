import '../models/message.dart';
import '../models/message_status.dart';

/// 消息仓库接口
/// 对齐: 架构 vFinal 5.3 (消息生命周期), 5.4 (全局搜索), 5.12 (大文件分片)
abstract class IMessageRepo {
  /// 插入新消息（应用层需同时同步 messages_fts）
  Future<Message> insert(Message message);

  /// 根据 clientId 查找消息
  Future<Message?> getByClientId(String clientId);

  /// 根据 serverId 查找消息
  Future<Message?> getByServerId(String serverId);

  /// 获取指定会话的消息列表（按逻辑时钟排序）
  /// [before] 游标：加载此消息之前的消息
  /// [limit] 每页数量，默认 50
  Future<List<Message>> getByConversation(
    String conversationId, {
    String? before,
    int limit = 50,
  });

  /// 锚点窗口查询（以 target 为中心，向上取 before 条，向下取 after 条）
  Future<List<Message>> getAnchorWindow(
    String conversationId, {
    required String targetClientId,
    int before = 5,
    int after = 10,
  });

  /// 更新消息状态
  Future<Message> updateStatus(String clientId, MessageStatus status);

  /// 绑定 serverId（SENDING -> SENT）
  Future<Message> bindServerId(String clientId, String serverId);

  /// 获取待发送队列（PENDING 和 FAILED 状态的消息）
  Future<List<Message>> getOutbox(String agentId);

  /// 全文搜索（基于 FTS5）
  Future<List<Message>> search(String query, {int limit = 20, int offset = 0});

  /// 为指定 Agent 清理超过 1000 条的旧消息
  Future<int> cleanupOldMessages(String agentId, {int keep = 1000});

  /// 获取 Agent 消息总数（用于统计）
  Future<int> getMessageCount(String agentId);

  /// 删除消息（仅本地）
  Future<void> deleteByClientId(String clientId);
}
