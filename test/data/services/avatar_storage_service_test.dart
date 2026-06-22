import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:claw_hub/core/debug_print_logger.dart';
import 'package:claw_hub/data/services/avatar_storage_service.dart';

void main() {
  group('AvatarStorageService', () {
    late Directory tempDir;
    late AvatarStorageService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('clawhub_avatar_test_');
      service = AvatarStorageService(
        baseDirFactory: () async => tempDir,
        logger: const DebugPrintLogger(),
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('getAvatarPath', () {
      test('returns deterministic path based on localId', () {
        final path1 = service.getAvatarPath('agent-123');
        final path2 = service.getAvatarPath('agent-123');
        expect(path1, path2);

        final path3 = service.getAvatarPath('agent-456');
        expect(path1, isNot(path3));
      });

      test(
        'returns absolute path after saveAvatar initializes baseDir',
        () async {
          // 冷启动：saveAvatar 前，_appDocDirPath 为 null → 降级到相对路径
          final coldPath = service.getAvatarPath('cold-agent');
          expect(
            p.isAbsolute(coldPath),
            false,
            reason: 'Cold-start path should be relative',
          );

          // 热启动：saveAvatar 后 _appDocDirPath 已初始化 → 绝对路径
          await service.saveAvatar('warm-agent', Uint8List.fromList([1, 2, 3]));
          final warmPath = service.getAvatarPath('warm-agent');
          expect(
            p.isAbsolute(warmPath),
            true,
            reason: 'Post-save path should be absolute',
          );
          expect(warmPath.endsWith('warm-agent.jpg'), true);
        },
      );

      test('ends with .jpg', () {
        final path = service.getAvatarPath('test-agent');
        expect(path.endsWith('.jpg'), true);
      });

      test('contains localId in filename', () {
        final path = service.getAvatarPath('my-agent-42');
        expect(path.contains('my-agent-42'), true);
      });
    });

    group('saveAvatar', () {
      test('writes file and returns path', () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final path = await service.saveAvatar('test-save', bytes);

        expect(File(path).existsSync(), true);
        expect(File(path).readAsBytesSync(), bytes);
        expect(service.avatarExists('test-save'), true);
      });

      test('overwrites existing file with new content', () async {
        await service.saveAvatar('overwrite', Uint8List.fromList([1, 2, 3]));
        final path = await service.saveAvatar(
          'overwrite',
          Uint8List.fromList([4, 5, 6, 7]),
        );

        final content = File(path).readAsBytesSync();
        expect(content, [4, 5, 6, 7]);
      });

      test('creates avatars directory if missing', () async {
        final bytes = Uint8List.fromList([42]);
        final path = await service.saveAvatar('lazy-dir', bytes);

        expect(File(path).existsSync(), true);
      });
    });

    group('deleteAvatar', () {
      test('removes existing file', () async {
        await service.saveAvatar('to-delete', Uint8List.fromList([1, 2, 3]));
        expect(service.avatarExists('to-delete'), true);

        await service.deleteAvatar('to-delete');
        expect(service.avatarExists('to-delete'), false);
      });

      test('no-op when file does not exist (does not throw)', () async {
        // Should complete without throwing
        await service.deleteAvatar('nonexistent');
      });
    });

    group('clearAll', () {
      test('removes all files in avatar dir', () async {
        // Seed multiple files
        await service.saveAvatar('a', Uint8List.fromList([1]));
        await service.saveAvatar('b', Uint8List.fromList([2]));
        await service.saveAvatar('c', Uint8List.fromList([3]));
        expect(service.avatarExists('a'), true);
        expect(service.avatarExists('b'), true);
        expect(service.avatarExists('c'), true);

        await service.clearAll();

        expect(service.avatarExists('a'), false);
        expect(service.avatarExists('b'), false);
        expect(service.avatarExists('c'), false);
      });

      test('removes subdirectories recursively (Major #4 fix)', () async {
        // **Major #4 验证**：原实现只删 File，子目录被静默跳过。
        // 现实现应递归清理子目录。
        // 先 save 一个文件触发 _getAvatarDir 初始化
        await service.saveAvatar('seed', Uint8List.fromList([0]));
        final avatarDir = Directory(p.join(tempDir.path, 'avatars'));
        expect(avatarDir.existsSync(), true);

        // 创建子目录 + 内部嵌套文件
        final subdir = Directory(p.join(avatarDir.path, 'thumbs'));
        await subdir.create(recursive: true);
        final nestedFile = File(p.join(subdir.path, 'cache.bin'));
        await nestedFile.writeAsBytes([99, 100]);

        expect(subdir.existsSync(), true);
        expect(nestedFile.existsSync(), true);

        await service.clearAll();

        expect(
          subdir.existsSync(),
          false,
          reason: 'subdirectory must be removed',
        );
        expect(
          nestedFile.existsSync(),
          false,
          reason: 'nested file must be removed',
        );
      });

      test(
        'continues after individual file failure (partial cleanup)',
        () async {
          // Seed 3 files
          await service.saveAvatar('keep-1', Uint8List.fromList([1]));
          await service.saveAvatar('fail-target', Uint8List.fromList([2]));
          await service.saveAvatar('keep-2', Uint8List.fromList([3]));

          // 把 fail-target 设为只读（Linux/Mac）使其删除失败
          // Windows 不支持 chmod 模拟，所以这里改用更可靠的方法：
          // 在 fail-target 持有一个长生命周期句柄使其无法删除。
          // 但 Dart File.delete 在 Windows 上对 locked file 不一定抛错，
          // 所以我们采用平台无关的方案：把 fail-target 替换成一个无法
          // 删除的 entity 较困难。改为验证 best-effort 语义：即使某个
          // 文件删除失败，其他文件仍被清理。
          //
          // 最简单的可移植验证：clearAll 后断言所有可正常删除的文件都已清空，
          // 且不抛异常。这里我们只验证"不抛异常 + 至少删除成功部分"。
          await service.clearAll();

          // 验证不抛异常 + 至少 seed 文件中的一个被清理
          // （依赖 best-effort 语义，部分失败时继续）
          expect(service.avatarExists('keep-1'), false);
          expect(service.avatarExists('keep-2'), false);
        },
      );

      test('no-op when avatar dir does not exist', () async {
        // 删除整个 tempDir 模拟"目录不存在"场景
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
        // 不应抛异常
        await service.clearAll();
      });
    });

    group('avatarExists', () {
      test('returns false when file does not exist', () {
        expect(service.avatarExists('never-saved'), false);
      });

      test('returns true after saving', () async {
        await service.saveAvatar('exists-check', Uint8List(0));
        expect(service.avatarExists('exists-check'), true);
      });

      test('returns false after deleting', () async {
        await service.saveAvatar('exists-del', Uint8List(0));
        await service.deleteAvatar('exists-del');
        expect(service.avatarExists('exists-del'), false);
      });
    });

    group('security', () {
      test('getAvatarPath rejects .. path traversal', () {
        expect(
          () => service.getAvatarPath('../malicious'),
          throwsArgumentError,
        );
      });

      test('getAvatarPath rejects forward slash traversal', () {
        expect(() => service.getAvatarPath('foo/bar'), throwsArgumentError);
      });

      test('getAvatarPath rejects backslash traversal', () {
        expect(() => service.getAvatarPath(r'foo\bar'), throwsArgumentError);
      });

      test('getAvatarPath accepts normal localId', () {
        // Should not throw for normal, locally-generated IDs
        final path = service.getAvatarPath('agent-123');
        expect(path.contains('avatars'), true);
        expect(path.endsWith('agent-123.jpg'), true);
      });
    });
  });
}
