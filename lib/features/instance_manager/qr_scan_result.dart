import 'dart:convert';

/// OpenClaw Gateway 二维码扫描结果
/// 对齐: PRD 3.1 US-001 (扫码添加实例)
class QrScanResult {
  final String? name;
  final String gatewayUrl;
  final String? token;

  const QrScanResult({
    this.name,
    required this.gatewayUrl,
    this.token,
  });

  /// 从 JSON 字符串解析
  ///
  /// 预期格式: {"gatewayUrl":"wss://...", "name":"...", "token":"..."}
  /// "type":"openclaw-gateway" 字段为可选项。
  factory QrScanResult.fromJsonString(String jsonString) {
    // ignore: depend_on_referenced_packages
    return QrScanResult.fromMap(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// 从已解析的 Map 创建
  factory QrScanResult.fromMap(Map<String, dynamic> json) {
    final gatewayUrl = json['gatewayUrl'] as String?;
    if (gatewayUrl == null || gatewayUrl.trim().isEmpty) {
      throw const FormatException('二维码缺少 gatewayUrl 字段');
    }
    final trimmed = gatewayUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || (!uri.scheme.startsWith('ws'))) {
      throw const FormatException('gatewayUrl 必须是 ws:// 或 wss:// 格式的 URL');
    }
    return QrScanResult(
      name: json['name'] as String?,
      gatewayUrl: trimmed,
      token: json['token'] as String?,
    );
  }
}
