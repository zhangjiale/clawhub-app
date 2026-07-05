/// Gateway 诊断事件统一抽象 (Gap #6 收尾 / Step 1)。
///
/// 把 Gateway 主动推送的「诊断类」事件（[LargePayloadNotice] 及后续
/// `rate.limit` / `quota.exceeded` 等）收敛成一个 sealed union，
/// 让 UI 层按 runtime type 分发文案。Finding #9 修复后 notice 不再
/// 进 ChatSessionState——改由 `gatewayNoticeProvider` (StreamProvider)
/// 直接暴露给 UI，新增事件不再碰 state 类与 page 订阅。
///
/// 纯 domain 模型 (Law 1)：零 Flutter / Riverpod / drift 依赖，也不依赖
/// `core/acl`。ACL 层的 JSON parser（`parseLargePayloadEvent`）保留在
/// `lib/core/acl/gateway_protocol.dart`，构造本类型返回——ACL→domain 允许，
/// 反向违反 Law 1。
sealed class GatewayNotice {
  const GatewayNotice();
}

/// 单帧负载超过 `policy.maxPayload` 时 Gateway 推送的诊断事件。
///
/// 字段对齐 spec §2.7：[sessionKey] 关联会话（回查哪条消息被拒）、
/// [size] 实际负载字节数、[limit] 当时的 maxPayload 上限。
///
/// 文案由 UI 层按本类型格式化（l10n 友好），本类只持结构化数据。
final class LargePayloadNotice extends GatewayNotice {
  final String sessionKey;
  final int size;
  final int limit;

  const LargePayloadNotice({
    required this.sessionKey,
    required this.size,
    required this.limit,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LargePayloadNotice &&
          sessionKey == other.sessionKey &&
          size == other.size &&
          limit == other.limit;

  @override
  int get hashCode => Object.hash(sessionKey, size, limit);

  @override
  String toString() =>
      'LargePayloadNotice(sessionKey: $sessionKey, size: $size, limit: $limit)';
}

/// 在途请求总字节数达到 `policy.maxBufferedBytes` 上限时由 ACL 翻译出的
/// 诊断事件（F-4）。
///
/// 与 [LargePayloadNotice] 的关键差异：缓冲满是**瞬态、不可由用户缓解**
/// —— 不像 payload.large 可以缩短内容重发，缓冲满只需等在途请求收完响应
/// 释放即可重试成功。故 toast 文案只定性（「网关繁忙，将自动重试」）不定量，
/// 不向用户暴露 buffered/attempted/max 字节数（用户既看不懂也无法操作）。
///
/// [emittedAt] 仅用于 toString 诊断，不参与相等性比较（review #9）。本类
/// 故意不重写 `==` / `hashCode` —— 每个实例都是独立的一次溢出事件，用
/// Object 默认的 identity 相等。此前 == 比较 emittedAt，Riverpod
/// `gatewayNoticeProvider` (StreamProvider) 对连续相等的 AsyncData 去重，
/// 导致同毫秒(web)/同微秒(native)的连续溢出只弹一次 toast。identity 相等
/// 保证每条 notice 都触发 ref.listen。时间戳不向 UI 展示。
///
/// 触发链路：`ConnectionManager.sendRequest` reject-new 抛
/// `BufferOverflowException` → `WsGatewayClient.sendMessage` 捕获后 `add()`
/// 本 notice 到 `gatewayNoticeCtrl` → 经 [GatewayNotice] 流复用 LargePayloadNotice
/// 的 toast 基建。异常仍 rethrow，`SendMessageUseCase` 照常标 FAILED（可重试），
/// OutboxProcessor 在缓冲排空后自动重发 —— 数据不丢。
final class BufferOverflowNotice extends GatewayNotice {
  final DateTime emittedAt;

  BufferOverflowNotice({DateTime? emittedAt})
    : emittedAt = emittedAt ?? DateTime.now();

  // No `==` / `hashCode` override — see class doc (review #9). Identity
  // equality ensures every transient notice is distinct, so Riverpod's
  // StreamProvider does not dedup consecutive BufferOverflowNotice events.

  @override
  String toString() =>
      'BufferOverflowNotice(emittedAt: ${emittedAt.toIso8601String()})';
}
