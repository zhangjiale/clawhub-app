# Thinking Indicator — Agent-Themed Dots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change `ThinkingIndicator`'s three bouncing dots from hardcoded `XiaColors.accent2` (violet) to `AgentTheme.of(context).primary`, aligning with the existing agent-theming pattern used by `QuickCommandBar` and `MessageBubble` in the same chat room. Update tests + spec note + verify visually.

**Architecture:** Single widget edit (`thinking_indicator.dart`) — build method reads `dotColor = AgentTheme.of(context).primary` once, threads it to the three `_BouncingDot` children via a new `dotColor` constructor field. `_BouncingDot`'s build method uses the new field instead of the hardcoded `XiaColors.accent2` constant. `ThinkingIndicator()` constructor signature stays unchanged → no caller updates. Test file (`thinking_indicator_test.dart`) parameterizes its wrap helper to optionally accept an `AgentTheme` and adds 2 new tests (color follows AgentTheme primary; falls back to sapphire when absent). Design spec gets a one-line edit + one new note in §4.3.

**Tech Stack:** Flutter 3.x, Dart 3.x, `flutter_test`, `flutter analyze`. No new dependencies.

## Global Constraints

- **Law 17 (TDD)**: For this widget change, RED step = new tests written to assert dot color follows AgentTheme (and falls back when absent), run them, confirm they FAIL against current hardcoded-`accent2` widget. GREEN step = widget edited to take color from AgentTheme, run again, confirm PASS. Both land in the same commit per Law 17 ("Repository/Widget no later than same commit").
- **Law 14 (≥2 widget tests)**: Final test count = 5 (3 existing + 2 new). New tests cover (a) AgentTheme primary color is honored, (b) absence-of-AgentTheme fallback is sapphire. Coverage of new contract is preserved.
- **Law 1 (domain pure)**: N/A — this change is purely UI-layer, no `lib/domain/` touched.
- **Law 2 (widgets render UI only)**: Widget continues to render UI only; no business logic added.
- **Commit message format**: `feat(chat_room): agent-themed dots in ThinkingIndicator` (Conventional Commits, single commit per scope).
- **Test runner**: `flutter test test/features/chat_room/thinking_indicator_test.dart -v`. Run from repo root `D:\claude\ClawHub\ClawHub-app`.
- **Verification before completion**: each commit ends with `flutter analyze && flutter test test/features/chat_room/thinking_indicator_test.dart` (must pass zero warnings/errors).
- **Existing precedents to match**: `lib/features/chat_room/widgets/quick_command_bar.dart:26` reads `final themeColor = AgentTheme.of(context).primary;`. `lib/features/chat_room/widgets/message_bubble.dart:96` uses `? AgentTheme.of(context).primary` for the user bubble's retry tint. Test wrap precedent: `test/features/chat_room/widgets/quick_command_bar_test.dart:18` uses `MaterialApp(theme: ThemeData(extensions: agentTheme != null ? [agentTheme] : []), home: Scaffold(body: child))`.
- **Out of scope**: bubble background/border/radius/padding/animation period, `StreamingBubble`, `chat_view_model`, `chat_room_page.dart` call site, `AgentTheme` class itself, design spec sections other than §4.3.

---

## File Responsibility Map

| File | Responsibility | Δ |
|------|---------------|-----|
| `lib/features/chat_room/widgets/thinking_indicator.dart` | Read AgentTheme primary in build; thread to `_BouncingDot.dotColor`; update class+inline comments | +3 lines (import + 2 comments), edit build method |
| `test/features/chat_room/thinking_indicator_test.dart` | Parameterize wrap helper; add 2 new tests for AgentTheme color + fallback | +50 lines (2 tests + helper update) |
| `docs/design/component-spec-v2.md` | §4.3 Typing Dot table `background` row updated; new "颜色来源" note appended to existing "装饰约束" paragraph | +3 lines, 1 row edit |
| `docs/superpowers/specs/2026-06-25-thinking-indicator-agent-themed-dots-design.md` | Already committed at `ffb2188` (no change) | 0 |

**Total**: ~60 lines changed across 3 files. One widget edit + one test edit + one spec table+note update.

---

## Task 1: TDD — Agent-Themed Dots (RED → GREEN, 1 commit)

**Rationale:** Smallest unit that delivers the user-visible behavior change (dots follow agent theme). TDD: new tests for "uses AgentTheme primary" + "falls back to sapphire" written first, run to FAIL against current hardcoded-violet widget, then widget edited to thread `AgentTheme.of(context).primary` to `_BouncingDot.dotColor`, run to PASS. Both in one commit per Law 17. Constructor signature unchanged → no callers need updating.

