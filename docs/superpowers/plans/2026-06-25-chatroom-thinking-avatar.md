# ChatRoom Thinking Indicator — Remove Stray Avatar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the spec-out 28×28 `Icons.psychology` avatar block from `ThinkingIndicator` so the implementation matches `component-spec-v2.md §4.3` (bubble + three bouncing dots only). Update tests + spec note + verify visually.

**Architecture:** Single-file widget edit (`thinking_indicator.dart`) — delete the icon `Container` and its trailing `SizedBox(width: XiaSpacing.s2)`, leaving only the bubble+dots `Container` inside the outer `Row`. `ThinkingIndicator()` constructor signature stays unchanged. Test file (`thinking_indicator_test.dart`) flips two `Icons.psychology` assertions from `findsOneWidget` to `findsNothing` and removes a redundant mid-animation assertion. Design spec gets a one-line "no avatar" note to lock down the contract.

**Tech Stack:** Flutter 3.x, Dart 3.x, `flutter_test`, `flutter analyze`. No new dependencies.

## Global Constraints

- **Law 17 (TDD)**: For this widget change, RED step = test updated to assert new (avatar-absent) behavior and run it to confirm it FAILS. GREEN step = widget edited, run again, confirm it PASSES. Both land in the same commit per Law 17 ("Repository/Widget no later than same commit").
- **Law 14 (≥2 widget tests)**: Existing `thinking_indicator_test.dart` already has 3 tests; this plan keeps 2 tests (the redundant mid-animation `Icons.psychology` assertion is removed; remaining 2 cover both positive behavior — three dots present — and negative behavior — psychology icon absent). Test count goes 3 → 2, but coverage of the new contract is preserved.
- **Law 1 (domain pure)**: N/A — this change is purely UI-layer, no `lib/domain/` touched.
- **Law 2 (widgets render UI only)**: Widget continues to render UI only; no business logic added.
- **Commit message format**: `feat(chat_room): remove stray avatar from ThinkingIndicator` (Conventional Commits, single commit per scope).
- **Test runner**: `flutter test test/features/chat_room/thinking_indicator_test.dart -v`. Run from repo root `D:\claude\ClawHub\ClawHub-app`.
- **Verification before completion**: each commit ends with `flutter analyze && flutter test test/features/chat_room/thinking_indicator_test.dart` (must pass zero warnings/errors).
- **Out of scope**: `StreamingBubble`, `chat_view_model`, `chat_room_page.dart` call site, `showAvatar` parameter, bubble color/radius/width, animation period.

---

## File Responsibility Map

| File | Responsibility | Δ |
|------|---------------|-----|
| `lib/features/chat_room/widgets/thinking_indicator.dart` | Remove icon Container + SizedBox from outer Row | −13 lines |
| `test/features/chat_room/thinking_indicator_test.dart` | Flip psychology assertions, remove redundant mid-animation check | 3 lines changed, 1 line removed |
| `docs/design/component-spec-v2.md` | Add "no avatar" note in §4.3 | +3 lines |
| `docs/superpowers/specs/2026-06-25-chatroom-thinking-avatar-design.md` | Already committed at `e23c7dd` (no change) | 0 |

**Total**: ~17 lines changed across 3 files. Single widget edit + spec note + test update.

---

## Task 1: TDD — Remove Stray Avatar (RED → GREEN, 1 commit)

**Rationale:** Smallest possible unit of work that delivers the user-visible behavior change. TDD discipline: test updated first to assert the new contract (no psychology icon), then widget edited to satisfy it, both in the same commit per Law 17. Constructor signature unchanged → no callers need updating.

**Risk if skipped:** Implementation drifts further from design spec; future PRs reintroduce the avatar without tests catching it.

### Task 1.1: RED — Update test to assert avatar absence

**Files:**
- Modify: `test/features/chat_room/thinking_indicator_test.dart` (existing 46-line file)

