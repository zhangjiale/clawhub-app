import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import '../../core/acl/i_gateway_client.dart';
import '../../core/i_logger.dart';
import 'generate_preview.dart';

/// 发送消息用例
/// 对齐: 架构 vFinal 6.1 (消息发送、Outbox 暂存与渲染闭环)
///
/// 流程:
/// 1. 生成 clientId，插入本地数据库（状态=PENDING）
/// 2. 检查实例在线状态
/// 3. 在线 → 通过 Gateway 发送 → 收到 ACK → 绑定 serverId（状态=SENT）
/// 4. 离线 → 保持 PENDING 状态（待 Outbox 重发）
/// 5. 发送失败 → 标记 FAILED
class SendMessageUseCase {
  final IMessageRepo _messageRepo;
  final IConversationRepo _conversationRepo;
  final IInstanceRepo _instanceRepo;
  final IGatewayClient _gatewayClient;
  final GeneratePreview _generatePreview;
  final Uuid _uuid;
  final ILogger? _logger;

  /// Monotonically increasing logical clock counter.
  /// Initialized from the current timestamp and incremented per message
  /// to guarantee strict ordering even within the same millisecond.
  int _logicalClockCounter = DateTime.now().millisecondsSinceEpoch;

  SendMessageUseCase({
    required this._messageRepo,
    required this._conversationRepo,
    required this._instanceRepo,
    required this._gatewayClient,
    GeneratePreview? generatePreview,
    Uuid? uuid,
    this._logger,
  }) : _generatePreview = generatePreview ?? GeneratePreview(),
       _uuid = uuid ?? const Uuid();

  /// Exposes the preview generator so other components (notably
  /// [ChatViewModel], when an agent reply arrives over the stream) can
  /// build the same canonical preview text the use case produces for
  /// user-sent messages.  Sharing the single instance keeps the
  /// preview rules (prefix, Markdown stripping, truncation) in one place.
  GeneratePreview get generatePreview => _generatePreview;

