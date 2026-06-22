import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/core/i_logger.dart';

/// [IAvatarStorageService] 的生产实现 — 将头像文件存储在应用文档目录下。
///
/// 存储结构：
/// ```
/// {baseDir}/
///   avatars/
///     {agentLocalId}.jpg
///     ...
/// ```
///
/// [baseDir] 默认为 [getApplicationDocumentsDirectory]，测试时可注入
/// [Directory.systemTemp] 以隔离文件系统副作用。
///
/// 头像路径基于 agent 的 [localId] 确定性地计算，更换头像时覆盖写入同一路径。
/// ViewModel 负责在更新后调用 [imageCache.evict] 清除 Flutter 图片缓存。
class AvatarStorageService implements IAvatarStorageService {
  /// 生产环境使用 [getApplicationDocumentsDirectory]；
  /// 测试可传入临时目录。
  final Future<Directory> Function()? _baseDirFactory;

  final ILogger _logger;

  AvatarStorageService({
    Future<Directory> Function()? baseDirFactory,
    required ILogger logger,
  }) : _baseDirFactory = baseDirFactory,
       _logger = logger;

  Future<Directory> get _baseDir async {
    if (_baseDirFactory != null) return _baseDirFactory!();
    return getApplicationDocumentsDirectory();
  }

  /// 缓存初始化完成的 avatar 目录实例。
  Directory? _avatarDir;

  /// 获取 `{baseDir}/avatars/` 目录（懒初始化）。
  Future<Directory> get _getAvatarDir async {
    if (_avatarDir != null) return _avatarDir!;
    final base = await _baseDir;
    final dir = Directory(p.join(base.path, 'avatars'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _avatarDir = dir;
    return dir;
  }

  @override
  String getAvatarPath(String localId) {
    // Defend against path traversal: localId should never contain directory
    // separators or parent references. In practice localId comes from Drift
    // auto-increment IDs or locally-generated UUIDs — not from user input —
    // so this is a defense-in-depth check rather than a real threat vector.
    if (localId.contains('..') ||
        localId.contains('/') ||
        localId.contains('\\')) {
      throw ArgumentError(
        'Invalid localId (contains path traversal): $localId',
      );
    }
    // getAvatarPath 是同步方法，不能 await _getAvatarDir。
    // 优先使用 _appDocDirPath（由 save/delete 设置）；降级使用
    // _avatarDir?.parent.path（_getAvatarDir 已初始化但 _appDocDirPath
    // 尚未写入的狭窄窗口）；都为 null 时回退到空字符串（冷启动）。
    final basePath = _appDocDirPath ?? _avatarDir?.parent.path;
    return p.join(basePath ?? '', 'avatars', '$localId.jpg');
  }

  /// 懒缓存的基础目录路径（用于同步路径构建）。
  String? _appDocDirPath;

  @override
  Future<String> saveAvatar(String localId, Uint8List bytes) async {
    final dir = await _getAvatarDir;
    _appDocDirPath ??= dir.parent.path;
    final file = File(p.join(dir.path, '$localId.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> deleteAvatar(String localId) async {
    final dir = await _getAvatarDir;
    _appDocDirPath ??= dir.parent.path;
    final file = File(p.join(dir.path, '$localId.jpg'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  bool avatarExists(String localId) {
    final path = getAvatarPath(localId);
    return File(path).existsSync();
  }

  @override
  Future<void> clearAll() async {
    final dir = await _getAvatarDir;
    if (!await dir.exists()) return;
    // Materialize the entity list first so independent deletes can run
    // concurrently via Future.wait — sequential awaits on disk I/O can
    // take hundreds of ms for large avatar sets, blocking the UI spinner.
    final entities = await dir.list().toList();
    await Future.wait(
      entities.map(
        (entity) => () async {
          try {
            // **Major #4 修复**：原实现仅删除 File，Directory 实例被静默跳过。
            // 这意味着任何未来放入 avatar 目录的子目录（thumbnail 缓存、
            // `.DS_Store`、OS 产物等）都会成为磁盘泄漏——用户点"清除缓存"
            // 但占用未真正清空。递归删除子目录彻底清理。
            if (entity is Directory) {
              await entity.delete(recursive: true);
            } else {
              await entity.delete();
            }
          } catch (error, stackTrace) {
            // iron-law-allow: Law8 — best-effort, skip files we can't delete
            // (e.g. permission denied). Cross-storage cleanup should not
            // block the rest of the cache clear.
            _logger.error(
              '[AvatarStorage] Failed to delete ${entity.path}: $error',
              stackTrace,
            );
          }
        }(),
      ),
    );
  }
}
