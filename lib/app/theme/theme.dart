import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/page_transition.dart';
import 'package:claw_hub/ui_kit/theme_color_utils.dart';

/// ClawHub global theme — Premium Dark Mode.
///
/// All visual values are sourced from [XiaColors], [XiaSpacing], [XiaRadius],
/// [XiaShadow], and [XiaMotion] design token classes, aligning with the
/// design spec defined in docs/DesignToken-虾Hub.md and
/// docs/ComponentSpec-虾Hub.md.
class AppTheme {
  AppTheme._();

  /// Manually constructed [ColorScheme] matching the warm dark palette.
  static const _colorScheme = ColorScheme.dark(
    primary: XiaColors.accent,
    onPrimary: XiaColors.text1,
    primaryContainer: XiaColors.accentMuted,
    surface: XiaColors.surface,
    onSurface: XiaColors.text1,
    surfaceContainerHighest: XiaColors.surface2,
    surfaceContainerHigh: XiaColors.surface2,
    surfaceContainer: XiaColors.surface,
    surfaceDim: XiaColors.bg,
    outline: XiaColors.text3,
    outlineVariant: XiaColors.text4,
    error: XiaColors.red,
    onError: XiaColors.text1,
    shadow: Colors.transparent,
  );

  static final _appBarTheme = AppBarTheme(
    elevation: 0,
    centerTitle: false,
    backgroundColor: XiaColors.bg,
    titleTextStyle: const TextStyle(
      fontSize: XiaTypography.heroTitle,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.2,
      color: XiaColors.text1,
    ),
    iconTheme: const IconThemeData(color: XiaColors.text2),
  );

  static final _cardTheme = CardThemeData(
    elevation: 0,
    color: XiaColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(XiaRadius.lg),
    ),
  );

  static final _inputDecorationTheme = InputDecorationTheme(
    filled: true,
    fillColor: XiaColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(XiaRadius.lg),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(XiaRadius.lg),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(XiaRadius.lg),
      borderSide: const BorderSide(color: XiaColors.accent, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: XiaSpacing.s5,
      vertical: XiaSpacing.s3,
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
    dividerColor: XiaColors.divider,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: XiaPageTransitionsBuilder(),
        TargetPlatform.iOS: XiaPageTransitionsBuilder(),
      },
    ),
    textTheme: const TextTheme(
      // Map Material type scale keys to design spec sizes
      displayLarge: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.2,
      ),
      headlineLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
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
/// but now resolve to the design-spec values.
class AppColors {
  AppColors._();

  /// Brand accent — #C27C68 desaturated coral (was purple #6C5CE7).
  static const Color primaryBlue = XiaColors.accent;

  /// Agent theme color presets (12 colors from design spec).
  static const List<Color> agentColors = XiaColors.agentColors;

  /// Health status colors — semantic colors from design spec.
  static const Color statusOnline = XiaColors.green;
  static const Color statusOffline = XiaColors.text4;
  static const Color statusConnecting = XiaColors.yellow;
  static const Color statusExpectedOffline = XiaColors.text4;
  static const Color statusUnknown = XiaColors.text4;

  /// Message status colors.
  static const Color messageFailed = XiaColors.red;
  static const Color messageSending = XiaColors.text3;

  /// Unread badge — branded accent instead of generic red.
  static const Color unreadBadge = XiaColors.accent;
}

/// Color extension — hex parsing and WCAG contrast utilities.
extension ColorExtension on Color {
  /// Parse a color from hex string (#RGB / #RRGGBB).
  static Color fromHex(String hex) => parseHexColor(hex);

  /// Output 6-digit uppercase hex string (e.g. #C27C68).
  String toHex() {
    final intValue = value;
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