  /// Returns the next monotonically increasing logical clock value.
  ///
  /// Shared between [execute] (user messages) and callers like
  /// [ChatViewModel] (incoming agent messages) to guarantee all
  /// messages in a conversation receive strictly ordered logicalClock
  /// values, regardless of whether they originate from the user or
  /// the Gateway.
  int nextLogicalClock() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > _logicalClockCounter) _logicalClockCounter = now;
    return _logicalClockCounter++;
  }

  /// 发送消息
  /// 返回最终状态的消息实体
  ///
  /// 若 [agent] 已被 Gateway 端 tombstone，则抛出 [AgentRemovedError]。
  Future<Message> execute({
    required String instanceId,
    required Agent agent,
    required String content,
    required MessageType type,
    Map<String, dynamic>? metadata,
  }) async {
    if (agent.isRemoved) {
      throw AgentRemovedError(agent.localId);
    }

    // 1. 生成 clientId 并构建消息
    final clientId = _uuid.v4();
    final conversation = await _conversationRepo.getOrCreate(
      instanceId,
      agent.localId,
    );

    // Get monotonic logical clock (increment counter for each message sent)
    final logicalClock = nextLogicalClock();

    var message = Message(
      clientId: clientId,
      conversationId: conversation.id,
      agentId: agent.localId,
      role: MessageRole.user,
      content: content,
      type: type,
      status: MessageStatus.pending,
      logicalClock: logicalClock,
      metadata: metadata,
    );

    // 2. 插入本地数据库
    message = await _messageRepo.insert(message);

    // 3. 更新会话预览
    final preview = _generatePreview.execute(
      role: message.role,
      type: message.type,
      content: message.content,
    );
    await _conversationRepo.updateLastMessage(
      conversationId: conversation.id,
      messageId: clientId,
      preview: preview,
      timestamp: message.timestamp,
      role: message.role,
    );

    // 4. 检查实例状态
    final instance = await _instanceRepo.getById(instanceId);
    if (instance == null || !instance.healthStatus.isConnectable) {
      // 实例离线，保持 PENDING 状态，等待 Outbox 重发
      return message;
    }

    // 5. 通过 Gateway 发送 — CAS 进入 SENDING。
    //    与 [retry] / [OutboxProcessor] 共用同一道 PENDING→SENDING 闸口，
    //    避免并发路径重复发送同一条消息，也避免对已被推进到 SENT 的消息
    //    再次 updateStatus(sending) 触发 FSM 校验异常（SENT→sending 非法）。
    final casOk = await _messageRepo.tryTransitionToSending(
      clientId,
      MessageStatus.pending,
    );
    if (!casOk) {
      // 消息已被并发路径（OutboxProcessor / retry）接管并推进，
      // 不重复发送，返回当前实体。
      final current = await _messageRepo.getByClientId(clientId);
      return current ?? message;
    }

    try {
      message = await _deliverViaGateway(
        clientId: clientId,
        instanceId: instanceId,
        agentRemoteId: agent.remoteId,
        message: message,
      );

      return message;
    } catch (e, st) {
      // 7. 发送失败，先记录错误再标记 FAILED
      _logger?.error(
        '[SendMessageUseCase.execute] send failed for clientId=$clientId: $e',
        st,
      );
      message = await _messageRepo.updateStatus(clientId, MessageStatus.failed);
      return message;
    }
  }

  /// 通过 Gateway 发送消息并绑定 serverId（SENDING → SENT）。
  ///
  /// [execute] 和 [retry] 的共用发送尾巴，保证发送逻辑唯一入口，
  /// 避免两条路径各自维护 sendMessage + bindServerId 而漂移。
  Future<Message> _deliverViaGateway({
    required String clientId,
    required String instanceId,
    required String agentRemoteId,
    required Message message,
  }) async {
    final ack = await _gatewayClient.sendMessage(
      instanceId: instanceId,
      agentId: agentRemoteId,
      message: message,
    );
    return _messageRepo.bindServerId(clientId, ack.serverId);
  }

  /// 重试一条 PENDING 或 FAILED 消息（统一发送入口）。
  ///
  /// 使用 CAS 条件更新（[expectedStatus] → SENDING）防止与并发的发送路径
  /// （SendMessageUseCase / OutboxProcessor / ChatViewModel.retryMessage）
  /// 重复操作同一条消息。
  ///
  /// **FAILED 的唯一权威**：发送失败 *或* 超时都由本方法的 catch 统一标记
  /// FAILED。调用方（OutboxProcessor / ChatViewModel）只消费 `sentNow`，
  /// 不得二次写入 FAILED —— 否则会出现三层状态写入彼此打架。
  ///
  /// 返回 record:
  /// - `message`: 最终状态的消息实体
  /// - `sentNow`: 本次调用是否成功发送给 gateway 并收到 ACK
  ///   （CAS 失败 / 发送失败 / 超时 时为 false）
  ///
  /// [expectedStatus] 默认为 [MessageStatus.failed]（手动重试场景）；
  /// OutboxProcessor 在冲刷队列时按消息当前状态传入 PENDING 或 FAILED。
  ///
  /// [timeout] 为单条消息发送超时上限；超时后标记 FAILED 并返回 sentNow=false。
  /// OutboxProcessor 传入冲刷超时；手动重试（ChatViewModel）默认不超时。
  Future<({Message message, bool sentNow})> retry({
    required String clientId,
    required String instanceId,
    required String agentRemoteId,
    MessageStatus expectedStatus = MessageStatus.failed,
    Duration? timeout,
  }) async {
    // CAS: 仅当消息仍为 [expectedStatus] 时才过渡到 SENDING
    final ok = await _messageRepo.tryTransitionToSending(
      clientId,
      expectedStatus,
    );
    if (!ok) {
      // 消息已被其他路径推进或不存在 — 返回当前状态，未发送
      final current = await _messageRepo.getByClientId(clientId);
      if (current == null) {
        throw StateError('消息不存在或已删除: $clientId');
      }
      return (message: current, sentNow: false);
    }

    // CAS 成功 — 当前状态为 SENDING，重新读取以获取最新实体
    final message = await _messageRepo.getByClientId(clientId);
    if (message == null) {
      throw StateError('消息在 CAS 后丢失: $clientId');
    }

    try {
      final deliverFuture = _deliverViaGateway(
        clientId: clientId,
        instanceId: instanceId,
        agentRemoteId: agentRemoteId,
        message: message,
      );
      final updated = timeout == null
          ? await deliverFuture
          : await deliverFuture.timeout(timeout);
      return (message: updated, sentNow: true);
    } catch (e, st) {
      // iron-law-allow: Law8 -- 发送失败与超时统一在此标记 FAILED；
      // 调用方只看 sentNow，不重复写状态。
      _logger?.error(
        '[SendMessageUseCase.retry] send failed for clientId=$clientId: $e',
        st,
      );
      final failed = await _messageRepo.updateStatus(
        clientId,
        MessageStatus.failed,
      );
      return (message: failed, sentNow: false);
    }
  }
}
