# Thinking Indicator — Agent-Themed Dots Design Doc

**Date**: 2026-06-25
**Status**: Draft — pending user review
**Source**: User request — "紫色的气泡有点违和，我想能根据当前页面主题自动变色" (clarified to: 三个圆点跟随 agent 主色)
**Related design spec**: [ComponentSpec V2 §4.3 Typing Indicator](../../design/component-spec-v2.md#43-typing-indicator输入中指示器)
**Sister spec**: [ChatRoom Thinking Avatar Removal (just merged)](2026-06-25-chatroom-thinking-avatar-design.md)

## Problem Summary

`lib/features/chat_room/widgets/thinking_indicator.dart` 三个跳动圆点的颜色硬编码为 `XiaColors.accent2`（紫罗兰 #9B7AFF），独立于当前页面的 agent 主色。这违反了用户在 chat 页面其他元素（`QuickCommandBar` pill 文字、`MessageBubble` 用户气泡）上观察到的"agent 染色"惯例，造成视觉违和：聊天里所有 agent 关联元素（quick command 文字、用户气泡背景）都跟着 agent 主色变，唯独 thinking 圆点永远是紫色。

这是一个"实现漂移"问题 — 修复让 `ThinkingIndicator` 与已有 chat_room 染色模式对齐。

| # | Aspect | Detail |
|---|--------|--------|
| 1 | 用户感知 | 圆点紫色和当前页面 agent 主色不一致时违和 |
| 2 | 视觉一致性 | chat_room 内 `QuickCommandBar` / `MessageBubble` 已用 `AgentTheme.of(context).primary`，`ThinkingIndicator` 应当对齐 |
| 3 | 已有架构支撑 | `chat_room_page.dart:244` 已用 `Theme(... extensions: [AgentTheme(primary: ...)])` 包裹整个聊天页，`AgentTheme.of(context)` 在所有 descendants 都可拿到 |
| 4 | 零成本 fallback | `AgentTheme.of()` 在没有 agent 在 scope 时自动回退到 `XiaColors.accent`（宝石蓝 #4F83FF），用户无需决策 |

## Architecture Principle

**复用现有模式，不发明新抽象**。

- **复用 1**: `AgentTheme.of(context).primary` — 已经在 `quick_command_bar.dart:26` 和 `message_bubble.dart:96` 使用，本 spec 直接套用
- **复用 2**: 测试 wrap 模式 `MaterialApp(theme: ThemeData(extensions: [...]))` — 已在 `quick_command_bar_test.dart:18` 和 `message_bubble_test.dart:12` 使用
- **复用 3**: 测试断言模式"找 Container 的 BoxDecoration.color 比对" — `message_bubble_test.dart:31-45` 的 `bubbleColor` helper 已示范

不做以下事情：
- ❌ 不给 `ThinkingIndicator` 加 `dotColor` 显式参数（YAGNI，全项目仅 1 处调用方）
- ❌ 不用 `Theme.of(context).colorScheme.secondary`（当前就是 `accent2` 紫罗兰，等于没改）
- ❌ 不动气泡背景/边框/圆角/padding/动画

## Change 1: Widget — 圆点颜色从硬编码 accent2 改为 AgentTheme.of

### 1.1 当前实现

`lib/features/chat_room/widgets/thinking_indicator.dart:35-87` 的 build 方法里，三个 `_BouncingDot` 子项的 `dotColor` 是通过 `_BouncingDot.build` 内部硬编码的 `XiaColors.accent2`：

```dart
@override
Widget build(BuildContext context) {
  return Container(
    width: 6,
    height: 6,
    decoration: const BoxDecoration(
      // V2: violet (accent2) dots per ComponentSpec §4.3
      color: XiaColors.accent2,
      shape: BoxShape.circle,
    ),
  );
}
```

### 1.2 修改后

`_BouncingDot` 接收 `dotColor` 作为构造参数，build 方法取 build 上下文里的 `AgentTheme.of(context).primary`：

```dart
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key});
  // 签名不变
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  // ... AnimationController 不变

  @override
  Widget build(BuildContext context) {
    final dotColor = AgentTheme.of(context).primary;  // ★ 新增

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.pagePaddingH,
        vertical: 4,
      ),
      child: Row(
        children: [
          Container(
            // 气泡不变
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: XiaColors.surface2,           // 不变
              borderRadius: const BorderRadius.only(...),  // 不变
              border: Border.all(color: XiaColors.border),  // 不变
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BouncingDot(controller: _controller, delay: 0.0, dotColor: dotColor),    // ★ 加参数
                const SizedBox(width: 4),
                _BouncingDot(controller: _controller, delay: 0.15, dotColor: dotColor),   // ★
                const SizedBox(width: 4),
                _BouncingDot(controller: _controller, delay: 0.3, dotColor: dotColor),    // ★
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
  final double delay;
  final Color dotColor;  // ★ 新增

  const _BouncingDot({
    required this.controller,
    required this.delay,
    required this.dotColor,  // ★ 新增
  });

  @override
  Widget build(BuildContext context) {
    final delayFraction = delay / 0.8;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value + delayFraction) % 1.0;
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
              color: dotColor,           // ★ 改：XiaColors.accent2 → dotColor
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
```

### 1.3 文件顶部 import

新增 `import 'package:claw_hub/app/theme/agent_theme.dart';`。`XiaColors` 仍被使用（气泡 background/border），保留 import。

### 1.4 注释更新

类注释从：
```dart
/// Thinking indicator — three bouncing dots, matching ComponentSpec Section 4.3.
///
/// Bubble: 20/20/8/20 radius (matches Agent bubble), surface bg, shadow-s.
/// Dots: 6×6, text3 color, 800ms bounce cycle, staggered delays.
```

微调到（修正已有的小事实错误：`text3 color` 实际是 `accent2`；删除过时的 `shadow-s`）：
```dart
/// Thinking indicator — three bouncing dots, matching ComponentSpec Section 4.3.
///
/// Bubble: 20/20/8/20 radius (matches Agent bubble), surface bg, border.
/// Dots: 6×6, AgentTheme.of(context).primary (full opacity), 800ms bounce cycle,
/// staggered delays.
```

`_BouncingDot.build` 内的内联注释 `// V2: violet (accent2) dots per ComponentSpec §4.3` 改为 `// Dot color from AgentTheme.of(context).primary (spec §4.3)`。

## Change 2: 测试 — 加 wrap helper + 3 个新测试 + 保留 3 个旧测试

`test/features/chat_room/thinking_indicator_test.dart` 当前 3 个测试（来自上一次 spec）。本 spec 调整为 4 个测试：

| # | 测试 | 现状 | 改为 |
|---|------|------|------|
| 1 | `'does NOT render psychology avatar icon (spec §4.3: bubble+dots only)'` | `findsNothing(Icons.psychology)` | 保留 |
| 2 | `'renders three bouncing dots inside bubble'` | `findsNWidgets(3)` for `_BouncingDot` | 保留 |
| 3 | `'animates dots with bouncing motion'` | dots present after 300ms pump | 保留 |
| 4 | `'dots use AgentTheme primary color when present'` | — | **新增** |
| 5 | `'dots fall back to sapphire (#4F83FF) when no AgentTheme in scope'` | — | **新增** |

### 2.1 Wrap helper（参考 quick_command_bar_test.dart:18）

```dart
Widget buildIndicator({AgentTheme? agentTheme}) {
  return MaterialApp(
    theme: ThemeData(extensions: agentTheme != null ? [agentTheme] : []),
    home: Scaffold(body: const ThinkingIndicator()),
  );
}
```

### 2.2 新增测试 4 — 跟随 AgentTheme

```dart
testWidgets('dots use AgentTheme primary color when present', (tester) async {
  await tester.pumpWidget(
    buildIndicator(agentTheme: const AgentTheme(primary: Color(0xFF5F9B96))),
  );

  // Find dot Containers by size 6x6 and verify decoration.color
  final dotContainers = find.byWidgetPredicate(
    (w) => w is Container && w.decoration is BoxDecoration
        && (w.decoration as BoxDecoration).shape == BoxShape.circle,
  );
  expect(dotContainers, findsNWidgets(3));
  for (final element in dotContainers.evaluate()) {
    final container = element.widget as Container;
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF5F9B96));
  }
});
```

### 2.3 新增测试 5 — fallback

```dart
testWidgets('dots fall back to sapphire (#4F83FF) when no AgentTheme in scope',
    (tester) async {
  await tester.pumpWidget(buildIndicator());  // 无 agentTheme

  final dotContainers = find.byWidgetPredicate(
    (w) => w is Container && w.decoration is BoxDecoration
        && (w.decoration as BoxDecoration).shape == BoxShape.circle,
  );
  expect(dotContainers, findsNWidgets(3));
  for (final element in dotContainers.evaluate()) {
    final container = element.widget as Container;
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF4F83FF));  // V2 sapphire
  }
});
```

### 2.4 旧测试更新 wrap 引用

旧测试的 `buildIndicator()` 调用需改为 `buildIndicator()` (helper 名相同) 或保留原 `buildIndicator()` helper 不变。最简单方案：保留现有 `MaterialApp(home: Scaffold(body: ThinkingIndicator()))` helper 在文件顶部，新增 `buildIndicator({AgentTheme? agentTheme})` 作为第二 helper 或重写为统一形式。

**决策**：重写 `buildIndicator()` 为参数化版本，所有 5 个测试都用它。Test 1/2/3 不传 `agentTheme: null`，test 4/5 显式传或不传。这样改动最小，文件结构干净。

## Change 3: 设计规范 — §4.3 圆点颜色从"紫罗兰"改为"agent 主色"

`docs/design/component-spec-v2.md` §4.3 中"Typing Dot（跳动圆点）"表格的 `background` 行：

| 属性 | 值 |
|---|---|
| 尺寸 | 6px x 6px |
| border-radius | 999px |
| background | `var(--accent2)`（紫罗兰色） |  ← 改为
| 动画 | `typingBounce 800ms ease infinite` |

改为：

| 属性 | 值 |
|---|---|
| 尺寸 | 6px x 6px |
| border-radius | 999px |
| background | agent 主色（取自 `AgentTheme.of(context).primary`；agent 不在 scope 时回退 V2 sapphire #4F83FF） |
| 动画 | `typingBounce 800ms ease infinite` |

并在 §4.3 末尾已有的"装饰约束"注脚旁追加（或合并到装饰约束段）：

> **颜色来源**: 圆点背景色取自当前页面的 AgentTheme primary，与 QuickCommandBar pill 文字、MessageBubble 用户气泡背景保持一致。

## Out of Scope

明确**不做**：

- ❌ 不改气泡背景（保持 `XiaColors.surface2`）
- ❌ 不改气泡边框（保持 `XiaColors.border`）
- ❌ 不改气泡圆角/padding/动画周期
- ❌ 不改 chat_view_model、chat_room_page 调用方（签名不变）
- ❌ 不给 `ThinkingIndicator` 加 `dotColor` 显式构造参数
- ❌ 不改 `StreamingBubble`
- ❌ 不动 `chat_room_page.dart:244` 的 Theme 注入
- ❌ 不动 `AgentTheme` 类本身
- ❌ 不动 `component-spec-v2.md` 其他章节

## Risk & Regression

| 风险 | 评估 | 缓解 |
|------|------|------|
| chat_room_page.dart:244 的 `Theme(... extensions: [...])` 包裹未来被移除 | 低（4 个 task 没动过） | `AgentTheme.of()` 内置 fallback 到宝石蓝 |
| 圆点颜色跟随 agent 主色后，在暗背景下某些 agent 主色对比度不足 | 中（用户/agent 自选颜色决定） | UX 层已知问题，超出本 spec 范围 |
| `_BouncingDot` 已经是 const 但新增 `dotColor` 参数后不能 const 化 | OK | 当前 `_BouncingDot` 也不是 const（内部有动画 builder），无影响 |
| 测试 wrap helper 改动让旧测试失败 | 低 | wrap helper 名字 `buildIndicator` 保留，5 个测试都用同一签名 |
| 设计规范其他章节未来引入"紫罗兰点"的引用 | 极低 | §4.3 是唯一引用点 |

## Verification

实现完成后人工核对：

1. `flutter test test/features/chat_room/thinking_indicator_test.dart` — 5/5 测试绿
2. `flutter test test/features/chat_room/` — 134+/134+ 通过（无回归）
3. `flutter analyze` — 0 新 warning
4. 启动 app，进入 agent #1 会话 → 发送消息 → 看到三个圆点颜色 = agent #1 主色
5. 切到 agent #2 会话 → 同样位置 → 看到三个圆点颜色 = agent #2 主色
6. 进入一个没有 AgentTheme 注入的页面（如果存在）→ 圆点回退到宝石蓝

## File Inventory

| 路径 | 类型 | 操作 |
|------|------|------|
| `lib/features/chat_room/widgets/thinking_indicator.dart` | 源 | 编辑（5 处：import、build 取色、3 处 dot 调用、`_BouncingDot` 加字段、内联注释） |
| `test/features/chat_room/thinking_indicator_test.dart` | 测试 | 编辑（重构 wrap helper 为参数化，加 2 个新测试） |
| `docs/design/component-spec-v2.md` | 规范 | 编辑（§4.3 Typing Dot 表格 background 行 + 装饰约束段追加颜色来源注） |
| `docs/superpowers/specs/2026-06-25-thinking-indicator-agent-themed-dots-design.md` | 本设计文档 | 新建 |