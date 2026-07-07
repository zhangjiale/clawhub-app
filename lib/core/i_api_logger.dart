/// API 请求/响应日志接口 — ACL 采集点依赖此抽象，不依赖具体环形缓冲实现。
///
/// 与 [ILogger]（console/dev 路径）补充共存：本接口服务 App 内结构化诊断路径
/// （带 req↔res 链接 / durationMs / instanceId）。spec §2.3 决策 5。
abstract interface class IApiLogger {
  /// 记录一条出站请求帧（req）。rawJson 由实现内部 redactAndTruncate 脱敏截断。
  /// 永不抛（spec §4.2 不变量）。
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  });

  /// 记录一条入站响应帧（res）。**必须在 completer.complete(frame) 之后调**
  /// （spec §5.1），确保日志路径失败不阻塞响应交付。永不抛。
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  });

  /// 记录一条连接生命周期/诊断事件。[state] 可为 null（纯 message 诊断条目，
  /// 如 buffer overflow / payload too large）。永不抛。
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
  });
}

/// 日志方向。state 条目方向为 null（见 [ApiLogEntry.direction]）。
enum ApiLogDirection { outgoing, incoming }

/// 日志类别。
enum ApiLogKind { req, res, state }

/// 一条 API/生命周期日志。普通不可变类（非 freezed，spec §2.3 决策 1）。
class ApiLogEntry {
  final String id;
  final int timestampMs;
  final String instanceId;
  final ApiLogDirection? direction; // null for state entries
  final ApiLogKind kind;
  final String? methodOrEvent; // "chat.send" / "connect"；state 为 null
  final String? requestId; // 帧 id，链接 req↔res（state 为 null）
  final bool? ok; // res 用
  final String? errorCode; // res 错误码，如 "NOT_PAIRED"
  final String? state; // state 用，如 "authFailed"；纯 message 诊断可为 null
  final int? byteSize; // req/res 帧字节数
  final int? durationMs; // res 用，由 store 匹配 req 算出
  final String? payloadPreview; // 截断+脱敏后的 JSON（≤2KB）；state 为 null
  final String? message; // state 用的人类可读说明

  const ApiLogEntry({
    required this.id,
    required this.timestampMs,
    required this.instanceId,
    this.direction,
    required this.kind,
    this.methodOrEvent,
    this.requestId,
    this.ok,
    this.errorCode,
    this.state,
    this.byteSize,
    this.durationMs,
    this.payloadPreview,
    this.message,
  });
}
