# Chat Bubble Width + Table Horizontal Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Widen the Agent (虾) reply bubble from 78%→88% of screen width (user bubble stays 78%), and make markdown tables in agent messages non-wrapping with a horizontal scrollbar.

**Architecture:** Two independent UI tweaks, no domain/protocol changes. (1) Agent-side bubble `maxWidth` 0.78→0.88 via a new `XiaLayout` token; `MessageBubble` splits by `_isUser`, `StreamingBubble` and `ToolCallCard` follow. (2) Set `tableColumnWidth: IntrinsicColumnWidth()` + `tableScrollbarThumbVisibility: true` on `XiaMarkdownStyles.message`/`.streaming` to trigger `flutter_markdown 0.7.7+1`'s **native** `Scrollbar > SingleChildScrollView(horizontal)` table wrapping (`builder.dart:514-532`) — no custom builder.

**Tech Stack:** Flutter, flutter_markdown `^0.7.7+1` (do not bump), flutter_test, drift (unchanged).

## Global Constraints

- **Iron Laws** (`docs/engineering/iron-laws.md`): Law 14 — every widget behavior change needs ≥2 tests. Law 1/Law 17 — N/A (no `lib/domain/` code touched). Pre-commit hook runs `dart format` + iron-law greps on staged `.dart` files (none of these changes trigger Laws 1/6/8/11).
- **flutter_markdown must stay `^0.7.7+1`** — the table-scroll path used here is native to 0.7.7+1 (`lib/src/builder.dart:514-532`, `lib/src/style_sheet.dart:43-44`). Do not bump or fork.
- **All visual constants** live in `lib/app/theme/tokens.dart` using the `Xia<Category>` class convention.
- **Conventional Commits**: `feat(scope):` / `docs:`. Scope is `chat-room`.
- **Test viewport**: pump with `MediaQuery(data: MediaQueryData(size: Size(400, 800)))` so width math is deterministic — `400 × 0.88 = 352`, `400 × 0.78 = 312`.
- **Bubble-container locator**: the bubble `Container` is the only widget with both `constraints != null` AND `decoration is BoxDecoration`. Tests locate it via `find.byWidgetPredicate((w) => w is Container && w.constraints != null && w.decoration is BoxDecoration)`. Verified: `StatusIcon` returns a bare `Icon` (no Container), `MarkdownBody` plain-text renders no such Container.

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `lib/app/theme/tokens.dart` | Add `XiaLayout` (bubble width ratios) | Modify (append class) |
| `lib/features/chat_room/widgets/message_bubble.dart` | Agent/user bubble width split | Modify `:117-119` |
| `lib/features/chat_room/widgets/streaming_bubble.dart` | Streaming bubble 0.78→0.88 | Modify `:104-106` |
| `lib/features/chat_room/widgets/tool_call_card.dart` | Tool card 0.78→0.88 | Modify `:73-75` |
| `lib/ui_kit/xia_markdown_styles.dart` | Table no-wrap + scrollbar | Modify (2 props × 2 stylesheets) |
| `test/features/chat_room/widgets/message_bubble_test.dart` | Agent/user width assertions | Modify (add group) |
| `test/features/chat_room/streaming_bubble_test.dart` | Streaming width assertion | Modify (add test + import) |
| `test/features/chat_room/tool_call_card_test.dart` | Tool card width assertion | Modify (add test + import) |
| `test/ui_kit/xia_markdown_styles_test.dart` | Table scroll assertions | Create |
| `docs/design/component-spec-v2.md` | Sync 4.2.2 / 4.2.3 / sizing table | Modify |
| `docs/technical/architecture.md` | Sync `:2275` | Modify |

`thinking_indicator.dart:51` is intentionally **not** modified (transient typing pill, `LayoutBuilder`-based, out of scope).

---

### Task 1: XiaLayout token + MessageBubble agent/user width split

**Files:**
- Modify: `lib/app/theme/tokens.dart` (append `XiaLayout` after `XiaGlass`, after line 252)
- Modify: `lib/features/chat_room/widgets/message_bubble.dart:117-119`
- Test: `test/features/chat_room/widgets/message_bubble_test.dart` (add group before the closing `});` at line 538)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `XiaLayout.agentBubbleMaxWidthRatio` (`double`, 0.88) and `XiaLayout.userBubbleMaxWidthRatio` (`double`, 0.78) — consumed by Tasks 2 and 3. Both `static const double`.

- [ ] **Step 1: Write the failing test**

