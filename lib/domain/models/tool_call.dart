import 'enums.dart';

/// 工具调用子实体
/// 对齐: 架构 vFinal 4.0 (ToolCall 子实体), 5.3 (工具调用状态机)
class ToolCall {
  final String id; // UUID
  final String messageId; // 关联 messages.clientId
  final String toolName; // 工具名称
  final ToolCallStatus status; // 工具调用状态枚举
  final String? inputArgs; // JSON 格式输入参数
  final String? outputResult; // JSON 格式输出结果
  final int? startedAt; // 开始时间(毫秒)
  final int? endedAt; // 结束时间(毫秒)

  ToolCall({
    required this.id,
    required this.messageId,
    required this.toolName,
    this.status = ToolCallStatus.pending,
    this.inputArgs,
    this.outputResult,
    this.startedAt,
    this.endedAt,
  });

  /// 开始执行: PENDING -> RUNNING
  ToolCall start() {
    return copyWith(
      status: ToolCallStatus.running,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 完成执行: RUNNING -> SUCCESS 或 FAILED
  ToolCall complete({required bool success, String? output}) {
    if (status != ToolCallStatus.running) {
      throw StateError('只能在 RUNNING 状态下完成工具调用，当前状态: $status');
    }
    return copyWith(
      status: success ? ToolCallStatus.success : ToolCallStatus.failed,
      outputResult: output,
      endedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 是否正在执行
  bool get isRunning => status == ToolCallStatus.running;

  /// 是否已结束
  bool get isCompleted => status.isCompleted;

  ToolCall copyWith({
    String? id,
    String? messageId,
    String? toolName,
    ToolCallStatus? status,
    String? inputArgs,
    String? outputResult,
    int? startedAt,
    int? endedAt,
  }) {
    return ToolCall(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      toolName: toolName ?? this.toolName,
      status: status ?? this.status,
      inputArgs: inputArgs ?? this.inputArgs,
      outputResult: outputResult ?? this.outputResult,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCall &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ToolCall(id: $id, toolName: $toolName, status: $status)';
}
