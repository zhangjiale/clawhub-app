/// 应用级客户端身份配置。
///
/// 集中管理客户端 ID、版本号等身份信息，
/// 避免在协议层硬编码。
class AppClientInfo {
  AppClientInfo._();

  /// 客户端标识（向 Gateway 注册时使用）。
  static const String id = 'clawhub-mobile';

  /// 客户端版本（应与 pubspec.yaml 保持同步）。
  static const String version = '1.0.0';

  /// 平台标识。
  static const String platform = 'flutter';

  /// 默认客户端角色。
  static const String role = 'operator';

  /// 默认授权范围。
  static const List<String> scopes = ['operator.read', 'operator.write'];
}

/// 默认地区（中文）。
const String defaultLocale = 'zh-CN';
