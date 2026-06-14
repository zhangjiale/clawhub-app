# UI Design Token Alignment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the Flutter app's visual layer with the premium dark-mode design spec by introducing design token constants, rewriting ThemeData, updating 20+ component styles, and adding glassmorphism + motion effects.

**Architecture:** Token constants (`tokens.dart`) → ThemeData rewrite (`theme.dart`) → component-by-component style alignment (colors, spacing, radii, shadows replaced with token references) → glassmorphism/motion (new toast widget, custom page transition) → page layout adjustments. All changes are visual-layer only — zero business logic changes.

**Tech Stack:** Flutter, Riverpod, `flutter_markdown`, Material 3

**Prerequisite:** The `master` branch has concurrent work on WebSocket/connection layer. Create a new branch `feat/ui-design-token-alignment` from `master` at implementation time. Merge or rebase after both branches land.

---

### Task 1: Create feature branch and token constants file

**Files:**
- Create: `lib/app/theme/tokens.dart`

- [ ] **Step 1: Create feature branch**

```bash
git checkout master
git checkout -b feat/ui-design-token-alignment
```

- [ ] **Step 2: Create `lib/app/theme/tokens.dart`**

```dart
import 'package:flutter/material.dart';

/// 虾Hub Design Tokens — single source of truth for all visual constants.
///
/// Translated from docs/DesignToken-虾Hub.md Section 8.
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
  static const Color text1 = Color(0xFFF5F4F0);       // 100% — primary
  static const Color text2 = Color(0x99F5F4F0);       // 60%  — secondary
  static const Color text3 = Color(0x59F5F4F0);       // 35%  — tertiary
  static const Color text4 = Color(0x2EF5F4F0);       // 18%  — decorative

  // Brand accent (desaturated coral)
  static const Color accent = Color(0xFFC27C68);
  static const Color accentHover = Color(0xFFD08E7C);
  static const Color accentMuted = Color(0x1FC27C68);  // 12% opacity
  static const Color accentGlow = Color(0x2EC27C68);   // 18% opacity

  // Semantic
  static const Color green = Color(0xFF6BA87A);
  static const Color greenMuted = Color(0x266BA87A);   // 15% opacity
  static const Color red = Color(0xFFC26464);
  static const Color redMuted = Color(0x1FC26464);     // 12% opacity
  static const Color yellow = Color(0xFFC4A86A);

  // Decorative
  static const Color divider = Color(0x0AF5F4F0);      // rgba(245,244,240,0.04)
  static const Color codeBlockBg = Color(0x0FF5F4F0);  // rgba(245,244,240,0.06)

  // 12 agent theme colors (foreground color + 12% alpha background)
  static const Map<String, Color> agentThemeColors = {
    'coral':   Color(0xFFC27C68),
    'blue':    Color(0xFF6C8AAF),
    'green':   Color(0xFF6BA87A),
    'orange':  Color(0xFFB98A64),
    'pink':    Color(0xFFAF788C),
    'teal':    Color(0xFF5F9B96),
    'yellow':  Color(0xFFAF9B5F),
    'rose':    Color(0xFFAA6E82),
    'slate':   Color(0xFF828282),
    'indigo':  Color(0xFF6E64A0),
    'caramel': Color(0xFFAA7D50),
    'jade':    Color(0xFF509678),
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
    0: '珊瑚', 1: '雾蓝', 2: '薄荷', 3: '暖橙',
    4: '烟粉', 5: '湖蓝', 6: '暖黄', 7: '玫瑰',
    8: '石墨', 9: '翡翠', 10: '靛蓝', 11: '焦糖',
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
  static const double s6 = 24;   // page horizontal padding
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
    BoxShadow(
      color: Color(0x2E000000),
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const List<BoxShadow> m = [
    BoxShadow(
      color: Color(0x33000000),
      offset: Offset(0, 4),
      blurRadius: 16,
    ),
  ];

  static const List<BoxShadow> l = [
    BoxShadow(
      color: Color(0x38000000),
      offset: Offset(0, 8),
      blurRadius: 32,
    ),
  ];

  static const List<BoxShadow> xl = [
    BoxShadow(
      color: Color(0x47000000),
      offset: Offset(0, 16),
      blurRadius: 48,
    ),
  ];

  /// Accent glow for primary buttons (brand color halo).
  static const List<BoxShadow> accentGlow = [
    BoxShadow(
      color: Color(0x2EC27C68),
      offset: Offset(0, 4),
      blurRadius: 20,
    ),
  ];

  /// Selected color dot glow (white halo).
  static const List<BoxShadow> selectedGlow = [
    BoxShadow(
      color: Color(0x26F5F4F0),
      blurRadius: 16,
    ),
  ];

  /// Online status dot green glow.
  static const List<BoxShadow> onlineGlow = [
    BoxShadow(
      color: Color(0xFF6BA87A),
      blurRadius: 8,
    ),
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

  // Source: docs/DesignToken-虾Hub.md Section 2.2
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
```

- [ ] **Step 3: Verify the file compiles**

```bash
flutter analyze lib/app/theme/tokens.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/app/theme/tokens.dart
git commit -m "feat(ui): add XiaHub design token constants (colors, spacing, radius, shadow, motion)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Rewrite AppTheme with manual ColorScheme.dark

**Files:**
- Modify: `lib/app/theme/theme.dart`

- [ ] **Step 1: Replace the entire theme.dart file**

Rewrite `lib/app/theme/theme.dart` to replace `ColorScheme.fromSeed` with a manually constructed `ColorScheme.dark()` and update `AppColors` to reference tokens.

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/theme_color_utils.dart';

/// ClawHub 全局应用主题 — Premium Dark Mode.
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
    textTheme: const TextTheme(
      // Map Material type scale keys to design spec sizes
      displayLarge: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.2),
      headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.3),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.3),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.1),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.55),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5),
      bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.4),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.3),
    ),
  );
}

/// ClawHub color constants (now sourced from [XiaColors] tokens).
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
```

