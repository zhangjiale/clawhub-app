import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:claw_hub/data/services/avatar_storage_service.dart';

void main() {
  group('AvatarStorageService', () {
    late Directory tempDir;
    late AvatarStorageService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('clawhub_avatar_test_');
      service = AvatarStorageService(baseDirFactory: () async => tempDir);
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
