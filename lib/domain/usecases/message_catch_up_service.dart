import '../../core/acl/i_gateway_client.dart';
import '../../core/i_logger.dart';
import '../models/conversation.dart';
import '../repositories/i_agent_repo.dart';
import '../repositories/i_conversation_repo.dart';
import '../repositories/i_message_repo.dart';

/// 消息增量同步服务 — 断线重连后拉取 Gateway 新消息（US-016 AC-1/AC-2）。
///
/// 在 [InstanceConnectedEvent] 后、[OutboxProcessor.flushOutbox] 前调用。
/// 先确保本地消息库拥有完整的会话上下文。
///
/// 流程（每 Agent）：
/// 1. 确保 conversation 行存在（FK 约束）
/// 2. 逐页调用 [IGatewayClient.fetchMessageHistory]（newest-first）
/// 3. 规整化每条消息的 conversationId
/// 4. 通过 [IMessageRepo.batchInsertByIndexedIds] 双 ID 去重插入
/// 5. 当某页出现已知消息时停止（已追平）
/// 6. 每 Agent 最多扫描 [_maxPagesPerConversation] 页
class MessageCatchUpService {
  final IAgentRepo _agentRepo;
  final IMessageRepo _messageRepo;
  final IConversationRepo _conversationRepo;
  final IGatewayClient _gatewayClient;
  final ILogger _logger;

  /// Per-instance 防重入锁
  final Set<String> _catchingUp =
      {}; // iron-law-allow: Law8 — empty Set literal, not catch block

  /// 每 Agent 最大翻页数（防止断线数天时无限制翻页）。
  ///
  /// 撞顶时本次同步被截断——更早的历史未拉取，调用方应通过
  /// [CatchUpResult.truncated] 通知 UI 展示"同步不完整"提示。
  /// 可注入小值用于测试，避免在单测里跑满 20 页。
  final int _maxPagesPerConversation;

  /// 每页拉取条数
  static const _pageSize = 50;

  /// 生产默认翻页上限。
  static const defaultMaxPagesPerConversation = 20;

  MessageCatchUpService({
    required IAgentRepo agentRepo,
    required IMessageRepo messageRepo,
    required IConversationRepo conversationRepo,
    required IGatewayClient gatewayClient,
    required ILogger logger,
    int? maxPagesPerConversation,
  }) : _agentRepo = agentRepo,
       _messageRepo = messageRepo,
       _conversationRepo = conversationRepo,
       _gatewayClient = gatewayClient,
       _logger = logger,
       _maxPagesPerConversation =
           maxPagesPerConversation ?? defaultMaxPagesPerConversation;

  /// 执行增量同步。
  ///
  /// 返回 [CatchUpResult]：插入的新消息总数 + 是否因翻页上限被截断。
  /// 0 插入表示无需同步或全部已存在；[CatchUpResult.truncated] 为 true
  /// 表示还有更早的历史未拉取（撞顶），UI 应提示用户。
  ///
  /// 防重入：同一实例不可并发调用。
  /// 错误隔离：单个 Agent 失败不影响其他 Agent 的同步。
  Future<CatchUpResult> catchUp(String instanceId) async {
    if (!_catchingUp.add(instanceId)) {
      _logger.info('[MessageCatchUp] Already catching up $instanceId');
      return const CatchUpResult(inserted: 0, truncated: false);
    }

    try {
      // 1. 获取该实例下所有 Agent
      final agents = await _agentRepo.getByInstanceId(instanceId);
      if (agents.isEmpty) {
        _logger.info('[MessageCatchUp] No agents found for $instanceId');
        return const CatchUpResult(inserted: 0, truncated: false);
      }

      var totalInserted = 0;
      var anyTruncated = false;

      // 2. 逐 Agent 翻页拉取（错误隔离：单个 Agent 失败不中断其余）
      for (final agent in agents) {
        try {
          final convId = Conversation.generateId(instanceId, agent.localId);
          final agentResult = await _catchUpForAgent(
            instanceId: instanceId,
            agentLocalId: agent.localId,
            agentRemoteId: agent.remoteId,
            conversationId: convId,
          );
          totalInserted += agentResult.inserted;
          anyTruncated = anyTruncated || agentResult.truncated;
        } catch (e, st) {
          _logger.error(
            '[MessageCatchUp] Failed to catch up agent ${agent.remoteId} '
            'for $instanceId: $e',
            st,
          );
          // Continue to next agent — per-agent error isolation
        }
      }

      _logger.info(
        '[MessageCatchUp] $instanceId: inserted $totalInserted messages '
        'across ${agents.length} agents'
        '${anyTruncated ? ' (TRUNCATED at page cap)' : ''}',
      );
      return CatchUpResult(inserted: totalInserted, truncated: anyTruncated);
    } finally {
      _catchingUp.remove(instanceId);
    }
  }