- [ ] **Step 2: Switch main.dart to always-dark mode**

Edit `lib/main.dart` line 135:

```dart
        themeMode: ThemeMode.dark, // was ThemeMode.system
```

- [ ] **Step 3: Verify no build errors**

```bash
flutter analyze
```

Expected: zero new warnings/errors.

- [ ] **Step 4: Commit**

```bash
git add lib/app/theme/theme.dart lib/main.dart
git commit -m "feat(ui): rewrite ThemeData with manual ColorScheme.dark matching design tokens

- Replace fromSeed(seedColor: purple) with hand-crafted warm dark palette
- Switch to always-dark ThemeMode.dark
- Map all TextTheme sizes to design spec typography scale
- Update AppColors constants to reference XiaColors tokens

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Custom page transition builder

**Files:**
- Create: `lib/app/theme/page_transition.dart`

- [ ] **Step 1: Create page_transition.dart**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Custom [PageTransitionsBuilder] matching the design spec page transition.
///
/// Forward navigation: incoming page slides in from right (100%→0),
/// outgoing page shifts left -30% with opacity fade.
/// Back navigation: reverse of forward.
///
/// Transform: 500ms XiaMotion.ease. Opacity: 350ms XiaMotion.ease.
/// This staggered timing creates a "fast fade, slow slide" rhythm.
class XiaPageTransitionsBuilder extends PageTransitionsBuilder {
  const XiaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Distinguish forward (push) vs back (pop) by the animation direction.
    // The secondaryAnimation drives the outgoing page; only the incoming
    // page (primary animation) uses a positive curve.
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: XiaMotion.ease,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),   // start 100% right
        end: Offset.zero,
      ).animate(curvedAnimation),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: XiaMotion.ease,
            reverseCurve: XiaMotion.easeOut,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Convenience extension to apply the custom transition to a PageRoute.
extension XiaPageRoute on PageRoute {
  /// Returns true if this route should use the Xia page transition.
  bool get useXiaTransition => true;
}
```

- [ ] **Step 2: Wire the transition into ThemeData**

Add to `lib/app/theme/theme.dart`'s `darkTheme`:

```dart
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: XiaPageTransitionsBuilder(),
        TargetPlatform.iOS: XiaPageTransitionsBuilder(),
      },
    ),
```

Also add the import at the top of `theme.dart`:
```dart
import 'package:claw_hub/app/theme/page_transition.dart';
```

- [ ] **Step 3: Verify**

```bash
flutter analyze
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/app/theme/page_transition.dart lib/app/theme/theme.dart
git commit -m "feat(ui): add custom page transition (500ms slide + 350ms fade)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Toast widget with glassmorphism

**Files:**
- Create: `lib/ui_kit/toast.dart`

- [ ] **Step 1: Create toast.dart**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// A pill-shaped, glassmorphism-backed toast notification displayed at the
/// top-center of the screen (72px from top), matching the design spec.
///
/// Auto-dismisses after 2500ms. Uses [BackdropFilter] for glassmorphism effect.
class XiaToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  /// Show a toast message. If a toast is already visible, it is replaced.
  static void show(BuildContext context, String message) {
    _dismiss();

    final overlay = Overlay.of(context);
    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 72,
        left: 0,
        right: 0,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(XiaRadius.full),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: XiaGlass.toastBlur,
                sigmaY: XiaGlass.toastBlur,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: XiaSpacing.s6,
                  vertical: XiaSpacing.s3,
                ),
                decoration: BoxDecoration(
                  color: XiaColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(XiaRadius.full),
                  boxShadow: XiaShadow.l,
                ),
                child: const Text(
                  message,
                  style: TextStyle(
                    color: XiaColors.text1,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_currentEntry!);

    _dismissTimer = Timer(const Duration(milliseconds: 2500), _dismiss);
  }

  static void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}
```

> **Import note:** Use `dart:ui` for `ImageFilter` — import as `import 'dart:ui' as ui;` or use `import 'dart:ui' show ImageFilter;`.

- [ ] **Step 2: Verify compilation**

