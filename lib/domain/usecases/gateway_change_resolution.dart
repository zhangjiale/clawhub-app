/// 用户在 GatewayChangeDialog 中的决策结果。
///
/// 编辑实例时若新 Gateway URL 的 host 与旧值不同，
/// SaveInstanceUseCase 会抛 [GatewayChangeRequiredException]。UI 弹窗后
/// 用户的选择通过此 enum 回传给 UseCase。
enum GatewayChangeResolution {
  /// 保留旧数据 — 不删除本地 agents，新 Gateway 的 agents 与本地合并。
  ///
  /// 旧 Gateway 上独有的 agents 会作为"孤儿"残留在本地（remoteId 未在新
  /// Gateway 返回中出现）。用户后续仍可手动删除实例彻底清空。
  keepLocal,

  /// 清除并切换 — 在保存前删除本实例下所有 agents。
  ///
  /// 通过 [IAgentRepo.deleteByInstanceId] 触发 ON DELETE CASCADE 级联，
  /// 同时清除 conversations + messages + FTS5 索引。不可恢复。
  purgeLocal,
}
