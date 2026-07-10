import '../../core/acl/i_gateway_client.dart';
import '../../core/i_api_logger.dart';
import '../../core/i_logger.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../repositories/i_agent_repo.dart';
import '../repositories/i_conversation_repo.dart';
import '../repositories/i_message_repo.dart';
import 'merge_inbound_message.dart';

// ignore_for_file: prefer_initializing_formals — `_apiLogger` library-private
// initializing formal blocked by `_` prefix (Dart 2.17+); explicit
// assignment keeps nullable param contract visible.

/// 消息增量同步服务 — 断线重连后拉取 Gateway 新消息（US-016 AC-1/AC-2）。
///
/// 在 [InstanceConnectedEvent] 后、[OutboxProcessor.flushOutbox] 前调用。
/// 先确保本地消息库拥有完整的会话上下文。
///
/// 流程（每 Agent）：
/// 1. 确保 conversation 行存在（FK 约束）
/// 2. 逐页调用 [IGatewayClient.fetchMessageHistory]（newest-first）
/// 3. 规整化每条消息的 conversationId
/// 4. 通过 [MergeInboundMessageUseCase.mergeWithStatus] 合并入库
///    （身份去重 + 内容/时间戳软匹配，与 ChatViewModel 历史路径共用同一去重）
/// 5. 当某页出现已知消息（wasNew=false）时停止（已追平）
/// 6. 每 Agent 最多扫描 [_maxPagesPerConversation] 页
///
/// **Bug #2 修复**：旧实现用 [IMessageRepo.batchInsertByIndexedIds]（仅按
/// clientId/serverId 身份去重）。但网关不给 user 消息回传 clientId、本地
/// serverId 是 runId/随机 UUID → 身份永远对不上 → 每次重启重连都把"已发的
/// user 消息"和"agent 回复"当成新消息再插一行 → 重复。改走 [mergeWithStatus]
/// 后，软匹配兜底去重，与 ChatViewModel 路径一致，重复根除。
class MessageCatchUpService {
  final IAgentRepo _agentRepo;
  final IMessageRepo _messageRepo;
  final IConversationRepo _conversationRepo;
  final IGatewayClient _gatewayClient;
  final ILogger _logger;

  /// 可选结构化诊断 logger —— 与 ChatViewModel 同模式。null 时所有埋点
  /// 走 no-op。生产代码在 providers.dart 注入 apiLoggerProvider。
  ///
  /// 背景:「重启 App 后历史变两份」类 bug 反复复发,catch-up 路径的 dedup
  /// 决策完全黑盒。本字段让 catch-up 路径上的 merge / dedupeConversation
  /// 决策有结构化日志,便于 DiagnosticsPage 5 分钟内定位 miss 的层级。
  /// 完整方案见 plan:
  /// `C:\Users\NING MEI\.claude\plans\enumerated-percolating-pascal.md`
  final IApiLogger? _apiLogger;

  /// 入站合并用例 —— 与 ChatViewModel 共用同一去重逻辑（身份 + 软匹配）。
  /// 在内部从 [_messageRepo] 构造，避免改动 DI 与所有构造点。
  /// `late` 不能省 —— Dart 不允许在非 late 的字段初始化器里访问 `this._messageRepo`。
  late final MergeInboundMessageUseCase _mergeUseCase =
      MergeInboundMessageUseCase(messageRepo: _messageRepo);

