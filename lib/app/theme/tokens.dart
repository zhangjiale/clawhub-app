import 'package:flutter/material.dart';

/// 虾Hub Design Tokens — single source of truth for all visual constants.
///
/// Translated from docs/design/design-tokens.md Section 8.
/// All spacing values follow the 8pt grid system.

// ─── Color System ──────────────────────────────────────────────────────────

class XiaColors {
  XiaColors._();

  // Background hierarchy (warm dark tones)
  static const Color bg = Color(0xFF111110);
  static const Color surface = Color(0xFF1A1917);
  static const Color surface2 = Color(0xFF232220);
  static const Color surface3 = Color(0xFF2C2B28);
  static const Color surfaceElevated = Color(0xFF1F1E1C);

  // Text (warm white base #F5F4F0, tonal opacity tiers)
  static const Color text1 = Color(0xFFF5F4F0); // 100% — primary
  static const Color text2 = Color(0x99F5F4F0); // 60%  — secondary
  static const Color text3 = Color(0x59F5F4F0); // 35%  — tertiary
  static const Color text4 = Color(0x2EF5F4F0); // 18%  — decorative

  // Brand accent (desaturated coral)
  static const Color accent = Color(0xFFC27C68);
  static const Color accentHover = Color(0xFFD08E7C);
  static const Color accentMuted = Color(0x1FC27C68); // 12% opacity
  static const Color accentGlow = Color(0x2EC27C68); // 18% opacity

  // Semantic
  static const Color green = Color(0xFF6BA87A);
  static const Color greenMuted = Color(0x266BA87A); // 15% opacity
  static const Color red = Color(0xFFC26464);
  static const Color redMuted = Color(0x1FC26464); // 12% opacity
  static const Color yellow = Color(0xFFC4A86A);
  static const Color yellowMuted = Color(0x1FC4A86A); // 12% opacity

  // Decorative
  static const Color divider = Color(0x0AF5F4F0); // rgba(245,244,240,0.04)
  static const Color codeBlockBg = Color(0x0FF5F4F0); // rgba(245,244,240,0.06)

  // 12 agent theme colors (foreground color)
  static const Map<String, Color> agentThemeColors = {
    'coral': Color(0xFFC27C68),
    'blue': Color(0xFF6C8AAF),
    'green': Color(0xFF6BA87A),
    'orange': Color(0xFFB98A64),
    'pink': Color(0xFFAF788C),
    'teal': Color(0xFF5F9B96),
    'yellow': Color(0xFFAF9B5F),
    'rose': Color(0xFFAA6E82),
    'slate': Color(0xFF828282),
    'indigo': Color(0xFF6E64A0),
    'caramel': Color(0xFFAA7D50),
    'jade': Color(0xFF509678),
  };

  /// Agent theme background color (12% alpha version of the foreground).
  static Color agentThemeBg(String themeKey) {
    final color = agentThemeColors[themeKey] ?? agentThemeColors['coral']!;
    return color.withAlpha(31); // 12% ≈ 31/255
  }

  /// 12 agent theme colors as a List for use in ColorGrid pickers.
  static const List<Color> agentColors = [
    Color(0xFFC27C68), // coral
    Color(0xFF6C8AAF), // blue
    Color(0xFF6BA87A), // green
    Color(0xFFB98A64), // orange
    Color(0xFFAF788C), // pink
    Color(0xFF5F9B96), // teal
    Color(0xFFAF9B5F), // yellow
    Color(0xFFAA6E82), // rose
    Color(0xFF828282), // slate
    Color(0xFF509678), // jade
    Color(0xFF6E64A0), // indigo
    Color(0xFFAA7D50), // caramel
  ];

  /// Agent theme color label in Chinese.
  static const Map<int, String> agentColorLabels = {
    0: '珊瑚',
    1: '雾蓝',
    2: '薄荷',
    3: '暖橙',
    4: '烟粉',
    5: '湖蓝',
    6: '暖黄',
    7: '玫瑰',
    8: '石墨',
    9: '翡翠',
    10: '靛蓝',
    11: '焦糖',
  };
}

