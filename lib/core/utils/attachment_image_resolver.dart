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
/// This is a pure function (no side effects, no I/O beyond lazy File handle
/// construction in [FileImage] — actual read happens in the image pipeline).
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

/// Decodes a `data:` URL to an [ImageProvider].
///
/// Format: `data:<mime>;base64,<payload>` or `data:<mime>,<url-encoded>`.
/// - base64 path: [base64Decode] the payload → [MemoryImage].
/// - non-base64 path: parse via [Uri.dataFromString] → [MemoryImage].
/// - corrupt input: return [MemoryImage] with empty bytes (errorBuilder path).
ImageProvider _dataUrlToImageProvider(String dataUrl) {
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
      bytes =
          Uri.dataFromString(dataUrl).data?.contentAsBytes() ?? Uint8List(0);
    }
    return MemoryImage(bytes);
  } on FormatException {
    // Corrupt base64 — return empty bytes so Image's errorBuilder fires
    // (renders _BrokenImage) instead of crashing the widget tree.
    return MemoryImage(Uint8List(0));
  }
}