```bash
flutter analyze lib/ui_kit/toast.dart
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add lib/ui_kit/toast.dart
git commit -m "feat(ui): add glassmorphism toast widget (pill-shaped, auto-dismiss 2.5s)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Update ui_kit components (emoji_avatar, empty_state, color_grid, connection_banner)

**Files:**
- Modify: `lib/ui_kit/emoji_avatar.dart`
- Modify: `lib/ui_kit/empty_state.dart`
- Modify: `lib/ui_kit/color_grid.dart`
- Modify: `lib/ui_kit/connection_banner.dart`

- [ ] **Step 1: Update emoji_avatar.dart — add borderRadius parameter, switch from CircleAvatar to rounded container**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Universal emoji/first-character avatar with configurable border radius.
///
/// Design spec: avatars use rounded rectangles (not circles):
/// - Agent cards / message lists: radius 12 ([XiaRadius.md])
/// - Chat header: radius 8 ([XiaRadius.sm])
/// - Agent detail: radius 16 ([XiaRadius.lg])
class EmojiAvatar extends StatelessWidget {
  final String displayName;
  final String themeColor;
  final double radius;
  final double borderRadius;
  final double fontSize;

  const EmojiAvatar({
    super.key,
    required this.displayName,
    required this.themeColor,
    this.radius = 24,
    this.borderRadius = XiaRadius.md,
    this.fontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final color = ColorExtension.fromHex(themeColor);
    final firstChar = displayName.isNotEmpty ? displayName.characters.first : '';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        firstChar,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: color.contrastingTextColor(),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Update empty_state.dart — use token colors and spacing**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Global empty state component matching design spec.
///
/// Icon: 48px, text4 color, opacity 0.7.
/// Title: 17px, weight 600, text2 color.
/// Description: 14px, text3 color.
/// Padding: 48 vertical / 24 horizontal (s9/s6).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: XiaSpacing.s9,
          horizontal: XiaSpacing.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.7,
              child: Icon(icon, size: 48, color: XiaColors.text4),
            ),
            const SizedBox(height: XiaSpacing.s5),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: XiaColors.text2,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: XiaSpacing.s2),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 14,
                  color: XiaColors.text3,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: XiaSpacing.s6),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Update color_grid.dart — 6-column grid, 40×40 rounded squares, checkmark on selection**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Color option for [ColorGrid].
class ColorOption {
  final String hex;
  final String label;

  const ColorOption({required this.hex, required this.label});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorOption && hex == other.hex && label == other.label;

  @override
  int get hashCode => Object.hash(hex, label);
}

/// 12-color grid picker (6 columns, 40×40 rounded squares).
/// Matching ComponentSpec Section 6.5.
class ColorGrid extends StatelessWidget {
  final List<ColorOption> colors;
  final String selectedColor;
  final ValueChanged<String> onColorSelected;

  const ColorGrid({
    super.key,
    required this.colors,
    required this.selectedColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: XiaSpacing.s3,
        crossAxisSpacing: XiaSpacing.s3,
        childAspectRatio: 1,
      ),
      itemCount: colors.length,
      itemBuilder: (context, index) {
        final option = colors[index];
        final color = ColorExtension.fromHex(option.hex);
        final isSelected =
            option.hex.toUpperCase() == selectedColor.toUpperCase();

        return GestureDetector(
          onTap: () => onColorSelected(option.hex),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(XiaRadius.sm),
              border: isSelected
                  ? Border.all(color: XiaColors.text1, width: 3)
                  : Border.all(color: Colors.transparent, width: 3),
              boxShadow: isSelected ? XiaShadow.selectedGlow : null,
            ),
            child: isSelected
                ? const Center(
                    child: Text(
                      '✓',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Update connection_banner.dart — use semantic colors from tokens**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// A slim status banner that slides in below the AppBar.
///
/// Three visual states:
/// - **disconnected / authFailed** — yellow-tinted bg, yellow text
/// - **connecting / recovering** — accent-muted bg, accent text
/// - **connected** — collapsed (zero height)
class ConnectionBanner extends StatelessWidget {
  final GatewayConnectionState connectionState;

  const ConnectionBanner({super.key, required this.connectionState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (connectionState == GatewayConnectionState.disconnected ||
        connectionState == GatewayConnectionState.authFailed) {
      return _banner(
        theme,
        '连接已断开，正在重连...',
        XiaColors.yellow,
        const Color(0x1FC4A86A), // rgba(196,168,106,0.12)
        Icons.wifi_off,
      );
    }
    if (connectionState == GatewayConnectionState.connecting ||
        connectionState == GatewayConnectionState.recovering) {
      return _banner(
        theme,
        '正在连接...',
        XiaColors.accent,
        XiaColors.accentMuted,
        Icons.sync,
      );
    }
    return const SizedBox.shrink();
  }

  static Widget _banner(
    ThemeData theme,
    String message,
    Color fgColor,
    Color bgColor,
    IconData icon,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: XiaSpacing.s2,
      ),
      color: bgColor,
      child: Row(
        children: [
          Icon(icon, size: 16, color: fgColor),
          const SizedBox(width: XiaSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(color: fgColor),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Verify**

```bash
flutter analyze
```

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ui_kit/emoji_avatar.dart lib/ui_kit/empty_state.dart lib/ui_kit/color_grid.dart lib/ui_kit/connection_banner.dart
git commit -m "feat(ui): align ui_kit components with design tokens

- EmojiAvatar: rounded rect (not circle), configurable borderRadius
- EmptyState: tokenized spacing, font sizes, and colors
- ColorGrid: 6-column grid, 40x40 rounded squares, checkmark selection
- ConnectionBanner: semantic colors from XiaColors tokens

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Update agent_card.dart

**Files:**
- Modify: `lib/features/agent_list/widgets/agent_card.dart`

- [ ] **Step 1: Replace agent_card.dart entirely**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// Agent card — matching ComponentSpec Section 2.4.
///
/// Layout: [48×48 avatar + status dot] [name + desc info] [chevron]
/// Card: 16px radius, surface background, no left border strip.
class AgentCard extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;
  final bool isOnline;
  final int? lastActiveAt;

  const AgentCard({
    super.key,
    required this.agent,
    required this.onTap,
    this.isOnline = false,
    this.lastActiveAt,
  });

  String get _lastActiveText {
    if (lastActiveAt == null) return 'Never';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - lastActiveAt!;
    if (diff < 60) return 'Just now';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    if (diff < 86400) return '${diff ~/ 3600}h ago';
    if (diff < 604800) return '${diff ~/ 86400}d ago';
    return '${diff ~/ 604800}w ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: XiaSpacing.s3 / 2,
      ),
      decoration: BoxDecoration(
        color: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: XiaSpacing.s5,
            vertical: XiaSpacing.s4,
          ),
          child: Row(
            children: [
              // Avatar with online status dot
              Stack(
                children: [
                  EmojiAvatar(
                    displayName: agent.displayName,
                    themeColor: agent.themeColor,
                    radius: 24, // 48×48
                    borderRadius: XiaRadius.md,
                    fontSize: 24,
                  ),
                  // Status dot (8×8, 2px border matching surface)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? XiaColors.green : XiaColors.text4,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: XiaColors.surface,
                          width: 2,
                        ),
                        boxShadow: isOnline ? XiaShadow.onlineGlow : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: XiaSpacing.s4),
              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      agent.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        height: 1.3,
                        color: XiaColors.text1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (agent.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        agent.description!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: XiaColors.text3,
                          height: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: XiaSpacing.s1),
              // Time + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _lastActiveText,
                    style: const TextStyle(
                      fontSize: 11,
                      color: XiaColors.text4,
                      letterSpacing: 0.2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right,
                  color: XiaColors.text4, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/agent_list/widgets/agent_card.dart
git commit -m "feat(ui): align agent card with design spec (16px radius, tokenized styling)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Update stats_bar.dart

**Files:**
- Modify: `lib/features/agent_list/widgets/stats_bar.dart`

- [ ] **Step 1: Replace stats_bar.dart**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Stats bar — three equal-width stat chips matching ComponentSpec Section 2.2.
class StatsBar extends StatelessWidget {
  final int activeInstances;
  final int totalInstances;
  final int onlineAgents;
  final int totalAgents;
  final int totalMessages;

  const StatsBar({
    super.key,
    required this.activeInstances,
    required this.totalInstances,
    required this.onlineAgents,
    required this.totalAgents,
    required this.totalMessages,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        XiaSpacing.s6,
        0,
        XiaSpacing.s6,
        XiaSpacing.s5,
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              emoji: '🖥',
              value: '$activeInstances',
              unit: '/$totalInstances',
              label: '活跃实例',
            ),
          ),
          const SizedBox(width: XiaSpacing.s3),
          Expanded(
            child: _StatChip(
              emoji: '🦐',
              value: '$onlineAgents',
              unit: '/$totalAgents',
              label: '在线虾',
            ),
          ),
          const SizedBox(width: XiaSpacing.s3),
          Expanded(
            child: _StatChip(
              emoji: '💬',
              value: _formatCount(totalMessages),
              unit: '',
              label: '总消息数',
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}

class _StatChip extends StatelessWidget {
  final String emoji;
  final String value;
  final String unit;
  final String label;

  const _StatChip({
    required this.emoji,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s3,
        vertical: XiaSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: XiaSpacing.s3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: XiaColors.text1,
                      letterSpacing: -0.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                      height: 1,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    const Text(
                      unit,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: XiaColors.text3,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: XiaColors.text3,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify + Commit**

```bash
flutter analyze
git add lib/features/agent_list/widgets/stats_bar.dart
git commit -m "feat(ui): align stats bar with design spec (equal-width chips, 22px values)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Update message_bubble.dart

