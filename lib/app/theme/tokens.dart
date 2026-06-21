import 'package:flutter/material.dart';

/// 虾Hub Design Tokens — single source of truth for all visual constants.
///
/// Translated from `docs/design/design-tokens-v2.md` Section 8.
/// V2 design system: cool-toned dark, sapphire blue (#4F83FF) primary,
/// violet (#9B7AFF) secondary, hairline borders replacing heavy surface
/// stacks, tighter 4pt grid spacing, smaller radii.

// ─── Color System ──────────────────────────────────────────────────────────

class XiaColors {
  XiaColors._();

  // Background hierarchy (cool dark tones — V2)
  static const Color bg = Color(0xFF08090D);
  static const Color surface = Color(0xFF0E1016);
  static const Color surface2 = Color(0xFF15171E);
  static const Color surface3 = Color(0xFF1C1F28);
  static const Color surfaceElevated = Color(0xFF12141B);

  // Hairline borders — V2's core visual separator (replaces surface stacking)
  /// 6% cool white — primary hairline divider color.
  static const Color border = Color(0x0FEBEFFA); // ~6% alpha on #EBEFFA

  /// 30% accent — emphasized border for selected / active states.
  static const Color borderAccent = Color(0x4D4F83FF);

  // Text (cool white base #EBEFFA, tonal opacity tiers — V2)
  static const Color text1 = Color(0xFFEBEFFA); // 100% — primary
  static const Color text2 = Color(0x8CEBEFFA); // 55%  — secondary
  static const Color text3 = Color(0x4DEBEFFA); // 30%  — tertiary
  static const Color text4 = Color(0x24EBEFFA); // 14%  — decorative

  // Brand accent — sapphire blue (V2)
  static const Color accent = Color(0xFF4F83FF);
  static const Color accentHover = Color(0xFF6B9AFF);
  static const Color accentMuted = Color(0x1A4F83FF); // 10% alpha
  static const Color accentGlow = Color(0x334F83FF); // 20% alpha

  // Secondary accent — violet (V2 — new slot)
  static const Color accent2 = Color(0xFF9B7AFF);
  static const Color accent2Muted = Color(0x1A9B7AFF); // 10% alpha

  // Tertiary — gold (V2 — new slot, for milestone celebration)
  static const Color gold = Color(0xFFE8C574);

  // Tier colors (V2 — replaces hardcoded silver/black54)
  /// Used for silver achievement tier background.
  static const Color silver = Color(0xFFCBD5E1);

  /// Modal scrim — 54% black for overlay backdrop.
  static const Color scrim = Color(0x8A000000);

  // Semantic — cooler/brighter for V2 dark theme
  static const Color green = Color(0xFF4ADE80);
  static const Color greenMuted = Color(0x1A4ADE80); // 10% alpha
  static const Color red = Color(0xFFF87171);
  static const Color redMuted = Color(0x14F87171); // 8% alpha
  static const Color yellow = Color(0xFFFBBF24);
  static const Color yellowMuted = Color(0x14FBBF24); // 8% alpha

  // Decorative — V2 hairline-friendly values
  /// Inline code background — 6% white.
  static const Color codeBlockBg = Color(0x0FEBEFFA);

  /// Search highlight background — 25% accent.
  static const Color searchHighlight = Color(0x404F83FF);

  // 12 agent theme colors (foreground color) — V2 cool-tone palette
  static const Map<String, Color> agentThemeColors = {
    'sapphire': Color(0xFF4F83FF),
    'violet': Color(0xFF9B7AFF),
    'cyan': Color(0xFF22D3EE),
    'emerald': Color(0xFF34D399),
    'amber': Color(0xFFFBBF24),
    'rose': Color(0xFFFB7185),
    'teal': Color(0xFF2DD4BF),
    'orange': Color(0xFFFB923C),
    'indigo': Color(0xFF818CF8),
    'pink': Color(0xFFF472B6),
    'lime': Color(0xFFA3E635),
    'slate': Color(0xFF94A3B8),
  };

  /// Agent theme background color (10% alpha version of the foreground).
  static Color agentThemeBg(String themeKey) {
    final color = agentThemeColors[themeKey] ?? agentThemeColors['sapphire']!;
    return color.withAlpha(26); // 10% ≈ 26/255
  }

  /// 12 agent theme colors as a List for use in ColorGrid pickers.
  /// Order MUST match V2 spec §1.5 (sapphire=0 .. slate=11) so the
  /// color grid picker aligns with [agentColorLabels].
  static const List<Color> agentColors = [
    Color(0xFF4F83FF), // sapphire
    Color(0xFF9B7AFF), // violet
    Color(0xFF22D3EE), // cyan
    Color(0xFF34D399), // emerald
    Color(0xFFFBBF24), // amber
    Color(0xFFFB7185), // rose
    Color(0xFF2DD4BF), // teal
    Color(0xFFFB923C), // orange
    Color(0xFF818CF8), // indigo
    Color(0xFFF472B6), // pink
    Color(0xFFA3E635), // lime
    Color(0xFF94A3B8), // slate
  ];

