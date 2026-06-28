import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/page_transition.dart';
import 'package:claw_hub/ui_kit/theme_color_utils.dart';

/// ClawHub global theme — Cool-Toned Dark Mode (V2).
///
/// All visual values are sourced from [XiaColors], [XiaSpacing], [XiaRadius],
/// [XiaShadow], and [XiaMotion] design token classes, aligning with the
/// design spec defined in docs/design/design-tokens-v2.md and
/// docs/design/component-spec-v2.md.
class AppTheme {
  AppTheme._();

  /// Manually constructed [ColorScheme] matching the V2 cool dark palette.
  static const _colorScheme = ColorScheme.dark(
    primary: XiaColors.accent,
    onPrimary: Color(0xFFEBEFFA),
    primaryContainer: XiaColors.accentMuted,
    secondary: XiaColors.accent2,
    onSecondary: Color(0xFFEBEFFA),
    secondaryContainer: XiaColors.accent2Muted,
    surface: XiaColors.surface,
    onSurface: XiaColors.text1,
    surfaceContainerHighest: XiaColors.surface2,
    surfaceContainerHigh: XiaColors.surface2,
    surfaceContainer: XiaColors.surface,
    surfaceDim: XiaColors.bg,
    outline: XiaColors.text3,
    outlineVariant: XiaColors.border,
    error: XiaColors.red,
    onError: XiaColors.text1,
    shadow: Colors.transparent,
  );

  static final _appBarTheme = AppBarTheme(
    elevation: 0,
    centerTitle: false,
    backgroundColor: XiaColors.bg,
    titleTextStyle: const TextStyle(
      fontSize: XiaTypography.heroTitle, // V2: 24px
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.15,
      color: XiaColors.text1,
    ),
    iconTheme: const IconThemeData(color: XiaColors.text2),
  );

  static final _cardTheme = CardThemeData(
    elevation: 0,
    color: XiaColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(XiaRadius.lg), // V2: 10px
      side: const BorderSide(color: XiaColors.border),
    ),
  );

  static final _inputDecorationTheme = InputDecorationTheme(
    filled: true,
    fillColor: XiaColors.surface2,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(XiaRadius.md), // V2: 8px
      borderSide: const BorderSide(color: XiaColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(XiaRadius.md),
      borderSide: const BorderSide(color: XiaColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(XiaRadius.md),
      borderSide: const BorderSide(color: XiaColors.accent, width: 1),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: XiaSpacing.s4, // V2: 12px
      vertical: XiaSpacing.s3, // V2: 8px
    ),
    hintStyle: const TextStyle(color: XiaColors.text4),
  );

  static const _iconTheme = IconThemeData(color: XiaColors.text2);

  /// The single dark theme applied via [ThemeMode.dark].
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _colorScheme,
    scaffoldBackgroundColor: XiaColors.bg,
    appBarTheme: _appBarTheme,
    cardTheme: _cardTheme,
    inputDecorationTheme: _inputDecorationTheme,
    iconTheme: _iconTheme,
    dividerColor: XiaColors.border, // V2 hairline divider
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: XiaPageTransitionsBuilder(),
        TargetPlatform.iOS: XiaPageTransitionsBuilder(),
      },
    ),
    textTheme: const TextTheme(
      // Map Material type scale keys to V2 design spec sizes
      displayLarge: TextStyle(
        fontSize: 24, // heroTitle — V2: 30 → 24
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.15,
      ),
      headlineLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 18, // sectionTitle — V2: 22 → 18
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        fontSize: 15, // subtitle — V2: 17 → 15
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        fontSize: 15, // agentName — V2: 16 → 15
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleSmall: TextStyle(
        fontSize: 14, // V2: 14 → 14 (unchanged)
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      bodyLarge: TextStyle(
        fontSize: 14, // body — V2: 15 → 14
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14, // V2: 14 → 14 (unchanged)
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        fontSize: 12, // aux — V2: 13 → 12
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 13, // V2 unchanged
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      labelMedium: TextStyle(
        fontSize: 12, // V2: 12 → 12 (unchanged)
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: TextStyle(
        fontSize: 11, // caption — V2: 11 → 11 (unchanged)
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    ),
  );
}

/// ClawHub color constants (sourced from [XiaColors] tokens).
///
/// Kept for backward compatibility — existing code references like
/// [AppColors.primaryBlue] and [AppColors.statusOnline] are preserved
/// but now resolve to the V2 design-spec values.
class AppColors {
  AppColors._();

  /// Brand accent — V2 sapphire blue #4F83FF.
  static const Color primaryBlue = XiaColors.accent;

  /// Agent theme color presets (12 colors from V2 design spec).
  static const List<Color> agentColors = XiaColors.agentColors;

  /// Health status colors — semantic colors from V2 design spec.
  static const Color statusOnline = XiaColors.green;
  static const Color statusOffline = XiaColors.text4;
  static const Color statusConnecting = XiaColors.yellow;
  static const Color statusExpectedOffline = XiaColors.text4;
  static const Color statusUnknown = XiaColors.text4;

  /// Message status colors.
  static const Color messageFailed = XiaColors.red;
  static const Color messageSending = XiaColors.text3;

  /// Unread badge — V2 uses red (#F87171) instead of accent for higher urgency.
  static const Color unreadBadge = XiaColors.red;
}

/// Color extension — hex parsing and WCAG contrast utilities.
extension ColorExtension on Color {
  /// Parse a color from hex string (#RGB / #RRGGBB).
  static Color fromHex(String hex) => parseHexColor(hex);

  /// Output 6-digit uppercase hex string (e.g. #4F83FF).
  String toHex() {
    final intValue = toARGB32();
    final r = (intValue >> 16) & 0xFF;
    final g = (intValue >> 8) & 0xFF;
    final b = intValue & 0xFF;
    return '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  /// Return black or white contrasting color using WCAG relative luminance.
  Color contrastingTextColor() => contrastTextColor(this);
}
