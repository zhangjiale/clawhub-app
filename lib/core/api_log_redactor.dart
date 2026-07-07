import 'dart:convert';

/// RE-AUDIT WHEN: gateway_protocol.dart 加新方法/凭据字段 → 审计 [redactedKeys]
/// 是否覆盖（spec §3.2 协议升级审计）。
const Set<String> redactedKeys = {
  'token',
  'deviceToken',
  'signature',
  'signPayload',
  'nonce',
  'secret',
  'password',
  'accessToken',
  'refreshToken',
  // 防御性：协议若新增这些字段名也覆盖
  'authToken',
  'sessionToken',
  'bearerToken',
};

const int defaultMaxPayloadPreviewBytes = 2048; // 最终 preview 截断
const int largeFrameThresholdBytes = 65536; // >此值跳过 jsonDecode 走 regex
const int regexFallbackScanBytes = 8192; // regex 兜底只扫前 N 字节

/// 脱敏 + 截断（truncate-then-parse，保护热路径，spec §3.2）。
///
/// 解析成本 O(阈值) 而非 O(payloadSize)：大帧（payloadSize > [largeFrameThresholdBytes]）
/// 跳过 jsonDecode，在前 [regexFallbackScanBytes] 子串上跑 regex 脱敏；小帧结构化脱敏。
/// 最终按 [maxBytes] 截断并附 `…(truncated, N bytes total)` marker。永不抛。
String redactAndTruncate(
  String rawJson, {
  int maxBytes = defaultMaxPayloadPreviewBytes,
  int? payloadSize,
}) {
  final int originalBytes;
  final bool largeFrame;
  if (payloadSize != null) {
    originalBytes = payloadSize;
    largeFrame = payloadSize > largeFrameThresholdBytes;
  } else {
    // 无 payloadSize 时用字符数近似（避免对大帧 utf8.encode 造成 jank）
    originalBytes = rawJson.length;
    largeFrame = rawJson.length > largeFrameThresholdBytes;
  }

  try {
    if (largeFrame) {
      return _truncate(_regexRedact(_head(rawJson)), maxBytes, originalBytes);
    }
    final decoded = jsonDecode(rawJson);
    _redactInPlace(decoded);
    return _truncate(jsonEncode(decoded), maxBytes, originalBytes);
  } catch (_) {
    // iron-law-allow: Law8 -- redactor 永不抛；畸形 JSON 走 regex 兜底
    return _truncate(_regexRedact(_head(rawJson)), maxBytes, originalBytes);
  }
}

String _head(String s) => s.length > regexFallbackScanBytes
    ? s.substring(0, regexFallbackScanBytes)
    : s;

void _redactInPlace(Object? node) {
  if (node is Map) {
    for (final key in node.keys.toList()) {
      if (redactedKeys.contains(key)) {
        node[key] = '<redacted>';
      } else {
        _redactInPlace(node[key]);
      }
    }
  } else if (node is List) {
    for (int i = 0; i < node.length; i++) {
      _redactInPlace(node[i]);
    }
  }
}

String _regexRedact(String s) {
  var result = s;
  for (final key in redactedKeys) {
    result = result.replaceAll(
      RegExp('"$key"\\s*:\\s*"[^"]*"'),
      '"$key":"<redacted>"',
    );
  }
  return result;
}

String _truncate(String s, int maxBytes, int originalBytes) {
  final bytes = utf8.encode(s);
  if (bytes.length <= maxBytes) return s;
  // 回退到 UTF-8 字符边界，避免切到多字节字符中间
  var cut = maxBytes;
  while (cut > 0 && (bytes[cut] & 0xC0) == 0x80) {
    cut--;
  }
  final truncated = utf8.decode(bytes.sublist(0, cut), allowMalformed: true);
  return '$truncated…(truncated, $originalBytes bytes total)';
}