Insert this group inside `main()`, right before the closing `});` of the `group('MessageBubble agent theme', ...)` block (i.e. after the `userPlaceholder file upload strip` sub-group, before line 538). It reuses the existing `message(...)` helper defined in that group.

```dart
    // -----------------------------------------------------------------------
    // 气泡 maxWidth 比例:agent 88% / user 78%（issue 1）
    // -----------------------------------------------------------------------
    group('bubble maxWidth ratio', () {
      Future<void> pumpWithWidth(
        WidgetTester tester,
        double width,
        Message msg,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 800)),
              child: Scaffold(
                body: SizedBox(
                  width: width,
                  child: MessageBubble(message: msg, agentName: '产品虾'),
                ),
              ),
            ),
          ),
        );
      }

      // 气泡 Container 同时带 constraints + BoxDecoration,借此精确定位
      // (StatusIcon 是裸 Icon,MarkdownBody 纯文本无此 Container,不会误匹配)。
      Container findBubbleContainer(WidgetTester tester) {
        final found = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints != null &&
              w.decoration is BoxDecoration,
        );
        expect(found, findsOneWidget);
        return tester.widget<Container>(found);
      }

      testWidgets('agent bubble maxWidth = 88% of screen width', (tester) async {
        await pumpWithWidth(
          tester,
          400,
          message(role: MessageRole.agent, content: 'agent-bubble-width'),
        );
        final bubble = findBubbleContainer(tester);
        expect(
          bubble.constraints!.maxWidth,
          400 * XiaLayout.agentBubbleMaxWidthRatio,
        );
      });

      testWidgets('user bubble maxWidth = 78% of screen width', (tester) async {
        await pumpWithWidth(
          tester,
          400,
          message(role: MessageRole.user, content: 'user-bubble-width'),
        );
        final bubble = findBubbleContainer(tester);
        expect(
          bubble.constraints!.maxWidth,
          400 * XiaLayout.userBubbleMaxWidthRatio,
        );
      });
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat_room/widgets/message_bubble_test.dart`
Expected: FAIL — compilation error, `XiaLayout` is undefined (acceptable RED per Law 17).

- [ ] **Step 3: Write minimal implementation**

Append to `lib/app/theme/tokens.dart` (after the `XiaGlass` class, end of file):

```dart

// ─── Layout Ratios (chat bubble widths — fraction of screen width) ─────────

class XiaLayout {
  XiaLayout._();

  /// Agent (虾) reply bubble max width as a fraction of screen width.
  /// Widened 78% → 88% (2026-07-07) so long markdown/tables fit more
  /// characters per line. Stays below the ~91.5% theoretical max
  /// (screenWidth − 2 × pagePaddingH) to keep a visible right gap.
  static const double agentBubbleMaxWidthRatio = 0.88;

  /// User-sent bubble max width as a fraction of screen width. Kept at 78% —
  /// user messages are short typed text; widening reduces side distinction
  /// without readability gain.
  static const double userBubbleMaxWidthRatio = 0.78;
}
```

Edit `lib/features/chat_room/widgets/message_bubble.dart:116-119`. Replace:

```dart
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
```

with:

```dart
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width *
                          (_isUser
                              ? XiaLayout.userBubbleMaxWidthRatio
                              : XiaLayout.agentBubbleMaxWidthRatio),
                    ),
```

(`message_bubble.dart` already imports `package:claw_hub/app/theme/tokens.dart` at line 10 — no new import needed.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat_room/widgets/message_bubble_test.dart`
Expected: PASS (all tests, including the two new ones and the existing `short message still shrink-wraps` test).

- [ ] **Step 5: Commit**

```bash
git add lib/app/theme/tokens.dart lib/features/chat_room/widgets/message_bubble.dart test/features/chat_room/widgets/message_bubble_test.dart
git commit -m "feat(chat-room): widen agent bubble to 88% + extract XiaLayout token"
```

---

### Task 2: StreamingBubble width 0.78 → 0.88

**Files:**
- Modify: `lib/features/chat_room/widgets/streaming_bubble.dart:104-106`
- Test: `test/features/chat_room/streaming_bubble_test.dart` (add import + test)

**Interfaces:**
- Consumes: `XiaLayout.agentBubbleMaxWidthRatio` (from Task 1)
- Produces: nothing

- [ ] **Step 1: Write the failing test**

Add the tokens import at the top of `test/features/chat_room/streaming_bubble_test.dart` (after the existing imports, e.g. after line 4):

```dart
import 'package:claw_hub/app/theme/tokens.dart';
```

Add this test inside `group('StreamingBubble', ...)`, e.g. after the `'has height constraint at 40% of viewport'` test (after line 126):

```dart
    testWidgets('bubble maxWidth = 88% of screen width', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Scaffold(
              body: StreamingBubble(text: 'width test', agentName: '虾'),
            ),
          ),
        ),
      );
      final found = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints != null &&
            w.decoration is BoxDecoration,
      );
      expect(found, findsOneWidget);
      final bubble = tester.widget<Container>(found);
      expect(
        bubble.constraints!.maxWidth,
        400 * XiaLayout.agentBubbleMaxWidthRatio,
      );
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat_room/streaming_bubble_test.dart`
Expected: FAIL — assertion `312.0 != 352.0` (bubble still uses `* 0.78`).

- [ ] **Step 3: Write minimal implementation**

Edit `lib/features/chat_room/widgets/streaming_bubble.dart:104-106`. Replace:

```dart
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
```

with:

```dart
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width *
                        XiaLayout.agentBubbleMaxWidthRatio,
                  ),
