# UI Design Token Alignment — Design Spec

**Date**: 2026-06-11  
**Branch**: (new branch, created at implementation time)  
**Status**: Approved  
**Mode**: Always dark (`ThemeMode.dark`) — design spec is dark-only  
**Sources**:
- `docs/DesignToken-虾Hub.md` (v1.0)
- `docs/ComponentSpec-虾Hub.md` (v1.0)
- `docs/虾Hub-原型Demo-Premium.html` (prototype)

---

## Goal

Align the Flutter app's visual layer with the premium dark-mode design spec. Change UI-only code (theme, tokens, component styles, motion, glassmorphism) — zero business logic changes.

---

## Approach

**Pattern**: Token constants → ThemeData override → component style alignment → motion/glassmorphism → layout adjustments.

All 5 modules implemented in sequence on this branch.

---

## Module 1: Design Token Constants

**File**: `lib/app/theme/tokens.dart` (new)

Single source of truth for all design values, directly translated from `DesignToken-虾Hub.md` Section 8 JSON → Dart:

```dart
class XiaColors {
  // Background hierarchy (warm dark tones)
  static const bg = Color(0xFF111110);
  static const surface = Color(0xFF1A1917);
  static const surface2 = Color(0xFF232220);
  static const surface3 = Color(0xFF2C2B28);
  static const surfaceElevated = Color(0xFF1F1E1C);

  // Text (warm white, tonal opacity tiers)
  static const text1 = Color(0xFFF5F4F0);       // 100%
  static const text2 = Color(0x99F5F4F0);       // 60%
  static const text3 = Color(0x59F5F4F0);       // 35%
  static const text4 = Color(0x2EF5F4F0);       // 18%

  // Brand accent (desaturated coral)
  static const accent = Color(0xFFC27C68);
  static const accentHover = Color(0xFFD08E7C);
  static const accentMuted = Color(0x1FC27C68);  // 12% opacity
  static const accentGlow = Color(0x2EC27C68);   // 18% opacity

  // Semantic
  static const green = Color(0xFF6BA87A);
  static const greenMuted = Color(0x266BA87A);   // 15% opacity
  static const red = Color(0xFFC26464);
  static const redMuted = Color(0x1FC26464);     // 12% opacity
  static const yellow = Color(0xFFC4A86A);

  // 12 agent theme colors (foreground + background 12% alpha)
  static const Map<String, Map<String, Color>> agentThemes = {
    'coral':   {'color': Color(0xFFC27C68), 'bg': Color(0x1FC27C68)},
    'blue':    {'color': Color(0xFF6C8AAF), 'bg': Color(0x1F6C8AAF)},
    'green':   {'color': Color(0xFF6BA87A), 'bg': Color(0x1F6BA87A)},
    'orange':  {'color': Color(0xFFB98A64), 'bg': Color(0x1FB98A64)},
    'pink':    {'color': Color(0xFFAF788C), 'bg': Color(0x1FAF788C)},
    'teal':    {'color': Color(0xFF5F9B96), 'bg': Color(0x1F5F9B96)},
    'yellow':  {'color': Color(0xFFAF9B5F), 'bg': Color(0x1FAF9B5F)},
    'rose':    {'color': Color(0xFFAA6E82), 'bg': Color(0x1FAA6E82)},
    'slate':   {'color': Color(0xFF828282), 'bg': Color(0x1F828282)},
    'indigo':  {'color': Color(0xFF6E64A0), 'bg': Color(0x1F6E64A0)},
    'caramel': {'color': Color(0xFFAA7D50), 'bg': Color(0x1FAA7D50)},
    'jade':    {'color': Color(0xFF509678), 'bg': Color(0x1F509678)},
  };
}

class XiaSpacing {
  static const s1 = 4.0;   static const s2 = 8.0;
  static const s3 = 12.0;  static const s4 = 16.0;
  static const s5 = 20.0;  static const s6 = 24.0;  // page horizontal padding
  static const s7 = 32.0;  static const s8 = 40.0;
  static const s9 = 48.0;  static const s10 = 56.0;
}

class XiaRadius {
  static const sm = 8.0;   static const md = 12.0;
  static const lg = 16.0;  static const xl = 20.0;
  static const full = 999.0;
}

class XiaShadow {
  static const s = [BoxShadow(color: Color(0x2E000000), offset: Offset(0,1), blurRadius: 2)];
  static const m = [BoxShadow(color: Color(0x33000000), offset: Offset(0,4), blurRadius: 16)];
  static const l = [BoxShadow(color: Color(0x38000000), offset: Offset(0,8), blurRadius: 32)];
  static const xl = [BoxShadow(color: Color(0x47000000), offset: Offset(0,16), blurRadius: 48)];
}

class XiaMotion {
  static const ease = Cubic(0.16, 1, 0.3, 1);
  static const easeSpring = Cubic(0.34, 1.56, 0.64, 1);
  static const easeOut = Cubic(0.0, 0.0, 0.2, 1);
  static const durationFast = Duration(milliseconds: 200);
  static const durationMid = Duration(milliseconds: 350);
  static const durationSlow = Duration(milliseconds: 500);
}
```