**Risk if skipped:** Implementation remains drifted from project-wide agent-theming pattern; user sees jarring color mismatch when switching agents.

### Task 1.1: RED — Add wrap helper parameterization + 2 new color tests

**Files:**
- Modify: `test/features/chat_room/thinking_indicator_test.dart` (existing file; current contents from prior task)

**Interfaces:**
- Consumes: `ThinkingIndicator` widget, `_BouncingDot` (private), `AgentTheme` (from `package:claw_hub/app/theme/agent_theme.dart`)
- Produces: Failing assertions that lock down the new "dots follow AgentTheme primary, fall back to sapphire" contract

- [ ] **Step 1: Read current test file to confirm exact starting state**

Run (read-only):
```
Read tool on D:\claude\ClawHub\ClawHub-app\test\features\chat_room\thinking_indicator_test.dart
```

Confirm the file currently has:
- import for `flutter/material.dart` and `thinking_indicator.dart`
- a `buildIndicator()` helper returning `MaterialApp(home: Scaffold(body: ThinkingIndicator()))`
- 3 tests: (1) "does NOT render psychology avatar icon", (2) "renders three bouncing dots", (3) "animates dots with bouncing motion"

- [ ] **Step 2: Update the existing `buildIndicator` helper to accept optional `AgentTheme`**

Replace the existing `buildIndicator()` definition (and its preceding `MaterialApp(...)`):

```dart
Widget buildIndicator() {
  return const MaterialApp(
    home: Scaffold(
      body: ThinkingIndicator(),
    ),
  );
}
```

with:

```dart
Widget buildIndicator({AgentTheme? agentTheme}) {
  return MaterialApp(
    theme: ThemeData(extensions: agentTheme != null ? [agentTheme] : []),
    home: const Scaffold(body: ThinkingIndicator()),
  );
}
```

Note: `const` keyword removed from outer `MaterialApp` because `theme` is no longer const (it depends on the optional `agentTheme`).

Add a new import at the top of the file (alongside existing imports):

```dart
import 'package:claw_hub/app/theme/agent_theme.dart';
```

- [ ] **Step 3: Append 2 new tests after the existing 3 tests**

At the end of the `group('ThinkingIndicator', ...)` block, add these two tests:

```dart
    testWidgets('dots use AgentTheme primary color when present', (tester) async {
      await tester.pumpWidget(
        buildIndicator(agentTheme: const AgentTheme(primary: Color(0xFF5F9B96))),
      );

      // Find dot Containers by BoxDecoration.shape == BoxShape.circle (only the
      // bouncing dots have circular decoration; the bubble Container has
      // BorderRadius, not shape).
      final dotFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(dotFinder, findsNWidgets(3));
      for (final element in dotFinder.evaluate()) {
        final container = element.widget as Container;
        final decoration = container.decoration as BoxDecoration;
        expect(decoration.color, const Color(0xFF5F9B96));
      }
    });

    testWidgets('dots fall back to sapphire (#4F83FF) when no AgentTheme in scope',
        (tester) async {
      await tester.pumpWidget(buildIndicator()); // no agentTheme

      final dotFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(dotFinder, findsNWidgets(3));
      for (final element in dotFinder.evaluate()) {
        final container = element.widget as Container;
        final decoration = container.decoration as BoxDecoration;
        expect(decoration.color, const Color(0xFF4F83FF)); // V2 sapphire
      }
    });
```

- [ ] **Step 4: Run tests to verify the 2 new tests FAIL**

Run from repo root:
```bash
flutter test test/features/chat_room/thinking_indicator_test.dart -v
```

**Expected**: Tests 1-3 (existing) PASS, tests 4-5 (new) FAIL with messages like:
- `Expected: <Color(0xff5f9b96)>  Actual: <Color(0xff9b7aff)>`  (test 4: hardcoded accent2 ≠ 5F9B96)
- `Expected: <Color(0xff4f83ff)>  Actual: <Color(0xff9b7aff)>`  (test 5: hardcoded accent2 ≠ sapphire)

The dotFinder predicate returns 3 dots correctly (the dots are circles), so the count assertion passes — only the color check fails. This is the RED state.

### Task 1.2: GREEN — Edit widget to thread AgentTheme primary color