**Files:**
- Modify: `lib/features/chat_room/widgets/message_bubble.dart`

- [ ] **Step 1: Replace message_bubble.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/ui_kit/status_icon.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Message bubble — matching ComponentSpec Section 4.2.2.
///
/// User: coral bg (#C27C68), white text, right-aligned, 20px radius with
///       8px bottom-right corner (speech tail).
/// Agent: surface bg, text1, left-aligned, 20px radius with
///        8px bottom-left corner, shadow-s.
class MessageBubble extends StatelessWidget {
  final Message message;
  final String agentName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.agentName,
  });

  bool get _isUser => message.role == MessageRole.user;

  String get _displayContent {
    if (message.content != null && message.content!.isNotEmpty) {
      return message.content!;
    }
    return switch (message.type) {
      MessageType.image => '[图片]',
      MessageType.file => '[文件]',
      MessageType.toolCall => '[工具调用]',
      MessageType.text => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: 4,
      ),
      child: Row(
        mainAxisAlignment:
            _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!_isUser) ...[
            // Agent mini avatar
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(XiaRadius.sm),
                color: XiaColors.accentMuted,
              ),
              alignment: Alignment.center,
              child: Text(
                agentName.characters.first,
                style: const TextStyle(
                  fontSize: 12,
                  color: XiaColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: XiaSpacing.s2),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: _isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: XiaSpacing.s5,
                    vertical: XiaSpacing.s3,
                  ),
                  decoration: BoxDecoration(
                    color: _isUser ? XiaColors.accent : XiaColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(XiaRadius.xl),
                      topRight: const Radius.circular(XiaRadius.xl),
                      bottomLeft: Radius.circular(
                        _isUser ? XiaRadius.xl : XiaRadius.sm,
                      ),
                      bottomRight: Radius.circular(
                        _isUser ? XiaRadius.sm : XiaRadius.xl,
                      ),
                    ),
                    boxShadow: _isUser ? null : XiaShadow.s,
                    border: message.status == MessageStatus.failed
                        ? Border.all(color: XiaColors.red, width: 1.5)
                        : null,
                  ),
                  child: _isUser
                      ? Text(
                          _displayContent,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.6,
                          ),
                        )
                      : _buildMarkdownContent(),
                ),
                // Message time
                Padding(
                  padding: const EdgeInsets.only(
                    top: XiaSpacing.s1,
                    left: XiaSpacing.s1,
                    right: XiaSpacing.s1,
                  ),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: XiaColors.text4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isUser) ...[
            const SizedBox(width: 4),
            StatusIcon(status: message.status, size: 14),
          ],
        ],
      ),
    );
  }

  String _formatTime(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildMarkdownContent() {
    return MarkdownBody(
      data: _displayContent,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(
          color: XiaColors.text1,
          fontSize: 15,
          height: 1.6,
        ),
        h1: const TextStyle(
          color: XiaColors.text1,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h2: const TextStyle(
          color: XiaColors.text1,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h3: const TextStyle(
          color: XiaColors.text1,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        strong: const TextStyle(
          color: XiaColors.text1,
          fontWeight: FontWeight.bold,
        ),
        em: const TextStyle(
          color: XiaColors.text1,
          fontStyle: FontStyle.italic,
        ),
        a: const TextStyle(
          color: XiaColors.accent,
          decoration: TextDecoration.underline,
        ),
        code: const TextStyle(
          backgroundColor: XiaColors.codeBlockBg,
          color: XiaColors.accent,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: XiaColors.surface2,
          borderRadius: BorderRadius.circular(XiaRadius.md),
        ),
        codeblockPadding: const EdgeInsets.all(XiaSpacing.s4),
        blockquoteDecoration: const BoxDecoration(
          border: Border(
            left: BorderSide(
              color: XiaColors.accent,
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: XiaSpacing.s3),
        tableBorder: TableBorder.all(color: XiaColors.divider),
        tableHead: const TextStyle(
          color: XiaColors.text1,
          fontWeight: FontWeight.bold,
        ),
        tableBody: const TextStyle(color: XiaColors.text1),
        listBullet: const TextStyle(color: XiaColors.text1),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify + Commit**

```bash
flutter analyze
git add lib/features/chat_room/widgets/message_bubble.dart
git commit -m "feat(ui): align message bubble with design spec (coral user bg, shadow-s agent, 20px radius)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Update chat_input_bar.dart

**Files:**
- Modify: `lib/features/chat_room/widgets/chat_input_bar.dart`

- [ ] **Step 1: Replace chat_input_bar.dart**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/toast.dart';

/// Chat input bar — matching ComponentSpec Section 4.5.
///
/// Layout: [Plus btn 40×40] [TextField 16px radius] [Send btn 40×40]
class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;

  const ChatInputBar({super.key, required this.onSend});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  void _showAttachmentOptions() {
    XiaToast.show(context, '附件功能开发中');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      color: XiaColors.bg,
      padding: EdgeInsets.fromLTRB(
        XiaSpacing.s6,
        XiaSpacing.s3,
        XiaSpacing.s6,
        XiaSpacing.s3 + bottomInset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Plus button
          _SmallButton(
            icon: Icons.add,
            onPressed: _showAttachmentOptions,
          ),
          const SizedBox(width: XiaSpacing.s3),
          // Input field
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                color: XiaColors.text1,
                fontSize: 15,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: '写点什么...',
                filled: true,
                fillColor: XiaColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(XiaRadius.lg),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: XiaSpacing.s5,
                  vertical: XiaSpacing.s3,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: XiaSpacing.s3),
          // Send button
          Opacity(
            opacity: _hasText ? 1.0 : 0.3,
            child: _SmallButton(
              icon: Icons.send,
              onPressed: _hasText ? _send : null,
              accent: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool accent;

  const _SmallButton({
    required this.icon,
    this.onPressed,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: accent ? XiaColors.accent : XiaColors.surface2,
        borderRadius: BorderRadius.circular(XiaRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(XiaRadius.md),
          onTap: onPressed,
          child: Icon(
            icon,
            color: accent ? Colors.white : XiaColors.text3,
            size: 20,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify + Commit**

```bash
flutter analyze
git add lib/features/chat_room/widgets/chat_input_bar.dart
git commit -m "feat(ui): align chat input bar with design spec (16px input radius, tokenized)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: Update quick_command_bar.dart, tool_call_card.dart, thinking_indicator.dart

**Files:**
- Modify: `lib/features/chat_room/widgets/quick_command_bar.dart`
- Modify: `lib/features/chat_room/widgets/tool_call_card.dart`
- Modify: `lib/features/chat_room/widgets/thinking_indicator.dart`

- [ ] **Step 1: Update quick_command_bar.dart**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/quick_command.dart';

/// Quick command bar — horizontally scrollable capsule pills.
/// Matching ComponentSpec Section 4.4.
class QuickCommandBar extends StatelessWidget {
  final List<QuickCommand> commands;
  final ValueChanged<String> onCommandTap;

  const QuickCommandBar({
    super.key,
    required this.commands,
    required this.onCommandTap,
  });

  @override
  Widget build(BuildContext context) {
    if (commands.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: XiaSpacing.s3),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: XiaSpacing.s6,
          ),
          itemCount: commands.length,
          separatorBuilder: (_, __) => const SizedBox(width: XiaSpacing.s2),
          itemBuilder: (context, index) {
            final cmd = commands[index];
            return GestureDetector(
              onTap: () => onCommandTap(cmd.payload),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: XiaSpacing.s4,
                  vertical: XiaSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: XiaColors.surface2,
                  borderRadius: BorderRadius.circular(XiaRadius.full),
                ),
                alignment: Alignment.center,
                child: const Text(
                  cmd.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: XiaColors.accent,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Update tool_call_card.dart**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/enums.dart';

/// Tool call card — matching ComponentSpec Section 4.2.3.
///
/// 3px accent left border, surface2 bg, 12px radius.
class ToolCallCard extends StatelessWidget {
  final ToolCall toolCall;

  const ToolCallCard({super.key, required this.toolCall});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: 4,
      ),
      child: Row(
        children: [
          const SizedBox(width: 36),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: XiaSpacing.s4,
                vertical: XiaSpacing.s3,
              ),
              decoration: BoxDecoration(
                color: XiaColors.surface2,
                borderRadius: BorderRadius.circular(XiaRadius.md),
                border: const Border(
                  left: BorderSide(color: XiaColors.accent, width: 3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusIcon(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          toolCall.toolName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: XiaColors.accent,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: XiaSpacing.s1),
                        Text(
                          _statusText,
                          style: const TextStyle(
                            color: XiaColors.green,
                            fontSize: 11,
                          ),
                        ),
                        if (toolCall.isCompleted &&
                            toolCall.outputResult != null) ...[
                          const SizedBox(height: XiaSpacing.s2),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(XiaSpacing.s2),
                            decoration: BoxDecoration(
                              color: XiaColors.surface,
                              borderRadius:
                                  BorderRadius.circular(XiaRadius.sm - 2),
                            ),
                            child: Text(
                              _truncateOutput(toolCall.outputResult!, 120),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: XiaColors.text1,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    return switch (toolCall.status) {
      ToolCallStatus.pending || ToolCallStatus.running => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: XiaColors.yellow,
          ),
        ),
      ToolCallStatus.success => const Icon(
          Icons.check_circle,
          size: 20,
          color: XiaColors.green,
        ),
      ToolCallStatus.failed => const Icon(
          Icons.error,
          size: 20,
          color: XiaColors.red,
        ),
    };
  }

  String get _statusText {
    return switch (toolCall.status) {
      ToolCallStatus.pending => 'Pending...',
      ToolCallStatus.running => 'Running...',
      ToolCallStatus.success => '✅ Completed',
      ToolCallStatus.failed => '❌ Failed',
    };
  }

  String _truncateOutput(String output, int maxLen) {
    if (output.length <= maxLen) return output;
    return '${output.substring(0, maxLen)}...';
  }
}
```

- [ ] **Step 3: Update thinking_indicator.dart**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Thinking indicator — three bouncing dots, matching ComponentSpec Section 4.3.
///
/// Bubble: 20/20/8/20 radius (matches Agent bubble), surface bg, shadow-s.
/// Dots: 6×6, text3 color, 800ms bounce cycle, staggered delays.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: 4,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: XiaColors.accentMuted,
              borderRadius: BorderRadius.circular(XiaRadius.sm),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.psychology, size: 16, color: XiaColors.accent),
          ),
          const SizedBox(width: XiaSpacing.s2),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: XiaSpacing.s5,
              vertical: XiaSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(XiaRadius.xl),
                topRight: Radius.circular(XiaRadius.xl),
                bottomRight: Radius.circular(XiaRadius.xl),
                bottomLeft: Radius.circular(XiaRadius.sm),
              ),
              boxShadow: XiaShadow.s,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BouncingDot(controller: _controller, delay: 0.0),
                const SizedBox(width: 4),
                _BouncingDot(controller: _controller, delay: 0.15),
                const SizedBox(width: 4),
                _BouncingDot(controller: _controller, delay: 0.3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BouncingDot extends StatelessWidget {
  final AnimationController controller;
  final double delay; // seconds

  const _BouncingDot({
    required this.controller,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final delayFraction = delay / 0.8;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value + delayFraction) % 1.0;
        // 0-40%: translateY(-8px), 40-80%: back, 80-100%: rest
        final y = t < 0.4
            ? -8.0 * (t / 0.4)
            : t < 0.8
                ? -8.0 + 8.0 * ((t - 0.4) / 0.4)
                : 0.0;
        return Transform.translate(
          offset: Offset(0, y),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: XiaColors.text3,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Verify + Commit**

```bash
flutter analyze
git add lib/features/chat_room/widgets/quick_command_bar.dart lib/features/chat_room/widgets/tool_call_card.dart lib/features/chat_room/widgets/thinking_indicator.dart
git commit -m "feat(ui): align quick commands, tool cards, thinking indicator with design spec

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 11: Update conversation_tile.dart and instance_card.dart

**Files:**
- Modify: `lib/features/message_hub/widgets/conversation_tile.dart`
- Modify: `lib/features/instance_manager/widgets/instance_card.dart`

- [ ] **Step 1: Update conversation_tile.dart — tokenize colors and shapes**

In `conversation_tile.dart`:

**Replace `_ConversationAvatar` class** (private widget inside conversation_tile.dart):

```dart
class _ConversationAvatar extends StatelessWidget {
  final Agent agent;
  final bool isMuted;
  final HealthStatus healthStatus;

  const _ConversationAvatar({
    required this.agent,
    required this.isMuted,
    required this.healthStatus,
  });

  @override
  Widget build(BuildContext context) {
    final color = isMuted
        ? XiaColors.surface2
        : ColorExtension.fromHex(agent.themeColor);

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(XiaRadius.md),
            ),
            alignment: Alignment.center,
            child: Text(
              agent.displayName.isNotEmpty ? agent.displayName[0] : '?',
              style: TextStyle(
                color: color.contrastingTextColor(),
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: healthStatus == HealthStatus.online ||
                        healthStatus == HealthStatus.connecting
                    ? XiaColors.green
                    : XiaColors.text4,
                shape: BoxShape.circle,
                border: Border.all(color: XiaColors.surface, width: 2),
                boxShadow: healthStatus == HealthStatus.online
                    ? XiaShadow.onlineGlow
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

**Replace `_UnreadBadge` class:**

```dart
class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: const BoxDecoration(
        color: XiaColors.accent,
        borderRadius: BorderRadius.all(Radius.circular(XiaRadius.full)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
```

**Other replacements in the main `ConversationTile` build method:**
- Truncate preview to 38 chars (change `40` to `38` on the truncation line)
- Add import for `package:claw_hub/app/theme/tokens.dart` at top

- [ ] **Step 2: Update instance_card.dart — tokenize styling**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Instance card — matching ComponentSpec Section 7.2.
///
/// Layout: [44×44 icon] [name + url + status] [action buttons]
class InstanceCard extends StatelessWidget {
  final Instance instance;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const InstanceCard({
    super.key,
    required this.instance,
    required this.onTap,
    this.onDelete,
  });

  Color _healthColor(HealthStatus status) {
    return switch (status) {
      HealthStatus.online => XiaColors.green,
      HealthStatus.offline => XiaColors.text4,
      HealthStatus.connecting => XiaColors.yellow,
      HealthStatus.expectedOffline => XiaColors.text4,
      HealthStatus.unknown => XiaColors.text4,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(XiaSpacing.s5),
          child: Row(
            children: [
              // Instance icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: XiaColors.surface2,
                  borderRadius: BorderRadius.circular(XiaRadius.md),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.dns,
                  size: 22,
                  color: XiaColors.text2,
                ),
              ),
              const SizedBox(width: XiaSpacing.s4),
              // Name + URL + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instance.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: XiaColors.text1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      instance.gatewayUrl,
                      style: const TextStyle(
                        fontSize: 13,
                        color: XiaColors.text3,
                        letterSpacing: -0.3,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: XiaSpacing.s1),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _healthColor(instance.healthStatus),
                            shape: BoxShape.circle,
                            boxShadow: instance.healthStatus ==
                                    HealthStatus.online
                                ? XiaShadow.onlineGlow
                                : null,
                          ),
                        ),
                        const SizedBox(width: XiaSpacing.s1),
                        Text(
                          instance.healthStatus == HealthStatus.online
                              ? '在线'
                              : '离线',
                          style: TextStyle(
                            fontSize: 12,
                            color: instance.healthStatus == HealthStatus.online
                                ? XiaColors.green
                                : XiaColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Action buttons
              Row(
                children: [
                  _ActionBtn(icon: Icons.refresh, onTap: () {}),
                  if (onDelete != null) ...[
                    const SizedBox(width: XiaSpacing.s2),
                    _ActionBtn(
                      icon: Icons.delete_outline,
                      onTap: onDelete,
                      danger: true,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  const _ActionBtn({required this.icon, this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: danger ? XiaColors.redMuted : XiaColors.surface2,
        borderRadius: BorderRadius.circular(XiaRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(XiaRadius.sm),
          onTap: onTap,
          child: Icon(
            icon,
            size: 16,
            color: danger ? XiaColors.red : XiaColors.text3,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Verify + Commit**

```bash
flutter analyze
git add lib/features/message_hub/widgets/conversation_tile.dart lib/features/instance_manager/widgets/instance_card.dart
git commit -m "feat(ui): align conversation tile and instance card with design spec

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 12: Update profile_header.dart and stats_grid.dart

**Files:**
- Modify: `lib/features/agent_profile/widgets/profile_header.dart`
- Modify: `lib/features/agent_profile/widgets/stats_grid.dart`

- [ ] **Step 1: Update profile_header.dart — 72×72 avatar, borderRadius 16, no border**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// Agent Profile header — matching ComponentSpec Section 5.2.
///
/// 72×72 avatar (borderRadius 16), 24px name, 14px description, inline status.
class ProfileHeader extends StatelessWidget {
  final Agent agent;
  final Instance? instance;

  const ProfileHeader({super.key, required this.agent, this.instance});

  @override
  Widget build(BuildContext context) {
    final isOnline = instance?.healthStatus.isConnectable ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: XiaSpacing.s6,
      ),
      child: Column(
        children: [
          // Avatar — 72×72, borderRadius 16
          EmojiAvatar(
            displayName: agent.displayName,
            themeColor: agent.themeColor,
            radius: 36,
            borderRadius: XiaRadius.lg,
            fontSize: 36,
          ),
          const SizedBox(height: XiaSpacing.s4),
          // Name — 24px, weight 700
          Text(
            agent.displayName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: XiaColors.text1,
            ),
          ),
          if (agent.description != null && agent.description!.isNotEmpty) ...[
            const SizedBox(height: XiaSpacing.s1),
            Text(
              agent.description!,
              style: const TextStyle(
                fontSize: 14,
                color: XiaColors.text3,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: XiaSpacing.s3),
          // Status row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isOnline ? XiaColors.green : XiaColors.text4,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: XiaSpacing.s1),
              Text(
                isOnline ? '在线' : '离线',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isOnline ? XiaColors.green : XiaColors.text4,
                ),
              ),
              const SizedBox(width: 6),
              const Text('·', style: TextStyle(color: XiaColors.text3, fontSize: 12)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  instance?.name ?? '未知实例',
                  style: const TextStyle(fontSize: 12, color: XiaColors.text3),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Update stats_grid.dart — 3 cols, 12px gap, tokenized**

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Stats grid — 3×2 data cards matching ComponentSpec Section 5.3.
class StatsGrid extends StatelessWidget {
  final int messageCount;

  const StatsGrid({super.key, required this.messageCount});

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem(label: '对话', value: '--'),
      _StatItem(label: '消息', value: _formatNumber(messageCount)),
      _StatItem(label: '工具', value: '--'),
      _StatItem(label: '天数', value: '--'),
      _StatItem(label: '连续', value: '--'),
      _StatItem(label: '首聊', value: '--'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: XiaSpacing.s6),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.6,
          crossAxisSpacing: XiaSpacing.s3,
          mainAxisSpacing: XiaSpacing.s3,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.md),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: XiaColors.text1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: XiaSpacing.s1),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: XiaColors.text3,
                      letterSpacing: 0.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatNumber(int n) {
    if (n < 1000) return n.toString();
    final s = n.toString();
    final buf = StringBuffer();
    final len = s.length;
    for (var i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _StatItem {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});
}
```

- [ ] **Step 3: Verify + Commit**

```bash
flutter analyze
git add lib/features/agent_profile/widgets/profile_header.dart lib/features/agent_profile/widgets/stats_grid.dart
git commit -m "feat(ui): align profile header and stats grid with design spec

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 13: Bottom navigation glassmorphism (router.dart)

**Files:**
- Modify: `lib/app/router/router.dart`

- [ ] **Step 1: Replace `_TabScaffold` with glassmorphism bottom nav**

Replace the `_TabScaffold` class in `router.dart` with a custom glassmorphism implementation. Replace the import for `package:claw_hub/app/theme/theme.dart` with `package:claw_hub/app/theme/tokens.dart`.

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/instance_manager/instance_list_page.dart';
import 'package:claw_hub/features/instance_manager/add_instance_page.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';
import 'package:claw_hub/features/agent_list/agent_list_page.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/message_hub/message_hub_page.dart';
import 'package:claw_hub/features/agent_profile/agent_profile_page.dart';
import 'package:claw_hub/features/agent_profile/agent_config_page.dart';
```

Replace `_TabScaffold` entirely:

```dart
/// Three-tab scaffold with glassmorphism bottom nav.
class _TabScaffold extends StatelessWidget {
  final StatefulShellNavigationShell navigationShell;

  const _TabScaffold({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: XiaGlass.navBlur,
            sigmaY: XiaGlass.navBlur,
          ),
          child: Container(
            height: 72,
            decoration: const BoxDecoration(
              color: XiaGlass.navBackground,
              border: Border(
                top: BorderSide(color: XiaColors.divider),
              ),
            ),
            child: Row(
              children: [
                _NavTab(
                  icon: Icons.pets,
                  label: '虾列表',
                  isActive: navigationShell.currentIndex == 0,
                  onTap: () => navigationShell.goBranch(0),
                ),
                _NavTab(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: '消息',
                  isActive: navigationShell.currentIndex == 1,
                  onTap: () => navigationShell.goBranch(1),
                ),
                _NavTab(
                  icon: Icons.dns_outlined,
                  activeIcon: Icons.dns,
                  label: '实例',
                  isActive: navigationShell.currentIndex == 2,
                  onTap: () => navigationShell.goBranch(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? XiaColors.accent : XiaColors.text4;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: XiaSpacing.s6,
            vertical: XiaSpacing.s2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? (activeIcon ?? icon) : icon,
                size: 22,
                color: color,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

> **Note:** Keep the rest of `router.dart` (AppRoutes, AppRouter, _chatRoute, _createRouter) unchanged.

- [ ] **Step 2: Verify + Commit**

```bash
flutter analyze
git add lib/app/router/router.dart
git commit -m "feat(ui): replace M3 NavigationBar with glassmorphism bottom nav (72px, blur 24)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 14: Page-level widget adjustments (config, add-instance, chat header)

**Files:**
- Modify: `lib/features/agent_profile/agent_config_page.dart`
- Modify: `lib/features/instance_manager/add_instance_page.dart`
- Modify: `lib/features/chat_room/chat_room_page.dart` (chat header area)

- [ ] **Step 1: Update agent_config_page.dart — tokenize section styling**

The `agent_config_page.dart` has section containers using `surfaceContainerHighest` and `borderRadius: 12`. Update all hardcoded values to use tokens:

- Section card: `color: XiaColors.surface`, `borderRadius: BorderRadius.circular(XiaRadius.lg)`, `padding: EdgeInsets.all(XiaSpacing.s5)`
- Section title text: `fontSize: 12, fontWeight: FontWeight.w600, color: XiaColors.text3, letterSpacing: 0.8` (uppercase via `Text` widget if needed)
- Config avatar: use `EmojiAvatar(radius: 32, borderRadius: XiaRadius.lg, fontSize: 30)` (64×64)
- Edit badge: `Container(width: 22, height: 22, decoration: BoxDecoration(color: XiaColors.accent, borderRadius: BorderRadius.circular(XiaRadius.sm)))` with "✎" child text, white, weight 700, size 10
- Input fields: `height: 44`, fill `XiaColors.surface2`, `borderRadius: XiaRadius.sm`, add `BoxShadow` inset style via decoration
- Save button: custom `Container` instead of `FilledButton` — `height: 52`, `borderRadius: XiaRadius.md`, `color: XiaColors.accent`, `boxShadow: XiaShadow.accentGlow`

- [ ] **Step 2: Update add_instance_page.dart — tokenize form styling**

- Form inputs: `height: 48`, `fillColor: XiaColors.surface`, `borderRadius: XiaRadius.md`, use InputDecoration borderless with fill
- Form labels: `fontSize: 12, fontWeight: FontWeight.w600, color: XiaColors.text2, letterSpacing: 0.5` (uppercase)
- Form hints: `fontSize: 12, color: XiaColors.text4, height: 1.4`
- Tab switcher row: `Container(decoration: BoxDecoration(color: XiaColors.surface, borderRadius: BorderRadius.circular(XiaRadius.md)), padding: EdgeInsets.all(3))`
  - Active tab: `color: XiaColors.accent, text: white`
  - Inactive tab: `color: XiaColors.text3`
- Connect button: custom primary button styling — `height: 52`, `borderRadius: XiaRadius.md`, `color: XiaColors.accent`, `boxShadow: XiaShadow.accentGlow`
- QR area: `Container(width: 200, height: 200, decoration: BoxDecoration(color: XiaColors.surface, borderRadius: BorderRadius.circular(XiaRadius.xl)))`
- Replace hardcoded `Colors.green.shade50/shade200/shade700` with `XiaColors.green`/`XiaColors.greenMuted`

- [ ] **Step 3: Update chat_room_page.dart — chat header styling**

The chat room page has a custom `AppBar` or header area. Ensure:
- Back button: 40×40, transparent bg, `borderRadius: XiaRadius.md`, icon 22px
- Avatar: 40×40, `borderRadius: XiaRadius.sm`, fontSize 18px
- Header name: 17px, weight 600, letterSpacing -0.2
- Status row: 12px, `XiaColors.text3`, inline status dot 6×6
- More button: 40×40, `XiaColors.surface2` bg, `borderRadius: XiaRadius.md`

- [ ] **Step 4: Verify + Commit**

```bash
flutter analyze
git add lib/features/agent_profile/agent_config_page.dart lib/features/instance_manager/add_instance_page.dart lib/features/chat_room/chat_room_page.dart
git commit -m "feat(ui): align config page, add-instance page, and chat header with design tokens

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 15: Final verification and cleanup

- [ ] **Step 1: Run full static analysis**

```bash
flutter analyze
```

Fix any warnings or errors. Expected: zero issues.

- [ ] **Step 2: Run all tests**

```bash
flutter test
```

Expected: all existing tests pass (no business logic changes).

- [ ] **Step 3: Color audit — verify no hardcoded colors outside tokens.dart and theme.dart**

```bash
grep -rn "Color(0x" lib/ --include="*.dart" | grep -v tokens.dart | grep -v theme.dart | grep -v theme_color_utils.dart
```

Any remaining `Color(0x...)` should be reviewed — they should only be in `tokens.dart`, `theme.dart`, or `theme_color_utils.dart` (the WCAG utility).

- [ ] **Step 4: Commit final cleanup**

```bash
git add -A
git commit -m "chore(ui): final cleanup — fix analysis warnings, ensure zero hardcoded colors

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Merge Strategy

After this branch is complete and the other agent's `master` changes have landed:

```bash
git checkout master
git merge feat/ui-design-token-alignment
# Resolve any conflicts in:
# - lib/features/instance_manager/widgets/instance_card.dart
# - lib/features/instance_manager/instance_list_page.dart
# - lib/features/instance_manager/add_instance_page.dart
# - lib/main.dart
flutter analyze
flutter test
git push
```

---

*Plan generated from docs/superpowers/specs/2026-06-11-ui-design-token-alignment-design.md*