  /// Agent theme color label in Chinese (V2).
  static const Map<int, String> agentColorLabels = {
    0: '宝蓝',
    1: '紫罗兰',
    2: '青碧',
    3: '翡翠绿',
    4: '琥珀',
    5: '玫瑰',
    6: '湖蓝',
    7: '暖橙',
    8: '靛蓝',
    9: '烟粉',
    10: '青柠',
    11: '石墨',
  };
}

// ─── Spacing System (4pt grid — V2) ────────────────────────────────────────

class XiaSpacing {
  XiaSpacing._();

  static const double s1 = 2;
  static const double s2 = 6;
  static const double s3 = 8;
  static const double s4 = 12;
  static const double s5 = 16;

  /// Page horizontal padding (V2 tightens from 24 → 16).
  /// Previously aliased as s6; given a semantic name to avoid
  /// confusion with the generic s5 (also 16).
  static const double pagePaddingH = 16;
  static const double s7 = 24;
  static const double s8 = 32;
}

// ─── Border Radius System (V2 — tighter) ───────────────────────────────────

class XiaRadius {
  XiaRadius._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 14;
  static const double full = 999;
}

// ─── Shadow System (V2 — minimal; hairline borders replace cards) ──────────

class XiaShadow {
  XiaShadow._();

  /// Mid shadow for floating layers (banners, tooltips).
  static const List<BoxShadow> m = [
    BoxShadow(color: Color(0x40000000), offset: Offset(0, 4), blurRadius: 12),
  ];

  /// Large shadow for toast / elevated overlay.
  static const List<BoxShadow> l = [
    BoxShadow(color: Color(0x4D000000), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// Accent blue glow for primary buttons & send button.
  static const List<BoxShadow> glow = [
    BoxShadow(color: Color(0x264F83FF), blurRadius: 20),
  ];

  /// Online status dot green glow.
  static const List<BoxShadow> onlineGlow = [
    BoxShadow(color: Color(0xFF4ADE80), blurRadius: 6),
  ];

  /// Search highlight ring (V2 — replaces V1 selectedGlow).
  static const List<BoxShadow> accentRing = [
    BoxShadow(color: Color(0xFF4F83FF), spreadRadius: 2),
  ];
}

// ─── Motion Tokens (V2 — faster, no spring) ────────────────────────────────

class XiaMotion {
  XiaMotion._();

  /// Default easing curve (custom expo-out).
  static const Cubic ease = Cubic(0.16, 1, 0.3, 1);

  /// Standard deceleration curve.
  static const Cubic easeOut = Cubic(0.0, 0.0, 0.2, 1);

  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMid = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);
}

// ─── Typography Constants (V2 — overall 1-2px smaller) ─────────────────────

class XiaTypography {
  XiaTypography._();

  /// Default font family stack matching design spec.
  static const String fontFamily =
      '-apple-system, BlinkMacSystemFont, "SF Pro Display", '
      '"Helvetica Neue", "PingFang SC", sans-serif';

  /// Monospace font family for code blocks, URLs.
  static const String monoFontFamily = '"SF Mono", "Fira Code", monospace';

  // Source: docs/design/design-tokens-v2.md Section 2.2
  static const double heroTitle = 24; // V2: 30 → 24
  static const double sectionTitle = 18; // V2: 22 → 18
  static const double statValue = 18; // V2: 24 → 18
  static const double detailName = 18; // V2: 22 → 18
  static const double configAvatarName = 18; // V2: 20 → 18
  static const double subtitle = 15; // V2: 17 → 15
  static const double agentName = 15; // V2: 16 → 15
  static const double body = 14; // V2: 15 → 14
  static const double msgPreview = 13; // V2: 14 → 13
  static const double aux = 13;
  static const double sectionLabel = 11; // V2: 12 → 11
  static const double caption = 11;
  static const double navLabel = 10;
  static const double timestamp = 10; // V2: 11 → 10
}

// ─── Glassmorphism Constants (V2) ──────────────────────────────────────────

class XiaGlass {
  XiaGlass._();

  /// Bottom nav background — rgba(8,9,13,0.92).
  static const Color navBackground = Color(0xE108090D);

  /// Bottom nav blur radius (V2: 24 → 20).
  static const double navBlur = 20;

  /// Bottom nav saturation boost (V2: 1.4 → 1.3).
  static const double navSaturate = 1.3;

  /// Toast blur radius (unchanged).
  static const double toastBlur = 12;
}