**Files:**
- Modify: `lib/features/chat_room/widgets/thinking_indicator.dart` (existing ~124-line file)

**Interfaces:**
- Consumes: `AgentTheme.of(context).primary`, existing `XiaColors` tokens (kept for bubble bg/border)
- Produces: `ThinkingIndicator` widget that renders dots in agent primary color; `_BouncingDot` accepts a `dotColor` constructor parameter

- [ ] **Step 1: Read current widget to confirm exact starting state**

Run (read-only):
```
Read tool on D:\claude\ClawHub\ClawHub-app\lib\features\chat_room\widgets\thinking_indicator.dart
```

Confirm:
- Lines 1-2: `import 'package:flutter/material.dart';` and `import 'package:claw_hub/app/theme/tokens.dart';`
- Lines 4-7: class doc comment
- Lines 35-87: `_ThinkingIndicatorState.build` with bubble Container wrapping 3 `_BouncingDot` calls
- Lines 90-124: `_BouncingDot` private class

- [ ] **Step 2: Add the `agent_theme.dart` import**

After the existing import line `import 'package:claw_hub/app/theme/tokens.dart';`, add:

```dart
import 'package:claw_hub/app/theme/agent_theme.dart';
```

- [ ] **Step 3: Update the class-level doc comment**

Replace the class comment (lines 4-7):

```dart
/// Thinking indicator — three bouncing dots, matching ComponentSpec Section 4.3.
///
/// Bubble: 20/20/8/20 radius (matches Agent bubble), surface bg, shadow-s.
/// Dots: 6×6, text3 color, 800ms bounce cycle, staggered delays.
```

with:

```dart
/// Thinking indicator — three bouncing dots, matching ComponentSpec Section 4.3.
///
/// Bubble: 20/20/8/20 radius (matches Agent bubble), surface bg, border.
/// Dots: 6×6, AgentTheme.of(context).primary (full opacity), 800ms bounce cycle,
/// staggered delays.
```

- [ ] **Step 4: Edit `_ThinkingIndicatorState.build` to read AgentTheme + thread dotColor**

In the build method, after `super.build(context);` (or at the top of the build method, just inside the `@override`), insert a local read:

```dart
@override
Widget build(BuildContext context) {
  final dotColor = AgentTheme.of(context).primary;
  return Padding(
```

The build method body is otherwise unchanged until the `_BouncingDot` calls.

Then update the three `_BouncingDot` calls inside the inner Row's children list. Replace:

```dart
              _BouncingDot(controller: _controller, delay: 0.0),
              const SizedBox(width: 4),
              _BouncingDot(controller: _controller, delay: 0.15),
              const SizedBox(width: 4),
              _BouncingDot(controller: _controller, delay: 0.3),
```

with:

```dart
              _BouncingDot(controller: _controller, delay: 0.0, dotColor: dotColor),
              const SizedBox(width: 4),
              _BouncingDot(controller: _controller, delay: 0.15, dotColor: dotColor),
              const SizedBox(width: 4),
              _BouncingDot(controller: _controller, delay: 0.3, dotColor: dotColor),
```

- [ ] **Step 5: Edit `_BouncingDot` to accept and use the new `dotColor` field**

Replace the entire `_BouncingDot` class (the lines from `class _BouncingDot extends StatelessWidget {` through the closing `}`):

```dart
class _BouncingDot extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final Color dotColor;

  const _BouncingDot({
    required this.controller,
    required this.delay,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    final delayFraction = delay / 0.8;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value + delayFraction) % 1.0;
        // V2: 0-40%: translateY(-6px), 40-80%: back, 80-100%: rest
        final y = t < 0.4
            ? -6.0 * (t / 0.4)
            : t < 0.8
            ? -6.0 + 6.0 * ((t - 0.4) / 0.4)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, y),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              // Dot color from AgentTheme.of(context).primary (spec §4.3)
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
```

The two changes from the original: (a) added `final Color dotColor;` field and required parameter, (b) changed `color: XiaColors.accent2` to `color: dotColor` (also removed the `const` from `BoxDecoration` since `dotColor` is not a compile-time constant).

- [ ] **Step 6: Run tests to verify all 5 PASS**

Run from repo root:
```bash
flutter test test/features/chat_room/thinking_indicator_test.dart -v
```

