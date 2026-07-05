import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/message.dart';
import 'attachment_encoder.dart';
import 'gateway_protocol.dart';
import 'outbound_message_serializer.dart';

/// Serializable input for [_buildChatSendRequestInIsolate].
///
/// Only primitives and plain Dart objects cross the isolate boundary.
final class _ChatSendBuildInput {
  final Message message;
  final String sessionKey;
  final String idempotencyKey;
  final String requestId;
  final int imageLimit;
  final int fileLimit;

  const _ChatSendBuildInput({
    required this.message,
    required this.sessionKey,
    required this.idempotencyKey,
    required this.requestId,
    required this.imageLimit,
    required this.fileLimit,
  });
}

/// Result of building a chat.send request inside a worker isolate.
sealed class _ChatSendBuildResult {
  const _ChatSendBuildResult();
}

final class _ChatSendBuildSuccess extends _ChatSendBuildResult {
  final String requestJson;
  final int payloadSize;

  const _ChatSendBuildSuccess(this.requestJson, this.payloadSize);
}

final class _ChatSendBuildTooLarge extends _ChatSendBuildResult {
  final int size;
  final int limit;

  const _ChatSendBuildTooLarge({required this.size, required this.limit});
}

final class _ChatSendBuildFailure extends _ChatSendBuildResult {
  final String error;

  const _ChatSendBuildFailure(this.error);
}

/// Worker isolate entry point.
///
/// Performs the entire outbound serialization chain in the worker so the main
/// isolate never allocates the intermediate base64 / attachments / JSON
/// strings. Returns the final JSON string and its UTF-8 byte count; the main
/// isolate only calls `_channel.sink.add(jsonString)`.
_ChatSendBuildResult _buildChatSendRequestInIsolate(_ChatSendBuildInput input) {
  final attachmentResult = _readAttachmentBase64Sync(
    input.message.type,
    input.message.content,
    input.imageLimit,
    input.fileLimit,
  );

  switch (attachmentResult) {
    case _AttachmentReadTooLarge(:final size, :final limit):
      return _ChatSendBuildTooLarge(size: size, limit: limit);
    case _AttachmentReadFailure(:final error):
      return _ChatSendBuildFailure(error);
    case _AttachmentReadSuccess(:final base64):
      try {
        final sendPayload = const OutboundMessageSerializer().serialize(
          input.message,
          base64Data: base64,
        );

        final params = <String, dynamic>{
          'sessionKey': input.sessionKey,
          'message': sendPayload.message,
          'idempotencyKey': input.idempotencyKey,
          if (sendPayload.attachments != null)
            'attachments': sendPayload.attachments,
        };

        final requestJson = buildRequest(
          id: input.requestId,
          method: Methods.chatSend,
          params: params,
        );

        final payloadSize = utf8.encode(requestJson).length;
        return _ChatSendBuildSuccess(requestJson, payloadSize);
      } catch (e) {
        return _ChatSendBuildFailure(e.toString());
      }
  }
}

/// Result of reading an attachment synchronously inside a worker isolate.
sealed class _AttachmentReadResult {
  const _AttachmentReadResult();
}

final class _AttachmentReadSuccess extends _AttachmentReadResult {
  final String? base64;

  const _AttachmentReadSuccess(this.base64);
}

final class _AttachmentReadTooLarge extends _AttachmentReadResult {
  final int size;
  final int limit;

  const _AttachmentReadTooLarge({required this.size, required this.limit});
}

final class _AttachmentReadFailure extends _AttachmentReadResult {
  final String error;

  const _AttachmentReadFailure(this.error);
}

/// Synchronous attachment read for use inside a worker isolate.
///
/// We intentionally do NOT call [AttachmentEncoder.encode] here because that
/// method itself spawns a worker isolate via [compute]. Running inside an
/// isolate, we can do synchronous file I/O directly without blocking the UI.
_AttachmentReadResult _readAttachmentBase64Sync(
  MessageType type,
  String? path,
  int imageLimit,
  int fileLimit,
) {
  final isAttachment = type == MessageType.image || type == MessageType.file;
  if (!isAttachment) return const _AttachmentReadSuccess(null);
  if (path == null || path.isEmpty) {
    return _AttachmentReadFailure('path missing for $type message');
  }

  final limit = type == MessageType.image ? imageLimit : fileLimit;
  final file = File(path);
  try {
    final size = file.lengthSync();
    if (size > limit) {
      return _AttachmentReadTooLarge(size: size, limit: limit);
    }
    final bytes = file.readAsBytesSync();
    return _AttachmentReadSuccess(base64Encode(bytes));
  } on FileSystemException catch (e) {
    return _AttachmentReadFailure(e.message);
  } catch (e) {
    return _AttachmentReadFailure(e.toString());
  }
}

/// Builds the full `chat.send` request JSON in a worker isolate.
///
/// The main isolate gets back the ready-to-send JSON string plus its UTF-8
/// byte count, which [ConnectionManager] uses for `maxPayload` /
/// `maxBufferedBytes` enforcement.
class OutboundRequestBuilder {
  static const int _imageLimit = 10 * 1024 * 1024;
  static const int _fileLimit = 5 * 1024 * 1024;

  const OutboundRequestBuilder();

  /// Builds the `chat.send` request JSON and returns its UTF-8 byte count.
  ///
  /// Text/toolCall messages take a synchronous main-isolate fast path (no
  /// large payload). Image/file messages are serialized in a worker isolate
  /// so the main isolate never allocates the intermediate base64 / JSON
  /// strings. Throws [AttachmentReadException] for missing / unreadable /
  /// too-large attachments.
  Future<({String requestJson, int payloadSize})> buildChatSendRequest({
    required Message message,
    required String sessionKey,
    required String idempotencyKey,
    required String requestId,
  }) async {
    final isAttachment =
        message.type == MessageType.image || message.type == MessageType.file;

    if (!isAttachment) {
      // Fast path: no file I/O, no large strings — build synchronously.
      final params = <String, dynamic>{
        'sessionKey': sessionKey,
        'message': message.content ?? '',
        'idempotencyKey': idempotencyKey,
      };
      final requestJson = buildRequest(
        id: requestId,
        method: Methods.chatSend,
        params: params,
      );
      final payloadSize = utf8.encode(requestJson).length;
      return (requestJson: requestJson, payloadSize: payloadSize);
    }

    // Slow path: read file + serialize + jsonEncode in worker isolate.
    final input = _ChatSendBuildInput(
      message: message,
      sessionKey: sessionKey,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
      imageLimit: _imageLimit,
      fileLimit: _fileLimit,
    );

    final result = await compute(_buildChatSendRequestInIsolate, input);

    switch (result) {
      case _ChatSendBuildSuccess(:final requestJson, :final payloadSize):
        return (requestJson: requestJson, payloadSize: payloadSize);
      case _ChatSendBuildTooLarge(:final size, :final limit):
        throw AttachmentReadException.tooLarge(
          size: size,
          limit: limit,
          type: message.type,
        );
      case _ChatSendBuildFailure(:final error):
        throw AttachmentReadException.readFailed(message.content ?? '', error);
    }
  }
}