**No existing files modified.**

---

## Module 2: ThemeData Override

**File**: `lib/app/theme/theme.dart` (rewrite)

**Before**: `ColorScheme.fromSeed(seedColor: Color(0xFF6C5CE7))` — purple-based, Material-generated.

**After**: Manually constructed `ColorScheme.dark()` with all values sourced from `XiaColors`:

| ColorScheme field | Value | Source |
|---|---|---|
| `primary` | `XiaColors.accent` | Brand accent |
| `onPrimary` | `XiaColors.text1` | Text on accent surfaces |
| `surface` | `XiaColors.surface` | Card/container bg |
| `onSurface` | `XiaColors.text1` | Text on surfaces |
| `surfaceContainerHighest` | `XiaColors.surface2` | Elevated containers |
| `outline` | `XiaColors.text3` | Borders/dividers |
| `error` | `XiaColors.red` | Error states |
| `shadow` | transparent | We use our own shadow system |

**ThemeData overrides**:

| Property | Value |
|---|---|
| `scaffoldBackgroundColor` | `XiaColors.bg` |
| `textTheme` | Custom: bodyLarge 15px/400/1.55, titleLarge 30px/700/1.2, etc. matching design typography |
| `appBarTheme` | titleTextStyle matching page type (30px H1 or 22px sub-title), left-aligned |
| `bottomNavigationBarTheme` | height 72, glassmorphism background, no elevation |
| `inputDecorationTheme` | borderless, borderRadius `XiaRadius.lg`, fillColor `XiaColors.surface` |
| `cardTheme` | borderRadius `XiaRadius.lg`, elevation 0, color `XiaColors.surface` |
| `iconTheme` | color `XiaColors.text2` |
| `pageTransitionsTheme` | Custom 500ms horizontal slide (see Module 4) |

**AppColors class** updated:
- `primaryBlue` → `XiaColors.accent` (also rename to `brandAccent`)
- Status colors → spec semantic colors
- Agent color list → 12 spec-defined colors

---

## Module 3: Component Style Alignment

### 3.1 Bottom Navigation (`lib/app/router/router.dart` `_TabScaffold`)

| Property | Before | After |
|---|---|---|
| height | Material default (≈80) | 72px |
| background | M3 `NavigationBar` default | `rgba(17,17,16,0.88)` + `BackdropFilter(blur: 24)` |
| top border | none | `1px solid rgba(245,244,240,0.04)` |
| active color | `AppColors.primaryBlue` | `XiaColors.accent` (both icon + label) |
| inactive color | M3 default | `XiaColors.text4` |
| label size | 12px | 10px, weight 500 |

**Implementation**: Switch from M3 `NavigationBar` to custom `BottomAppBar` + `BackdropFilter` to achieve glassmorphism. `ColorFiltered` with saturation matrix to simulate saturate(1.4).

### 3.2 Agent Card (`lib/features/agent_list/widgets/agent_card.dart`)

| Property | Before | After |
|---|---|---|
| border-radius | 14 | 16 (`XiaRadius.lg`) |
| padding | 14 (all sides) | 16 horizontal, 20 vertical (`s4`/`s5`) |
| left border | 3px agent color | removed |
| avatar radius | CircleAvatar | 48×48, borderRadius 12 (`XiaRadius.md`) |
| avatar font | 24px | emoji 24px |
| status dot | 12×12, no border | 8×8, 2px border matching `XiaColors.surface` |
| status dot online | no glow | `boxShadow: 0 0 8px XiaColors.green` |
| offline opacity | 0.55 | intact (1.0), only status dot changes |
| agent-name | titleMedium | 16px, weight 600, letterSpacing -0.2, lineHeight 1.3 |
| agent-desc | bodySmall | 13px, `XiaColors.text3`, single-line ellipsis |
| agent-time | labelSmall | 11px, `XiaColors.text4`, tabular-nums |
| press feedback | InkWell ripple | `AnimatedScale(0.98)` + background → `XiaColors.surface2` |

