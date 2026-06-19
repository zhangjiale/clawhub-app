import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/storage_info.dart';

void main() {
  group('StorageInfo', () {
    group('sizeLabel', () {
      test('should format bytes correctly (B range)', () {
        const info = StorageInfo(databaseSizeBytes: 500);
        expect(info.sizeLabel, '500 B');
      });

      test('should format kilobytes correctly', () {
        const info = StorageInfo(databaseSizeBytes: 1024);
        expect(info.sizeLabel, '1.0 KB');
      });

      test('should format kilobytes with one decimal', () {
        const info = StorageInfo(databaseSizeBytes: 1536); // 1.5 KB
        expect(info.sizeLabel, '1.5 KB');
      });

      test('should format megabytes correctly', () {
        const info = StorageInfo(databaseSizeBytes: 1048576); // exactly 1 MB
        expect(info.sizeLabel, '1.0 MB');
      });

      test('should format megabytes with one decimal', () {
        const info = StorageInfo(databaseSizeBytes: 2621440); // 2.5 MB
        expect(info.sizeLabel, '2.5 MB');
      });

      test('should handle zero bytes', () {
        const info = StorageInfo(databaseSizeBytes: 0);
        expect(info.sizeLabel, '0 B');
      });

      test('should handle boundary between KB and MB', () {
        const info = StorageInfo(databaseSizeBytes: 1048575); // 1024*1024 - 1
        expect(info.sizeLabel, '1024.0 KB');
      });
    });

    group('constructor', () {
      test('should default messageCount to 0', () {
        const info = StorageInfo(databaseSizeBytes: 100);
        expect(info.messageCount, 0);
      });

      test('should accept custom messageCount', () {
        const info = StorageInfo(databaseSizeBytes: 100, messageCount: 42);
        expect(info.messageCount, 42);
      });
    });
  });
}
