import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;

/// 返回当前操作系统的标识字符串，兼容所有 Flutter 平台（包括 Web）。
///
/// 不使用 `dart:io`（Web 不可用），改用 [defaultTargetPlatform]
/// + [kIsWeb]。返回值与 [dart:io.Platform.operatingSystem] 一致：
/// `'ios'`, `'android'`, `'macos'`, `'linux'`, `'windows'`；
/// Web 平台返回 `'web'`。
String platformOS() {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform.name.toLowerCase();
}
