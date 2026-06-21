# Design Token Specification — 虾Hub (XiaHub)

> Cool-Toned Dark Mode Mobile App for OpenClaw AI Agent Management
> Version 2.0 · 2026-06-15
> Source: `虾Hub-原型Demo-V2.html`

---

## 目录

1. [色彩体系 Color System](#1-色彩体系-color-system)
2. [字体体系 Typography](#2-字体体系-typography)
3. [间距体系 Spacing — 4pt Grid](#3-间距体系-spacing--4pt-grid)
4. [圆角体系 Border Radius](#4-圆角体系-border-radius)
5. [阴影体系 Shadows](#5-阴影体系-shadows)
6. [动效体系 Motion](#6-动效体系-motion)
7. [毛玻璃效果 Glassmorphism](#7-毛玻璃效果-glassmorphism)
8. [导出代码 Code Export](#8-导出代码-code-export)

---

## 1. 色彩体系 Color System

虾Hub V2 采用冷色调深色模式设计，以宝石蓝 (sapphire blue) 为品牌主色，遵循 **60-30-10** 配色法则：

| 比例 | 角色 | 色域 |
|------|------|------|
| **60%** | 主色 (Background) | `--bg`, `--surface` 系列冷蓝灰色 |
| **30%** | 辅助色 (Secondary) | 卡片表面 `--surface2/3`、文字层级、hairline 边框 |
| **10%** | 点缀色 (Accent) | `--accent: #4F83FF` 宝石蓝 + `--accent2: #9B7AFF` 紫罗兰 |

### 1.1 背景色 Background Colors

采用冷色暗灰渐变层叠，从最底层到最顶层依次变亮，形成自然的空间纵深感。V2 从暖灰 (#111110 带黄底) 全面转向冷灰 (#08090D 带蓝底)。表面层级不再靠大幅明度跳跃来区分，而是用 hairline 边框 + 微弱色差。

| Token 名称 | Hex | RGBA | 用途 | 对比度说明 |
|:---|:---|:---|:---|:---|
| `--bg` | `#08090D` | `rgb(8, 9, 13)` | 页面最底层背景，全局底色 | 基准层 |
| `--surface` | `#0E1016` | `rgb(14, 16, 22)` | 卡片、列表项、聊天气泡背景 | 与 `--bg` 形成微弱层级区分 |
| `--surface2` | `#15171E` | `rgb(21, 23, 30)` | 次级卡片、输入框背景、按钮底色 | 比 surface 亮一级 |
| `--surface3` | `#1C1F28` | `rgb(28, 31, 40)` | 代码块背景、三级嵌套容器、图标底色 | 最亮的表面色 |
| `--surface-elevated` | `#12141B` | `rgb(18, 20, 27)` | Toast 弹窗、浮层背景 (带毛玻璃) | 介于 surface 和 surface2 之间 |
| `--border` | `rgba(255,255,255,0.06)` | — | **新增** hairline 边框色，V2 的核心视觉分隔手段 | 装饰性 |
| `--border-accent` | `rgba(79,131,255,0.30)` | — | **新增** 强调边框（选中态、激活态） | 装饰性 |

**层级关系示意:**

```
bg (#08090D)  ←  最暗，页面底色，带蓝调
 └─ surface (#0E1016)  ←  卡片层
     └─ surface2 (#15171E)  ←  嵌套元素
         └─ surface3 (#1C1F28)  ←  最内层元素
 surface-elevated (#12141B)  ←  浮层（配合 backdrop-filter）

V2 层级策略: bg ← hairline border → surface ← hairline border → surface2
(依赖精细边框分层级，色差仅作辅助)
```

### 1.2 文字色 Text Colors

文字色采用 `rgba(235, 239, 250, α)` 统一基调（冷白，带微弱蓝调），通过透明度 (alpha) 区分层级，确保在深色背景上的视觉层次。

| Token 名称 | 值 | 等效 Hex (on #08090D) | Alpha | 用途 | WCAG 对比度 (vs --bg) |
|:---|:---|:---|:---|:---|:---|
| `--text-1` | `#EBEFFA` | `#EBEFFA` | 100% | 主标题、正文、重要数据 | **16.5:1** AAA |
| `--text-2` | `rgba(235,239,250,0.55)` | `~#8A8F9E` | 55% | 次要标签、辅助说明 | **5.8:1** AA |
| `--text-3` | `rgba(235,239,250,0.30)` | `~#525663` | 30% | 时间戳、描述文本、占位符说明 | **2.7:1** AA-Large |
| `--text-4` | `rgba(235,239,250,0.14)` | `~#2E313A` | 14% | 禁用态、极弱提示、分割线 | **1.4:1** 装饰性 |

> **WCAG 说明:**
> - `--text-1` 在所有背景色上均满足 AAA (7:1+) 要求。
> - `--text-2` 在 `--bg` 和 `--surface` 上满足 AA (4.5:1) 要求。
> - `--text-3` 仅用于 18px+ 大字号或装饰性文本 (AA-Large 3:1)。
> - `--text-4` 不适用于可读性文本，仅用于装饰性元素和极低优先级信息。

**文字色在 surface 上的对比度 (vs #0E1016):**

| Token | 对比度 | 等级 |
|:---|:---|:---|
| `--text-1` on `--surface` | 15.5:1 | AAA |
| `--text-2` on `--surface` | 5.5:1 | AA |
| `--text-3` on `--surface` | 2.6:1 | AA-Large |
| `--text-4` on `--surface` | 1.3:1 | 装饰性 |

### 1.3 品牌色 Brand Accent

宝石蓝 (sapphire blue) 作为品牌主色，紫罗兰 (violet) 作为次级强调色，贯穿全局。蓝色传达精准、可信、科技感；紫色增加高端辨识度。

| Token 名称 | Hex / 值 | 用途 | 对比度说明 |
|:---|:---|:---|:---|
| `--accent` | `#4F83FF` `rgb(79,131,255)` | 主按钮、发送按钮、活跃 Tab、导航高亮、未读徽章、链接文字 | vs --bg: **5.1:1** AA ✓; vs #fff 文字: **3.2:1** (仅大字号) |
| `--accent-hover` | `#6B9AFF` `rgb(107,154,255)` | Hover/Pressed 态提亮 | vs --bg: **6.5:1** AA ✓ |
| `--accent-muted` | `rgba(79,131,255,0.10)` | 轻量背景: 连接提示 banner、快捷指令按压态、选中态标签 | 用于背景色，不用于文字 |
| `--accent-glow` | `rgba(79,131,255,0.20)` | 主按钮外发光阴影 `box-shadow` | 纯装饰性 |
| `--accent2` | `#9B7AFF` `rgb(155,122,255)` | **新增** 次级强调色: 成就图标、特殊标记、在线脉冲动画、引用块竖条、工具调用卡片 | vs --bg: **4.7:1** AA ✓ |
| `--accent2-muted` | `rgba(155,122,255,0.10)` | 紫罗兰轻量背景 | 用于背景色 |
| `--gold` | `#E8C574` `rgb(232,197,116)` | **新增** 金色高光: 里程碑庆祝动画、成就解锁高亮、成长面板星级 | 用于装饰性元素 |

> **设计意图:** V2 从暖珊瑚色全面转向冷色宝石蓝，传达"精准工具"而非"温暖陪伴"的气质。三种强调色（蓝、紫、金）不可同时出现在同一组件上，保持视觉清晰。白色文字 (`#FFFFFF`) 在 `--accent` 上的对比度为 3.2:1，满足 WCAG AA Large (3:1) 要求，适用于 14px+ bold 按钮文字。

### 1.4 语义色 Semantic Colors

用于状态指示：在线/离线、成功/失败、警告等。V2 语义色更亮更冷，与冷色调背景更协调。

| Token 名称 | Hex / 值 | 用途 | 对比度 (vs --bg) |
|:---|:---|:---|:---|
| `--green` | `#4ADE80` `rgb(74,222,128)` | 在线状态点、成功标识、"已解锁"文本 | **7.2:1** AAA ✓ |
| `--green-muted` | `rgba(74,222,128,0.10)` | 成功状态轻量背景 | 背景用途 |
| `--red` | `#F87171` `rgb(248,113,113)` | 错误状态、删除按钮 hover/active | **5.0:1** AA ✓ |
| `--red-muted` | `rgba(248,113,113,0.08)` | 删除按钮轻量背景 | 背景用途 |
| `--yellow` | `#FBBF24` `rgb(251,191,36)` | 警告 Banner 文字、连接不稳定提示 | **9.6:1** AAA ✓ |

**附加语义色 (从 CSS 中提取):**

| 来源 | 值 | 用途 |
|:---|:---|:---|
| `.conn-banner.warning` background | `rgba(251,191,36,0.08)` | 警告 Banner 背景 |
| `.conn-banner.info` background | `var(--accent-muted)` | 信息 Banner 背景 |
| `.achievement-item.unlocked` icon border | `rgba(155,122,255,0.25)` | 已解锁成就图标边框 (accent2) |
| `.achievement-item.locked` icon bg | `var(--surface3)` | 未解锁成就图标背景 |
| 分割线/边框 | `rgba(255,255,255,0.06)` | 列表项分割线、导航栏顶部边框、卡片边框 |
| 代码高亮背景 | `rgba(255,255,255,0.06)` | 行内代码 `<code>` 背景 |
| Phone frame border | `rgba(255,255,255,0.08)` | 设备外框描边 |
| 搜索高亮 | `rgba(79,131,255,0.25)` | 搜索结果关键词高亮背景 |
| 在线状态点辉光 | `0 0 6px var(--green)` | 状态指示点绿色辉光 |

### 1.5 Per-Agent 主题色 Theme Colors

每个 AI Agent 实例可分配独立的主题色，用于头像背景、详情页装饰等。V2 保持 12 色体系，但全部调整为冷色调基底、中等饱和度，与 V2 冷色背景更协调。主题色以低透明度 (10%) 作为背景，实色作为前景。

| Theme Key | 中文名 | 实色 (Foreground) | 背景色 (10% Alpha) | 使用示例 |
|:---|:---|:---|:---|:---|
| `sapphire` | 宝蓝 | `#4F83FF` | `rgba(79,131,255,0.10)` | 产品虾 (默认主题) |
| `violet` | 紫罗兰 | `#9B7AFF` | `rgba(155,122,255,0.10)` | 代码虾 |
| `cyan` | 青碧 | `#22D3EE` | `rgba(34,211,238,0.10)` | 英语虾 |
| `emerald` | 翡翠绿 | `#34D399` | `rgba(52,211,153,0.10)` | 旅行规划师 |
| `amber` | 琥珀 | `#FBBF24` | `rgba(251,191,36,0.10)` | 写作虾 |
| `rose` | 玫瑰 | `#FB7185` | `rgba(251,113,133,0.10)` | 设计虾 |
| `teal` | 湖蓝 | `#2DD4BF` | `rgba(45,212,191,0.10)` | 数据虾 |
| `orange` | 暖橙 | `#FB923C` | `rgba(251,146,60,0.10)` | 运维虾 |
| `indigo` | 靛蓝 | `#818CF8` | `rgba(129,140,248,0.10)` | (预留) |
| `pink` | 烟粉 | `#F472B6` | `rgba(244,114,182,0.10)` | (预留) |
| `lime` | 青柠 | `#A3E635` | `rgba(163,230,53,0.10)` | (预留) |
| `slate` | 石墨 | `#94A3B8` | `rgba(148,163,184,0.10)` | (预留) |

> **设计原则:** V2 主题色从 V1 的中低饱和度暖色调整为冷色调基底、中等饱和度，与冷蓝灰背景更协调。10% 透明度背景与实色搭配形成和谐的深浅对比。

---

## 2. 字体体系 Typography

### 2.1 字体栈 Font Stack

```css
font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display",
             "Helvetica Neue", "PingFang SC", sans-serif;
```

| 字体 | 优先级 | 适用场景 |
|:---|:---|:---|
| `-apple-system` | 1 | iOS/macOS 系统字体 (SF Pro) |
| `BlinkMacSystemFont` | 2 | Chrome on macOS |
| `SF Pro Display` | 3 | 明确指定 SF Pro Display 变体 |
| `Helvetica Neue` | 4 | 旧版 macOS 回退 |
| `PingFang SC` | 5 | **中文回退字体** — 苹方简体 |
| `sans-serif` | 6 | 终极回退 |

**特殊字体栈:**

| 场景 | 字体栈 | 用途 |
|:---|:---|:---|
| 行内代码 / 代码块 | `"SF Mono", "Fira Code", monospace` | `.msg.agent code`, `.msg.agent pre` |
| URL / 等宽文本 | `"SF Mono", monospace` | `.inst-url`, `.cmd-cmd-input` |

**OpenType 特性:**

```css
font-feature-settings: "ss01", "cv11";
```

- `ss01`: Stylistic Set 1 — SF Pro 的替代字形 (如单层 a)
- `cv11`: Character Variant 11 — 数字变体

### 2.2 字号层级 Type Scale

V2 字号整体缩小 1-2px，提升信息密度。

| 层级 | Token/描述 | Size | Weight | Line-Height | Letter-Spacing | 用途 |
|:---|:---|:---|:---|:---|:---|:---|
| **大标题** | Header H1 | `24px` | `700` (Bold) | `1.15` | `-0.5px` | 页面主标题 ("虾Hub"、"消息"、"实例") |
| **标题** | Section Title | `18px` | `600` (Semibold) | `1.15` | `-0.3px` | 子页面标题 ("详情"、"添加实例"、"设置")、统计数值 |
| **模块标题** | Section Label | `11px` | `600` (Semibold) | `1.45` | `+0.8px` `uppercase` | 实例分组标题、配置分区标题、设置分区标题 |
| **小标题** | Subtitle | `15px` | `600` (Semibold) | `1.3` | `-0.2px` | 聊天页 Agent 名称、卡片标题 |
| **正文** | Body | `14px` | `400` (Regular) | `1.45` (default) / `1.5` (chat) | `0` | 聊天气泡文字、输入框、设置行 |
| **辅助** | Auxiliary | `12px` ~ `13px` | `400`~`500` | `1.4`~`1.5` | `-0.1px`~`0` | Agent 描述、URL、消息预览、Toast |
| **标注** | Caption | `10px` ~ `11px` | `500`~`600` | `1.4` | `+0.2px`~`+0.8px` | 底部导航标签、时间戳、状态文字 |

**各组件字号详细映射:**

| 组件 | 字号 | 字重 | Letter-Spacing | 特殊属性 |
|:---|:---|:---|:---|:---|
| `.page-header h1` | 24px | 700 | -0.5px | line-height: 1.15 |
| `.stat-item .stat-val` | 13px | 600 | — | `font-variant-numeric: tabular-nums` |
| `.stat-item` | 13px | 400 | — | 行内统计指标 |
| `.group-name` | 11px | 600 | +0.8px | `text-transform: uppercase` |
| `.group-count` | 11px | 400 | — | `font-variant-numeric: tabular-nums` |
| `.agent-name` | 15px | 600 | -0.2px | line-height: 1.3 |
| `.agent-desc` | 12px | 400 | — | line-height: 1.4, 单行截断 |
| `.agent-time` | 10px | — | — | `font-variant-numeric: tabular-nums` |
| `.msg` (气泡) | 14px | 400 | — | line-height: 1.5 |
| `.msg-time` | 10px | — | — | `font-variant-numeric: tabular-nums` |
| `.nav-item span` | 10px | 500 | +0.2px | — |
| `.form-label` | 12px | 500 | — | — |
| `.settings-section-title` | 11px | 600 | +0.8px | `text-transform: uppercase` |
| `.detail-name` | 18px | 700 | — | — |
| `.status-bar .time` | 14px | 600 | +0.2px | — |
| `.inst-name` | 14px | 600 | — | — |
| `.inst-url` | 11px | — | — | `"SF Mono"`, 单行截断 |
| `.inst-status` | 11px | 500 | — | `padding: 2px 8px; border-radius: 999px` |
| `.stat-card .stat-value` | 18px | 700 | — | `font-variant-numeric: tabular-nums` |
| `.stat-card .stat-label` | 10px | — | — | — |
| `.achievement-name` | 13px | 600 | — | — |
| `.achievement-desc` | 11px | — | — | — |
| `.msg-item-name` | 14px | 600 | — | — |
| `.msg-item-preview` | 12px | — | — | line-height: 1.4, 单行截断 |
| `.msg-item-time` | 10px | — | — | `font-variant-numeric: tabular-nums` |
| Inline `code` | 12px | — | — | `"SF Mono"` |
| `.quick-cmd` | 12px | — | — | — |
| `.filter-tab` | 12px | — | — | — |
| `.search-result-text` | 13px | — | — | line-height: 1.5 |
| `.primary-btn` | 14px | 600 | — | — |
| `.detail-tab` | 13px | 500 | — | — |
| `.cmd-text` | 13px | — | — | `"SF Mono"` |

### 2.3 字重 Font Weights

| Weight | 数值 | 用途 |
|:---|:---|:---|
| **Bold** | `700` | 页面标题、统计数值、未读徽章、选中 Tab |
| **Semibold** | `600` | 小标题、模块标题、按钮文字、Agent 名称、表单标签 |
| **Medium** | `500` | 底部导航标签、辅助说明文字、状态栏、快捷指令 |
| **Regular** | `400` | 正文、聊天气泡、输入框、描述文本 |

### 2.4 行高 Line Heights

| 值 | 用途 |
|:---|:---|
| `1.15` | 大标题 (24px)、标题 (18px)，紧凑排列 |
| `1.3` | Agent 名称、小标题 |
| `1.4` | 辅助文字 (12-13px)、描述文本 |
| `1.45` | **全局默认** (body line-height) |
| `1.5` | 聊天气泡正文、时间线文本、输入框、代码块 |
| `1.8` | 关于页面底部版权信息 |

### 2.5 Letter Spacing 规则

| 模式 | 值范围 | 适用场景 |
|:---|:---|:---|
| 负值 (紧缩) | `-0.5px` ~ `-0.1px` | 大字号标题 (24px, 18px, 15px) — 字号越大负值越大 |
| 零值 | `0` | 正文 14px、聊天气泡 |
| 正值 (松散) | `+0.2px` ~ `+0.8px` | 小号标注、大写模块标题 (uppercase) — 增大字间距提升可读性 |

### 2.6 特殊字体规则

| 规则 | CSS 属性 | 适用选择器 |
|:---|:---|:---|
| 数字等宽 | `font-variant-numeric: tabular-nums` | `.stat-item .stat-val`, `.group-count`, `.agent-time`, `.msg-time`, `.msg-item-time`, `.stat-card .stat-value` |
| 中文优先 | `"PingFang SC"` 在字体栈中 | 全局 `body` |
| 等宽字体 | `"SF Mono", "Fira Code", monospace` | `code`, `.inst-url`, `.form-input.mono`, `.cmd-text` |
| 抗锯齿 | `-webkit-font-smoothing: antialiased` | 全局 `body` |

---

## 3. 间距体系 Spacing — 4pt Grid

基于 **4pt 基准网格** 的间距系统。V2 从 V1 的 8pt 网格整体缩小约 30-40%，以提升信息密度。间距值以 `--s1` ~ `--s8` 命名。

### 3.1 间距 Token 表

| Token | 值 | 倍率 | 典型用途 |
|:---|:---|:---|:---|
| `--s1` | `2px` | 0.5x | 元素内微间距: 图标与文字间隙、状态点边距、极小 gap |
| `--s2` | `6px` | 1.5x | 紧凑间距: 列表项间隙、导航图标与标签、卡片间距 |
| `--s3` | `8px` | 2x | 组件内间距: Header 内垂直 padding、聊天气泡 padding、按钮 gap |
| `--s4` | `12px` | 3x | 标准内边距: Agent 卡片 padding、表单行间距 |
| `--s5` | `16px` | 4x | 较大内边距: 统计区域、实例卡片、表单容器 padding |
| `--s6` | `16px` | 4x | **页面水平 padding** (所有页面的左右边距) |
| `--s7` | `24px` | 6x | 区块间距: 配置分区 margin-bottom |
| `--s8` | `32px` | 8x | 大区块间距: 配置页底部留白 |

### 3.2 组件级间距映射

**Header 区域:**
```css
.page-header { padding: 8px var(--s6) 10px; }
/* 8px 16px 10px */
```

**Agent 卡片:**
```css
.agent-card { padding: 10px 12px; margin-bottom: 6px; }
/* 10px 12px; margin-bottom: 6px */
```

**聊天气泡:**
```css
.msg { padding: 9px 13px; }  /* 9px 13px */
.chat-messages { padding: 10px var(--s6); gap: 8px; }  /* 10px 16px; gap: 8px */
```

**统计栏 (行内):**
```css
.stats-inline { gap: 10px; margin-top: 6px; padding: 0 2px; }
.stat-item { gap: 4px; }
```

**分组头:**
```css
.group-header { padding: 10px var(--s6); gap: 6px; min-height: 44px; }
```

**列表区域:**
```css
.agent-list { padding: 0 var(--s6); }  /* 0 16px */
.msg-item { padding: 10px var(--s6); gap: 10px; }  /* 10px 16px; gap: 10px */
```

**表单:**
```css
.form-group { padding: 0 var(--s5); margin-bottom: 14px; }
.form-input { padding: 10px 12px; }  /* padding-based sizing */
```

**按钮:**
```css
.primary-btn { padding: 12px; }
.header-btn { width: 36px; height: 36px; }
.back-btn { width: 32px; height: 32px; }
```

**底部导航:**
```css
.bottom-nav { height: 56px; }
.nav-item { gap: 2px; padding: 6px 0; }
```

**实例卡片:**
```css
.inst-card { padding: 12px 14px; margin: 0 var(--s6) 8px; gap: 10px; }
```

---

## 4. 圆角体系 Border Radius

V2 从紧凑到圆润的 6 级圆角系统（新增 `--r-xs`），整体比 V1 缩小，传达"精密精确"。

| Token | 值 | 用途映射 |
|:---|:---|:---|
| `--r-xs` | `4px` | **新增** hairline 分隔符、微型标签、聊天气泡尾巴缩角、搜索高亮标记 |
| `--r-sm` | `6px` | 小按钮、行内代码、状态徽章、引用块圆角 |
| `--r-md` | `8px` | Header 按钮、Agent 头像 (36px)、返回按钮、聊天气泡内工具卡片、代码块 `pre`、表单输入框、Tab 容器、按钮、实例图标、成就图标、编辑徽章、命令项 |
| `--r-lg` | `10px` | **主要卡片圆角**: Agent 卡片、实例卡片、主/次按钮、设置容器、配置区域卡片、统计卡片 |
| `--r-xl` | `14px` | **聊天气泡主圆角** (用户消息、Agent 消息、输入指示器、输入框) |
| `--r-full` | `999px` | **胶囊形**: 发送按钮、快捷指令按钮、状态标签、色块选择器、筛选标签、未读徽章、Toast 弹窗 |

**聊天气泡特殊圆角规则:**

```css
/* 用户消息 (靠右) — 右下缩角 */
.msg.user {
  border-radius: var(--r-xl);           /* 14px */
  border-bottom-right-radius: var(--r-xs); /* 4px */
}

/* Agent 消息 (靠左) — 左下缩角 */
.msg.agent {
  border-radius: var(--r-xl);          /* 14px */
  border-bottom-left-radius: var(--r-xs); /* 4px */
}
```

> **设计说明:** V2 聊天气泡采用更紧凑的"14px 大圆角 + 4px 单侧缩角"设计（V1 为 20px + 8px），缩角方向指向消息发送者，形成自然的对话气泡尾巴效果。

**Phone Frame 特殊圆角:**

```css
.phone-frame { border-radius: 48px; }      /* 设备外壳 */
.notch { border-radius: 0 0 20px 20px; }   /* 刘海 */
```

---

## 5. 阴影体系 Shadows

V2 减少阴影使用（深色背景上阴影几乎不可见），改用 hairline border 和微弱发光。3 级阴影系统（移除 `--shadow-s` 和 `--shadow-xl`）。

| Token | CSS 值 | 扩散范围 | 用途 |
|:---|:---|:---|:---|
| `--shadow-m` | `0 4px 12px rgba(0,0,0,0.25)` | 12px blur, 4px Y-offset | 浮层用（V1 卡片阴影已移除，改用 border） |
| `--shadow-l` | `0 8px 24px rgba(0,0,0,0.30)` | 24px blur, 8px Y-offset | Toast 弹窗 (`.toast`) |
| `--shadow-glow` | `0 0 20px rgba(79,131,255,0.15)` | 20px blur, 0 offset | **新增** 主按钮蓝色发光、发送按钮发光 |

**特殊阴影组合:**

| 组件 | 阴影值 | 说明 |
|:---|:---|:---|
| `.phone-frame` | `0 16px 48px rgba(0,0,0,0.4), 0 0 60px rgba(79,131,255,0.04)` | 主阴影 + 品牌色环境光 (蓝宝石) |
| `.primary-btn` | `var(--shadow-glow)` | 主按钮下方品牌色发光 |
| `.send-btn` | `var(--shadow-glow)` | 发送按钮品牌色发光 |
| `.color-swatch.selected` | `0 0 0 2px var(--accent)` | 选中色块的蓝色外环 |
| `.stat-dot.online` | `0 0 6px var(--green)` | 在线状态点绿色辉光 |
| `.group-dot.online` | `0 0 6px var(--green)` | 分组头在线状态辉光 |

**输入框焦点态 (border 切换):**

| 状态 | border 样式 | 说明 |
|:---|:---|:---|
| `.form-input` 默认 | `1px solid var(--border)` | hairline 边框 |
| `.form-input` 聚焦 | `1px solid var(--accent)` | 聚焦时切换为品牌色描边 |
| `.search-bar input` 默认 | `1px solid var(--border)` | hairline 边框 |
| `.search-bar input` 聚焦 | `1px solid var(--accent)` | 聚焦时切换为品牌色描边 |
| `.input-bar textarea` 默认 | `1px solid var(--border)` | hairline 边框 |
| `.input-bar textarea` 聚焦 | `1px solid var(--accent)` | 聚焦时切换为品牌色描边 |

---

## 6. 动效体系 Motion

### 6.1 缓动曲线 Easing Curves

| Token | cubic-bezier 值 | 曲线特征 | 用途 |
|:---|:---|:---|:---|
| `--ease` | `cubic-bezier(0.16, 1, 0.3, 1)` | 快速启动，平滑减速 (expo-out) | **默认缓动** — 几乎所有过渡动画 |
| `--ease-out` | `cubic-bezier(0.0, 0.0, 0.2, 1)` | 标准 Material Decelerate | 用于需要更温和减速的场景 |

> **V2 变更:** 移除 `--ease-spring`（弹性超调），V2 不用弹性超调，更克制。

### 6.2 持续时间 Durations

V2 动效整体更快，提升敏捷感。

| Token | 值 | 用途 |
|:---|:---|:---|
| `--dur-fast` | `150ms` | 微交互: 按钮 hover/active、导航切换、卡片按压反馈、分组折叠 |
| `--dur-mid` | `250ms` | 中等动画: 页面 opacity 过渡、Toast 弹出、消息入场、连接 Banner |
| `--dur-slow` | `400ms` | 慢速动画: 页面 transform 滑动过渡、大型布局变化 |

### 6.3 动效组合速查表

| 场景 | Duration | Easing | CSS 属性 |
|:---|:---|:---|:---|
| 按钮按压反馈 | fast (150ms) | ease | `all` |
| 卡片点击反馈 | fast (150ms) | ease | `all` |
| 导航图标颜色切换 | fast (150ms) | ease | `all` |
| 分组折叠/展开 (chevron) | fast (150ms) | ease | `transform, color` |
| 状态点辉光 | fast (150ms) | ease | `box-shadow` |
| 页面滑入/滑出 | slow (400ms) | ease | `transform` |
| 页面透明度渐变 | mid (250ms) | ease | `opacity` |
| Toast 弹出/消失 | mid (250ms) | ease | `all` (opacity + transform) |
| 聊天气泡入场 | mid (250ms) | ease | `opacity, translateY` (keyframes) |
| 连接 Banner 滑入 | mid (250ms) | ease | `transform` |
| 输入框焦点切换 | fast (150ms) | ease | `border-color` |
| 删除项滑出 | 250ms | ease | `all` (opacity + translateX) |
| 输入指示器弹跳 | 800ms | ease | `translateY` (keyframes, infinite) |
| 筛选标签切换 | fast (150ms) | ease | `all` |
| 搜索取消淡出 | fast (150ms) | ease | `opacity` |

### 6.4 按钮按压 Scale 值

| 组件 | Scale 值 | 附加效果 |
|:---|:---|:---|
| 分组头 (`.group-header:active`) | **不缩放** | **opacity: 0.5**（结构性元素，不用背景高亮） |
| Header 按钮 (`.header-btn:active`) | `scale(0.93)` | background 变为 surface3 |
| 返回按钮 (`.back-btn:active`) | `scale(0.93)` | background 变为 surface2 |
| Agent 卡片 (`.agent-card:active`) | `scale(0.97)` | background 变为 surface2 |
| 实例卡片 (`.inst-card:active`) | `scale(0.97)` | background 变为 surface2 |
| 快捷指令 (`.quick-cmd:active`) | `scale(0.93)` | background 变为 rgba(79,131,255,0.18) |
| 发送按钮 (`.send-btn:active`) | `scale(0.88)` | `filter: brightness(0.88)` |
| 主按钮 (`.primary-btn:active`) | `scale(0.97)` | `filter: brightness(0.9)` |
| 次按钮 (`.secondary-btn:active`) | `scale(0.97)` | background 变为 accent-muted |
| 色块选择器 (`.color-swatch:active`) | `scale(0.9)` | — |
| 筛选标签 (`.filter-tab:active`) | `scale(0.95)` | — |
| 搜索取消 (`.search-cancel:active`) | — | opacity: 0.5 |
| 导航项 (`.nav-item:active`) | — | opacity: 0.6 |
| 详情 Tab (`.detail-tab:active`) | — | opacity: 0.6 |
| 添加实例 (`.add-inst-btn:active`) | — | border-color 变为 accent, background 变为 accent-muted |
| 编辑头像 (`.edit-avatar:active`) | `scale(0.95)` | — |

### 6.5 页面转场 Page Transition

```css
.page {
  transition: transform var(--dur-slow) var(--ease),
              opacity var(--dur-mid) var(--ease);
  will-change: transform, opacity;
}
.page.hidden      { transform: translateX(100%); opacity: 0; }  /* 右侧隐藏 (即将进入) */
.page.hidden-left { transform: translateX(-30%); opacity: 0; }  /* 左侧隐藏 (已离开) */
.page.hidden-right { transform: translateX(100%); opacity: 0; } /* 右侧隐藏 */
```

**转场逻辑:**
- 前进导航: 当前页 → `hidden-left` (左移 30% 淡出)，目标页 → 可见 (从右侧 100% 滑入)
- 后退导航: 当前页 → `hidden` (右移 100% 淡出)，目标页 → 可见 (从左侧 -30% 滑入)
- Transform 使用 400ms，opacity 使用 250ms，形成先快后慢的节奏感

### 6.6 Keyframe 动画

| 动画名 | 用途 | 关键帧 |
|:---|:---|:---|
| `msgIn` | 聊天气泡入场 | `from { opacity:0; translateY(10px) }` → `to { opacity:1; translateY(0) }` |
| `typingBounce` | 输入指示器跳动 | `0%,80%,100% { translateY(0) }` → `40% { translateY(-6px) }` 周期 800ms |
| `fadeIn` | 通用淡入 | `from { opacity:0 }` → `to { opacity:1 }` |
| `slideUp` | 通用上滑入场 | `from { translateY(16px); opacity:0 }` → `to { translateY(0); opacity:1 }` |
| `pulse` | 通用脉冲 | `0%, 100% { opacity: 1 }` → `50% { opacity: 0.5 }` |

**交错入场 (Staggered Animation):**

```css
.animate-in { animation: slideUp var(--dur-mid) var(--ease) both; }
.delay-1 { animation-delay: 0.03s; }
.delay-2 { animation-delay: 0.06s; }
.delay-3 { animation-delay: 0.09s; }
.delay-4 { animation-delay: 0.12s; }
.delay-5 { animation-delay: 0.15s; }
.delay-6 { animation-delay: 0.18s; }
.delay-7 { animation-delay: 0.21s; }
```

> Agent 卡片列表使用 30ms 间隔交错入场，最多 7 级延迟 (0ms → 210ms)。

---

## 7. 毛玻璃效果 Glassmorphism

### 7.1 底部导航 Bottom Navigation

```css
.bottom-nav {
  background: rgba(8,9,13,0.92);         /* --bg 的 92% 不透明度 */
  backdrop-filter: blur(20px) saturate(1.3);
  -webkit-backdrop-filter: blur(20px) saturate(1.3);
  border-top: 1px solid var(--border);   /* rgba(255,255,255,0.06) */
}
```

| 属性 | 值 | 说明 |
|:---|:---|:---|
| `background` | `rgba(8,9,13,0.92)` | 页面背景色 92% 不透明 (V1 为 88%) |
| `backdrop-filter: blur` | `20px` | 高斯模糊半径 20px (V1 为 24px) |
| `backdrop-filter: saturate` | `1.3` | 饱和度增强 130% (V1 为 1.4) |
| `border-top` | `1px solid var(--border)` | 顶部微弱分割线 `rgba(255,255,255,0.06)` |

### 7.2 Toast 弹窗

```css
.toast {
  background: var(--surface-elevated);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  box-shadow: var(--shadow-l);
}
```

| 属性 | 值 | 说明 |
|:---|:---|:---|
| `background` | `var(--surface-elevated)` `#12141B` | 浮层专用背景色 |
| `backdrop-filter: blur` | `12px` | 中等模糊 (比导航栏轻) |
| `box-shadow` | `var(--shadow-l)` | 大阴影增强浮起感 |

> **设计说明:** 底部导航使用较强的模糊 (20px) + 饱和度增强 (1.3x)，因为它是常驻元素，需要与滚动内容有清晰分离。Toast 使用较轻的模糊 (12px) 配合实色背景，确保短暂出现时信息可读。V2 底部导航新增了 2px accent 色底部线条指示器替代 V1 的填充色胶囊。

---

## 8. 导出代码 Code Export

### 8.1 CSS Custom Properties (可直接复制使用)

```css
:root {
  /* ========================================
     虾Hub V2 Design Tokens — CSS Custom Properties
     ======================================== */

  /* Background — cool dark */
  --bg: #08090D;
  --surface: #0E1016;
  --surface2: #15171E;
  --surface3: #1C1F28;
  --surface-elevated: #12141B;

  /* Borders — V2 core visual separator */
  --border: rgba(255,255,255,0.06);
  --border-accent: rgba(79,131,255,0.30);

  /* Text — cool white */
  --text-1: #EBEFFA;
  --text-2: rgba(235,239,250,0.55);
  --text-3: rgba(235,239,250,0.30);
  --text-4: rgba(235,239,250,0.14);

  /* Primary accent — sapphire blue */
  --accent: #4F83FF;
  --accent-hover: #6B9AFF;
  --accent-muted: rgba(79,131,255,0.10);
  --accent-glow: rgba(79,131,255,0.20);

  /* Secondary accent — violet */
  --accent2: #9B7AFF;
  --accent2-muted: rgba(155,122,255,0.10);

  /* Tertiary — gold */
  --gold: #E8C574;

  /* Semantic */
  --green: #4ADE80;
  --green-muted: rgba(74,222,128,0.10);
  --red: #F87171;
  --red-muted: rgba(248,113,113,0.08);
  --yellow: #FBBF24;

  /* Spacing — 4pt grid */
  --s1: 2px;
  --s2: 6px;
  --s3: 8px;
  --s4: 12px;
  --s5: 16px;
  --s6: 16px; /* page padding */
  --s7: 24px;
  --s8: 32px;

  /* Radius — tighter */
  --r-xs: 4px;
  --r-sm: 6px;
  --r-md: 8px;
  --r-lg: 10px;
  --r-xl: 14px;
  --r-full: 999px;

  /* Shadow — minimal */
  --shadow-m: 0 4px 12px rgba(0,0,0,0.25);
  --shadow-l: 0 8px 24px rgba(0,0,0,0.30);
  --shadow-glow: 0 0 20px rgba(79,131,255,0.15);

  /* Motion — faster */
  --ease: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-out: cubic-bezier(0.0, 0.0, 0.2, 1);
  --dur-fast: 150ms;
  --dur-mid: 250ms;
  --dur-slow: 400ms;

  /* Safe area */
  --safe-bottom: env(safe-area-inset-bottom, 0px);
}
```

### 8.2 JSON Format (Flutter / React Native)

```json
{
  "color": {
    "bg": "#08090D",
    "surface": "#0E1016",
    "surface2": "#15171E",
    "surface3": "#1C1F28",
    "surfaceElevated": "#12141B",
    "border": "rgba(255,255,255,0.06)",
    "borderAccent": "rgba(79,131,255,0.30)",
    "text1": "#EBEFFA",
    "text2": "rgba(235,239,250,0.55)",
    "text3": "rgba(235,239,250,0.30)",
    "text4": "rgba(235,239,250,0.14)",
    "accent": "#4F83FF",
    "accentHover": "#6B9AFF",
    "accentMuted": "rgba(79,131,255,0.10)",
    "accentGlow": "rgba(79,131,255,0.20)",
    "accent2": "#9B7AFF",
    "accent2Muted": "rgba(155,122,255,0.10)",
    "gold": "#E8C574",
    "green": "#4ADE80",
    "greenMuted": "rgba(74,222,128,0.10)",
    "red": "#F87171",
    "redMuted": "rgba(248,113,113,0.08)",
    "yellow": "#FBBF24"
  },
  "themeColors": {
    "sapphire": { "color": "#4F83FF", "bg": "rgba(79,131,255,0.10)" },
    "violet":   { "color": "#9B7AFF", "bg": "rgba(155,122,255,0.10)" },
    "cyan":     { "color": "#22D3EE", "bg": "rgba(34,211,238,0.10)" },
    "emerald":  { "color": "#34D399", "bg": "rgba(52,211,153,0.10)" },
    "amber":    { "color": "#FBBF24", "bg": "rgba(251,191,36,0.10)" },
    "rose":     { "color": "#FB7185", "bg": "rgba(251,113,133,0.10)" },
    "teal":     { "color": "#2DD4BF", "bg": "rgba(45,212,191,0.10)" },
    "orange":   { "color": "#FB923C", "bg": "rgba(251,146,60,0.10)" },
    "indigo":   { "color": "#818CF8", "bg": "rgba(129,140,248,0.10)" },
    "pink":     { "color": "#F472B6", "bg": "rgba(244,114,182,0.10)" },
    "lime":     { "color": "#A3E635", "bg": "rgba(163,230,53,0.10)" },
    "slate":    { "color": "#94A3B8", "bg": "rgba(148,163,184,0.10)" }
  },
  "spacing": {
    "s1": 2,
    "s2": 6,
    "s3": 8,
    "s4": 12,
    "s5": 16,
    "s6": 16,
    "s7": 24,
    "s8": 32
  },
  "radius": {
    "xs": 4,
    "sm": 6,
    "md": 8,
    "lg": 10,
    "xl": 14,
    "full": 999
  },
  "shadow": {
    "m": "0 4px 12px rgba(0,0,0,0.25)",
    "l": "0 8px 24px rgba(0,0,0,0.30)",
    "glow": "0 0 20px rgba(79,131,255,0.15)"
  },
  "motion": {
    "ease": "cubic-bezier(0.16, 1, 0.3, 1)",
    "easeOut": "cubic-bezier(0.0, 0.0, 0.2, 1)",
    "durFast": 150,
    "durMid": 250,
    "durSlow": 400
  },
  "typography": {
    "fontFamily": "-apple-system, BlinkMacSystemFont, \"SF Pro Display\", \"Helvetica Neue\", \"PingFang SC\", sans-serif",
    "monoFontFamily": "\"SF Mono\", \"Fira Code\", monospace",
    "fontSize": {
      "heroTitle": 24,
      "sectionTitle": 18,
      "statValue": 18,
      "detailName": 18,
      "subtitle": 15,
      "agentName": 15,
      "body": 14,
      "msgItemName": 14,
      "instName": 14,
      "quickCmd": 12,
      "agentDesc": 12,
      "formLabel": 12,
      "sectionLabel": 11,
      "groupCount": 11,
      "caption": 11,
      "navLabel": 10,
      "timestamp": 10
    },
    "fontWeight": {
      "bold": 700,
      "semibold": 600,
      "medium": 500,
      "regular": 400
    },
    "lineHeight": {
      "tight": 1.15,
      "compact": 1.3,
      "narrow": 1.4,
      "default": 1.45,
      "relaxed": 1.5,
      "loose": 1.8
    }
  },
  "glassmorphism": {
    "bottomNav": {
      "background": "rgba(8,9,13,0.92)",
      "blur": 20,
      "saturate": 1.3
    },
    "toast": {
      "background": "#12141B",
      "blur": 12
    }
  }
}
```

### 8.3 Tailwind Config Snippet

```js
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        bg: '#08090D',
        surface: {
          DEFAULT: '#0E1016',
          2: '#15171E',
          3: '#1C1F28',
          elevated: '#12141B',
        },
        border: {
          DEFAULT: 'rgba(255,255,255,0.06)',
          accent: 'rgba(79,131,255,0.30)',
        },
        text: {
          1: '#EBEFFA',
          2: 'rgba(235,239,250,0.55)',
          3: 'rgba(235,239,250,0.30)',
          4: 'rgba(235,239,250,0.14)',
        },
        accent: {
          DEFAULT: '#4F83FF',
          hover: '#6B9AFF',
          muted: 'rgba(79,131,255,0.10)',
          glow: 'rgba(79,131,255,0.20)',
        },
        accent2: {
          DEFAULT: '#9B7AFF',
          muted: 'rgba(155,122,255,0.10)',
        },
        gold: '#E8C574',
        semantic: {
          green: '#4ADE80',
          'green-muted': 'rgba(74,222,128,0.10)',
          red: '#F87171',
          'red-muted': 'rgba(248,113,113,0.08)',
          yellow: '#FBBF24',
        },
        agent: {
          sapphire: '#4F83FF',
          violet:   '#9B7AFF',
          cyan:     '#22D3EE',
          emerald:  '#34D399',
          amber:    '#FBBF24',
          rose:     '#FB7185',
          teal:     '#2DD4BF',
          orange:   '#FB923C',
          indigo:   '#818CF8',
          pink:     '#F472B6',
          lime:     '#A3E635',
          slate:    '#94A3B8',
        },
      },
      spacing: {
        s1: '2px',
        s2: '6px',
        s3: '8px',
        s4: '12px',
        s5: '16px',
        s6: '16px',
        s7: '24px',
        s8: '32px',
      },
      borderRadius: {
        xs: '4px',
        sm: '6px',
        md: '8px',
        lg: '10px',
        xl: '14px',
        full: '999px',
      },
      boxShadow: {
        'm': '0 4px 12px rgba(0,0,0,0.25)',
        'l': '0 8px 24px rgba(0,0,0,0.30)',
        'glow': '0 0 20px rgba(79,131,255,0.15)',
      },
      transitionTimingFunction: {
        'ease': 'cubic-bezier(0.16, 1, 0.3, 1)',
        'ease-out': 'cubic-bezier(0.0, 0.0, 0.2, 1)',
      },
      transitionDuration: {
        fast: '150ms',
        mid: '250ms',
        slow: '400ms',
      },
      fontSize: {
        'hero':    ['24px', { lineHeight: '1.15', letterSpacing: '-0.5px', fontWeight: '700' }],
        'title':   ['18px', { lineHeight: '1.15', letterSpacing: '-0.3px', fontWeight: '600' }],
        'section': ['11px', { lineHeight: '1.45', letterSpacing: '0.8px', fontWeight: '600' }],
        'subtitle':['15px', { lineHeight: '1.3', letterSpacing: '-0.2px', fontWeight: '600' }],
        'body':    ['14px', { lineHeight: '1.45', fontWeight: '400' }],
        'aux':     ['12px', { lineHeight: '1.4', fontWeight: '400' }],
        'caption': ['11px', { lineHeight: '1.4', letterSpacing: '0.2px', fontWeight: '500' }],
        'nav':     ['10px', { lineHeight: '1.4', letterSpacing: '0.2px', fontWeight: '500' }],
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'SF Pro Display', 'Helvetica Neue', 'PingFang SC', 'sans-serif'],
        mono: ['SF Mono', 'Fira Code', 'monospace'],
      },
      backdropBlur: {
        nav: '20px',
        toast: '12px',
      },
    },
  },
};
```

---

## 附录 A: 尺寸常量速查

| 组件 | 宽度 | 高度 | 备注 |
|:---|:---|:---|:---|
| Phone Frame | 393px | 852px | iPhone 15 Pro 尺寸 |
| Notch | 126px | 34px | Dynamic Island 模拟 |
| Status Bar | — | 54px | 含 padding-top 14px |
| Bottom Nav | 100% | 56px | V2 瘦身 (V1: 72px)，含 safe-area-inset |
| Header Btn | 36px | 36px | V2: border 1px solid var(--border) |
| Back Btn | 32px | 32px | — |
| Agent Avatar | 36px | 36px | 卡片内 / 消息列表 (V1: 48px) |
| Agent Avatar (chat header) | 32px | 32px | — |
| Agent Avatar (detail) | 56px | 56px | 详情页 (V1: 72px) |
| Edit Avatar | 64px | 64px | 编辑页 |
| Instance Icon | 36px | 36px | V1: 44px |
| Achievement Icon | 32px | 32px | — |
| Status Dot (online pulse) | 10px | 10px | border: 2px (card avatar) |
| Status Dot (mini) | 8px | 8px | border: 1.5px (msg list avatar) |
| Group Dot | 6px | 6px | 分组头状态点 |
| Stat Dot | 5px | 5px | 行内统计指标点 |
| Primary Btn | 100% (calc -32px) | padding: 12px | V2 padding-based (V1: height 52px) |
| Secondary Btn | 100% (calc -32px) | padding: 11px | — |
| Form Input | 100% | padding: 10px 12px | V2 padding-based (V1: height 48px) |
| Send Btn | 36px | 36px | V1: 40px |
| Color Swatch | max-width: 40px | aspect-ratio: 1 | border: 2px |
| Unread Badge | min 16px | 16px | padding: 0 5px |
| Nav Badge | min 14px | 14px | padding: 0 4px |
| Nav Icon (SVG) | 20px | 20px | V1: 22px |
| Toggle | 40px | 22px | border-radius: 11px |
| Chat Header | — | 52px | V2 紧凑 (V1: ~96px) |
| QR Scan Area | 180px | 180px | 虚线框 border: 2px dashed var(--border-accent) |

## 附录 B: Agent 主题色 Flutter 映射表

```dart
// Dart/Flutter 常量示例
class XiaHubThemeColors {
  static const Map<String, Map<String, Color>> agentThemes = {
    'sapphire': {'color': Color(0xFF4F83FF), 'bg': Color(0x1A4F83FF)},
    'violet':   {'color': Color(0xFF9B7AFF), 'bg': Color(0x1A9B7AFF)},
    'cyan':     {'color': Color(0xFF22D3EE), 'bg': Color(0x1A22D3EE)},
    'emerald':  {'color': Color(0xFF34D399), 'bg': Color(0x1A34D399)},
    'amber':    {'color': Color(0xFFFBBF24), 'bg': Color(0x1AFBBF24)},
    'rose':     {'color': Color(0xFFFB7185), 'bg': Color(0x1AFB7185)},
    'teal':     {'color': Color(0xFF2DD4BF), 'bg': Color(0x1A2DD4BF)},
    'orange':   {'color': Color(0xFFFB923C), 'bg': Color(0x1AFB923C)},
    'indigo':   {'color': Color(0xFF818CF8), 'bg': Color(0x1A818CF8)},
    'pink':     {'color': Color(0xFFF472B6), 'bg': Color(0x1AF472B6)},
    'lime':     {'color': Color(0xFFA3E635), 'bg': Color(0x1AA3E635)},
    'slate':    {'color': Color(0xFF94A3B8), 'bg': Color(0x1A94A3B8)},
  };

  // 核心色 — V2 Cool-Toned Dark
  static const Color bg            = Color(0xFF08090D);
  static const Color surface       = Color(0xFF0E1016);
  static const Color surface2      = Color(0xFF15171E);
  static const Color surface3      = Color(0xFF1C1F28);
  static const Color surfaceElevated = Color(0xFF12141B);

  static const Color text1 = Color(0xFFEBEFFA);
  static const Color text2 = Color(0x8CEBEFFA); // 55%
  static const Color text3 = Color(0x4DEBEFFA); // 30%
  static const Color text4 = Color(0x24EBEFFA); // 14%

  static const Color accent      = Color(0xFF4F83FF);
  static const Color accentHover = Color(0xFF6B9AFF);
  static const Color accent2     = Color(0xFF9B7AFF);
  static const Color gold        = Color(0xFFE8C574);

  static const Color green  = Color(0xFF4ADE80);
  static const Color red    = Color(0xFFF87171);
  static const Color yellow = Color(0xFFFBBF24);
}
```

---

*Document generated from `虾Hub-原型Demo-V2.html` · Design Token Specification v2.0*
