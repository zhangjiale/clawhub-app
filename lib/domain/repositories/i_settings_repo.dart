import '../models/clear_all_result.dart';
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
  /// 供存储管理设置页使用。数据库大小通过 SQLite PRAGMA 获取,
  /// 不依赖文件系统访问,因此跨平台安全。
  Future<StorageInfo> getStorageInfo();

  /// 清空所有聊天内容(US-030 清除缓存)。
  ///
  /// **范围**:
  /// - 清:消息 / 工具调用 / Agent 统计 / 成就解锁 / 待发通知队列 /
  ///   头像文件
  /// - 保留:agents / conversations 骨架、`instances` 表(用户配置的 gateway
  ///   URL / token)、`user_preferences` 表(通知 / DND / 生物识别等设置)
  ///
  /// **为何保留 agents/conversations 骨架**:进行中的流式会话在 clearAll 后
  /// 仍会收到 `StreamingDone`,最终消息 INSERT 依赖 conversation_id 外键存在;
  /// 删骨架会导致 FK 异常、回复永久丢失。保留骨架后 agent 列表仍显示这些
  /// agent(仅无历史),对用户更友好。
  ///
  /// **失败语义**:事务内任意步骤失败 → 整体回滚,DB 状态不变。事务外的
  /// 文件系统清理(best-effort)失败 → 不影响 DB 清理结果,但返回的
  /// [ClearAllResult] 中 [ClearAllResult.avatarsCleared] 为 false,
  /// UI 层应据此提示用户"部分清理完成"。
  ///
  /// **后续**:调用方在收到成功后应 `ref.invalidate(storageInfoProvider)`
  /// 以触发 storage 大小重新计算。
  Future<ClearAllResult> clearAll();
}
