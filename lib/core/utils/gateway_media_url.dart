/// Pure-Dart helpers for resolving Gateway media URLs.
///
/// Agent reply images arrive as **relative** paths
/// (`/api/chat/media/outgoing/<id>/full` or `/__openclaw__/assistant-media?...`)
/// — see docs/technical/openclaw-media-protocol.md and the captured packet at
/// docs/technical/图片抓包.txt. [NetworkImage] requires an absolute http(s) URL,
/// and the Gateway media endpoints require Bearer auth (§6.2). These helpers
/// turn a relative media URL into an absolute one and signal whether the caller
/// should attach the Gateway device token as auth.
///
/// Pure Dart (no Flutter / Riverpod / drift) — Law 1-safe, unit-testable.
library;

/// Derives the HTTP(S) base URL (`scheme://host:port`) from a Gateway WebSocket
/// URL (`ws://` → `http://`, `wss://` → `https://`).
///
/// Returns `null` if [wsUrl] is not a valid `ws`/`wss` URL. Path and query are
/// dropped — callers join the relative media path onto the bare base.
String? httpBaseFromWsUrl(String wsUrl) {
  if (wsUrl.isEmpty) return null;
  final uri = Uri.tryParse(wsUrl);
  if (uri == null) return null;
  final String scheme;
  switch (uri.scheme) {
    case 'ws':
      scheme = 'http';
    case 'wss':
      scheme = 'https';
    default:
      return null;
  }
  if (uri.host.isEmpty) return null;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '$scheme://${uri.host}$port';
}

/// The result of resolving a media URL: the absolute [url] to fetch, and
/// [needsAuth] — true when the URL was a Gateway-relative path that requires a
/// `Bearer` device token (vs. a public CDN / inline data: URL).
typedef ResolvedMediaUrl = ({String url, bool needsAuth});

/// Resolves a Gateway media [imageUrl] against [gatewayBaseUrl].
///
/// - Absolute `http(s)` and `data:` URLs are returned unchanged with
///   `needsAuth: false` (public CDN or inline base64 — no token attached, to
///   avoid leaking the device token to third-party hosts).
/// - Relative URLs (leading `/`) are joined onto [gatewayBaseUrl] and flagged
///   `needsAuth: true` so the caller can attach the Bearer header.
/// - A relative URL with no [gatewayBaseUrl] is returned as-is with
///   `needsAuth: false` (cannot resolve — will fail to load, but no crash and
///   no spurious auth).
ResolvedMediaUrl resolveGatewayMediaUrl(
  String imageUrl, {
  String? gatewayBaseUrl,
}) {
  if (imageUrl.startsWith('http://') ||
      imageUrl.startsWith('https://') ||
      imageUrl.startsWith('data:')) {
    return (url: imageUrl, needsAuth: false);
  }
  if (imageUrl.startsWith('/') && gatewayBaseUrl != null) {
    // Strip a trailing slash on the base so we never produce `//` in the join.
    final base = gatewayBaseUrl.endsWith('/')
        ? gatewayBaseUrl.substring(0, gatewayBaseUrl.length - 1)
        : gatewayBaseUrl;
    return (url: '$base$imageUrl', needsAuth: true);
  }
  return (url: imageUrl, needsAuth: false);
}

/// Bundles the Gateway HTTP base URL + device token for a given instance, used
/// to authenticate media fetches. Both nullable: `null` base = cannot resolve
/// relative URLs; `null` token = unauthenticated (will 401 on protected media).
class GatewayMediaAuth {
  final String? baseUrl;
  final String? token;

  const GatewayMediaAuth({this.baseUrl, this.token});
}