**Expected**: All 5 tests pass:
1. "does NOT render psychology avatar icon" → `findsNothing` ✓
2. "renders three bouncing dots inside bubble" → `findsNWidgets(3)` ✓
3. "animates dots with bouncing motion" → dots present after 300ms tick ✓
4. "dots use AgentTheme primary color when present" → all 3 dots are `Color(0xFF5F9B96)` ✓
5. "dots fall back to sapphire (#4F83FF) when no AgentTheme in scope" → all 3 dots are `Color(0xFF4F83FF)` ✓

- [ ] **Step 7: Run analyzer to confirm zero new warnings**

Run from repo root:
```bash
flutter analyze lib/features/chat_room/widgets/thinking_indicator.dart test/features/chat_room/thinking_indicator_test.dart
```

**Expected**: `No issues found!` (or pre-existing warnings only; verify no new warnings introduced by this change).

- [ ] **Step 8: Commit (widget + test together, per Law 17)**

Run from repo root:
```bash
git add lib/features/chat_room/widgets/thinking_indicator.dart test/features/chat_room/thinking_indicator_test.dart
git commit -m "feat(chat_room): agent-themed dots in ThinkingIndicator"
```

---

## Task 2: Sync design spec — §4.3 dot color + color-source note

**Rationale:** Per spec §"Change 3" — update the design spec to reflect the new dot color contract. Two edits: (a) the `background` row in §4.3's "Typing Dot" table, (b) a new "颜色来源" note appended to the existing "装饰约束" paragraph (already added by the prior task). Pure documentation edit; no code or test change. Committed separately so widget+test and spec are independently revertable.

**Risk if skipped:** Spec contradicts implementation; future readers reference "紫罗兰" but see agent-colored dots.

### Task 2.1: Update §4.3 Typing Dot table `background` row + append color-source note

**Files:**
- Modify: `docs/design/component-spec-v2.md` (around lines 724-732 in §4.3)

- [ ] **Step 1: Read §4.3 to confirm current state**

Run (read-only):
```
Read tool on D:\claude\ClawHub\ClawHub-app\docs\design\component-spec-v2.md, offset 708, limit 45
```

Confirm §4.3 contains:
- Title `### 4.3 Typing Indicator（输入中指示器）`
- A "容器 .typing-indicator" table
- A "Typing Dot（跳动圆点） .typing-dot" table whose `background` row reads `var(--accent2)（紫罗兰色）`
- A "三个圆点的延迟" bullet list
- A "生命周期" line
- A "装饰约束" paragraph (added by the prior spec/task) that ends right before `### 4.4 Quick Commands（快捷指令栏）`

- [ ] **Step 2: Edit the `background` row of the Typing Dot table**

In the table whose row currently reads:

```
| background | `var(--accent2)`（紫罗兰色） |
```

change that row to:

```
| background | agent 主色（取自 `AgentTheme.of(context).primary`；agent 不在 scope 时回退 V2 sapphire `#4F83FF`） |
```

Keep the row's position in the table (after `border-radius`, before `动画`).

- [ ] **Step 3: Append a "颜色来源" note to the existing "装饰约束" paragraph**

Find the existing "装饰约束" paragraph (added by the prior task; it currently reads in full):

```
**装饰约束**: Typing Indicator 仅由气泡和三个跳动圆点组成，**不包含**左侧头像或图标装饰。容器从页面左 padding 直接开始，不前置 avatar。
```

Replace it with:

```
**装饰约束**: Typing Indicator 仅由气泡和三个跳动圆点组成，**不包含**左侧头像或图标装饰。容器从页面左 padding 直接开始，不前置 avatar。

**颜色来源**: 圆点背景色取自当前页面的 AgentTheme primary，与 QuickCommandBar pill 文字、MessageBubble 用户气泡背景保持一致；无 AgentTheme 时回退 V2 sapphire `#4F83FF`。
```

That is: one blank line between the existing "装饰约束" sentence and the new "颜色来源" sentence; then the next section (`### 4.4`) remains at the same position.

- [ ] **Step 4: Verify the insertion landed correctly**

Run (read-only):
```
Read tool on D:\claude\ClawHub\ClawHub-app\docs\design\component-spec-v2.md, offset 724, limit 30
```

**Expected**: §4.3's "Typing Dot" table with the new `background` row, followed by "三个圆点的延迟" bullets, "生命周期" line, "装饰约束" paragraph, blank line, new "颜色来源" paragraph, blank line, `### 4.4` heading.

- [ ] **Step 5: Commit the spec edit**

Run from repo root:
```bash
git add docs/design/component-spec-v2.md
git commit -m "docs(design): agent-themed dot color in Typing Indicator §4.3"
```