// ─── Spacing System (8pt grid) ──────────────────────────────────────────────

class XiaSpacing {
  XiaSpacing._();

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24; // page horizontal padding
  static const double s7 = 32;
  static const double s8 = 40;
  static const double s9 = 48;
  static const double s10 = 56;
}

// ─── Border Radius System ───────────────────────────────────────────────────

class XiaRadius {
  XiaRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double full = 999;
}

// ─── Shadow System (warm-tone, pure black with alpha) ───────────────────────

class XiaShadow {
  XiaShadow._();

  static const List<BoxShadow> s = [
    BoxShadow(color: Color(0x2E000000), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> m = [
    BoxShadow(color: Color(0x33000000), offset: Offset(0, 4), blurRadius: 16),
  ];

  static const List<BoxShadow> l = [
    BoxShadow(color: Color(0x38000000), offset: Offset(0, 8), blurRadius: 32),
  ];

  static const List<BoxShadow> xl = [
    BoxShadow(color: Color(0x47000000), offset: Offset(0, 16), blurRadius: 48),
  ];

  /// Accent glow for primary buttons (brand color halo).
  static const List<BoxShadow> accentGlow = [
    BoxShadow(color: Color(0x2EC27C68), offset: Offset(0, 4), blurRadius: 20),
  ];

  /// Selected color dot glow (white halo).
  static const List<BoxShadow> selectedGlow = [
    BoxShadow(color: Color(0x26F5F4F0), blurRadius: 16),
  ];

  /// Online status dot green glow.
  static const List<BoxShadow> onlineGlow = [
    BoxShadow(color: Color(0xFF6BA87A), blurRadius: 8),
  ];
}

// ─── Motion Tokens ──────────────────────────────────────────────────────────

class XiaMotion {
  XiaMotion._();

  /// Default easing curve (custom expo-out).
  static const Cubic ease = Cubic(0.16, 1, 0.3, 1);

  /// Spring/overshoot curve for playful animations.
  static const Cubic easeSpring = Cubic(0.34, 1.56, 0.64, 1);

  /// Standard deceleration curve.
  static const Cubic easeOut = Cubic(0.0, 0.0, 0.2, 1);

  static const Duration durationFast = Duration(milliseconds: 200);
  static const Duration durationMid = Duration(milliseconds: 350);
  static const Duration durationSlow = Duration(milliseconds: 500);
}

// ─── Typography Constants ───────────────────────────────────────────────────

class XiaTypography {
  XiaTypography._();

  /// Default font family stack matching design spec.
  static const String fontFamily =
      '-apple-system, BlinkMacSystemFont, "SF Pro Display", '
      '"Helvetica Neue", "PingFang SC", sans-serif';

  /// Monospace font family for code blocks, URLs.
  static const String monoFontFamily = '"SF Mono", "Fira Code", monospace';

  // Source: docs/design/design-tokens.md Section 2.2
  static const double heroTitle = 30;
  static const double sectionTitle = 22;
  static const double statValue = 24;
  static const double configAvatarName = 20;
  static const double subtitle = 17;
  static const double agentName = 16;
  static const double body = 15;
  static const double msgPreview = 14;
  static const double aux = 13;
  static const double sectionLabel = 12;
  static const double caption = 11;
  static const double navLabel = 10;
}

// ─── Glassmorphism Constants ────────────────────────────────────────────────

class XiaGlass {
  XiaGlass._();

  /// Bottom nav background — rgba(17,17,16,0.88).
  static const Color navBackground = Color(0xE0111110);

  /// Bottom nav blur radius.
  static const double navBlur = 24;

  /// Bottom nav saturation boost.
  static const double navSaturate = 1.4;

  /// Toast blur radius.
  static const double toastBlur = 12;
}
