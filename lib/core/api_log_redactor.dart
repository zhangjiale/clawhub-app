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
  // payloadSize 缺省时用字符数近似（避免对大帧 utf8.encode 造成 jank）
  final originalBytes = payloadSize ?? rawJson.length;
  final largeFrame = originalBytes > largeFrameThresholdBytes;

  try {
    if (largeFrame) return _regexFallback(rawJson, maxBytes, originalBytes);
    final decoded = jsonDecode(rawJson);
    _redactInPlace(decoded);
    return _truncate(jsonEncode(decoded), maxBytes, originalBytes);
  } catch (_) {
    // iron-law-allow: Law8 -- redactor 永不抛；畸形 JSON 走 regex 兜底
    return _regexFallback(rawJson, maxBytes, originalBytes);
  }
}

String _head(String s) => s.length > regexFallbackScanBytes
    ? s.substring(0, regexFallbackScanBytes)
    : s;

void _redactInPlace(Object? node) {
  if (node is Map) {
    // value-only put（node[key]=...）不触发结构性变更，Map.keys 迭代器保持有效，
    // 无需 .toList() 快照。
    for (final key in node.keys) {
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

/// JSON 字符串字面量匹配（含转义序列）。供 [_redactPattern] 的 value 部分复用。
///
/// 用 `(?:[^"\\]|\\.)*` 而非 `[^"]*`（ARB #6）：后者在遇到 `\"` 时停在第一个
/// 引号，导致含转义引号的 token/签名只脱敏前半段、尾部泄漏且破坏 preview 的 JSON
/// 合法性。`\\.` 正确吞掉 `\"`/`\\` 等转义序列，使整个字符串值被一次性脱敏。
const String _jsonStringPattern = r'"(?:[^"\\]|\\.)*"';

/// Precompiled alternation of all redacted keys（Dart 不缓存非字面量 RegExp，
/// 逐 key 编译会重复付 11 次编译成本）。单趟替换 `"key":"value"` ->
/// `"key":"<redacted>"`，match group 1 保留命中的具体 key 名。key 全为字母数字，
/// 无需 regex 转义。
final RegExp _redactPattern = RegExp(
  '"(${redactedKeys.join('|')})"\\s*:\\s*$_jsonStringPattern',
);

String _regexRedact(String s) =>
    s.replaceAllMapped(_redactPattern, (m) => '"${m[1]}":"<redacted>"');

/// 大帧 / 畸形 JSON 的统一脱敏+截断兜底路径。
String _regexFallback(String rawJson, int maxBytes, int originalBytes) =>
    _truncate(_regexRedact(_head(rawJson)), maxBytes, originalBytes);

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
