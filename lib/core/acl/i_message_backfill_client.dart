import '../../domain/models/models.dart';

/// 可选能力接口：拉取单条完整消息（避开 `chat.history` 的
/// display-normalization 截断）。
///
/// 对应 Gateway RPC `chat.message.get(sessionKey, messageId)`（spec §3.2，
/// docs/technical/openclaw-gateway-client-reference.md line 219/233）。
/// `chat.history` 会把超大消息的 content 替换为占位符
/// `[chat.history omitted: message too large]`；ACL mapper 检测到该占位符后
/// 置 `metadata.contentOmitted = true`（见 [GatewayDomainMapper.isChatHistoryOmitted]），
/// UI 据此渲染「点击加载」气泡，由用户点击触发本方法 lazy 拉取原始完整内容。
///
/// 为什么是独立接口而非 [IGatewayClient] 的成员：backfill 是**可选能力**--
/// 真实客户端（[WsGatewayClient] / [MockGatewayClient]）实现它；大量测试 fake
/// 只需 [IGatewayClient] 的核心契约、不需 backfill。把它放进 [IGatewayClient]
/// 会让所有 fake 被迫实现一个永不调用的方法。ChatViewModel 在 [loadFullMessage]
/// 中用 `is IMessageBackfillClient` 探测能力，不支持时优雅降级。
///
/// [messageId] 即目标消息的 [Message.serverId]（来自 `__openclaw.id`）。
/// 返回 null 表示消息不存在（已删除等）--调用方据此展示「无法加载」降级态。
abstract class IMessageBackfillClient {
  Future<Message?> fetchSingleMessage({
    required String instanceId,
    required String agentId,
    required String messageId,
  });
}