  /// 为单个 Agent 翻页拉取历史消息。
  ///
  /// 从最新消息开始向后翻页。当一页中至少有一条已知消息时，
  /// 意味着已经追平断开期间产生的消息，停止继续翻页。
  ///
  /// 在执行任何插入之前先确保 conversation 行存在（满足 FK 约束）。
  Future<CatchUpResult> _catchUpForAgent({
    required String instanceId,
    required String agentLocalId,
    required String agentRemoteId,
    required String conversationId,
  }) async {
    // Pre-create conversation row — satisfies FK constraint on messages table.
    // Without this, messages referencing a conversation that doesn't exist in
    // the local DB would fail the FOREIGN KEY check and be silently dropped.
    //
    // NOTE: agentId passed to getOrCreate MUST match the id used in
    // Conversation.generateId (i.e. the local ID), not the remote ID.
    // ChatViewModel._init uses the same local-ID convention.
    await _conversationRepo.getOrCreate(
      instanceId,
      agentLocalId, // local ID for local DB
    );

    String? cursor;
    var totalInserted = 0;
    var pageCount = 0;
    var truncated = false;

    do {
      try {
        final history = await _gatewayClient.fetchMessageHistory(
          instanceId: instanceId,
          agentId: agentRemoteId,
          cursor: cursor,
          limit: _pageSize,
        );

        if (history.messages.isEmpty) break;

        // Normalize conversationId on every message BEFORE batch insert.
        // WsGatewayClient._parseMessage sets conversationId from the Gateway
        // response, which may be empty — that would fail the FK constraint
        // (messages.conversation_id REFERENCES conversations.id).
        final normalized = history.messages
            .map((msg) => msg.copyWith(conversationId: conversationId))
            .toList();

        final inserted = await _messageRepo.batchInsertByIndexedIds(normalized);
        totalInserted += inserted.length;

        // AC-2 dedup check: if any messages on this page already existed,
        // we've found the boundary of known messages. Since chat.history
        // returns newest-first, all subsequent pages are older → all known.
        if (inserted.length < normalized.length) {
          _logger.info(
            '[MessageCatchUp] Caught up for agent $agentRemoteId '
            '(found ${normalized.length - inserted.length} already-known '
            'messages on page $pageCount)',
          );
          break;
        }

        cursor = history.nextCursor;
        pageCount++;

        // 撞顶：还有下一页（cursor != null）但已达翻页上限。
        // 必须在 cursor 赋值之后判断 —— 启发式命中 / 错误 break 在
        // cursor 赋值之前退出，truncated 保持 false，不会误判。
        if (cursor != null && pageCount >= _maxPagesPerConversation) {
          truncated = true;
          _logger.info(
            '[MessageCatchUp] Truncated for agent $agentRemoteId at '
            '$_maxPagesPerConversation pages — older history not fetched',
          );
          break;
        }
      } catch (e, st) {
        _logger.error(
          '[MessageCatchUp] Failed to fetch history for agent '
          '$agentRemoteId (page $pageCount): $e',
          st,
        );
        break; // Network error during catch-up — stop and try next time
      }
    } while (cursor != null && pageCount < _maxPagesPerConversation);

    return CatchUpResult(inserted: totalInserted, truncated: truncated);
  }
}

/// 增量同步结果。
///
/// [truncated] 为 true 表示因翻页上限（每 Agent 最多
/// [MessageCatchUpService.defaultMaxPagesPerConversation] 页）被截断，
/// 更早的历史未拉取——UI 层应据此展示"同步不完整"提示，避免用户误以为
/// 历史已完整而实际存在缺口。
class CatchUpResult {
  final int inserted;
  final bool truncated;

  const CatchUpResult({required this.inserted, required this.truncated});
}
