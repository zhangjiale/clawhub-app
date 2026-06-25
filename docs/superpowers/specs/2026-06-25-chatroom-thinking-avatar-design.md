# ChatRoom Thinking Indicator — Remove Stray Avatar

**Date**: 2026-06-25
**Status**: Draft — pending user review
**Source**: User request — "在聊天页面，我发送消息等待回复的时候，对方会有一个小头像。我想把这个思考时的小头像给去掉"
**Related design spec**: [ComponentSpec V2 §4.3 Typing Indicator](../../design/component-spec-v2.md#43-typing-indicator输入中指示器)

## Problem Summary

聊天页面在等待 Agent 回复时显示"思考中"指示器。当前实现 `lib/features/chat_room/widgets/thinking_indicator.dart` 在气泡左侧多渲染了一个 28×28 的紫色方块 + `Icons.psychology` 图标，**这个方块在设计规范 [ComponentSpec V2 §4.3](../../design/component-spec-v2.md#43-typing-indicator输入中指示器) 中并不存在** — 规范定义的 Typing Indicator 只有气泡和三个紫罗兰跳动圆点。

这是一个实现漂移：UI 与设计规范不一致。用户希望去掉这个规范外的方块，让实现回到规范。

| # | Aspect | Detail |
|---|--------|--------|
| 1 | 用户感知 | 等待回复时左侧有"小头像"视觉噪音 |
| 2 | 规范一致性 | component-spec-v2.md §4.3 没有这个方块 |
| 3 | 实现职责 | `ThinkingIndicator` 的核心职责是"三点跳动动画"，28×28 图标方块是多余装饰 |
| 4 | 影响面 | 单组件 + 单测试文件 + 1 处规范注脚 |

## Architecture Principle

**最小侵入 + 规范对齐**。

- 不新增参数（YAGNI）：用户已明确表态"想去掉"，加 `showAvatar: bool` 软开关只会污染 API 表面
- 不动 StreamingBubble / chat_view_model / chat_room_page 调用方（签名不变，向后兼容）
- 同步更新 component-spec-v2.md §4.3：加注脚明确"无左侧 avatar 装饰"，让规范与实现一致

## Change 1: 移除 ThinkingIndicator 左侧图标方块

### 1.1 当前实现

`lib/features/chat_room/widgets/thinking_indicator.dart:36-86`：

```dart
Padding(
  padding: const EdgeInsets.symmetric(
    horizontal: XiaSpacing.pagePaddingH,
    vertical: 4,
  ),
  child: Row(
    children: [
      Container(                            // ← 删除这个 28×28 紫色方块
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
      const SizedBox(width: XiaSpacing.s2),  // ← 同步删除
      Container(                            // ← 保留气泡
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        ...
      ),
    ],
  ),
)
```

### 1.2 修改后

```dart
Padding(
  padding: const EdgeInsets.symmetric(
    horizontal: XiaSpacing.pagePaddingH,
    vertical: 4,
  ),
  child: Row(
    children: [
      Container(                            // ← 气泡（保留）
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
)
```

### 1.3 视觉差异

```
Before:                                    After:
┌──────────────────────────────┐           ┌──────────────────────────────┐
│ ┌──┐                         │           │                              │
│ │🧠│  ┌─────────────────┐    │           │  ┌─────────────────┐         │
│ │28│  │  ●   ●   ●      │    │    →      │  │  ●   ●   ●      │         │
│ └──┘  └─────────────────┘    │           │  └─────────────────┘         │
└──────────────────────────────┘           └──────────────────────────────┘
  ↑pagePaddingH                  气泡左移 ≈ 36px（28 + s2 间距）
```

气泡整体左移约 36px（28 像素图标 + 8 像素 s2 间距），与 component-spec-v2.md §4.3 描述的"紧贴页面左 padding"对齐。

### 1.4 文件注释

类注释从：

```dart
/// Thinking indicator — three bouncing dots, matching ComponentSpec Section 4.3.
///
/// Bubble: 20/20/8/20 radius (matches Agent bubble), surface bg, shadow-s.
/// Dots: 6×6, text3 color, 800ms bounce cycle, staggered delays.
```

保持不变（注释与规范一致，无需更新）。

## Change 2: 同步更新测试

`test/features/chat_room/thinking_indicator_test.dart` 当前三处断言：

| # | 测试 | 现状 | 改为 |
|---|------|------|------|
| 1 | `'renders psychology icon indicating AI thinking'` | `expect(find.byIcon(Icons.psychology), findsOneWidget);` | `expect(find.byIcon(Icons.psychology), findsNothing);` |
| 2 | `'renders three bouncing dots inside bubble'` | 三个 `_BouncingDot` | 不变 |
| 3 | `'animates dots with bouncing motion'` | `expect(find.byIcon(Icons.psychology), findsOneWidget);`（动画期间） | 删除该断言（测试目的已由三个 dot 存在性覆盖） |

## Change 3: 同步更新设计规范（推荐，包含在本 spec 范围）

`docs/design/component-spec-v2.md` §4.3 在 "Typing Indicator" 标题下追加一行：

```
**注意**: Typing Indicator 仅由气泡和三个跳动圆点组成，**不包含**左侧头像或图标装饰。
```

目的：防止实现再次漂移回来；让规范成为测试断言的"上位依据"。

## Out of Scope

明确**不做**：

- ❌ 不改 StreamingBubble（流式消息有自己的头像，但属于另一类视觉，不在用户请求范围）
- ❌ 不改气泡宽度、颜色、圆角、动画周期
- ❌ 不改 chat_view_model、chat_room_page 调用方（`ThinkingIndicator()` 签名不变）
- ❌ 不引入 `showAvatar` 之类的开关参数
- ❌ 不抽基类 / 不动 widget 树结构（最小侵入）

## Risk & Regression

| 风险 | 评估 | 缓解 |
|------|------|------|
| 视觉回归：气泡左移是否违和 | 低 | 与 component-spec-v2.md §4.3 对齐，规范本身就是这么定的 |
| API 破坏 | 无 | `ThinkingIndicator()` 签名不变，仅一处调用方 |
| 规范与实现再次漂移 | 低 | 在 component-spec-v2.md §4.3 追加"无头像"注脚 |
| 其他 widget 引用 `Icons.psychology` | 无 | grep 全项目仅 thinking_indicator.dart 使用 |

## Verification

实现完成后人工核对：

1. `flutter test test/features/chat_room/thinking_indicator_test.dart` — 三个测试全绿
2. `flutter analyze` — 无新增 warning
3. 启动 app，进入任一会话 → 发送消息 → 等待回复期间肉眼确认：
   - 气泡+三点跳动正常显示
   - 气泡左侧无 28×28 紫色方块
   - 气泡整体左移后视觉无错位

## File Inventory

| 路径 | 类型 | 操作 |
|------|------|------|
| `lib/features/chat_room/widgets/thinking_indicator.dart` | 源 | 编辑（删除 28×28 Container + SizedBox） |
| `test/features/chat_room/thinking_indicator_test.dart` | 测试 | 编辑（2 处断言调整） |
| `docs/design/component-spec-v2.md` | 规范 | 编辑（§4.3 加注脚） |
| `docs/superpowers/specs/2026-06-25-chatroom-thinking-avatar-design.md` | 本设计文档 | 新建 |