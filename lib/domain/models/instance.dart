import 'enums.dart';

/// 实例实体
/// 对齐: 架构 vFinal 4.0 (核心领域模型), 5.1 (ACL 状态机), 5.6 (网络环境感知)
///
/// 每个 Instance 代表一个 OpenClaw Gateway 连接配置
class Instance {
  final String id; // UUID, 业务主键
  final String name; // 实例名称，不可为空，不可重复
  final String gatewayUrl; // ws://... 或 wss://...，含端口号
  final String tokenRef; // iOS Keychain / Android Keystore 引用 Key
  final HealthStatus healthStatus;
  final bool isLocalNetwork; // 是否为内网 IP
  final int? lastConnectedAt; // 最后连接成功时间戳(秒)
  final int createdAt; // 创建时间(秒)

  Instance({
    required this.id,
    required this.name,
    required this.gatewayUrl,
    required this.tokenRef,
    this.healthStatus = HealthStatus.unknown,
    bool? isLocalNetwork,
    this.lastConnectedAt,
    int? createdAt,
  })  : isLocalNetwork = isLocalNetwork ?? _detectLocalNetwork(gatewayUrl),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 {
    _validate();
  }

  void _validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError('实例名称不能为空');
    }
    if (!isValidGatewayUrl(gatewayUrl)) {
      throw ArgumentError(
        'Gateway URL 格式不合法，必须以 ws:// 或 wss:// 开头且包含端口号',
      );
    }
  }

  /// 检测是否为内网 IP
  static final _localIpPatterns = [
    RegExp(r'^127\.\d+\.\d+\.\d+$'),
    RegExp(r'^10\.\d+\.\d+\.\d+$'),
    RegExp(r'^172\.(1[6-9]|2\d|3[01])\.\d+\.\d+$'),
    RegExp(r'^192\.168\.\d+\.\d+$'),
    RegExp(r'^localhost$', caseSensitive: false),
  ];

  static bool _detectLocalNetwork(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host;

    return _localIpPatterns.any((p) => p.hasMatch(host));
  }

  /// 校验 Gateway URL 格式（公开，供 UI 层复用）
  static bool isValidGatewayUrl(String url) {
    if (url.trim().isEmpty) return false;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // 必须是 ws:// 或 wss://
    if (uri.scheme != 'ws' && uri.scheme != 'wss') return false;

    // 必须有端口号
    if (!uri.hasPort) return false;

    // 必须有 host
    if (uri.host.isEmpty) return false;

    return true;
  }

  Instance copyWith({
    String? id,
    String? name,
    String? gatewayUrl,
    String? tokenRef,
    HealthStatus? healthStatus,
    bool? isLocalNetwork,
    int? lastConnectedAt,
    int? createdAt,
  }) {
    return Instance(
      id: id ?? this.id,
      name: name ?? this.name,
      gatewayUrl: gatewayUrl ?? this.gatewayUrl,
      tokenRef: tokenRef ?? this.tokenRef,
      healthStatus: healthStatus ?? this.healthStatus,
      isLocalNetwork: isLocalNetwork ?? this.isLocalNetwork,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Instance &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Instance(id: $id, name: $name, gatewayUrl: $gatewayUrl, healthStatus: $healthStatus)';
}
