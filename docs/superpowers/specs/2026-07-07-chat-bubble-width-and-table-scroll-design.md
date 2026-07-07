# 聊天气泡加宽 + 表格横向滚动 — 设计

- 日期：2026-07-07
- 范围：`lib/features/chat_room/`、`lib/ui_kit/xia_markdown_styles.dart`、`lib/app/theme/tokens.dart`、设计文档
- 类型：UI 调整（无领域层 / 无协议改动）

## 背景与问题

聊天页面有两个阅读体验问题：

1. **Agent 回复气泡太窄**：`message_bubble.dart` 与 `streaming_bubble.dart` 把气泡 `maxWidth` 钉死在屏宽的 **78%**，长文本每行可容纳的字符少，垂直滚动频繁。用户只关心 Agent（虾）回复气泡——自己发出的气泡（短文本）保持 78% 即可。
2. **消息内表格自动换行**：`flutter_markdown` 默认 `tableColumnWidth: FlexColumnWidth()`，列宽等分并强制换行，宽表格阅读困难。用户要求表格文字不换行、提供左右滚动条。

## 关键发现（决定方案的事实）

查 `flutter_markdown 0.7.7+1` 源码（`pub.flutter-io.cn` 镜像）后发现表格横向滚动是**原生支持**的，不需要自定义 builder：

- `lib/src/builder.dart:514-532`：当 `styleSheet.tableColumnWidth` 是 `IntrinsicColumnWidth` 或 `FixedColumnWidth` 时，自动把表格包进 `Scrollbar(thumbVisibility: styleSheet.tableScrollbarThumbVisibility) > SingleChildScrollView(scrollDirection: Axis.horizontal)`。
- `lib/src/builder.dart:650-657`：`_buildTable()` 用 `defaultColumnWidth: styleSheet.tableColumnWidth!`。
- `lib/src/style_sheet.dart:143`：`MarkdownStyleSheet.fromTheme` 默认 `tableColumnWidth: const FlexColumnWidth()` → 这才是换行根因。
- `lib/src/widget.dart:389-391`：`MarkdownBody` 用 `fallbackStyleSheet.merge(widget.styleSheet)`，`merge` 对每个字段取 `other ?? this`。当前 `XiaMarkdownStyles.message` / `.streaming` 都没显式设 `tableColumnWidth`，故回退到 `FlexColumnWidth()`（换行）。

结论：只需在 stylesheet 显式设 `tableColumnWidth: IntrinsicColumnWidth()` 即触发原生横向滚动；`tableScrollbarThumbVisibility: true` 让滚动条常驻。

被否决方案：注册自定义 `table` `MarkdownElementBuilder`——需自行重建单元格组装，约 100 行且脆弱，原生能力已够用，不采用。

## 设计

### Issue 1：Agent 气泡 78% → 88%（user 气泡不动）

| 文件:行 | 现状 | 改为 |
|---|---|---|
| `message_bubble.dart:118` | `maxWidth: MediaQuery.of(context).size.width * 0.78`（user/agent 共用） | `* (_isUser ? XiaLayout.userBubbleMaxWidthRatio : XiaLayout.agentBubbleMaxWidthRatio)` |
| `streaming_bubble.dart:105` | `* 0.78`（恒为 agent） | `* XiaLayout.agentBubbleMaxWidthRatio` |
| `tool_call_card.dart:74` | `* 0.78`（agent 侧工具卡） | `* XiaLayout.agentBubbleMaxWidthRatio`（与 agent 文本气泡右边沿对齐） |
| `thinking_indicator.dart:51` | `constraints.maxWidth * 0.7`（LayoutBuilder，typing 药丸） | **不动** |

理由：
- `message_bubble.dart` 的 `Container` 同时服务 user/agent 两种角色，按 `_isUser` 分流即可只加宽 agent。
- `tool_call_card` 与 agent 文本气泡交错出现，同步到 88% 避免右边沿错落。
- `thinking_indicator` 是瞬时 typing 药丸、独立瞬时元素，且走 `LayoutBuilder` 不同代码路径，保持 0.7 不动。
- 用户气泡保持 78%，形成 agent 宽 / user 窄的非对称——agent 承载长内容，可接受且符合用户明确选择。

**新增 token**（`lib/app/theme/tokens.dart`，沿用 `Xia<Category>` 约定）：

```dart
/// Chat bubble layout ratios (of screen width).
class XiaLayout {
  XiaLayout._();
  static const double agentBubbleMaxWidthRatio = 0.88;
  static const double userBubbleMaxWidthRatio = 0.78;
}
```