---

## Task 3: Final verification

**Rationale:** Spec §Verification requires (1) `flutter test`, (2) `flutter analyze`, (3) manual visual check. Task 1's green state already covers (1) for the targeted file and (2) for the changed files. This task runs the broader chat_room suite as a smoke test to catch any cross-feature regressions (e.g., chat_room_page_test.dart exercising the widget tree indirectly).

**Risk if skipped:** Hidden regressions in other chat_room tests not caught by the targeted test run.

### Task 3.1: Run broader chat_room test suite + full repo analyzer

- [ ] **Step 1: Run all chat_room tests**

Run from repo root:
```bash
flutter test test/features/chat_room/ -v
```

**Expected**: All tests pass. Pay particular attention to:
- `thinking_indicator_test.dart` (5/5 from Task 1)
- `chat_room_page_test.dart` (uses `ThinkingIndicator` indirectly via integration)
- `quick_command_bar_test.dart` and `message_bubble_test.dart` (sister agent-themed widgets — no change expected)

If any test fails, the cause is most likely a snapshot/golden test comparing the old dot color — REPORT and do NOT auto-update snapshots.

- [ ] **Step 2: Run full repo analyzer**

Run from repo root:
```bash
flutter analyze
```

**Expected**: `No issues found!` for `lib/features/chat_room/widgets/thinking_indicator.dart` and `test/features/chat_room/thinking_indicator_test.dart`. (218 pre-existing repo-wide issues are expected and unrelated — confirmed in the prior task.)

- [ ] **Step 3: Document manual visual check (do not execute)**

Document for the user. The user (not the agent) must run this since it requires `flutter run` on a device/emulator:

1. `flutter run` on an Android emulator or iOS simulator (or use mock gateway for offline dev — see `lib/app/di/providers.dart`, switch `wsGatewayClientProvider` → `mockGatewayClientProvider`)
2. Open **agent #1** conversation, send a message → confirm 3 dots appear in **agent #1's theme color** (e.g., default V2 sapphire `#4F83FF`)
3. Back out, open **agent #2** conversation (different `themeColor`), send a message → confirm 3 dots appear in **agent #2's theme color** (e.g., `#5F9B96` if that's the agent's chosen color, or whatever they set in agent config)
4. Open **agent #3** conversation (yet another theme color) → confirm dots change accordingly
5. Verify the bubble background remains gray (`surface2`) and the border remains gray — only the dots change
6. Verify the animation timing (800ms cycle, staggered delays) is unchanged — the dots still bounce the same way

- [ ] **Step 4: Report completion**

Reply to the user with:
- 2 commits made (widget+test, spec edit)
- Test result: `flutter test test/features/chat_room/thinking_indicator_test.dart` — 5/5 pass
- Analyzer: `flutter analyze` — clean for changed files
- Manual visual check: ✅ / ⚠️ (depending on user feedback)
- Diff summary: lines changed in thinking_indicator.dart (≈ 3 added + edits), lines added in test (≈ 50), lines changed in spec (1 row + 1 note)

---

## Self-Review

**1. Spec coverage:**
- ✅ Spec §Change 1 (widget edit: read AgentTheme, thread `dotColor` to `_BouncingDot`) → Task 1.2
- ✅ Spec §Change 2 (test wrap helper + 2 new tests for color + fallback) → Task 1.1
- ✅ Spec §Change 3 (design spec §4.3 row + color-source note) → Task 2.1
- ✅ Spec §Verification (`flutter test`, `flutter analyze`, manual visual) → Task 3.1

**2. Placeholder scan:** No TBD/TODO/"implement later" in any step. Every code block is the actual replacement content.

**3. Type consistency:** No new types introduced beyond a `Color dotColor` field on `_BouncingDot`. `ThinkingIndicator()` constructor signature is unchanged. The `_BouncingDot` constructor gains one required parameter — but it's a private class with only one call site (the widget itself), so no external breakage. `AgentTheme.of(context).primary` returns `Color`, matching the new field type.

**4. Backwards compat:** `ThinkingIndicator()` constructor signature is unchanged — the single call site in `chat_room_page.dart:439` needs no edit. Confirmed by inspection of the spec's "Out of scope" list and the plan's "Out of scope" constraint.

---

Plan complete. Saved to `D:\claude\ClawHub\ClawHub-app\docs\superpowers\plans\2026-06-25-thinking-indicator-agent-themed-dots.md`.