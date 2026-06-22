/// US-030 清除全部缓存的结果。
///
/// 由 [ISettingsRepo.clearAll] 返回，让 UI 层能区分：
/// - 完全成功（DB + 头像文件都清理）
/// - 部分失败（DB 清了但头像文件清理抛错 —— macOS 沙箱/权限拒绝等）
/// - 完全失败（DB 事务回滚；头像未尝试）
///
/// 旧实现仅返回 void 并在 catch 中静默吞掉头像清理错误，导致 UI 永远显示
/// "已清除全部缓存"，用户不知道头像文件残留在磁盘。
class ClearAllResult {
  /// DB 事务（清消息/工具调用/统计/FTS5）是否成功。
  final bool dbCleared;

  /// 头像文件清理是否完全成功。仅当 [dbCleared] 为 true 时才有意义。
  /// false 时表示部分或全部头像文件残留在磁盘。
  final bool avatarsCleared;

  const ClearAllResult({required this.dbCleared, required this.avatarsCleared});

  /// 全部步骤都成功。
  bool get allSucceeded => dbCleared && avatarsCleared;

  /// DB 清理成功但头像清理失败 —— UI 层应提示用户"部分清理完成"。
  bool get partialFailure => dbCleared && !avatarsCleared;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClearAllResult &&
          other.dbCleared == dbCleared &&
          other.avatarsCleared == avatarsCleared;

  @override
  int get hashCode => Object.hash(dbCleared, avatarsCleared);

  @override
  String toString() =>
      'ClearAllResult(dbCleared: $dbCleared, avatarsCleared: $avatarsCleared)';
}