**Interfaces:**
- Consumes: `ThinkingIndicator` widget (signature unchanged), `Icons.psychology`, `_BouncingDot` (private)
- Produces: Failing assertions that lock down the new "no psychology icon, three dots still present" contract

- [ ] **Step 1: Read current test file to confirm exact text**

Run (read-only):
```
Read tool on D:\claude\ClawHub\ClawHub-app\test\features\chat_room\thinking_indicator_test.dart
```

Confirm the file matches the 46-line structure shown in the spec (3 tests: psychology icon present / 3 dots present / animation with psychology icon still present).

- [ ] **Step 2: Replace the first test name + assertion**

In `test/features/chat_room/thinking_indicator_test.dart`, change:

```dart
testWidgets('renders psychology icon indicating AI thinking', (tester) async {
  await tester.pumpWidget(buildIndicator());

  expect(find.byIcon(Icons.psychology), findsOneWidget);
});
```

to:

```dart
testWidgets('does NOT render psychology avatar icon (spec §4.3: bubble+dots only)', (tester) async {
  await tester.pumpWidget(buildIndicator());

  expect(find.byIcon(Icons.psychology), findsNothing);
});
```

- [ ] **Step 3: Remove the third test's redundant mid-animation psychology assertion**

In the third test (`'animates dots with bouncing motion'`), change:

```dart
testWidgets('animates dots with bouncing motion', (tester) async {
  await tester.pumpWidget(buildIndicator());

  // All three dots should be present
  final dotFinder = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_BouncingDot',
  );
  expect(dotFinder, findsNWidgets(3));

  // Pump forward to exercise the animation controller (now 800ms cycle)
  await tester.pump(const Duration(milliseconds: 300));
  // Widget should still be present after animation ticks
  expect(find.byIcon(Icons.psychology), findsOneWidget);
});
```

to:

```dart
testWidgets('animates dots with bouncing motion', (tester) async {
  await tester.pumpWidget(buildIndicator());

  // All three dots should be present
  final dotFinder = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_BouncingDot',
  );
  expect(dotFinder, findsNWidgets(3));

  // Pump forward to exercise the animation controller (now 800ms cycle)
  await tester.pump(const Duration(milliseconds: 300));
  // Three dots should still be present after animation ticks
  expect(dotFinder, findsNWidgets(3));
});
```

The third test now exercises the animation controller (pump 300ms) without checking a now-irrelevant icon — it confirms the dots survive the animation tick.

- [ ] **Step 4: Run test to verify it FAILS**

Run from repo root `D:\claude\ClawHub\ClawHub-app`:
```bash
flutter test test/features/chat_room/thinking_indicator_test.dart -v
```

**Expected**: FAIL with messages like:
- `Expected: exactly one matching candidate ... Actual: ? ... Which: no candidates` (test 1)
- `Expected: exactly one matching candidate ... Actual: ? ... Which: no candidates` (test 3 still has old assertion)

This is the RED state — tests assert new contract but widget still renders the icon.

### Task 1.2: GREEN — Edit widget to remove avatar block

**Files:**
- Modify: `lib/features/chat_room/widgets/thinking_indicator.dart` (existing 124-line file)

**Interfaces:**
- Consumes: `XiaSpacing.pagePaddingH`, `XiaColors.surface2`, `XiaColors.border`, `XiaRadius.xl`/`xs` (existing tokens)
- Produces: `ThinkingIndicator` widget that renders bubble+3 dots only — `Icons.psychology` no longer referenced in this file

- [ ] **Step 1: Read current widget to confirm exact text**

Run (read-only):
```
Read tool on D:\claude\ClawHub\ClawHub-app\lib\features\chat_room\widgets\thinking_indicator.dart
```

Confirm the file matches the 124-line structure shown in the spec, especially lines 36-86 (the build method Row containing icon Container + SizedBox + bubble Container).

- [ ] **Step 2: Replace the outer Row's children block**

