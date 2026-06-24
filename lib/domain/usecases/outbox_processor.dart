import '../../core/i_logger.dart';
import '../models/agent.dart';
import '../models/message_status.dart';
import '../repositories/repositories.dart';
import 'send_message.dart';

/// 离线消息队列冲刷处理器（US-015）。
///
/// 在实例重连成功且 agent 同步完成后由 [ConnectionOrchestrator] 触发。
/// 职责：
/// - **崩溃恢复**：将 App 被 kill 时残留的 SENDING 状态重置为 PENDING
/// - **过期清理**：超过 24h 的 PENDING/FAILED 消息标记为 EXPIRED
/// - **顺序冲刷**：按 [Message.logicalClock] 升序逐条重发 PENDING/FAILED 消息
/// - **CAS 防竞争**：通过 [SendMessageUseCase.retry] 的条件更新避免与
///   并发的发送路径（SendMessageUseCase / ChatViewModel.retryMessage）重复操作
///
/// 不直接持有 [IGatewayClient] —— 所有发送都委托给 [SendMessageUseCase.retry]
/// 以保证发送逻辑的唯一入口。
class OutboxProcessor {
  final IMessageRepo _messageRepo;
  final IInstanceRepo _instanceRepo;
  final IAgentRepo _agentRepo;
  final SendMessageUseCase _sendMessageUseCase;
  final ILogger _logger;

  /// Per-instance 防重入锁。同一实例不可并发冲刷。
  final Set<String> _flushing = {};

  /// Outbox 消息过期阈值：超过 24 小时的 PENDING/FAILED 标记为 EXPIRED。
  static const Duration _expireThreshold = Duration(hours: 24);

  /// 单条消息发送超时上限。
  static const Duration _perMessageTimeout = Duration(seconds: 30);

  /// 整轮 flush 总时长上限。
  ///
  /// outbox 顺序串行重发，最坏情况 N × [_perMessageTimeout]。大队列时
  /// 一轮可能长时间占用连接、阻塞用户感知的重试反馈。设整轮上限后，
  /// 超时则停止本轮（已发送的计入返回值），剩余消息留待下一轮 flush
  /// （连接恢复/手动重试会再次触发）。下一轮会重新 resetStaleSending
  /// 把卡在 SENDING 的消息拉回 PENDING。
  static const Duration _flushRoundTimeout = Duration(minutes: 5);

  OutboxProcessor({
    required IMessageRepo messageRepo,
    required IInstanceRepo instanceRepo,
    required IAgentRepo agentRepo,
    required SendMessageUseCase sendMessageUseCase,
    required ILogger logger,
  }) : _messageRepo = messageRepo,
       _instanceRepo = instanceRepo,
       _agentRepo = agentRepo,
       _sendMessageUseCase = sendMessageUseCase,
       _logger = logger;

