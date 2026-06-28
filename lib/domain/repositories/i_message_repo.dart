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

  /// 批量更新多条消息的状态。
  ///
  /// 跳过不存在的 clientId 以及状态机不允许的转换，返回实际被更新的消息列表。
  /// 空列表时直接返回空列表，不查询数据库（Law 6 批量入口）。
  Future<List<Message>> updateStatuses(
    List<String> clientIds,
    MessageStatus status,
  );

  /// 绑定 serverId（SENDING -> SENT）
  Future<Message> bindServerId(String clientId, String serverId);

  /// 获取待发送队列（PENDING 和 FAILED 状态的消息）
  Future<List<Message>> getOutbox(String agentId);

  /// 获取指定实例的待发送队列（PENDING 和 FAILED 状态的消息）
  /// 按 logicalClock 升序排列，保证按发送顺序重发
  Future<List<Message>> getOutboxByInstance(String instanceId);

  /// 获取指定实例的待发送消息数量（用于 UI 警告提示）
  Future<int> getOutboxCountByInstance(String instanceId);

  /// 监听指定实例的待发送消息数量变化（SSOT 驱动 OutboxWarningBanner）。
  ///
  /// 任何影响 outbox 计数的写入（insert/updateStatus/bindServerId/
  /// tryTransitionToSending/resetStaleSending）都应触发新值发射；
  /// 首次订阅时发射当前值。返回 int stream，开销低（单值，非列表查询）。
  ///
  /// 取代 ChatViewModel 里散落在 init/send/connection/retry 多处的
  /// 显式 `getOutboxCountByInstance` 轮询 —— 让 DB 写入自动驱动 UI 计数。
  Stream<int> watchOutboxCount(String instanceId);

  /// CAS 条件更新: 仅当消息当前状态为 [expectedStatus] 时才过渡到 SENDING。
  /// 返回 true 表示更新成功，false 表示状态已变化（被其他路径处理）。
  /// 防止 SendMessageUseCase 和 OutboxProcessor 并发操作同一条消息。
  Future<bool> tryTransitionToSending(
    String clientId,
    MessageStatus expectedStatus,
  );

  /// 崩溃恢复: 将指定实例中所有 SENDING 状态的消息重置为 PENDING。
  /// 不经过 FSM 校验 — 这是崩溃恢复而非正常业务流转。
  ///
  /// **⚠️ 仅供 [OutboxProcessor] 崩溃恢复调用，绕过领域状态机（[Message.transitionTo]）。
  /// 业务路径不得调用 —— 正常状态流转必须经 FSM 校验，否则会破坏 7-state 生命周期不变量。**
  ///
  /// 仅影响 [instanceId] 对应的消息（通过 conversations JOIN 过滤），
  /// 防止跨实例竞态：实例 B 启动冲刷时不应重置实例 A 正在发送的消息。
  ///
  /// **serverId 守卫**: 已绑定 `serverId` 的 SENDING 消息（已被 Gateway ACK，
  /// 但状态机未推进到 SENT，App 即被 kill）**不会被重置**。否则下一轮 flush
  /// 会重发已被服务端确认的消息，造成服务端重复。
  ///
  /// 应在 App 启动时、OutboxProcessor flush 前调用。
  Future<int> resetStaleSending(String instanceId);

  /// 全文搜索（基于 FTS5）
  Future<List<Message>> search(String query, {int limit = 20, int offset = 0});

  /// 为指定 Agent 清理超过 1000 条的旧消息
  Future<int> cleanupOldMessages(String agentId, {int keep = 1000});

  /// 获取单个 Agent 消息总数（用于统计）
  Future<int> getMessageCount(String agentId);

  /// 批量获取多个 Agent 的消息总数（替代 N+1 查询）
  /// 返回 `Map<String, int>`（`agentId` → count），未出现在结果中的 `agentId` 表示消息数为 0
  Future<Map<String, int>> getMessageCountsByAgent(List<String> agentIds);

  /// 删除消息（仅本地）
  Future<void> deleteByClientId(String clientId);

  /// US-020 AC-3：清空指定 Agent 的对话内容与全部派生缓存。
  ///
  /// 删除范围：messages（+ tool_calls 经 FK CASCADE）、
  /// achievement_unlocks、pending_notifications、FTS5 索引。
  /// 保留：agents / conversations 骨架（避免破坏进行中流式会话的 FK 约束，
  /// 与 [clearAllContent] 一致的取舍）。
  ///
  /// 实现必须在单一事务内执行，要么全部成功要么全部回滚。
  Future<void> clearAgentContent(String agentId);

  /// 清理指定会话中历史遗留的重复消息行（Bug #2 补强）。
  ///
  /// 旧 [batchInsertByIndexedIds]（仅身份去重）在每次重启重连时把已发的
  /// user 消息 / agent 回复再插一行，DB 累积重复。本方法清理这些已存在的
  /// 重复：按 (role, content, ±60s 时间窗, type=text 且内容非空) 聚簇，每簇
  /// 保留一行（优先有 `serverId` 的；其次最早的），删除其余并同步 FTS5。
  ///
  /// - 不合并 >60s 间隔的相同内容（视为不同消息）。
  /// - 不合并不同 role 的相同内容。
  /// - 不处理 `type != text` 或空内容的消息（工具调用等无法安全按内容去重）。
  ///
  /// 返回删除的行数。无重复时返回 0（no-op，幂等）。
  Future<int> dedupeConversation(String conversationId);

  /// 批量插入消息，同时按 clientId 和 serverId 去重（US-016 AC-2）。
  ///
  /// 跳过已有 clientId 或 serverId 的消息。在单次事务中执行 INSERT + FTS5 同步。
  /// 调用方负责在调用前将所有消息的 [Message.conversationId] 规整化为规范值。
  ///
  /// 返回实际插入的消息列表。
  Future<List<Message>> batchInsertByIndexedIds(List<Message> messages);
}