### 3.3 Stats Bar (`lib/features/agent_list/widgets/stats_bar.dart`)

| Property | Before | After |
|---|---|---|
| chip border-radius | 20 | 16 (`XiaRadius.lg`) |
| chip padding | h:14, v:8 | h:12, v:16 (`s3`/`s4`) |
| chip gap | — | 12 (`s3`) |
| value color | `colorScheme.primary` | `XiaColors.text1` |
| value size | titleSmall | 22px, weight 700, tabular-nums |
| label size | labelSmall | 11px, `XiaColors.text3`, weight 500 |
| chip layout | vertical stack | row: [emoji 18px] [value+unit column] (label beneath) |

### 3.4 Message Bubble (`lib/features/chat_room/widgets/message_bubble.dart`)

| Property | Before | After |
|---|---|---|
| user bg | `AppColors.primaryBlue` | `XiaColors.accent` |
| user text | white | white |
| user border-radius | 16/16/16/4 | 20/20/20/8 (`XiaRadius.xl` with bottom-right sm) |
| agent bg | `surfaceContainerHighest` | `XiaColors.surface` |
| agent shadow | none | `XiaShadow.s` |
| agent border-radius | 16/16/4/16 | 20/20/8/20 (`XiaRadius.xl` with bottom-left sm) |
| max-width | no limit | 78% of screen |
| padding | 12/16 | 12/20 (`s3`/`s5`) |
| line-height | default | 1.6 |
| avatar in bubble | CircleAvatar | 28×28, borderRadius 8 (`XiaRadius.sm`) |
| code block bg | M3 default | `XiaColors.surface2` |
| inline code bg | M3 default | `rgba(245,244,240,0.06)` |
| msg time | — | 11px, `XiaColors.text4`, tabular-nums |

### 3.5 Chat Input Bar (`lib/features/chat_room/widgets/chat_input_bar.dart`)

| Property | Before | After |
|---|---|---|
| input bg | `surfaceContainerHighest` | `XiaColors.surface` |
| input border-radius | 24 (pill) | 16 (`XiaRadius.lg`) |
| input padding | default | 12/20 (`s3`/`s5`) |
| send btn bg | `primaryBlue` | `XiaColors.accent` |
| send btn size | 36×36 | 40×40 |
| send btn disabled | — | opacity 0.3 |
| plus btn bg | `surfaceContainerHighest` | `XiaColors.surface2` |
| plus btn size | 36×36 | 40×40 |
| bar bg | `colorScheme.surface` | transparent / `XiaColors.bg` |
| placeholder | "输入消息..." | "写点什么..." |
| divider | top 0.5px | none |

### 3.6 Quick Command Bar (`lib/features/chat_room/widgets/quick_command_bar.dart`)

| Property | Before | After |
|---|---|---|
| chip shape | `ActionChip` default | capsule (`XiaRadius.full`) |
| chip bg | `accent.withAlpha(20)` | `XiaColors.surface2` |
| chip text color | — | `XiaColors.accent` |
| chip text size | 13px | 13px, weight 500 |
| chip padding | default | h:8, v:16 (`s2`/`s4`) |
| press feedback | default | bg → `XiaColors.accentMuted`, scale 0.95 |

### 3.7 Tool Call Card (`lib/features/chat_room/widgets/tool_call_card.dart`)

| Property | Before | After |
|---|---|---|
| left border | 1px colored | 3px `XiaColors.accent` |
| bg | `surfaceContainerHighest` | `XiaColors.surface2` |
| border-radius | 12 | 12 (`XiaRadius.md`) |
| padding | 12 | 12/16 (`s3`/`s4`) |
| tool name | — | weight 600, `XiaColors.accent` |
| status text | — | 11px, `XiaColors.green` |

### 3.8 Thinking Indicator (`lib/features/chat_room/widgets/thinking_indicator.dart`)