  /// 冲刷指定实例的待发送队列。
  ///
  /// 在 [ConnectionOrchestrator] agent sync 完成后调用。
  /// 返回成功发送的消息数量。
  ///
  /// 流程：
  /// 1. 防重入锁（同一实例不可并发冲刷）
  /// 2. 崩溃恢复：[IMessageRepo.resetStaleSending] 重置残留的 SENDING
  /// 3. 拉取 outbox（PENDING + FAILED，按 logicalClock 升序）
  /// 4. 检查实例在线状态（离线则返回 0）
  /// 5. 遍历每条消息：
  ///    - 超过 24h → 标记 EXPIRED，跳过
  ///    - agent 已删除 → 跳过
  ///    - 调用 [SendMessageUseCase.retry]（CAS + 发送 + 状态更新）
  ///    - 单条 30s 超时，超时/失败标记 FAILED 并继续下一条
  Future<int> flushOutbox(String instanceId) async {
    if (!_flushing.add(instanceId)) {
      _logger.info(
        '[OutboxProcessor] flushOutbox skipped: already flushing $instanceId',
      );
      return 0;
    }

    try {
      // 1. 崩溃恢复：将 App 被 kill 时残留的 SENDING 状态重置为 PENDING。
      //    这些消息在本轮 flush 中会被重新捕获。
      final reset = await _messageRepo.resetStaleSending(instanceId);
      if (reset > 0) {
        _logger.info(
          '[OutboxProcessor] Crash recovery: reset $reset SENDING messages '
          'to PENDING',
        );
      }

      // 2. 检查实例在线状态（在拉取 outbox 之前，避免离线实例浪费 JOIN 查询）
      final instance = await _instanceRepo.getById(instanceId);
      if (instance == null || !instance.healthStatus.isConnectable) {
        _logger.info(
          '[OutboxProcessor] flushOutbox skipped: instance $instanceId '
          'not connectable',
        );
        return 0;
      }

      // 3. 拉取该实例的 outbox（PENDING + FAILED，按 logicalClock 升序）
      final outbox = await _messageRepo.getOutboxByInstance(instanceId);
      if (outbox.isEmpty) return 0;

      final now = DateTime.now().millisecondsSinceEpoch;
      final roundDeadline = DateTime.now().add(_flushRoundTimeout);
      var sent = 0;

      // Agent 查询缓存 — 避免 N+1 查询（同一 agent 的多条消息共享一次 DB 查询）。
      // 存储 Agent? 类型，null 表示 agent 不存在（也缓存，避免重复查询已删除的 agent）。
      final Map<String, Agent?> agentCache = {};

      // 4. 顺序遍历队列
      for (final message in outbox) {
        // 4a. 整轮超时检查：超过 _flushRoundTimeout 则停止本轮，
        //     剩余消息留待下一轮 flush（连接恢复/手动重试再次触发）。
        if (DateTime.now().isAfter(roundDeadline)) {
          _logger.info(
            '[OutboxProcessor] Round timeout reached for $instanceId — '
            'flushed $sent/${outbox.length} this round, '
            'remaining deferred to next flush',
          );
          break;
        }

        // 4b. 过期检查：超过 24h 的消息标记 EXPIRED
        if (now - message.timestamp > _expireThreshold.inMilliseconds) {
          try {
            await _messageRepo.updateStatus(
              message.clientId,
              MessageStatus.expired,
            );
            _logger.info(
              '[OutboxProcessor] Marked expired: ${message.clientId} '
              '(age=${(now - message.timestamp) ~/ 1000}s)',
            );
          } catch (_) {
            // iron-law-allow: Law8 -- FSM validation failure when status already changed by concurrent path
          }
          continue;
        }

        // 4c. 查 agent 的 remoteId（带缓存，避免 N+1 查询）。
        //     同一 agent 的多条消息共享一次 DB 查询；
        //     null 也会被缓存，避免重复查询已删除的 agent。
        final agent =
            agentCache[message.agentId] ??
            await _agentRepo.getById(message.agentId);
        agentCache[message.agentId] = agent;
        // US-021: tombstoned agent（Gateway 端已删除）也必须跳过 —— 否则
        // chat.send 会返回 agent_not_found → 消息变 FAILED → 下轮 flush 重试
        // → 死循环到 24h 过期。tombstoned agent 仍存在于 DB（getById 不过滤，
        // 见 US-021 契约），故原 `agent == null` guard 不够，必须加 isRemoved。
        if (agent == null || agent.isRemoved) {
          // US-021 v1.1: tombstoned / missing agent 的消息转 EXPIRED 而非
          // 继续留在 outbox（避免 PENDING 计数 24h 卡死）。对齐同函数 24h
          // 过期分支的 updateStatus(expired) 模式。批量写入留给 v2 spec。
          try {
            await _messageRepo.updateStatus(
              message.clientId,
              MessageStatus.expired,
            );
            _logger.info(
              '[OutboxProcessor] Marked expired (agent ${message.agentId} '
              '${agent == null ? "not found" : "tombstoned"}): '
              '${message.clientId}',
            );
          } catch (e, st) {
            // 不抛：不让单条消息失败阻塞后续消息，与现有 24h 分支对齐。
            // 24h 自然过期兜底；监控通过 _logger.error 抓异常。
            _logger.error(
              '[OutboxProcessor] Failed to EXPIRE tombstoned-agent message '
              '${message.clientId}: $e',
              st,
            );
          }
          continue;
        }

        // 4d. 通过 SendMessageUseCase.retry 发送（统一发送路径）。
        //     retry 是 FAILED 的唯一权威：发送失败 / 超时都由 retry 的 catch
        //     统一标记 FAILED，此处只消费 sentNow，不再二次写状态。
        //     retry 返回 (message, sentNow)：
        //     - sentNow=true 表示本次调用成功发送给 gateway 并收到 ACK
        //     - sentNow=false 表示 CAS 失败（已被其他路径处理）或发送失败/超时
        try {
          final result = await _sendMessageUseCase.retry(
            clientId: message.clientId,
            instanceId: instanceId,
            agentRemoteId: agent.remoteId,
            expectedStatus: message.status, // PENDING 或 FAILED
            timeout: _perMessageTimeout,
          );
          if (result.sentNow) {
            sent++;
          }
        } catch (error, stackTrace) {
          // retry 自身抛出的非发送异常（如消息丢失 StateError）。
          // 不重复标记 FAILED —— 若消息卡在 SENDING，下一轮 flush 的
          // resetStaleSending（崩溃恢复）会将其重置为 PENDING 再处理。
          // 不中断整条队列，继续下一条。
          _logger.error(
            '[OutboxProcessor] Failed to send ${message.clientId}: $error',
            stackTrace,
          );
          continue;
        }
      }

      _logger.info(
        '[OutboxProcessor] Flushed $sent/${outbox.length} messages for '
        '$instanceId',
      );
      return sent;
    } finally {
      _flushing.remove(instanceId);
    }
  }
}
