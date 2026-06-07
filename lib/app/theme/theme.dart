import 'package:flutter/material.dart';
import 'package:claw_hub/ui_kit/theme_color_utils.dart';

/// ClawHub 全局应用主题
/// 对齐: 架构 vFinal 5.7 (动态主题), 8.2 (全局主题色)
class AppTheme {
  AppTheme._();

  // Shared sub-themes to avoid duplication between light and dark themes.
  static const _appBarTheme = AppBarTheme(centerTitle: true, elevation: 0);
  static final _cardTheme = CardThemeData(
    elevation: 1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
  static final _inputDecorationTheme = InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
  static const _fabTheme = FloatingActionButtonThemeData(elevation: 2);

  static ThemeData _baseTheme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        brightness: brightness,
      ),
      appBarTheme: _appBarTheme,
      cardTheme: _cardTheme,
      inputDecorationTheme: _inputDecorationTheme,
      floatingActionButtonTheme: _fabTheme,
    );
  }

  /// 浅色主题
  static final ThemeData lightTheme = _baseTheme(Brightness.light);

  /// 深色主题
  static final ThemeData darkTheme = _baseTheme(Brightness.dark);
}

/// ClawHub 全局颜色常量
class AppColors {
  AppColors._();

  /// 主色调 — ClawHub Blue
  static const Color primaryBlue = Color(0xFF007AFF);

  /// Agent 主题色预设（12 色）
  static const List<Color> agentColors = [
    Color(0xFF6C5CE7), // 紫色
    Color(0xFF0984E3), // 蓝色
    Color(0xFFFD79A8), // 粉色
    Color(0xFF00B894), // 绿色
    Color(0xFFE17055), // 橙色
    Color(0xFF00CEC9), // 青色
    Color(0xFFFDCB6E), // 黄色
    Color(0xFFE84393), // 玫红
    Color(0xFF636E72), // 灰蓝
    Color(0xFF2D3436), // 深灰
    Color(0xFF6AB04C), // 草绿
    Color(0xFF5352ED), // 靛蓝
  ];

  /// 健康状态颜色
  static const Color statusOnline = Color(0xFF34C759);
  static const Color statusOffline = Color(0xFFFF3B30);
  static const Color statusConnecting = Color(0xFFFF9500);
  static const Color statusExpectedOffline = Color(0xFF8E8E93);
  static const Color statusUnknown = Color(0xFFC8C8CD); // 浅灰，区别于预期离线

  /// 消息状态颜色
  static const Color messageFailed = Color(0xFFFF3B30);
  static const Color messageSending = Color(0xFF8E8E93);

  /// 未读角标
  static const Color unreadBadge = Color(0xFFFF3B30);
}

/// Color 扩展
extension ColorExtension on Color {
  /// 从 Hex 字符串解析颜色（委托给 ui_kit 的 parseHexColor，支持 #RGB/#RRGGBB 格式）
  static Color fromHex(String hex) => parseHexColor(hex);

  /// 输出 6 位 Hex 字符串（如 #007AFF）
  /// 使用位提取避免 Flutter 3.x 广色域下的值偏差
  String toHex() {
    final intValue = value;
    final r = (intValue >> 16) & 0xFF;
    final g = (intValue >> 8) & 0xFF;
    final b = intValue & 0xFF;
    return '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  /// 根据背景亮度返回对比文字颜色（黑或白）
  Color contrastingTextColor() {
    final luminance = computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