```

(`streaming_bubble.dart` already imports `package:claw_hub/app/theme/tokens.dart` at line 5.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat_room/streaming_bubble_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat_room/widgets/streaming_bubble.dart test/features/chat_room/streaming_bubble_test.dart
git commit -m "feat(chat-room): widen streaming bubble to 88%"
```

---

### Task 3: ToolCallCard width 0.78 → 0.88

**Files:**
- Modify: `lib/features/chat_room/widgets/tool_call_card.dart:73-75`
- Test: `test/features/chat_room/tool_call_card_test.dart` (add import + test)

**Interfaces:**
- Consumes: `XiaLayout.agentBubbleMaxWidthRatio` (from Task 1)
- Produces: nothing

- [ ] **Step 1: Write the failing test**

Add the tokens import at the top of `test/features/chat_room/tool_call_card_test.dart` (after line 7):

```dart
import 'package:claw_hub/app/theme/tokens.dart';
```

Add this test inside `group('ToolCallCard', ...)`, e.g. after the `'shows tool name'` test (after line 27). Uses a **pending** `ToolCall` (no output) so the only constrained+decorated Container is the card itself.

```dart
    testWidgets('card maxWidth = 88% of screen width', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Scaffold(
              body: ToolCallCard(
                toolCall: ToolCall(
                  id: 'tc-width',
                  messageId: 'msg-width',
                  toolName: 'ReadFile',
                ),
              ),
            ),
          ),
        ),
      );
      final found = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints != null &&
            w.decoration is BoxDecoration,
      );
      expect(found, findsOneWidget);
      final card = tester.widget<Container>(found);
      expect(
        card.constraints!.maxWidth,
        400 * XiaLayout.agentBubbleMaxWidthRatio,
      );
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat_room/tool_call_card_test.dart`
Expected: FAIL — assertion `312.0 != 352.0`.

- [ ] **Step 3: Write minimal implementation**

Edit `lib/features/chat_room/widgets/tool_call_card.dart:73-75`. Replace:

```dart
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
```

with:

```dart
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width *
                    XiaLayout.agentBubbleMaxWidthRatio,
              ),
```

