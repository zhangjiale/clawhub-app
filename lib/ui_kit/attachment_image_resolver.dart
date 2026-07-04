import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

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
/// (least-recently-used). 16 entries bounds raw-bytes retention (data URLs can
/// be MB-scale) while covering a conversation's visible inline-image bubbles.
const int _dataUrlImageCacheLimit = 16;
final Map<String, ImageProvider> _dataUrlImageCache = {};

/// Decodes a `data:` URL to an [ImageProvider], memoized per URL.
///
/// Format: `data:<mime>;base64,<payload>` or `data:<mime>,<url-encoded>`.
/// - base64 path: [base64Decode] the payload → [MemoryImage].
/// - non-base64 path: parse via [Uri.dataFromString] → [MemoryImage].
/// - corrupt input: return [MemoryImage] with empty bytes (errorBuilder path).
ImageProvider _dataUrlToImageProvider(String dataUrl) {
  final cached = _dataUrlImageCache[dataUrl];
  if (cached != null) {
    // LRU refresh: move to most-recently-used so the entry survives eviction.
    _dataUrlImageCache.remove(dataUrl);
    _dataUrlImageCache[dataUrl] = cached;
    return cached;
  }

  final provider = _decodeDataUrl(dataUrl);
  if (_dataUrlImageCache.length >= _dataUrlImageCacheLimit) {
    _dataUrlImageCache.remove(_dataUrlImageCache.keys.first);
  }
  _dataUrlImageCache[dataUrl] = provider;
  return provider;
}

ImageProvider _decodeDataUrl(String dataUrl) {
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
