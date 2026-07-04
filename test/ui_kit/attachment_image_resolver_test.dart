import 'dart:io';

import 'package:claw_hub/ui_kit/attachment_image_resolver.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [resolveAttachmentImage].
///
/// Law 17 (test-first for ui_kit helpers — recommended, not strictly mandated).
/// This file was created BEFORE its source counterpart (`attachment_image_resolver.dart`)
/// to satisfy the RED→GREEN flow.
void main() {
  group('resolveAttachmentImage', () {
    test('data: URL with valid base64 → MemoryImage', () {
      // 1×1 transparent PNG, well-known base64.
      const dataUrl =
          'data:image/png;base64,'
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final provider = resolveAttachmentImage(imageUrl: dataUrl);
      expect(provider, isNotNull);
      expect(provider, isA<MemoryImage>());
      expect((provider as MemoryImage).bytes.length, greaterThan(0));
    });

    test('https URL → NetworkImage', () {
      final provider = resolveAttachmentImage(
        imageUrl: 'https://example.com/x.png',
      );
      expect(provider, isA<NetworkImage>());
    });

    test('http URL → NetworkImage', () {
      final provider = resolveAttachmentImage(
        imageUrl: 'http://example.com/x.png',
      );
      expect(provider, isA<NetworkImage>());
    });

    test('local file path → FileImage', () async {
      final tempDir = await Directory.systemTemp.createTemp('resolver_test_');
      final tempFile = File('${tempDir.path}/img.jpg');
      await tempFile.writeAsBytes([0xFF, 0xD8, 0xFF]); // JPEG-ish header
      addTearDown(() async => tempDir.delete(recursive: true));

      final provider = resolveAttachmentImage(imagePath: tempFile.path);
      expect(provider, isA<FileImage>());
    });

    test('both null → null (caller renders placeholder)', () {
      expect(resolveAttachmentImage(), isNull);
      expect(resolveAttachmentImage(imageUrl: null, imagePath: null), isNull);
    });

    test('empty strings → null', () {
      expect(resolveAttachmentImage(imageUrl: ''), isNull);
      expect(resolveAttachmentImage(imagePath: ''), isNull);
    });

    test('imageUrl takes precedence over imagePath (Agent 回图优先)', () {
      // When both are present, imageUrl (Agent response image) wins.
      // Message.imagePath getter already returns null when imageUrl is set,
      // so this is a defensive guard against double-supply.
      final provider = resolveAttachmentImage(
        imageUrl: 'https://example.com/a.png',
        imagePath: '/tmp/b.jpg',
      );
      expect(provider, isA<NetworkImage>());
    });

    // -------------------------------------------------------------------------
    // P0 regression guard: corrupt data: URL must NOT bubble up as a
    // FormatException (which would crash the widget tree). Instead the
    // resolver returns a provider that Image's errorBuilder can handle,
    // so the rendering layer shows _BrokenImage instead of crashing.
    // -------------------------------------------------------------------------
    group('corrupt data: URL (P0 regression guard)', () {
      test(
        'invalid base64 does not throw — returns provider for errorBuilder',
        () {
          expect(
            () => resolveAttachmentImage(
              imageUrl: 'data:image/png;base64,!!!not-valid-base64!!!',
            ),
            returnsNormally,
          );
          final provider = resolveAttachmentImage(
            imageUrl: 'data:image/png;base64,!!!not-valid-base64!!!',
          );
          expect(
            provider,
            isNotNull,
            reason:
                'must return a provider so Image.errorBuilder fires '
                '(_BrokenImage), not null (null → [图片] text placeholder)',
          );
        },
      );

      test(
        'data: URL with no comma → returns provider (errorBuilder path)',
        () {
          expect(
            () => resolveAttachmentImage(imageUrl: 'data:image/png'),
            returnsNormally,
          );
          final provider = resolveAttachmentImage(imageUrl: 'data:image/png');
          expect(provider, isNotNull);
        },
      );
    });

    // -------------------------------------------------------------------------
    // data: URL decode cache: the same data: URL must return the SAME
    // ImageProvider instance across calls. This is what lets Flutter's
    // ImageCache dedup (MemoryImage == is identity-based) and avoids
    // re-running base64Decode + image decode on every chat-list rebuild
    // (which fires ~6×/sec during streaming).
    // -------------------------------------------------------------------------
    group('data: URL decode cache', () {
      test('same data: URL returns identical ImageProvider across calls', () {
        // Distinct URL so prior tests' cache entries don't influence this.
        const dataUrl =
            'data:image/png;base64,'
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+P///38GAwACvAEB1YwAAAAASUVORK5CYII=';
        final p1 = resolveAttachmentImage(imageUrl: dataUrl);
        final p2 = resolveAttachmentImage(imageUrl: dataUrl);

        expect(p1, isA<MemoryImage>());
        expect(
          identical(p1, p2),
          isTrue,
          reason:
              'same data: URL must return the same MemoryImage instance so '
              'ImageCache hits and base64Decode runs once, not per rebuild',
        );
      });
    });
  });
}