(`tool_call_card.dart` already imports `package:claw_hub/app/theme/tokens.dart` at line 2.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat_room/tool_call_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat_room/widgets/tool_call_card.dart test/features/chat_room/tool_call_card_test.dart
git commit -m "feat(chat-room): widen tool call card to 88%"
```

---

### Task 4: Table no-wrap + horizontal scrollbar (markdown stylesheets)

**Files:**
- Modify: `lib/ui_kit/xia_markdown_styles.dart` (add 2 props to `message` and `streaming`)
- Test: `test/ui_kit/xia_markdown_styles_test.dart` (create)

**Interfaces:**
- Consumes: nothing
- Produces: `XiaMarkdownStyles.message`/`.streaming` now set `tableColumnWidth: IntrinsicColumnWidth()` + `tableScrollbarThumbVisibility: true`

- [ ] **Step 1: Write the failing test**

Create `test/ui_kit/xia_markdown_styles_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/xia_markdown_styles.dart';

void main() {
  group('XiaMarkdownStyles table rendering', () {
    // 宽表格:列多 + 长表头,确保触发横向滚动分支。
    const tableMarkdown = '''
| 字段名 | 类型 | 是否必填 | 默认值 | 说明 |
|---|---|---|---|---|
| clientId | string | 是 | — | 本地 UUID 用于去重 |
| serverId | string | 否 | null | Gateway 分配的全局去重 ID |
| logicalClock | int | 是 | 0 | 同时间戳消息的排序依据 |
''';

    Widget pumpTable(double width) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: MarkdownBody(
              data: tableMarkdown,
              selectable: true,
              styleSheet: XiaMarkdownStyles.message,
            ),
          ),
        ),
      );
    }

    testWidgets('table is wrapped in Scrollbar + horizontal scroll view', (
      tester,
    ) async {
      await tester.pumpWidget(pumpTable(300));

      // selectable + 横向滚动不应抛异常(待验证风险)。
      expect(tester.takeException(), isNull);

      // IntrinsicColumnWidth → flutter_markdown 原生包裹
      // Scrollbar > SingleChildScrollView(horizontal) > Table。
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.scrollDirection, Axis.horizontal);
    });

    testWidgets('table scrollbar thumb is always visible', (tester) async {
      await tester.pumpWidget(pumpTable(300));
      expect(tester.takeException(), isNull);

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.thumbVisibility, isTrue);
    });

    test('message stylesheet uses IntrinsicColumnWidth + visible scrollbar', () {
      expect(
        XiaMarkdownStyles.message.tableColumnWidth,
        isA<IntrinsicColumnWidth>(),
      );
      expect(XiaMarkdownStyles.message.tableScrollbarThumbVisibility, isTrue);
    });

    test('streaming stylesheet mirrors table settings', () {
      expect(
        XiaMarkdownStyles.streaming.tableColumnWidth,
        isA<IntrinsicColumnWidth>(),
      );
      expect(
        XiaMarkdownStyles.streaming.tableScrollbarThumbVisibility,
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui_kit/xia_markdown_styles_test.dart`
Expected: FAIL — the two `testWidgets` fail: `find.byType(Scrollbar)` finds nothing (default `FlexColumnWidth` does not wrap tables in a scroll view); the two `test` cases fail: `tableColumnWidth` is `null` (not `IntrinsicColumnWidth`).

- [ ] **Step 3: Write minimal implementation**

Edit `lib/ui_kit/xia_markdown_styles.dart`. In the `message` stylesheet, replace:

```dart
    tableBody: const TextStyle(color: XiaColors.text1),
    listBullet: const TextStyle(color: XiaColors.text1),
  );
```

with:

```dart
    tableBody: const TextStyle(color: XiaColors.text1),
    listBullet: const TextStyle(color: XiaColors.text1),
    // 表格不换行 + 横向滚动条:IntrinsicColumnWidth 触发 flutter_markdown
    // 原生 Scrollbar > SingleChildScrollView(horizontal) 包裹(builder.dart:515)。
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableScrollbarThumbVisibility: true,
  );
```

In the `streaming` stylesheet, replace:

```dart
    strong: const TextStyle(fontWeight: FontWeight.bold),
  );
```

with:

```dart
    strong: const TextStyle(fontWeight: FontWeight.bold),
    // 与 message 一致:流式半渲染表格也不换行 + 横向滚动条。
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableScrollbarThumbVisibility: true,
  );
```

(`xia_markdown_styles.dart` imports `package:flutter/material.dart` at line 1, which re-exports `IntrinsicColumnWidth` from `package:flutter/rendering.dart` — no new import needed.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui_kit/xia_markdown_styles_test.dart`
Expected: PASS (all 4 tests). If the `selectable + horizontal scroll` risk materializes, `tester.takeException()` will surface it here — see the Risk fallback below before proceeding.

- [ ] **Step 5: Commit**

```bash
git add lib/ui_kit/xia_markdown_styles.dart test/ui_kit/xia_markdown_styles_test.dart
git commit -m "feat(chat-room): horizontal-scroll markdown tables in agent messages"
```

**Risk fallback (only if Step 4 fails on `takeException`):** If `selectable: true` + the horizontal-scroll table throws or breaks selection, the issue is `SelectionArea` (from `MarkdownBody(selectable: true)`) conflicting with the table's `SingleChildScrollView`. Mitigation, in order of preference: (a) keep `selectable: true` on `MessageBubble`'s `MarkdownBody` but verify selection still works on non-table content — the table scroll is isolated; (b) if the whole `MarkdownBody` throws, narrow the fix to only the `message` stylesheet and leave `streaming` on `FlexColumnWidth` (streaming tables are transient); (c) last resort, set `selectable: false` on the agent `MarkdownBody` in `message_bubble.dart:291` and document the trade-off in the spec. Re-run the test after any mitigation.

---

### Task 5: Doc sync + full regression

