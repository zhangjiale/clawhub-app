import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// 读取设备型号标识，用于 Gateway 握手时上报 `client.modelIdentifier`。
///
/// **返回值** (可空,best-effort):
/// - iOS: `IosDeviceInfo.model` (如 "iPhone" / "iPad")— 模拟器稳定
/// - Android: `AndroidDeviceInfo.manufacturer + model` (如 "Google Pixel 7")
/// - Web / macOS / Windows / Linux / 任何异常: **null**
///
/// **重要约束** (Law 8):任何失败(platform channel 异常、OS 不支持、
/// 信息缺失)都**返回 null**。`WsGatewayClient` 在协议层会用 `if != null`
/// 跳过该字段,绝不会让 connect 失败。
///
/// **缓存**:在 `app/di/providers.dart` 中通过 `deviceModelIdentifierProvider`
/// 包装为 FutureProvider,结果对所有后续连接复用。
///
/// **依赖**:需在 `pubspec.yaml` 添加 `device_info_plus: ^11.0.0`。
/// iOS 额外需要 `cd ios && pod install`;Android 要求 `minSdkVersion >= 21`。
Future<String?> loadDeviceModelIdentifier() async {
  // Web + 桌面:device_info_plus 支持有限或语义不同,直接短路。
  // 避免 macOS 缺少 entitlement / Windows 注册表访问失败等噪音。
  if (kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux) {
    return null;
  }

  try {
    final info = await DeviceInfoPlugin().deviceInfo;
    // 仅 iOS / Android 路径会进入这里(其他平台已在上方短路)。
    return switch (info) {
      IosDeviceInfo() => info.model,
      AndroidDeviceInfo() => _formatAndroidModel(info),
      _ => null,
    };
  } catch (_) {
    // iron-law-allow: Law8 -- device_info_plus 失败必须 best-effort 返回 null,
    // 协议层会用 if != null 跳过该字段,不能让 connect 失败。
    return null;
  }
}

/// "Google Pixel 7" 风格拼接 — manufacturer 和 model 各自做 trim,
/// 任何一方为空时回退到另一方,都为空才返回 null。
String? _formatAndroidModel(AndroidDeviceInfo info) {
  final mfr = info.manufacturer.trim();
  final mdl = info.model.trim();
  if (mfr.isEmpty) return mdl.isEmpty ? null : mdl;
  return mdl.isEmpty ? mfr : '$mfr $mdl';
}