| Property | Before | After |
|---|---|---|
| bubble bg | `surfaceContainerHighest` | `XiaColors.surface` |
| bubble shadow | none | `XiaShadow.s` |
| bubble border-radius | 16/16/16/4 | 20/20/8/20 (matches Agent bubble) |
| dot size | 8×8 | 6×6 |
| dot color | `onSurface.withAlpha(150)` | `XiaColors.text3` |
| animation | 1200ms custom bounce | 800ms `typingBounce` pattern (40% → translateY(-8px)) |
| dot delays | — | 0s / 0.15s / 0.3s |

### 3.9 Connection Banner (`lib/ui_kit/connection_banner.dart`)

| Property | Before | After |
|---|---|---|
| warning bg | `statusConnecting.withAlpha(25)` | `rgba(196,168,106,0.12)` |
| warning text | — | `XiaColors.yellow` |
| info bg | `statusOffline.withAlpha(25)` | `XiaColors.accentMuted` |
| info text | — | `XiaColors.accent` |
| animation | instant show/hide | slide-in 350ms transform |

### 3.10 Empty State (`lib/ui_kit/empty_state.dart`)

| Property | Before | After |
|---|---|---|
| icon color | `colorScheme.outline` | `XiaColors.text4` |
| title color | `onSurface` | `XiaColors.text2` |
| title size | titleMedium | 17px, weight 600 |
| desc color | `outline` | `XiaColors.text3` |
| padding | 32 | 48 vertical / 24 horizontal (`s9`/`s6`) |
| icon size | 64 | 48px, opacity 0.7 |

### 3.11 Loading Skeleton (`lib/ui_kit/loading_skeleton.dart`)

| Property | Before | After |
|---|---|---|
| bg color | `surfaceContainerHighest` | `XiaColors.surface` |
| shimmer base | — | `XiaColors.surface2` |
| shimmer highlight | — | `XiaColors.surface3` |
| border-radius | 4 | 8 (`XiaRadius.sm`) |

### 3.12 Emoji Avatar (`lib/ui_kit/emoji_avatar.dart`)

| Property | Before | After |
|---|---|---|
| shape | CircleAvatar | rounded rect (borderRadius varies by context) |
| border-radius | n/a (circle) | 12 for cards, 8 for chat header, 16 for detail |

**Note**: This widget needs context awareness. Add optional `borderRadius` parameter, default to `XiaRadius.md` (12).

### 3.13 Color Grid (`lib/ui_kit/color_grid.dart`)

| Property | Before | After |
|---|---|---|
| grid columns | auto (Wrap) | 6 columns (`XiaSpacing.s3` gap) |
| color dot size | 32×32 (circle) | 40×40, borderRadius 8 (`XiaRadius.sm`) |
| selection border | 1px white + shadow | 3px `XiaColors.text1` + `0 0 16px rgba(245,244,240,0.15)` glow |
| checkmark | none | white ✓ after selection |
| press feedback | none | scale(0.9) |

### 3.14 Instance Card (`lib/features/instance_manager/widgets/instance_card.dart`)

| Property | Before | After |
|---|---|---|
| icon size | — | 44×44, borderRadius 12 |
| card border-radius | 12 (from CardTheme) | 16 (`XiaRadius.lg`) |
| card padding | default | 20 (`XiaSpacing.s5`) |
| gap | default | 16 (`XiaSpacing.s4`) |
| name size | titleMedium | 16px, weight 600, letterSpacing -0.2 |
| url font | bodySmall | 13px, `XiaColors.text3`, `SF Mono` font |
| status dot | — | 6×6, online: green + glow, offline: text4 |
| action btn | — | 36×36, borderRadius 8, bg `XiaColors.surface2` |

### 3.15 Conversation Tile (`lib/features/message_hub/widgets/conversation_tile.dart`)

| Property | Before | After |
|---|---|---|
| avatar | 48×48 CircleAvatar | 48×48, borderRadius 12 |
| status dot | 14×14 | 8×8, 2px border `XiaColors.surface` |
| unread badge | `Colors.red` | `XiaColors.accent`, 18px height, capsule |
| preview text | bodySmall | 14px, `XiaColors.text3`, 38-char truncation |
| "你:" prefix | — | `XiaColors.text2` colored |
| time | labelSmall | 12px, `XiaColors.text4`, tabular-nums |
| divider | Divider(indent: 76) | `rgba(245,244,240,0.04)` full-width |

