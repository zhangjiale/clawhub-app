/// 编辑实例时检测到 Gateway host 变化、本地有 agents、用户尚未给出 resolution。
///
/// SaveInstanceUseCase 抛出此异常，UI 层捕获后应弹出 GatewayChangeDialog
/// 询问用户保留/清除/取消，然后用得到的 [GatewayChangeResolution] 再次调用
/// `execute(onGatewayChange: choice)` 完成保存。
class GatewayChangeRequiredException implements Exception {
  /// 本实例下当前本地 agents 的数量（用于弹窗文案）。
  final int localAgentCount;

  const GatewayChangeRequiredException({required this.localAgentCount});

  @override
  String toString() =>
      'GatewayChangeRequiredException(localAgentCount: $localAgentCount)';
}

/// purgeLocal 路径下 `agentRepo.deleteByInstanceId` 失败时抛出。
///
/// 数据可能处于部分清除的不一致状态 — UI 应展示错误并建议用户重试。
/// 包装底层错误（[cause]）便于诊断，对外暴露中文 [message] 供 UI 展示。
class PurgeFailedException implements Exception {
  final String message;
  final Object cause;

  const PurgeFailedException({required this.message, required this.cause});

  @override
  String toString() => 'PurgeFailedException: $message';
}

/// purgeLocal 路径下 `testConnection` 返回 false（新 Gateway 不可达）时抛出。
///
/// 此时 UseCase 拒绝执行 purge —— 避免“为了切换到一个不可达的 Gateway 而把本地
/// agents/conversations/messages 全部删掉”这一不可逆的数据丢失场景。
/// UI 应展示错误并提示用户检查地址、网络后重试（无需再次弹窗确认）。
class GatewayUnreachableException implements Exception {
  final String message;

  const GatewayUnreachableException({this.message = 'Gateway 不可达，请检查地址与网络后重试'});

  @override
  String toString() => 'GatewayUnreachableException: $message';
}