消除 3 处 `0.78` 魔法数字重复；88% 接近理论上限（屏宽 − 2×`pagePaddingH` ≈ 91.5%），右侧仍留约 13px 窄空隙，保留"左侧气泡"视觉线索。

### Issue 2：表格不换行 + 横向滚动条

`lib/ui_kit/xia_markdown_styles.dart` 的 `message` 与 `streaming` 两个 stylesheet 各新增两行：

```dart
tableColumnWidth: const IntrinsicColumnWidth(),
tableScrollbarThumbVisibility: true,   // 滚动条常驻
```

效果：
- 列宽按内容自然宽度（`IntrinsicColumnWidth`）→ 不换行。
- 超出气泡宽度时自动横向滚动 + 常驻滚动条（`builder.dart:515-529` 自动包裹）。
- 窄表格不超宽 → `SingleChildScrollView` 不滚动、`Scrollbar` 自动隐藏，视觉与今天一致。
- `streaming` stylesheet 同步加这两行，避免流式半渲染表格换行；流式气泡外层已有的竖向 `SingleChildScrollView(reverse: true)` 与表格横向滚动轴正交，可正常嵌套。
- **streaming 表格边框/表头样式**：`streaming` stylesheet 仅加这两行，不补 `tableBorder`/`tableHead`/`tableBody`，故流式表格沿用 `kFallbackStyle` 默认边框（既有行为，本次不引入回归）。流式结束后定稿气泡用 `message` 样式表呈现完整 Xia 风格。若实测发现 fallback 边框在深色主题下明显违和，再单独议（不在本次范围）。

### 文档同步

- `docs/design/component-spec-v2.md` 4.2.2 Message Bubble：`max-width: 78%` → 注明 agent `88%` / user `78%`（同步 4.2.3 Tool Card 的 78% → 88%）。
- `docs/technical/architecture.md:2275`：`消息气泡 maxWidth 78%` → `agent 88% / user 78%`。

## 测试（Law 14：每行为 ≥2 测试）

**气泡宽度**（`test/features/chat_room/widgets/message_bubble_test.dart`）：
- agent 气泡 `Container` 的 `maxWidth` 约束 = 屏宽 × 0.88。
- user 气泡 `Container` 的 `maxWidth` 约束 = 屏宽 × 0.78。
- 流式气泡（`test/features/chat_room/streaming_bubble_test.dart`）：maxWidth = 屏宽 × 0.88。

**表格滚动**（新增 `test/ui_kit/xia_markdown_styles_test.dart`，或在 `test/features/chat_room/widgets/message_bubble_test.dart` 加用例）：
- 渲染含表格的 agent 消息，断言树中存在 `Table` + 外层 `Scrollbar` + `SingleChildScrollView`（横向）。
- 断言 `Scrollbar` 的 `thumbVisibility` 为 `true`。
- 断言 `MarkdownStyleSheet.message.tableColumnWidth` 是 `IntrinsicColumnWidth`。

现有 `message_bubble_test.dart:254-260` 只断言约束性质（`minWidth < maxWidth`），不涉及 0.78 数值 → 不破坏。

## 风险与降级

- **`selectable: true` + 横向滚动表格的手势冲突**：`MarkdownBody` 的 `SelectionArea` 与表格内 `SingleChildScrollView(horizontal)` 可能争夺拖动手势。预期可共存（Scrollbar 走自身 `ScrollController`，文本选区走 `SelectionArea`），但需在测试中实测。若冲突，降级方案：对表格内容关闭 selectable（`MarkdownBody` 无法按元素粒度关闭 selectable，则改为接受选区不覆盖表格，或评估切换到 `MarkdownSelectable` 等方案——届时再议）。
- **`IntrinsicColumnWidth` 性能**：按列内容最长行计算宽度，超大表格（数十行 × 长文本）布局开销高于 `FlexColumnWidth`。聊天场景表格通常较小，可接受；若出现卡顿，可对单元格文本加 `maxLines`/`softWrap` 限制（但会重新引入换行，与需求冲突，仅作极端兜底）。

## 不在范围内（YAGNI）

- 用户气泡加宽（用户明确不需要）。
- 流式气泡 40% 视高上限调整（用户未选）。
- `thinking_indicator` 宽度调整。
- 切换 markdown 渲染库、重写表格 builder。
- 表格列宽自适应 / 冻结首列等高级表格特性。