### 3.16 Profile Header (`lib/features/agent_profile/widgets/profile_header.dart`)

| Property | Before | After |
|---|---|---|
| avatar size | CircleAvatar 72px | 72×72, borderRadius 16 |
| avatar border | 4px agent color | removed (use background color only) |
| name size | headlineSmall | 24px, weight 700, letterSpacing -0.5 |
| desc size | bodyMedium | 14px, `XiaColors.text3`, lineHeight 1.5 |
| status row | dot + text | dot(6×6) + text(13px, 500), online: green, offline: text4 |

### 3.17 Stats Grid (`lib/features/agent_profile/widgets/stats_grid.dart`)

| Property | Before | After |
|---|---|---|
| grid | 3 cols, 1px spacing | 3 cols, 12px gap |
| card bg | `surfaceContainerHighest` | `XiaColors.surface` |
| card border-radius | default | 12 (`XiaRadius.md`) |
| card padding | default | 20/12 (`s5`/`s3`) |
| value color | `AppColors.primaryBlue` | `XiaColors.text1` |
| value size | 22px | 24px, weight 700, tabular-nums |
| label size | labelSmall | 11px, `XiaColors.text3`, weight 500 |

### 3.18 Agent Config Page (`lib/features/agent_profile/agent_config_page.dart`)

| Property | Before | After |
|---|---|---|
| section card bg | `surfaceContainerHighest` | `XiaColors.surface` |
| section card border-radius | 12 | 16 (`XiaRadius.lg`) |
| section card padding | default | 20 (`XiaSpacing.s5`) |
| section title | — | 12px, weight 600, uppercase, letterSpacing 0.8 |
| avatar | CircleAvatar 64px | 64×64, borderRadius 16 |
| edit badge | — | 22×22, borderRadius 8, `XiaColors.accent` bg |
| input height | default | 44px |
| input border | outline | `inset shadow 1px XiaColors.surface3` |
| input focus border | primary colored | `inset shadow 1px XiaColors.accent` |
| save btn | `FilledButton` | custom: 52px height, borderRadius 12, `XiaColors.accent` bg, accent glow shadow |
| nickname label | — | 13px, `XiaColors.text3`, width 52px |

### 3.19 Add Instance Page (`lib/features/instance_manager/add_instance_page.dart`)

| Property | Before | After |
|---|---|---|
| form input height | default | 48px |
| form input border-radius | default | 12 (`XiaRadius.md`) |
| form input border | outline | `inset shadow 1.5px XiaColors.surface3` |
| form input focus | primary colored | `inset shadow 1.5px XiaColors.accent` |
| form label | — | 12px, weight 600, uppercase, letterSpacing 0.5 |
| form hint | — | 12px, `XiaColors.text4` |
| tab switcher | — | `XiaColors.surface` bg, 3px padding, active: `XiaColors.accent` |
| connect btn | `FilledButton` | custom primary btn: 52px, borderRadius 12, accent glow |
| QR scan area | — | 200×200, borderRadius 20, `XiaColors.surface` bg |

### 3.20 Settings Page (currently stub/not implemented)

- Setting row: 20px padding, `rgba(245,244,240,0.04)` divider
- Left: emoji + label (15px), Right: value (`XiaColors.text3`)
- Container: `XiaColors.surface` bg, borderRadius 16
- Footer: centered, 12px `XiaColors.text4`

---

## Module 4: Glassmorphism & Motion

### 4.1 Glassmorphism Implementations

**Bottom Nav** (custom implementation, replaces M3 `NavigationBar`):
```dart
ClipRect(
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
    child: Container(
      height: 72,
      decoration: BoxDecoration(
        color: Color(0xE0111110),  // rgba(17,17,16,0.88)
        border: Border(top: BorderSide(color: XiaColors.text4, width: 0.5)),
      ),
      child: Row(...),  // 3 nav items
    ),
  ),
)
```
Saturation boost: wrap with `ColorFiltered` using a saturation matrix (scale 1.4).

**Toast** (new widget `lib/ui_kit/toast.dart`):
```dart
BackdropFilter(
  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
  child: Container(
    decoration: BoxDecoration(
      color: XiaColors.surfaceElevated,
      borderRadius: BorderRadius.circular(999),
      boxShadow: XiaShadow.l,
    ),
  ),
)
```
Position: top 72px, centered. Show/hide: 350ms slide + fade. Auto-dismiss: 2500ms.

