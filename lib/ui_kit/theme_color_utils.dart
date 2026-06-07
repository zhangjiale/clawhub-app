import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 主题色工具函数
/// 对齐: 架构 vFinal 5.7 (动态主题), WCAG 2.1 AA 标准
///
/// 提供 Hex 解析、WCAG 对比度计算、HSL 调整等纯函数。

/// 解析 Hex 颜色字符串为 Color
/// 支持 #RRGGBB, #RGB, RRGGBB 格式
Color parseHexColor(String hex) {
  hex = hex.replaceFirst('#', '').trim();
  if (hex.isEmpty) {
    throw ArgumentError('Hex color string cannot be empty');
  }

  // 3-digit shorthand: #F00 → FF0000
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }

  if (hex.length != 6) {
    throw ArgumentError('Invalid hex color length: $hex (expected 3 or 6 digits)');
  }

  final value = int.tryParse(hex, radix: 16);
  if (value == null) {
    throw ArgumentError('Invalid hex color: $hex');
  }

  return Color(0xFF000000 | value);
}

/// 计算两个颜色的 WCAG 2.1 对比度
/// 返回 [1.0, 21.0] 范围内的值
double wcagContrastRatio(Color color1, Color color2) {
  final l1 = _relativeLuminance(color1);
  final l2 = _relativeLuminance(color2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// 计算相对亮度 (sRGB)
double _relativeLuminance(Color color) {
  // Extract raw sRGB from int value for reliable computation
  // (avoids wide-gamut issues with Color.red/green/blue in Flutter 3.x)
  final intValue = color.value;
  final r = ((intValue >> 16) & 0xFF) / 255.0;
  final g = ((intValue >> 8) & 0xFF) / 255.0;
  final b = (intValue & 0xFF) / 255.0;

  double linearize(double channel) {
    if (channel <= 0.04045) return channel / 12.92;
    return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  final linR = linearize(r);
  final linG = linearize(g);
  final linB = linearize(b);
  return 0.2126 * linR + 0.7152 * linG + 0.0722 * linB;
}

/// 是否满足 WCAG AA 对比度标准 (≥ 4.5:1)
bool meetsWCAGAA(Color foreground, Color background) {
  return wcagContrastRatio(foreground, background) >= 4.5;
}
