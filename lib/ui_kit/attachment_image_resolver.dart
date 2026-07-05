import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Resolves a message attachment's image source to an [ImageProvider].
///
/// Centralizes the data: vs http(s) vs local-file branching so that:
/// - P0: `data:` URLs (Agent inline base64 images) decode to [MemoryImage]
///   instead of being fed to [NetworkImage] (which only handles http/https
///   and would trigger errorBuilder → broken-image placeholder).
/// - P2: `dart:io` (for [FileImage]) lives here, NOT in the widget layer
///   (Law 2: widgets render UI only, no direct platform/File calls).
///
/// Contract:
/// - [imageUrl] (Agent response image) takes precedence over [imagePath].
/// - Returns `null` when both are null/empty — caller renders a text
///   placeholder (`[图片]`).
/// - Corrupt `data:` URLs (invalid base64) do NOT throw. They return a
///   [MemoryImage] with empty bytes so the [Image] widget's `errorBuilder`
///   fires and renders the broken-image placeholder, rather than crashing
///   the widget tree with a [FormatException].
///
/// Lives in `ui_kit/` (not `core/utils/`) because it returns a Flutter
/// [ImageProvider] and holds a small decode cache — it is not a pure-Dart
/// utility and must not be imported from `domain/` or `data/`.
///
/// **`data:` URL caching**: [MessageImageContent] rebuilds on every
/// [ChatSessionState] change (including rapid streaming-text updates). Without
/// caching, each rebuild re-runs [base64Decode] (synchronous, MB-scale) on the
/// UI isolate AND returns a fresh [MemoryImage] whose identity-based `==`
/// defeats Flutter's [ImageCache] — so the image is re-decoded too. Returning
/// the same [MemoryImage] instance for a given `data:` URL makes [ImageCache]
/// hit, skipping both costs after the first decode. Network/file paths are NOT
/// cached here: [NetworkImage] and [FileImage] already override `==`/hashCode
/// by URL/path, so [ImageCache] dedups them without help.
ImageProvider? resolveAttachmentImage({String? imageUrl, String? imagePath}) {
  if (imageUrl != null && imageUrl.isNotEmpty) {
    if (imageUrl.startsWith('data:')) {
      return _dataUrlToImageProvider(imageUrl);
    }
    return NetworkImage(imageUrl);
  }
  if (imagePath != null && imagePath.isNotEmpty) {
    return FileImage(File(imagePath));
  }
  return null;
}

/// Bounded LRU cache of decoded `data:` URL image providers (see doc above).
///
/// Insertion-ordered [Map] used as an LRU: a cache hit is moved to the end
/// (most-recently-used) via remove + re-insert; eviction drops `keys.first`
/// (least-recently-used).
///
/// Two budgets bound memory retention (data URLs can be MB-scale):
/// - [_dataUrlImageCacheMaxBytes]: total bytes across all cached entries.
/// - [_dataUrlImageCacheMaxEntryBytes]: a single entry larger than this is
///   not cached at all (decoding cost is paid, but the raw bytes are not
///   retained). This prevents one giant inline image from evicting everything
///   else or pinning a huge allocation.
const int _dataUrlImageCacheLimit = 16;
const int _dataUrlImageCacheMaxBytes = 8 * 1024 * 1024;
const int _dataUrlImageCacheMaxEntryBytes = 1024 * 1024;
final Map<String, MemoryImage> _dataUrlImageCache = {};
int _dataUrlImageCacheBytes = 0;

/// Decodes a `data:` URL to a [MemoryImage], memoized per URL.
///
/// Format: `data:<mime>;base64,<payload>` or `data:<mime>,<url-encoded>`.
/// - base64 path: [base64Decode] the payload → [MemoryImage].
/// - non-base64 path: parse via [Uri.dataFromString] → [MemoryImage].
/// - corrupt input: return [MemoryImage] with empty bytes (errorBuilder path).
/// Total retained bytes for one cache entry: the data: URL string key (the
/// [Map] retains it as a Dart String) plus the decoded [Uint8List]. Both must
/// be counted — otherwise the budget under-counts actual retention ~2.3×
/// (a 5MB image is ~6.7MB base64 string + 5MB bytes ≈ 11.7MB, not 5MB)
/// (review #11).
int _dataUrlEntryBytes(String dataUrl, int decodedBytes) =>
    dataUrl.length + decodedBytes;

