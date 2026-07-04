import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/utils/format_bytes.dart';

/// Unit tests for [formatBytes].
///
/// Law 17 (test-first for domain/utils — recommended). This file was created
/// BEFORE its source counterpart (`format_bytes.dart`) to satisfy the
/// RED→GREEN flow.
///
/// The exact outputs are pinned to match the pre-existing `StorageInfo.sizeLabel`
/// expectations (see `test/domain/models/storage_info_test.dart`) so the
/// extracted helper is a behaviour-identical SSOT for both call sites.
void main() {
  group('formatBytes', () {
    test('formats bytes below 1 KiB as B', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1), '1 B');
      expect(formatBytes(500), '500 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('formats KiB with one decimal', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB'); // 1.5 KB
      // Boundary: just under 1 MiB still renders in KB.
      expect(formatBytes(1048575), '1024.0 KB'); // 1024*1024 - 1
    });

    test('formats MiB with one decimal', () {
      expect(formatBytes(1048576), '1.0 MB'); // exactly 1 MB
      expect(formatBytes(2621440), '2.5 MB'); // 2.5 MB
    });
  });
}