  /// Per-instance 防重入锁
  final Set<String> _catchingUp = {};

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
    required this._agentRepo,
    required this._messageRepo,
    required this._conversationRepo,
    required this._gatewayClient,
    required this._logger,
    IApiLogger? apiLogger,
    int? maxPagesPerConversation,
  }) : _apiLogger = apiLogger,
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

        // Normalize conversationId on every message BEFORE merge.
        // WsGatewayClient._parseMessage sets conversationId from the Gateway
        // response, which may be empty — that would fail the FK constraint
        // (messages.conversation_id REFERENCES conversations.id),且软匹配
        // 也需要 conversationId 来查近期消息。
        final normalized = history.messages
            .map((msg) => msg.copyWith(conversationId: conversationId))
            .toList();

        // 逐条合并入库（身份去重 + 内容/时间戳软匹配）。
        // 用 wasNew 区分真新插入 vs 命中已有行,驱动"已追平"停止判定。
        // 软匹配的"近期消息"在循环外预取一次（_mergeUseCase 内部不再
        // getByConversation）—— 历史 catch-up 一页 50 条,避免 50 次相同查询。
        final recent = await _messageRepo.getByConversation(
          conversationId,
          limit: 50,
        );
        var pageNew = 0;
        var pageKnown = 0;
        var pageSkipped = 0;
        for (final msg in normalized) {
          try {
            final result = await _mergeUseCase.mergeWithStatus(
              msg,
              softMatch: true,
              recent: recent,
            );
            // 结构化诊断:让 diagnostics page 看到「catch-up 路径上每条
            // 入站消息走了哪个 dedup 分支」。state 前缀约定 'merge:'
            // 与 ChatViewModel 一致,path=catchUp 便于区分来源。
            _logMergeDecision(result, msg, agentRemoteId);
            if (result.wasSkipped) {
              // 空内容 / 业务规则丢弃 —— 既非新插入也非命中已有行,不计入
              // pageKnown,避免误触发「已追平」停止条件。
              pageSkipped++;
            } else if (result.wasNew) {
              pageNew++;
            } else {
              pageKnown++;
            }
          } catch (e, st) {
            // 单条合并失败（FK/约束冲突等）不中断整页——与 ChatViewModel
            // 历史路径的 per-insert 兜底语义一致。
            _logger.error(
              '[MessageCatchUp] merge failed for ${msg.clientId}: $e',
              st,
            );
          }
        }
        totalInserted += pageNew;

        // AC-2 dedup check: if any messages on this page already existed
        // (pageKnown > 0), we've found the boundary of known messages.
        // Since chat.history returns newest-first, all subsequent pages are
        // older → all known.
        // 注意:pageSkipped 不计入 pageKnown —— 空内容 skip 与「命中已有行」
        // 语义不同,不能误触发 break。
        if (pageKnown > 0) {
          _logger.info(
            '[MessageCatchUp] Caught up for agent $agentRemoteId '
            '(found $pageKnown already-known messages on page $pageCount, '
            'inserted $pageNew new, skipped $pageSkipped empty)',
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

    // Bug #2 修复补强: 无论是否新插入了消息,都清理一次历史重复行。
    // 单靠 ChatViewModel 在打开聊天时调用,用户从未打开的会话里
    // 重复永远在;在 catch-up 路径上做一次,才能兑现 PR 的「重复根除」承诺。
    // dedupeConversation 是幂等的,无重复时为 no-op。
    try {
      final deleted = await _messageRepo.dedupeConversation(conversationId);
      if (deleted > 0) {
        _logger.info(
          '[MessageCatchUp] Cleaned $deleted legacy duplicate rows for '
          'agent $agentRemoteId conversation $conversationId',
        );
        // 结构化诊断:让 diagnostics 看到「这次 catch-up 在这条会话清理了
        // N 条重复」。state 前缀 'merge:' 与 merge 决策共用一套配色约定。
        _apiLogger?.logStateChange(
          instanceId: instanceId,
          state: 'merge:dedupeDeleted',
          message:
              'count=$deleted path=catchUp conv=$conversationId '
              'agent=$agentRemoteId',
        );
      }
    } catch (e, st) {
      // dedupeConversation 自身是事务 + 已建索引,失败概率极低;不影响
      // catch-up 主路径,仅记日志,下次 catch-up 或聊天打开时会重试。
      _logger.error(
        '[MessageCatchUp] dedupeConversation failed for agent '
        '$agentRemoteId conversation $conversationId: $e',
        st,
      );
    }

    return CatchUpResult(inserted: totalInserted, truncated: truncated);
  }

  /// 记录一次 catch-up dedup 决策到结构化诊断日志。
  ///
  /// 与 ChatViewModel._logMergeDecision 同套约定(state 前缀 `merge:`),
  /// 仅 [path] 不同(`catchUp`)。这是「重启 App 后历史变两份」诊断的主
  /// 数据源 —— 大量 `merge:inserted:new` 表示 catch-up 路径 Branch 4
  /// 命中,问题在前 3 层 dedup 全 miss。
  ///
  /// null logger 时静默返回 —— 现有 catch-up 测试构造点不传 apiLogger,
  /// 这里确保它们继续工作。
  void _logMergeDecision(
    MergeResult result,
    Message inbound,
    String agentRemoteId,
  ) {
    final apiLogger = _apiLogger;
    if (apiLogger == null) return;
    final m = result.message;
    final outcome = result.wasSkipped
        ? 'skipped:emptyContent'
        : (result.wasNew ? 'inserted:new' : 'hit:dedup');
    apiLogger.logStateChange(
      instanceId: inbound.agentId.isNotEmpty ? inbound.agentId : agentRemoteId,
      state: 'merge:$outcome',
      message:
          'path=catchUp '
          'clientId=${m.clientId} '
          'serverId=${m.serverId ?? "-"} '
          'role=${m.role.name} '
          'conv=${m.conversationId} '
          'agent=$agentRemoteId',
      // payloadPreview 让 diagnostics 页显示 ▼ 展开按钮 —— 「重启后多出
      // agent 消息」类 bug 的核心诊断可见性。
      payloadPreview: m.content,
    );
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