MemoryImage _dataUrlToImageProvider(String dataUrl) {
  _DataUrlImageCacheMemoryObserver.ensureRegistered();

  final cached = _dataUrlImageCache[dataUrl];
  if (cached != null) {
    // LRU refresh: move to most-recently-used so the entry survives eviction.
    _dataUrlImageCache.remove(dataUrl);
    _dataUrlImageCache[dataUrl] = cached;
    return cached;
  }

  final provider = _decodeDataUrl(dataUrl);
  final decodedBytes = provider.bytes.length;

  // Do not cache giant single entries; just return the decoded provider.
  if (decodedBytes > _dataUrlImageCacheMaxEntryBytes) {
    return provider;
  }

  final entryBytes = _dataUrlEntryBytes(dataUrl, decodedBytes);

  // Evict LRU entries until the new entry fits under the total byte budget.
  while (_dataUrlImageCacheBytes + entryBytes > _dataUrlImageCacheMaxBytes &&
      _dataUrlImageCache.isNotEmpty) {
    final oldestKey = _dataUrlImageCache.keys.first;
    final oldest = _dataUrlImageCache.remove(oldestKey)!;
    _dataUrlImageCacheBytes -= _dataUrlEntryBytes(
      oldestKey,
      oldest.bytes.length,
    );
  }

  _dataUrlImageCache[dataUrl] = provider;
  _dataUrlImageCacheBytes += entryBytes;

  // Keep the legacy entry-count cap as a secondary guard.
  while (_dataUrlImageCache.length > _dataUrlImageCacheLimit) {
    final oldestKey = _dataUrlImageCache.keys.first;
    final oldest = _dataUrlImageCache.remove(oldestKey)!;
    _dataUrlImageCacheBytes -= _dataUrlEntryBytes(
      oldestKey,
      oldest.bytes.length,
    );
  }

  return provider;
}

/// Clears the data: URL image cache when the OS signals memory pressure
/// (backgrounding / low-memory), so inline Agent images don't pin MB-scale
/// decoded bytes until LRU eviction (review #11). The cache is process-global
/// (module-level), so the observer is registered once on first cache use and
/// lives for the app's lifetime — it does not need to be removed.
class _DataUrlImageCacheMemoryObserver extends WidgetsBindingObserver {
  _DataUrlImageCacheMemoryObserver._();
  static _DataUrlImageCacheMemoryObserver? _instance;
  static bool _registered = false;

  /// Idempotently registers this observer with the [WidgetsBinding]. Safe to
  /// call on every cache insertion; only the first call has effect.
  static void ensureRegistered() {
    if (_registered) return;
    _instance ??= _DataUrlImageCacheMemoryObserver._();
    WidgetsBinding.instance.addObserver(_instance!);
    _registered = true;
  }

  @override
  void didHaveMemoryPressure() {
    _dataUrlImageCache.clear();
    _dataUrlImageCacheBytes = 0;
  }
}

/// Test-only hook: clears the data: URL image cache and resets the byte counter.
@visibleForTesting
void resetDataUrlImageCacheForTesting() {
  _dataUrlImageCache.clear();
  _dataUrlImageCacheBytes = 0;
}

/// Test-only hook: current total bytes retained in the data: URL image cache.
@visibleForTesting
int get dataUrlImageCacheBytesForTesting => _dataUrlImageCacheBytes;

/// Test-only hook: number of entries currently in the data: URL image cache.
@visibleForTesting
int get dataUrlImageCacheLengthForTesting => _dataUrlImageCache.length;

MemoryImage _decodeDataUrl(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  if (comma < 0) {
    // Malformed (no comma) — let errorBuilder render _BrokenImage.
    return MemoryImage(Uint8List(0));
  }
  final meta = dataUrl.substring(5, comma); // strip "data:" prefix
  final payload = dataUrl.substring(comma + 1);
  try {
    final Uint8List bytes;
    if (meta.contains('base64')) {
      bytes = base64Decode(payload);
    } else {
      // URL-encoded data: URL (rare for images; defensive).
      // Uri.dataFromString WRAPS the whole string as a new data: URI's text
      // content rather than parsing the existing one — it returned the ASCII
      // bytes of the literal `data:...` string, not the decoded image. Use
      // Uri.parse(...).data to actually decode it (review #2).
      bytes = Uri.parse(dataUrl).data?.contentAsBytes() ?? Uint8List(0);
    }
    return MemoryImage(bytes);
  } on FormatException {
    // Corrupt base64 — return empty bytes so Image's errorBuilder fires
    // (renders _BrokenImage) instead of crashing the widget tree.
    return MemoryImage(Uint8List(0));
  }
}
