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

/// Precompiled alternation of all redacted keys（Dart 不缓存非字面量 RegExp，
/// 逐 key 编译会重复付 11 次编译成本）。只匹配到 `:` 后的空白，具体 value 用
/// [_findJsonValueEnd] 做 JSON-aware 扫描，从而覆盖 string / number / object /
/// array / boolean / null 全部类型（review finding #1）。key 全为字母数字，无需
/// regex 转义。
final RegExp _redactPattern = RegExp('"(${redactedKeys.join('|')})"\\s*:\\s*');

String _regexRedact(String s) {
  // Best-effort: malformed input must not crash the preview pipeline.
  try {
    final buffer = StringBuffer();
    var lastEnd = 0;
    for (final match in _redactPattern.allMatches(s)) {
      // 当前 match 若落在已脱敏的 value 区间内，则跳过（嵌套对象里多个 key 命中时）。
      if (match.start < lastEnd) continue;
      buffer.write(s.substring(lastEnd, match.end));
      final valueEnd = _findJsonValueEnd(s, match.end);
      buffer.write('"<redacted>"');
      lastEnd = valueEnd;
    }
    buffer.write(s.substring(lastEnd));
    return buffer.toString();
  } catch (_) {
    return s;
  }
}

int _findJsonValueEnd(String s, int start) {
  var i = start;
  while (i < s.length && _isJsonWhitespace(s.codeUnitAt(i))) {
    i++;
  }
  if (i >= s.length) return s.length;

  final first = s[i];
  if (first == '"') return _endOfString(s, i);
  if (first == '{') return _endOfStructured(s, i, '{', '}');
  if (first == '[') return _endOfStructured(s, i, '[', ']');

  // number / true / false / null：读到下一个 delimiter 为止。
  while (i < s.length) {
    final c = s[i];
    if (c == ',' || c == '}' || c == ']') break;
    i++;
  }
  return i;
}

bool _isJsonWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

int _endOfString(String s, int openQuote) {
  var i = openQuote + 1;
  while (i < s.length) {
    final c = s[i];
    if (c == '\\') {
      i += 2;
    } else if (c == '"') {
      return i + 1;
    } else {
      i++;
    }
  }
  return s.length;
}

int _endOfStructured(String s, int open, String openChar, String closeChar) {
  var depth = 1;
  var inString = false;
  var escaped = false;
  for (var i = open + 1; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
    } else {
      if (c == '"') {
        inString = true;
      } else if (c == openChar) {
        depth++;
      } else if (c == closeChar) {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
  }
  return s.length;
}

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