In `lib/features/chat_room/widgets/thinking_indicator.dart`, change the `build` method (lines 36-86):

```dart
@override
Widget build(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: XiaSpacing.pagePaddingH,
      vertical: 4,
    ),
    child: Row(
      children: [
        Container(                            // ← delete this 13-line block
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: XiaColors.accentMuted,
            borderRadius: BorderRadius.circular(XiaRadius.sm),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.psychology,
            size: 16,
            color: XiaColors.accent,
          ),
        ),
        const SizedBox(width: XiaSpacing.s2),  // ← delete this line
        Container(                            // ← keep this bubble
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: XiaColors.surface2,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(XiaRadius.xl),
              topRight: Radius.circular(XiaRadius.xl),
              bottomRight: Radius.circular(XiaRadius.xl),
              bottomLeft: Radius.circular(XiaRadius.xs),
            ),
            border: Border.all(color: XiaColors.border),
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
```

to:

```dart
@override
Widget build(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: XiaSpacing.pagePaddingH,
      vertical: 4,
    ),
    child: Row(
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: XiaColors.surface2,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(XiaRadius.xl),
              topRight: Radius.circular(XiaRadius.xl),
              bottomRight: Radius.circular(XiaRadius.xl),
              bottomLeft: Radius.circular(XiaRadius.xs),
            ),
            border: Border.all(color: XiaColors.border),
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
```

- [ ] **Step 3: Run test to verify it PASSES**

Run from repo root:
```bash
flutter test test/features/chat_room/thinking_indicator_test.dart -v
```

**Expected**: PASS — both tests green:
- "does NOT render psychology avatar icon" → `findsNothing` ✓
- "renders three bouncing dots inside bubble" → `findsNWidgets(3)` ✓
- "animates dots with bouncing motion" → `findsNWidgets(3)` after 300ms tick ✓

- [ ] **Step 4: Run analyzer to confirm zero warnings**

Run from repo root:
```bash
flutter analyze lib/features/chat_room/widgets/thinking_indicator.dart test/features/chat_room/thinking_indicator_test.dart
```

**Expected**: `No issues found!` (or pre-existing warnings only, none introduced by this change).

- [ ] **Step 5: Commit (widget + test together, per Law 17)**

Run from repo root:
```bash
git add lib/features/chat_room/widgets/thinking_indicator.dart test/features/chat_room/thinking_indicator_test.dart
git commit -m "feat(chat_room): remove stray avatar from ThinkingIndicator (spec §4.3)"
```

---

## Task 2: Sync design spec note

**Rationale:** Per spec §3 "Change 3" — lock down the contract in `component-spec-v2.md §4.3` so future implementations don't reintroduce the icon. Pure documentation edit; no code or test change. Committed separately so the widget change and spec change are independently revertable.

**Risk if skipped:** Future agentic implementations may re-add the icon without tests catching it (the new test asserts absence, but a spec note is a clearer upstream signal).

### Task 2.1: Insert "no avatar" note in component-spec-v2.md §4.3

**Files:**
- Modify: `docs/design/component-spec-v2.md` (around line 746, in section 4.3)

- [ ] **Step 1: Insert note after §4.3's "生命周期" line**

In `docs/design/component-spec-v2.md`, after the existing line:

```
**生命周期**: 用户发送消息后插入 DOM，Agent 回复后 remove()。模拟延迟 1200ms + random(0~800ms)。
```

(Line 746) and before `### 4.4 Quick Commands（快捷指令栏）`, insert:

```

**装饰约束**: Typing Indicator 仅由气泡和三个跳动圆点组成，**不包含**左侧头像或图标装饰。容器从页面左 padding 直接开始，不前置 avatar。
```

(That is: one blank line, then the bold note, then a blank line before the next section.)

- [ ] **Step 2: Verify the insertion landed correctly**

Run (read-only):
```
Read tool on D:\claude\ClawHub\ClawHub-app\docs\design\component-spec-v2.md, offset 744, limit 12
```