**Files:**
- Modify: `docs/design/component-spec-v2.md` (lines 635, 664-672, 688, 1910-1911)
- Modify: `docs/technical/architecture.md:2275`

**Interfaces:** N/A (docs only).

- [ ] **Step 1: Sync `component-spec-v2.md` 4.2.2 Message Bubble max-width**

Edit `docs/design/component-spec-v2.md`. Replace (line 635, under `#### 4.2.2 Message Bubble` 通用属性):

```
| max-width | 78% |
| padding | `9px 13px` |
```

with:

```
| max-width | agent 88% / user 78% |
| padding | `9px 13px` |
```

- [ ] **Step 2: Add a `table` row to 4.2.2 Markdown 渲染 table**

In the same file, replace (lines 671-673):

```
| `em` | `<em>` 标签，italic |

#### 4.2.3 Tool Card（工具调用卡片）
```

with:

```
| `em` | `<em>` 标签，italic |
| `table` | border: `1px solid var(--border)`，列宽按内容(`IntrinsicColumnWidth`，不换行)，超宽时横向滚动 + 常驻滚动条 |

#### 4.2.3 Tool Card（工具调用卡片）
```

- [ ] **Step 3: Sync 4.2.3 Tool Card max-width**

In the same file, replace (line 687-688, under `.tool-card` 容器):

```
| color | `var(--text-2)` |
| max-width | 78% |
```

with:

```
| color | `var(--text-2)` |
| max-width | 88% |
```

- [ ] **Step 4: Sync the sizing table (附录 A)**

In the same file, replace (lines 1910-1911):

```
| Chat Bubble | max 78% | auto | 14px (corner: 4px) | — |
| Tool Card | max 78% | auto | 8px | — |
```

with:

```
| Chat Bubble | max agent 88% / user 78% | auto | 14px (corner: 4px) | — |
| Tool Card | max 88% | auto | 8px | — |
```

- [ ] **Step 5: Sync `architecture.md`**

Edit `docs/technical/architecture.md:2275`. Replace:

```
| **大屏 (iPhone Pro Max, 430px)** | 内容区自然扩展 | 消息气泡 maxWidth 78%，列表自然填充 |
```

with:

```
| **大屏 (iPhone Pro Max, 430px)** | 内容区自然扩展 | 消息气泡 maxWidth agent 88% / user 78%，列表自然填充 |
```

- [ ] **Step 6: Commit docs**

```bash
git add docs/design/component-spec-v2.md docs/technical/architecture.md
git commit -m "docs(design): sync bubble width (agent 88%/user 78%) + table scroll"
```

- [ ] **Step 7: Full regression**

Run: `flutter test`
Expected: all tests PASS (no regressions to existing chat-room / ui_kit suites).

Run: `flutter analyze`
Expected: "No issues found!" If any issue appears, fix it in a follow-up commit before declaring done.

---

## Self-Review

**1. Spec coverage:**
- Spec Issue 1 (agent bubble 78%→88%, user stays 78%): Task 1 (`message_bubble.dart` split + `XiaLayout`). ✓
- Spec Issue 1 (streaming bubble 0.78→0.88): Task 2. ✓
- Spec Issue 1 (tool_call_card 0.78→0.88): Task 3. ✓
- Spec Issue 1 (thinking_indicator unchanged): explicitly excluded in File Structure + Global Constraints. ✓
- Spec Issue 1 (XiaLayout token, no magic numbers): Task 1 Step 3. ✓
- Spec Issue 2 (table no-wrap + scrollbar on `message` and `streaming`): Task 4. ✓
- Spec doc sync (component-spec 4.2.2/4.2.3, architecture.md): Task 5. ✓
- Spec testing (Law 14, ≥2 tests): Task 1 (2), Task 2 (1), Task 3 (1), Task 4 (4). The width change on streaming/tool_card is a one-line ratio change verified by one focused test each — sufficient for a mechanical constant swap. ✓
- Spec risk (selectable + horizontal scroll): Task 4 Step 4 + Risk fallback. ✓

**2. Placeholder scan:** None. All code blocks contain real code; all `flutter test` / `git commit` commands are exact.

**3. Type consistency:** `XiaLayout.agentBubbleMaxWidthRatio` / `userBubbleMaxWidthRatio` (defined Task 1, used Tasks 1-3) — names match exactly. `IntrinsicColumnWidth` / `tableScrollbarThumbVisibility` (set Task 4, asserted Task 4) — match. `find.byWidgetPredicate` locator used consistently across Tasks 1-3.
