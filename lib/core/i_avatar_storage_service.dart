import 'dart:typed_data';

/// 头像文件存储服务接口 — 面向接口编程，便于单测 mock。
///
/// [AgentProfileViewModel] 通过此接口操作头像文件（保存/删除/检查），
/// 不直接依赖 [dart:io] 文件系统 API。测试侧可注入 fake 实现。
///
/// [getAvatarPath] 提供确定性路径，供 [EmojiAvatar] 等 UI 组件
/// 将 [Agent.avatarUrl] 解析为磁盘文件路径。
abstract interface class IAvatarStorageService {
  /// 保存头像图片到本地文件，返回持久化路径。
  ///
  /// [localId] 对应 [Agent.localId]，文件名固定为 `{localId}.jpg`。
  /// [bytes] 为已压缩/裁剪的图片字节（JPEG 编码）。
  Future<String> saveAvatar(String localId, Uint8List bytes);

  /// 删除指定 agent 的头像文件。
  ///
  /// 若文件不存在则为 no-op（不抛出异常）。
  Future<void> deleteAvatar(String localId);

  /// 检查头像文件是否存在。
  bool avatarExists(String localId);

  /// 返回头像文件的确定性路径（不检查文件是否实际存在）。
  ///
  /// 路径格式：`{appDocDir}/avatars/{localId}.jpg`
  String getAvatarPath(String localId);
}
