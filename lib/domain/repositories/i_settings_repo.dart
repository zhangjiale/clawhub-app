import '../models/storage_info.dart';
import '../models/user_preferences.dart';

/// 用户设置仓库接口
///
/// 对齐: US-030 (设置页), PRD 3.8 (推送通知与状态提醒)
///
/// 管理应用级全局用户偏好，以单例行 (singleton row) 持久化。
/// 所有方法操作全局唯一一份设置；不涉及 per-agent 粒度。
abstract class ISettingsRepo {
  /// 获取当前用户偏好。首次调用且数据库无记录时返回 [UserPreferences.defaults]。
  Future<UserPreferences> getPreferences();

  /// 全量覆写用户偏好。
  ///
  /// 调用方应先通过 [getPreferences] + [copyWith] 产生新实例再传入，
  /// 以确保未修改字段不变。
  Future<void> updatePreferences(UserPreferences preferences);

  /// 监听偏好变更。
  ///
  /// 每次 [updatePreferences] 成功后 emit 新值。
  /// 首次订阅时立即 emit 当前值（若无记录则 emit defaults）。
  Stream<UserPreferences> watchPreferences();

  /// 获取存储使用信息（数据库大小、消息条数等）。
  ///
  /// 供存储管理设置页使用。数据库大小通过 SQLite PRAGMA 获取，
  /// 不依赖文件系统访问，因此跨平台安全。
  Future<StorageInfo> getStorageInfo();
}