### 4.2 Motion System

**Custom page transition** (`lib/app/theme/page_transition.dart`, new):
- Forward: incoming from right (translateX: 100% → 0), outgoing to left (-30% + fade)
- Back: incoming from left (-30% → 0), outgoing to right (0 → 100%)
- Duration: transform 500ms `XiaMotion.ease`, opacity 350ms same curve
- Built as a custom `PageTransitionsBuilder`

**Button press feedback** — replace `InkWell` ripple with scale animation:
- Header buttons: `scale(0.95)` + bg shift
- Cards: `scale(0.98)` + bg shift
- Primary buttons: `scale(0.97)` + brightness(0.92)
- Send button: `scale(0.92)`

**Message entry animation**: `SlideTransition` + `FadeTransition`, from translateY(12px) to 0, 350ms `XiaMotion.ease`.

**Staggered list entry**: Agent cards animate in with `slideUp` animation (from translateY(20px) to 0), 40ms increments between cards (`delay-1` through `delay-5`).

**Chevron rotation**: Instance group collapse/expand — `RotationTransition` 200ms.

---

## Module 5: Page Layout Adjustments

Layout corrections to match ComponentSpec page structures. All changes are visual positioning/sizing — routing and data flow untouched.

| Page | Adjustment |
|---|---|
| **Home** | Header: title left-aligned (no centered AppBar), buttons right. Stats bar below header. |
| **Messages** | Same header pattern as home. List items: structured per spec (avatar + info + badge). |
| **Chat** | Header: back btn (40×40, transparent bg) + avatar (40×40, br 8) + name/status + more btn. No default AppBar. |
| **Agent Detail** | Header: back btn + title "虾名" (22px) + edit btn. Profile section centered. Stats grid 3×2. |
| **Agent Config** | Header: back btn + title "个性化配置" (22px). Sections: avatar editor, nickname/desc inputs, color grid (6 cols), command list, save btn. |
| **Instances** | Header: title "实例" (no back btn, main tab). Cards per spec. Add button with dashed border. |
| **Add Instance** | Header: back btn + title "添加实例". Tab switcher + form groups / QR area. |
| **Settings** | Header: back btn + title "设置". Rows in surface container with dividers. Footer text. |

---

## Implementation Order

```
1. tokens.dart          — new file, zero risk
2. theme.dart           — rewrite, establishes visual foundation
3. page_transition.dart — new file, custom transition builder
4. toast.dart           — new file, toast widget
5. ui_kit/ components   — emoji_avatar, empty_state, loading_skeleton, color_grid, connection_banner
6. features/ components — agent_card, stats_bar, message_bubble, chat_input_bar, quick_command_bar, tool_call_card, thinking_indicator, instance_card, conversation_tile, profile_header, stats_grid
7. features/ pages      — agent_list_page, chat_room_page, message_hub_page, agent_profile_page, agent_config_page, instance_list_page, add_instance_page
8. router.dart          — bottom nav glassmorphism + page transition wiring
```

---

## Constraints & Risks

### Constraints
- **Zero business logic changes**: No changes to ViewModels, UseCases, Repositories, Providers, or data models.
- **No navigation changes**: Routes, navigation structure, and smart back stack logic unchanged.
- **Always dark mode**: `ThemeMode.dark` — the design spec defines only a dark palette. System light/dark setting is ignored.
- **Accessibility**: All text must meet WCAG AA contrast on their background surfaces per DesignToken-虾Hub.md Section 1.

### Risks
- **Low**: All changes are visual-layer only. Existing tests should continue to pass (no logic changes).
- **Medium**: Glassmorphism `BackdropFilter` performance on low-end Android devices. Mitigation: apply filter only on nav/toast, not on scrollable content.
- **Low**: M3 `NavigationBar` → custom implementation loses built-in a11y. Mitigation: add `Semantics` labels to nav items.

---

## Verification

1. `flutter analyze` — zero new warnings
2. `flutter test` — all existing tests pass
3. Visual spot-check: compare each page against `docs/虾Hub-原型Demo-Premium.html` side-by-side
4. Color audit: verify all hardcoded `Color(...)` uses are in `tokens.dart` or `theme.dart` only (grep for `Color(0x` outside theme/)

---

*Design approved 2026-06-11. Implementation via writing-plans skill.*
