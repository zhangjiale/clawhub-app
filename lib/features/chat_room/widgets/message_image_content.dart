import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/core/utils/gateway_media_url.dart';
import 'package:claw_hub/ui_kit/attachment_image_resolver.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:flutter/material.dart';

/// Renders the image portion of a chat message bubble.
///
/// Extracted from [MessageBubble._buildImageContent] (P1 + P0 + P2 fix):
/// - **P0**: delegates to [resolveAttachmentImage] which decodes `data:` URLs
///   to [MemoryImage] (Agent inline base64 images), instead of feeding them
///   to `NetworkImage` (which only handles http/https and would render a
///   broken-image placeholder).
/// - **P1**: wraps the [Image] in a [RepaintBoundary] + [ConstrainedBox] and
///   sets `cacheWidth` so large source images (4000×3000 → ~48MB decoded)
///   are downsampled at decode time, avoiding OOM in long lists. Adds a
///   [loadingBuilder] placeholder.
/// - **P2**: no `dart:io` import here (lives in [resolveAttachmentImage]).
/// - **#1**: [mediaAuth] supplies the Gateway HTTP base URL + device token so
///   Agent reply images (relative `/api/chat/media/outgoing/...` URLs) resolve
///   to an authenticated absolute URL instead of failing in [NetworkImage].
///
/// Law 2 compliant: this widget renders UI only — all path/URL → ImageProvider
/// resolution is delegated to the core util.
class MessageImageContent extends StatelessWidget {
  final Message message;
  final bool isUser;
  final GatewayMediaAuth? mediaAuth;

  const MessageImageContent({
    super.key,
    required this.message,
    required this.isUser,
    this.mediaAuth,
  });

  @override
  Widget build(BuildContext context) {
    final provider = resolveAttachmentImage(
      imageUrl: message.imageUrl,
      imagePath: message.imagePath,
      gatewayBaseUrl: mediaAuth?.baseUrl,
      authToken: mediaAuth?.token,
    );
    if (provider == null) {
      return Text(
        '[图片]',
        style: TextStyle(
          color: isUser ? Colors.white : XiaColors.text2,
          fontSize: 14,
        ),
      );
    }
    // caption 由 domain getter 统一解析（用户图取 metadata.caption；
    // Agent 回图取 content 作图片描述）。
    final caption = message.displayCaption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 220),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(XiaRadius.lg),
              child: Image(
                image: ResizeImage(
                  provider,
                  width: (220 * MediaQuery.devicePixelRatioOf(context)).round(),
                ),
                width: 220,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const _ImageLoadingPlaceholder();
                },
                errorBuilder: (_, _, _) => const _BrokenImage(),
              ),
            ),
          ),
        ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              caption,
              style: TextStyle(
                color: isUser ? Colors.white : XiaColors.text1,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

/// 图片加载中占位(网络图 / 大文件解码期间)。
class _ImageLoadingPlaceholder extends StatelessWidget {
  const _ImageLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 120,
      color: XiaColors.surface3,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: XiaColors.text4,
        ),
      ),
    );
  }
}

/// 图片加载失败占位(本地文件被清理或 data: URL 损坏或网络图 404)。
class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 120,
      color: XiaColors.surface3,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: XiaColors.text4, size: 32),
          const SizedBox(height: 4),
          Text('图片不可用', style: TextStyle(color: XiaColors.text4, fontSize: 12)),
        ],
      ),
    );
  }
}
