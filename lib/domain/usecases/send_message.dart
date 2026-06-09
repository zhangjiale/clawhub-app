import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import '../../core/acl/i_gateway_client.dart';
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

  /// Monotonically increasing logical clock counter.
  /// Initialized from the current timestamp and incremented per message
  /// to guarantee strict ordering even within the same millisecond.
  int _logicalClockCounter = DateTime.now().millisecondsSinceEpoch;

  SendMessageUseCase({
    required IMessageRepo messageRepo,
    required IConversationRepo conversationRepo,
    required IInstanceRepo instanceRepo,
    required IGatewayClient gatewayClient,
    GeneratePreview? generatePreview,
    Uuid? uuid,
  })  : _messageRepo = messageRepo,
        _conversationRepo = conversationRepo,
        _instanceRepo = instanceRepo,
        _gatewayClient = gatewayClient,
        _generatePreview = generatePreview ?? GeneratePreview(),
        _uuid = uuid ?? const Uuid();

  /// 发送消息
  /// 返回最终状态的消息实体
  Future<Message> execute({
    required String instanceId,
    required Agent agent,
    required String content,
    required MessageType type,
    Map<String, dynamic>? metadata,
  }) async {
    // 1. 生成 clientId 并构建消息
    final clientId = _uuid.v4();
    final conversation = await _conversationRepo.getOrCreate(instanceId, agent.localId);

    // Get monotonic logical clock (increment counter for each message sent)
    final logicalClock = _logicalClockCounter++;

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

    // 5. 通过 Gateway 发送
    try {
      message = await _messageRepo.updateStatus(clientId, MessageStatus.sending);

      final ack = await _gatewayClient.sendMessage(
        instanceId: instanceId,
        agentId: agent.remoteId,
        message: message,
      );

      // 6. 绑定 serverId，状态 → SENT
      message = await _messageRepo.bindServerId(clientId, ack.serverId);

      return message;
    } catch (e) {
      // 7. 发送失败，标记 FAILED
      message = await _messageRepo.updateStatus(clientId, MessageStatus.failed);
      return message;
    }
  }
}
