import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/models/enums.dart';
import '../../domain/utils/format_bytes.dart';

/// Typed exception for attachment (image/file) read failures in the ACL.
///
/// Thrown by [AttachmentEncoder.encode] when:
///   - the attachment path is missing/empty
///   - the file doesn't exist or can't be read (original cause preserved)
///   - the file exceeds the inline-attachment size limit
///
/// Propagates out of [WsGatewayClient.sendMessage] and is caught by the UseCase
/// layer, which marks the message FAILED. Implementing [Exception] preserves
/// backward-compat with broad `catch (e)` / `on Exception` handlers.
class AttachmentReadException implements Exception {
  final String reason;
  final String? path;
  final Object? cause;

  AttachmentReadException(this.reason, {this.path, this.cause});

  /// File size exceeds the inline-attachment limit.
  ///
  /// Sizes are formatted via [formatBytes] (one-decimal B/KB/MB). Pre-fix the
  /// inline `${size ~/ 1024 ~/ 1024}MB` floored both size and limit to integer
  /// MB, so a 5.5 MB file over a 5.0 MB limit rendered as the contradictory
  /// "5MB > 5MB limit", and sub-MB sizes collapsed to "0MB" (review #14).
  factory AttachmentReadException.tooLarge({
    required int size,
    required int limit,
    required MessageType type,
  }) {
    return AttachmentReadException(
      'Attachment too large (${formatBytes(size)} > '
      '${formatBytes(limit)} limit for $type; see appendix F.6 — '
      'use OSS URL for large files)',
    );
  }

  /// File read failed (missing, permission, I/O). Preserves [cause].
  factory AttachmentReadException.readFailed(String path, Object cause) {
    return AttachmentReadException(
      'Failed to read attachment $path',
      path: path,
      cause: cause,
    );
  }

  @override
  String toString() {
    final p = path != null ? ', path: $path' : '';
    final c = cause != null ? ', cause: $cause' : '';
    return 'AttachmentReadException($reason$p$c)';
  }
}

/// Serializable input for [_encodeAttachmentInIsolate].
/// Only primitives cross the isolate boundary.
final class _AttachmentReadInput {
  const _AttachmentReadInput({required this.path, required this.limit});
  final String path;
  final int limit;
}

/// Result of reading an attachment inside a worker isolate.
sealed class _AttachmentReadResult {
  const _AttachmentReadResult();
}

final class _AttachmentReadSuccess extends _AttachmentReadResult {
  const _AttachmentReadSuccess(this.base64);
  final String base64;
}

final class _AttachmentReadTooLarge extends _AttachmentReadResult {
  const _AttachmentReadTooLarge({required this.size, required this.limit});
  final int size;
  final int limit;
}

final class _AttachmentReadFailure extends _AttachmentReadResult {
  const _AttachmentReadFailure(this.error);
  final String error;
}

/// Worker isolate entry point: reads the file, enforces the size limit and
/// encodes the bytes to base64. Returns a typed result so the main isolate can
/// map it back to domain exceptions without losing type safety.
_AttachmentReadResult _encodeAttachmentInIsolate(_AttachmentReadInput input) {
  final file = File(input.path);
  try {
    final size = file.lengthSync();
    if (size > input.limit) {
      return _AttachmentReadTooLarge(size: size, limit: input.limit);
    }
    final bytes = file.readAsBytesSync();
    return _AttachmentReadSuccess(base64Encode(bytes));
  } on FileSystemException catch (e) {
    return _AttachmentReadFailure(e.message);
  } catch (e) {
    return _AttachmentReadFailure(e.toString());
  }
}

/// Gateway 附件编码器。
///
/// 负责从本地文件路径读取 image/file 内容并编码为 base64。所有重 I/O 工作都
/// 通过 [compute] 下沉到 worker isolate，避免阻塞主 isolate。
class AttachmentEncoder {
  /// Image 内联大小上限（appendix F.6）。
  static const int _imageLimit = 10 * 1024 * 1024;

  /// File 内联大小上限（appendix F.6）。
  static const int _fileLimit = 5 * 1024 * 1024;

  const AttachmentEncoder();

  /// Reads the local attachment file at [path] and returns its base64-encoded
  /// bytes, or `null` if [type] does not require a file read.
  ///
  /// Throws [AttachmentReadException] if the path is missing, the file can't be
  /// read, or it exceeds the inline-attachment size limit.
  Future<String?> encode({
    required MessageType type,
    required String? path,
  }) async {
    final isAttachment = type == MessageType.image || type == MessageType.file;
    if (!isAttachment) return null;
    if (path == null || path.isEmpty) {
      throw AttachmentReadException('path missing for $type message');
    }
    final limit = type == MessageType.image ? _imageLimit : _fileLimit;

    final result = await compute(
      _encodeAttachmentInIsolate,
      _AttachmentReadInput(path: path, limit: limit),
    );

    switch (result) {
      case _AttachmentReadSuccess(:final base64):
        return base64;
      case _AttachmentReadTooLarge(:final size, :final limit):
        throw AttachmentReadException.tooLarge(
          size: size,
          limit: limit,
          type: type,
        );
      case _AttachmentReadFailure(:final error):
        throw AttachmentReadException.readFailed(path, error);
    }
  }
}