**Expected**: section §4.3's "生命周期" line, blank line, new "装饰约束" note, blank line, `### 4.4` heading.

- [ ] **Step 3: Commit the spec note**

Run from repo root:
```bash
git add docs/design/component-spec-v2.md
git commit -m "docs(design): add no-avatar note to Typing Indicator §4.3"
```

---

## Task 3: Final verification

**Rationale:** Spec §Verification requires (1) flutter test, (2) flutter analyze, (3) manual visual check. Task 1's green state already covers (1) and (2). This task documents the manual check and runs the broader test suite as a smoke test to catch any unexpected cross-feature breakage.

**Risk if skipped:** Hidden regressions in other chat_room tests (e.g., widget tree snapshot tests) not caught by the targeted test run.

### Task 3.1: Run broader chat_room test suite

- [ ] **Step 1: Run all chat_room tests**

Run from repo root:
```bash
flutter test test/features/chat_room/ -v
```

**Expected**: All tests pass. Pay particular attention to:
- `chat_room_page_test.dart` (uses ThinkingIndicator indirectly via integration)
- `chat_view_model_*_test.dart` (state, no widget render check)
- Any other widget test that pumps the chat_room_page

If any test fails, the cause is most likely a snapshot/golden test comparing the old widget tree — investigate, and only update snapshots if the new layout (bubble+dots only) is the intended final state (it is).

- [ ] **Step 2: Run full repo analyzer**

Run from repo root:
```bash
flutter analyze
```

**Expected**: `No issues found!` (or pre-existing warnings only, no new ones from this change).

- [ ] **Step 3: Manual visual check (document, not execute)**

Document the manual check in the final report to the user. The user (not the agent) should run this since it requires `flutter run` on a device/emulator:

1. `flutter run` on an Android emulator or iOS simulator
2. Navigate to any conversation (or use mock gateway for offline dev — see `lib/app/di/providers.dart`)
3. Send a message → confirm "thinking" state appears within ~1s
4. Visually confirm:
   - Bubble with three bouncing violet dots is visible at bottom-left of chat list
   - **No 28×28 purple square to the left of the bubble**
   - Bubble is left-aligned at page padding (≈ 16px from screen edge), not indented by ~36px
5. While thinking is active, switch to background for 5s and back — confirm dots resume animation (controller not disposed prematurely)
6. When the agent's first streaming text arrives, thinking indicator disappears, `StreamingBubble` takes its place

- [ ] **Step 4: Report completion**

Reply to the user with:
- 2 commits made (widget+test, spec note)
- Test result: `flutter test test/features/chat_room/thinking_indicator_test.dart` — N tests pass
- Analyzer: `flutter analyze` — clean
- Manual visual check: ✅ / ⚠️ (depending on user feedback)
- Diff summary: N lines removed from thinking_indicator.dart, M lines changed in test, 1 line added to spec

---

## Self-Review

**1. Spec coverage:**
- ✅ Spec §Change 1 (remove icon Container + SizedBox) → Task 1.2
- ✅ Spec §Change 2 (update test assertions) → Task 1.1
- ✅ Spec §Change 3 (sync component-spec-v2.md §4.3) → Task 2.1
- ✅ Spec §Verification (`flutter test`, `flutter analyze`, manual visual) → Task 3.1

**2. Placeholder scan:** No TBD/TODO/"implement later" in any step. Every code block is the actual replacement content.

**3. Type consistency:** No new types introduced. `_BouncingDot`, `ThinkingIndicator` constructors unchanged. Test imports unchanged.

**4. Backwards compat:** `ThinkingIndicator()` constructor signature is unchanged — the single call site in `chat_room_page.dart:439` needs no edit. Confirmed.

---

Plan complete. Saved to `D:\claude\ClawHub\ClawHub-app\docs\superpowers\plans\2026-06-25-chatroom-thinking-avatar.md`.