import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:claw_hub/ui_kit/attachment_image_resolver.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [resolveAttachmentImage].
///
/// Law 17 (test-first for ui_kit helpers — recommended, not strictly mandated).
/// This file was created BEFORE its source counterpart (`attachment_image_resolver.dart`)
/// to satisfy the RED→GREEN flow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    // Review #2: the non-base64 branch must PARSE the data: URL (URL-decode
    // the payload), not wrap the whole string as a new data: URI's content.
    // The old `Uri.dataFromString(dataUrl)` returned the ASCII bytes of the
    // literal `data:...` string — a corrupt MemoryImage that hit errorBuilder
    // and polluted the LRU cache.
    test(
      'non-base64 (URL-encoded) data: URL decodes actual content (review #2)',
      () {
        // URL-encoded "<svg/>" (%3C=<, %2F=/, %3E=>).
        const dataUrl = 'data:image/svg+xml,%3Csvg%2F%3E';
        final provider = resolveAttachmentImage(imageUrl: dataUrl);
        expect(provider, isA<MemoryImage>());
        final bytes = (provider as MemoryImage).bytes;
        // Decoded content is "<svg/>" (6 bytes), NOT the 31-byte literal
        // `data:image/svg+xml,%3Csvg%2F%3E` string the old bug produced.
        expect(String.fromCharCodes(bytes), '<svg/>');
        expect(bytes.length, 6);
      },
    );

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
      setUp(resetDataUrlImageCacheForTesting);

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

      test('single entry larger than 1MB is not cached', () {
        // 1.5MB of base64-encoded zeros (≈2MB data URL string).
        const onePointFiveMb = 1536 * 1024;
        final bigBytes = Uint8List(onePointFiveMb);
        final dataUrl = 'data:image/png;base64,${base64Encode(bigBytes)}';

        resolveAttachmentImage(imageUrl: dataUrl);

        expect(dataUrlImageCacheBytesForTesting, 0);
      });

      test('total cache byte budget evicts LRU when exceeded', () {
        // Each entry is ~700KB decoded, well under the per-entry cap but
        // 12 of them exceed the 8MB total budget.
        const entrySize = 700 * 1024;
        final urls = <String>[];
        for (var i = 0; i < 12; i++) {
          final bytes = Uint8List(entrySize);
          bytes[0] = i; // make each payload distinct
          final url = 'data:image/png;base64,${base64Encode(bytes)}';
          urls.add(url);
          resolveAttachmentImage(imageUrl: url);
        }

        expect(
          dataUrlImageCacheBytesForTesting,
          lessThanOrEqualTo(8 * 1024 * 1024),
          reason: 'cache must evict LRU entries to stay under total budget',
        );
        expect(
          dataUrlImageCacheBytesForTesting,
          greaterThan(0),
          reason: 'recent entries should still be cached',
        );

        // The most-recently-used entry must still be cached.
        final lastProvider = resolveAttachmentImage(imageUrl: urls.last);
        expect(lastProvider, isA<MemoryImage>());
      });

      test(
        'byte budget counts the data: URL string key + decoded bytes (review #11)',
        () {
          // The cache retains BOTH the data: URL string (Map key) and the
          // decoded Uint8List (MemoryImage value). The budget must account
          // for both, not just the decoded bytes — otherwise actual retention
          // is ~2.3× the nominal 8MB cap.
          const payload =
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
          const dataUrl = 'data:image/png;base64,$payload';
          final decodedBytes = base64Decode(payload);

          resolveAttachmentImage(imageUrl: dataUrl);

          expect(
            dataUrlImageCacheBytesForTesting,
            dataUrl.length + decodedBytes.length,
            reason:
                'budget must include the data: URL string key length plus '
                'the decoded Uint8List length',
          );
        },
      );

      test('memory pressure clears the data: URL cache (review #11)', () {
        // The OS signals memory pressure (backgrounding, low-memory). The
        // cache must release its MB-scale decoded bytes via a
        // WidgetsBindingObserver.didHaveMemoryPressure handler, not pin them
        // until LRU eviction.
        const dataUrl =
            'data:image/png;base64,'
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+P///38GAwACvAEB1YwAAAAASUVORK5CYII=';
        resolveAttachmentImage(imageUrl: dataUrl);
        expect(dataUrlImageCacheBytesForTesting, greaterThan(0));
        expect(dataUrlImageCacheLengthForTesting, 1);

        WidgetsBinding.instance.handleMemoryPressure();

        expect(
          dataUrlImageCacheBytesForTesting,
          0,
          reason: 'memory pressure must clear cached bytes',
        );
        expect(
          dataUrlImageCacheLengthForTesting,
          0,
          reason: 'memory pressure must empty the cache map',
        );
      });
    });
  });
}
