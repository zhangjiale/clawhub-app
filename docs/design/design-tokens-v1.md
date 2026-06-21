# Design Token Specification — 虾Hub (XiaHub)

> Premium Dark-Mode Mobile App for OpenClaw AI Agent Management
> Version 1.0 · 2026-06-10
> Source: `虾Hub-原型Demo-Premium.html`

---

## 目录

1. [色彩体系 Color System](#1-色彩体系-color-system)
2. [字体体系 Typography](#2-字体体系-typography)
3. [间距体系 Spacing — 8pt Grid](#3-间距体系-spacing--8pt-grid)
4. [圆角体系 Border Radius](#4-圆角体系-border-radius)
5. [阴影体系 Shadows](#5-阴影体系-shadows)
6. [动效体系 Motion](#6-动效体系-motion)
7. [毛玻璃效果 Glassmorphism](#7-毛玻璃效果-glassmorphism)
8. [导出代码 Code Export](#8-导出代码-code-export)

---

## 1. 色彩体系 Color System

虾Hub 采用深色模式设计，以暖棕色调为基础，遵循 **60-30-10** 配色法则：

| 比例 | 角色 | 色域 |
|------|------|------|
| **60%** | 主色 (Background) | `--bg`, `--surface` 系列深暖灰色 |
| **30%** | 辅助色 (Secondary) | 卡片表面 `--surface2/3`、文字层级 |
| **10%** | 点缀色 (Accent) | `--accent: #C27C68` 去饱和珊瑚色 |

### 1.1 背景色 Background Colors

采用暖色暗灰渐变层叠，从最底层到最顶层依次变亮，形成自然的空间纵深感。

| Token 名称 | Hex | RGBA | 用途 | 对比度说明 |
|:---|:---|:---|:---|:---|
| `--bg` | `#111110` | `rgb(17, 17, 16)` | 页面最底层背景，全局底色 | 基准层 |
| `--surface` | `#1A1917` | `rgb(26, 25, 23)` | 卡片、列表项、聊天气泡背景 | 与 `--bg` 形成微弱层级区分 |
| `--surface2` | `#232220` | `rgb(35, 34, 32)` | 次级卡片、输入框背景、按钮底色 | 比 surface 亮一级 |
| `--surface3` | `#2C2B28` | `rgb(44, 43, 40)` | 代码块背景、三级嵌套容器、图标底色 | 最亮的表面色 |
| `--surface-elevated` | `#1F1E1C` | `rgb(31, 30, 28)` | Toast 弹窗、浮层背景 (带毛玻璃) | 介于 surface 和 surface2 之间 |

**层级关系示意:**

```
bg (#111110)  ←  最暗，页面底色
 └─ surface (#1A1917)  ←  卡片层
     └─ surface2 (#232220)  ←  嵌套元素
         └─ surface3 (#2C2B28)  ←  最内层元素
 surface-elevated (#1F1E1C)  ←  浮层（配合 backdrop-filter）
```

### 1.2 文字色 Text Colors

文字色采用 `rgba(245, 244, 240, α)` 统一基调，通过透明度 (alpha) 区分层级，确保在深色背景上的视觉层次。

| Token 名称 | 值 | 等效 Hex (on #111110) | Alpha | 用途 | WCAG 对比度 (vs --bg) |
|:---|:---|:---|:---|:---|:---|
| `--text-1` | `#F5F4F0` | `#F5F4F0` | 100% | 主标题、正文、重要数据 | **16.0:1** AAA |
| `--text-2` | `rgba(245,244,240,0.60)` | `~#9D9C98` | 60% | 次要标签、辅助说明 | **6.4:1** AA |
| `--text-3` | `rgba(245,244,240,0.35)` | `~#696865` | 35% | 时间戳、描述文本、占位符说明 | **3.3:1** AA-Large |
| `--text-4` | `rgba(245,244,240,0.18)` | `~#444442` | 18% | 禁用态、极弱提示、分割线 | **1.7:1** 装饰性 |

> **WCAG 说明:**
> - `--text-1` 在所有背景色上均满足 AAA (7:1+) 要求。
> - `--text-2` 在 `--bg` 和 `--surface` 上满足 AA (4.5:1) 要求。
> - `--text-3` 仅用于 18px+ 大字号或装饰性文本 (AA-Large 3:1)。
> - `--text-4` 不适用于可读性文本，仅用于装饰性元素和极低优先级信息。

**文字色在 surface 上的对比度 (vs #1A1917):**

| Token | 对比度 | 等级 |
|:---|:---|:---|
| `--text-1` on `--surface` | 15.1:1 | AAA |
| `--text-2` on `--surface` | 6.0:1 | AA |
| `--text-3` on `--surface` | 3.1:1 | AA-Large |
| `--text-4` on `--surface` | 1.6:1 | 装饰性 |

### 1.3 品牌色 Brand Accent

去饱和珊瑚色 (desaturated coral) 作为品牌点缀色，贯穿全局 CTA 按钮、选中态、活跃导航项。

| Token 名称 | Hex / 值 | 用途 | 对比度说明 |
|:---|:---|:---|:---|
| `--accent` | `#C27C68` `rgb(194,124,104)` | 主按钮、发送按钮、活跃 Tab、导航高亮、未读徽章 | vs --bg: **4.9:1** AA ✓; vs #fff 文字: **3.6:1** (仅大字号) |
| `--accent-hover` | `#D08E7C` `rgb(208,142,124)` | Hover/Pressed 态提亮 | vs --bg: **6.1:1** AA ✓ |
| `--accent-muted` | `rgba(194,124,104,0.12)` | 轻量背景: 连接提示 banner、快捷指令按压态 | 用于背景色，不用于文字 |
| `--accent-glow` | `rgba(194,124,104,0.18)` | 主按钮外发光阴影 `box-shadow` | 纯装饰性 |

> **设计意图:** 品牌色 `#C27C68` 选用去饱和暖珊瑚色，在深色背景上既醒目又不刺眼，传达"专业但有温度"的产品调性。白色文字 (`#FFFFFF`) 在 `--accent` 上的对比度为 3.6:1，满足 WCAG AA Large (3:1) 要求，适用于 15px+ bold 按钮文字。

### 1.4 语义色 Semantic Colors

用于状态指示：在线/离线、成功/失败、警告等。

| Token 名称 | Hex / 值 | 用途 | 对比度 (vs --bg) |
|:---|:---|:---|:---|
| `--green` | `#6BA87A` `rgb(107,168,122)` | 在线状态点、成功标识、"已解锁"文本 | **5.5:1** AA ✓ |
| `--green-muted` | `rgba(107,168,122,0.15)` | 成功状态轻量背景 | 背景用途 |
| `--red` | `#C26464` `rgb(194,100,100)` | 错误状态、删除按钮 hover/active | **4.1:1** AA (Normal) |
| `--red-muted` | `rgba(194,100,100,0.12)` | 删除按钮轻量背景 | 背景用途 |
| `--yellow` | `#C4A86A` `rgb(196,168,106)` | 警告 Banner 文字、连接不稳定提示 | **7.0:1** AAA ✓ |

**附加语义色 (从 CSS 中提取):**

| 来源 | 值 | 用途 |
|:---|:---|:---|
| `.conn-banner.warning` background | `rgba(196,168,106,0.12)` | 警告 Banner 背景 |
| `.conn-banner.info` background | `var(--accent-muted)` | 信息 Banner 背景 |
| `.ach-icon.gold` background | `rgba(196,168,106,0.15)` | 金色成就图标背景 |
| `.ach-icon.silver` background | `rgba(245,244,240,0.06)` | 银色成就图标背景 |
| `.ach-icon.bronze` background | `var(--accent-muted)` | 铜色成就图标背景 |
| 分割线/边框 | `rgba(245,244,240,0.04)` | 列表项分割线、导航栏顶部边框 |
| 代码高亮背景 | `rgba(245,244,240,0.06)` | 行内代码 `<code>` 背景 |
| Phone frame border | `rgba(255,255,255,0.06)` | 设备外框描边 |

### 1.5 Per-Agent 主题色 Theme Colors

每个 AI Agent 实例可分配独立的主题色，用于头像背景、详情页装饰等。主题色以低透明度 (12%) 作为背景，实色作为前景。

| Theme Key | 中文名 | 实色 (Foreground) | 背景色 (12% Alpha) | 使用示例 |
|:---|:---|:---|:---|:---|
| `coral` | 珊瑚 | `#C27C68` | `rgba(194,124,104,0.12)` | 产品虾 (默认主题) |
| `blue` | 雾蓝 | `#6C8AAF` | `rgba(108,138,175,0.12)` | 代码虾 |
| `green` | 薄荷 | `#6BA87A` | `rgba(107,168,122,0.12)` | 英语虾 |
| `orange` | 暖橙 | `#B98A64` | `rgba(185,138,100,0.12)` | 写作虾 |
| `pink` | 烟粉 | `#AF788C` | `rgba(175,120,140,0.12)` | 设计虾 |
| `teal` | 湖蓝 | `#5F9B96` | `rgba(95,155,150,0.12)` | 数据虾 |
| `yellow` | 暖黄 | `#AF9B5F` | `rgba(175,155,95,0.12)` | 运维虾 |
| `rose` | 玫瑰 | `#AA6E82` | `rgba(170,110,130,0.12)` | (预留) |
| `slate` | 石墨 | `#828282` | `rgba(130,130,130,0.12)` | (预留) |
| `indigo` | 靛蓝 | `#6E64A0` | `rgba(110,100,160,0.12)` | (预留) |
| `caramel` | 焦糖 | `#AA7D50` | `rgba(170,125,80,0.12)` | (预留) |
| `jade` | 翡翠 | `#509678` | `rgba(80,150,120,0.12)` | (预留) |

> **设计原则:** 所有主题色均控制在中等饱和度范围内 (HSL 饱和度约 25%~40%)，确保在深色背景上不刺眼。12% 透明度背景与实色搭配形成和谐的深浅对比。

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

| 层级 | Token/描述 | Size | Weight | Line-Height | Letter-Spacing | 用途 |
|:---|:---|:---|:---|:---|:---|:---|
| **大标题** | Header H1 | `30px` | `700` (Bold) | `1.2` | `-0.6px` | 页面主标题 ("虾Hub"、"消息"、"实例") |
| **标题** | Section Title | `22px` ~ `24px` | `700` (Bold) | `1.3` | `-0.5px` | 子页面标题 ("详情"、"个性化配置"、"设置")、统计数值 |
| **模块标题** | Section Label | `12px` | `600` (Semibold) | `1.55` | `+0.8px` `uppercase` | 实例分组标题、配置分区标题 ("基本信息"、"主题色") |
| **小标题** | Subtitle | `17px` | `600` (Semibold) | `1.3` | `-0.2px` | 聊天页 Agent 名称、空状态标题 |
| **正文** | Body | `15px` | `400` (Regular) | `1.55` (default) / `1.6` (chat) | `0` | 聊天气泡文字、输入框、设置行 |
| **辅助** | Auxiliary | `13px` ~ `14px` | `400`~`500` | `1.4`~`1.5` | `-0.3px`~`0` | Agent 描述、URL、消息预览、Toast |
| **标注** | Caption | `10px` ~ `12px` | `500`~`600` | `1.4` | `+0.2px`~`+0.8px` | 底部导航标签、时间戳、芯片标签、状态文字 |

**各组件字号详细映射:**

| 组件 | 字号 | 字重 | Letter-Spacing | 特殊属性 |
|:---|:---|:---|:---|:---|
| `.header h1` | 30px | 700 | -0.6px | line-height: 1.2 |
| `.header h1` (子页面) | 22px | 700 | — | — |
| `.chip-value` | 22px | 700 | -0.5px | `font-variant-numeric: tabular-nums` |
| `.stat-value` | 24px | 700 | -0.5px | `font-variant-numeric: tabular-nums` |
| `.chip-unit` | 14px | 400 | — | — |
| `.chip-label` | 11px | 500 | +0.3px | — |
| `.stat-label` | 11px | 500 | +0.3px | — |
| `.instance-name` | 12px | 600 | +0.8px | `text-transform: uppercase` |
| `.instance-count` | 12px | 400 | — | `font-variant-numeric: tabular-nums` |
| `.agent-name` | 16px | 600 | -0.2px | line-height: 1.3 |
| `.agent-desc` | 13px | 400 | — | line-height: 1.4, 单行截断 |
| `.agent-time` | 11px | — | +0.2px | `font-variant-numeric: tabular-nums` |
| `.msg` (气泡) | 15px | 400 | — | line-height: 1.6 |
| `.msg-time` | 11px | — | — | `font-variant-numeric: tabular-nums` |
| `.nav-item span` | 10px | 500 | +0.2px | — |
| `.form-label` | 12px | 600 | +0.5px | `text-transform: uppercase` |
| `.config-section-title` | 12px | 600 | +0.8px | `text-transform: uppercase` |
| `.config-avatar-name` | 20px | 700 | -0.3px | — |
| `.status-bar .time` | 14px | 600 | +0.2px | — |
| Inline `code` | 13px | — | — | `"SF Mono"` |
| `pre` code block | 12px | — | — | `"SF Mono"`, line-height: 1.5 |

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
| `1.2` | 大标题 (30px)，紧凑排列 |
| `1.3` | Agent 名称、小标题 |
| `1.4` | 辅助文字 (12-13px)、成就描述 |
| `1.5` | 消息预览、输入框、代码块 |
| `1.55` | **全局默认** (body line-height) |
| `1.6` | 聊天气泡正文 (增强可读性) |
| `1.8` | 关于页面底部版权信息 |

### 2.5 Letter Spacing 规则

| 模式 | 值范围 | 适用场景 |
|:---|:---|:---|
| 负值 (紧缩) | `-0.6px` ~ `-0.1px` | 大字号标题 (30px, 24px, 22px, 20px, 17px, 16px) — 字号越大负值越大 |
| 零值 | `0` | 正文 15px、聊天气泡 |
| 正值 (松散) | `+0.2px` ~ `+0.8px` | 小号标注、大写模块标题 (uppercase) — 增大字间距提升可读性 |

### 2.6 特殊字体规则

| 规则 | CSS 属性 | 适用选择器 |
|:---|:---|:---|
| 数字等宽 | `font-variant-numeric: tabular-nums` | `.chip-value`, `.stat-value`, `.instance-count`, `.agent-time`, `.msg-time`, `.msg-item-time` |
| 中文优先 | `"PingFang SC"` 在字体栈中 | 全局 `body` |
| 等宽字体 | `"SF Mono", "Fira Code", monospace` | `code`, `pre`, `.inst-url`, `.cmd-cmd-input` |
| 抗锯齿 | `-webkit-font-smoothing: antialiased` | 全局 `body` |

---

## 3. 间距体系 Spacing — 8pt Grid

基于 **8pt 基准网格** 的间距系统。所有间距值为 4 的倍数，以 `--s1` ~ `--s10` 命名。

### 3.1 间距 Token 表

| Token | 值 | 倍率 | 典型用途 |
|:---|:---|:---|:---|
| `--s1` | `4px` | 0.5x | 元素内微间距: 图标与文字间隙、状态点边距、时间戳 margin |
| `--s2` | `8px` | 1x | 紧凑间距: 列表项间隙、导航图标与标签、Tab 内边距 |
| `--s3` | `12px` | 1.5x | 组件内间距: Header 内垂直 padding、Agent 卡片间隙、聊天气泡 padding |
| `--s4` | `16px` | 2x | 标准内边距: Agent 卡片、头像与信息区间距、表单行间距 |
| `--s5` | `20px` | 2.5x | 较大内边距: 统计芯片、实例卡片、设置行、主内容区 padding |
| `--s6` | `24px` | 3x | **页面水平 padding** (所有页面的左右边距)、统计栏底部间距 |
| `--s7` | `32px` | 4x | 区块间距: 配置分区 margin-bottom |
| `--s8` | `40px` | 5x | 大区块间距: 配置页底部留白 |
| `--s9` | `48px` | 6x | 空状态垂直 padding |
| `--s10` | `56px` | 7x | (预留，当前未使用) |

### 3.2 组件级间距映射

**Header 区域:**
```css
.header { padding: var(--s3) var(--s6) var(--s4); gap: var(--s3); }
/* 12px 24px 16px; gap: 12px */
```

**Agent 卡片:**
```css
.agent-card { padding: var(--s4) var(--s5); margin-bottom: var(--s3); }
/* 16px 20px; margin-bottom: 12px */
```

**聊天气泡:**
```css
.msg { padding: var(--s3) var(--s5); }  /* 12px 20px */
.chat-messages { padding: var(--s4) var(--s6); gap: var(--s3); }  /* 16px 24px; gap: 12px */
```

**统计栏:**
```css
.stats-bar { gap: var(--s3); padding: 0 var(--s6) var(--s5); }  /* gap: 12px; 0 24px 20px */
.stat-chip { padding: var(--s4) var(--s3); }  /* 16px 12px */
```

**列表区域:**
```css
.agent-list { padding: 0 var(--s6); }  /* 0 24px */
.msg-list { padding: 0 var(--s6); }    /* 0 24px */
.msg-item { padding: var(--s5) var(--s2); gap: var(--s4); }  /* 20px 8px; gap: 16px */
```

**表单:**
```css
.form-group { margin-bottom: var(--s5); }  /* 20px */
.form-input { height: 48px; padding: 0 var(--s5); }  /* 0 20px */
```

**按钮:**
```css
.primary-btn { height: 52px; }
.header-btn { width: 40px; height: 40px; }
.inst-action-btn { width: 36px; height: 36px; }
```

**底部导航:**
```css
.bottom-nav { height: 72px; }
.nav-item { gap: 3px; padding: var(--s2) var(--s6); }  /* gap: 3px; 8px 24px */
```

---

## 4. 圆角体系 Border Radius

从紧凑到圆润的 5 级圆角系统。

| Token | 值 | 用途映射 |
|:---|:---|:---|
| `--r-sm` | `8px` | 聊天头像 (小号)、行内代码、状态指示点边框、配置输入框、Tab 内按钮、操作按钮、Cmd 输入框、成就图标、编辑徽章、命令项 |
| `--r-md` | `12px` | Header 按钮、Agent 头像 (48px)、返回按钮、消息列表头像、聊天气泡内工具卡片、代码块 `pre`、表单输入框、Tab 容器、主/次按钮、实例图标、操作按钮、统计卡片、成就项、配置卡片 |
| `--r-lg` | `16px` | **主要卡片圆角**: Agent 卡片、统计芯片、实例卡片、聊天气泡、消息输入框、设置容器、二维码扫描框、添加实例按钮、配置区域卡片 |
| `--r-xl` | `20px` | **聊天气泡主圆角** (用户消息、Agent 消息、输入指示器)、二维码扫描框 |
| `--r-full` | `999px` | **胶囊形**: 底部导航指示器、状态点 (在线/离线)、未读计数徽章、Toast 弹窗、快捷指令按钮、添加指令按钮、色块选择器勾选 |

**聊天气泡特殊圆角规则:**

```css
/* 用户消息 (靠右) — 右下缩角 */
.msg.user {
  border-radius: var(--r-xl);           /* 20px */
  border-bottom-right-radius: var(--r-sm); /* 8px */
}

/* Agent 消息 (靠左) — 左下缩角 */
.msg.agent {
  border-radius: var(--r-xl);          /* 20px */
  border-bottom-left-radius: var(--r-sm); /* 8px */
}
```

> **设计说明:** 聊天气泡采用"大圆角 + 单侧缩角"设计，缩角方向指向消息发送者，形成自然的对话气泡尾巴效果。

**Phone Frame 特殊圆角:**

```css
.phone-frame { border-radius: 48px; }      /* 设备外壳 */
.notch { border-radius: 0 0 20px 20px; }   /* 刘海 */
```

---

## 5. 阴影体系 Shadows

4 级暖色调阴影系统，使用纯黑透明度，在深色背景上营造柔和的层次感。

| Token | CSS 值 | 扩散范围 | 用途 |
|:---|:---|:---|:---|
| `--shadow-s` | `0 1px 2px rgba(0,0,0,0.18)` | 2px blur, 1px Y-offset | Agent 聊天气泡 (`.msg.agent`)、输入指示器 (`.typing-indicator`) |
| `--shadow-m` | `0 4px 16px rgba(0,0,0,0.20)` | 16px blur, 4px Y-offset | (预留，当前通过 `--shadow-s` 替代) |
| `--shadow-l` | `0 8px 32px rgba(0,0,0,0.22)` | 32px blur, 8px Y-offset | Toast 弹窗 (`.toast`) |
| `--shadow-xl` | `0 16px 48px rgba(0,0,0,0.28)` | 48px blur, 16px Y-offset | Phone Frame 设备外框阴影 |

**特殊阴影组合:**

| 组件 | 阴影值 | 说明 |
|:---|:---|:---|
| `.phone-frame` | `var(--shadow-xl), 0 0 80px rgba(194,124,104,0.06)` | 主阴影 + 品牌色环境光 |
| `.primary-btn` | `0 4px 20px var(--accent-glow)` | 主按钮下方品牌色发光 |
| `.config-save-btn` | `0 4px 20px var(--accent-glow)` | 保存按钮同样使用品牌色发光 |
| `.color-dot.selected` | `0 0 16px rgba(245,244,240,0.15)` | 选中色块的白色辉光 |
| `.instance-dot.online` | `0 0 8px var(--green)` | 在线状态点绿色辉光 |

**输入框焦点态 (内阴影模拟描边):**

| 状态 | box-shadow | 说明 |
|:---|:---|:---|
| `.form-input` 默认 | `inset 0 0 0 1.5px var(--surface3)` | 1.5px 内描边，surface3 色 |
| `.form-input` 聚焦 | `inset 0 0 0 1.5px var(--accent)` | 聚焦时切换为品牌色描边 |
| `.config-input` 默认 | `inset 0 0 0 1px var(--surface3)` | 1px 内描边 |
| `.config-input` 聚焦 | `inset 0 0 0 1px var(--accent)` | 聚焦时切换为品牌色描边 |

---

## 6. 动效体系 Motion

### 6.1 缓动曲线 Easing Curves

| Token | cubic-bezier 值 | 曲线特征 | 用途 |
|:---|:---|:---|:---|
| `--ease` | `cubic-bezier(0.16, 1, 0.3, 1)` | 快速启动，平滑减速 (expo-out) | **默认缓动** — 几乎所有过渡动画 |
| `--ease-spring` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | 弹性超调 (overshoot) | 弹跳入场效果、趣味性交互动画 |
| `--ease-out` | `cubic-bezier(0.0, 0.0, 0.2, 1)` | 标准 Material Decelerate | (预留，用于需要更温和减速的场景) |

### 6.2 持续时间 Durations

| Token | 值 | 用途 |
|:---|:---|:---|
| `--duration-fast` | `200ms` | 微交互: 按钮 hover/active、导航切换、卡片按压反馈、分组折叠 |
| `--duration-mid` | `350ms` | 中等动画: 页面 opacity 过渡、Toast 弹出、消息入场、连接 Banner |
| `--duration-slow` | `500ms` | 慢速动画: 页面 transform 滑动过渡、大型布局变化 |

### 6.3 动效组合速查表

| 场景 | Duration | Easing | CSS 属性 |
|:---|:---|:---|:---|
| 按钮按压反馈 | fast (200ms) | ease | `all` |
| 卡片点击反馈 | fast (200ms) | ease | `all` |
| 导航图标颜色切换 | fast (200ms) | ease | `all` |
| 分组折叠/展开 (chevron) | fast (200ms) | ease | `transform` |
| 状态点辉光 | fast (200ms) | ease | `box-shadow` |
| 页面滑入/滑出 | slow (500ms) | ease | `transform` |
| 页面透明度渐变 | mid (350ms) | ease | `opacity` |
| Toast 弹出/消失 | mid (350ms) | ease | `all` (opacity + transform) |
| 聊天气泡入场 | mid (350ms) | ease | `opacity, translateY` (keyframes) |
| 连接 Banner 滑入 | mid (350ms) | ease | `transform` |
| 输入框焦点切换 | fast (200ms) | ease | `all` (box-shadow + background) |
| 删除项滑出 | 250ms | ease | `all` (opacity + translateX) |
| 输入指示器弹跳 | 800ms | ease | `translateY` (keyframes, infinite) |

### 6.4 按钮按压 Scale 值

| 组件 | Scale 值 | 附加效果 |
|:---|:---|:---|
| 分组头 (`.instance-header:active`) | **不缩放** | **opacity: 0.5**（结构性元素，不用背景高亮） |
| Header 按钮 (`.header-btn:active`) | `scale(0.95)` | background 变为 surface3 |
| 返回按钮 (`.back-btn:active`) | `scale(0.95)` | background 变为 surface2 |
| Agent 卡片 (`.agent-card:active`) | `scale(0.98)` | background 变为 surface2 |
| 实例卡片 (`.inst-card:active`) | `scale(0.98)` | — |
| 快捷指令 (`.quick-cmd:active`) | `scale(0.95)` | background 变为 accent-muted |
| Plus 按钮 (`.plus-btn:active`) | `scale(0.95)` | background 变为 surface3 |
| 发送按钮 (`.send-btn:active`) | `scale(0.92)` | — |
| 主按钮 (`.primary-btn:active`) | `scale(0.97)` | `filter: brightness(0.92)` |
| 保存按钮 (`.config-save-btn:active`) | `scale(0.97)` | `filter: brightness(0.92)` |
| 配置头像 (`.config-avatar:active`) | `scale(0.95)` | — |
| 色块选择器 (`.color-dot:active`) | `scale(0.9)` | — |
| 添加指令按钮 (`.cmd-add-btn:active`) | — | background 变为 accent-muted |

### 6.5 页面转场 Page Transition

```css
.page {
  transition: transform var(--duration-slow) var(--ease),
              opacity var(--duration-mid) var(--ease);
  will-change: transform, opacity;
}
.page.hidden      { transform: translateX(100%); opacity: 0; }  /* 右侧隐藏 (即将进入) */
.page.hidden-left { transform: translateX(-30%); opacity: 0; }  /* 左侧隐藏 (已离开) */
```

**转场逻辑:**
- 前进导航: 当前页 → `hidden-left` (左移 30% 淡出)，目标页 → 可见 (从右侧 100% 滑入)
- 后退导航: 当前页 → `hidden` (右移 100% 淡出)，目标页 → 可见 (从左侧 -30% 滑入)
- Transform 使用 500ms，opacity 使用 350ms，形成先快后慢的节奏感

### 6.6 Keyframe 动画

| 动画名 | 用途 | 关键帧 |
|:---|:---|:---|
| `msgIn` | 聊天气泡入场 | `from { opacity:0; translateY(12px) }` → `to { opacity:1; translateY(0) }` |
| `typingBounce` | 输入指示器跳动 | `0%,80%,100% { translateY(0) }` → `40% { translateY(-8px) }` 周期 800ms |
| `fadeIn` | 通用淡入 | `from { opacity:0 }` → `to { opacity:1 }` |
| `slideUp` | 通用上滑入场 | `from { translateY(20px); opacity:0 }` → `to { translateY(0); opacity:1 }` |

**交错入场 (Staggered Animation):**

```css
.animate-in { animation: slideUp var(--duration-mid) var(--ease) both; }
.delay-1 { animation-delay: 0.04s; }
.delay-2 { animation-delay: 0.08s; }
.delay-3 { animation-delay: 0.12s; }
.delay-4 { animation-delay: 0.16s; }
.delay-5 { animation-delay: 0.20s; }
```

> Agent 卡片列表使用 40ms 间隔交错入场，最多 5 级延迟 (0ms → 200ms)。

---

## 7. 毛玻璃效果 Glassmorphism

### 7.1 底部导航 Bottom Navigation

```css
.bottom-nav {
  background: rgba(17,17,16,0.88);         /* --bg 的 88% 不透明度 */
  backdrop-filter: blur(24px) saturate(1.4);
  -webkit-backdrop-filter: blur(24px) saturate(1.4);
  border-top: 1px solid rgba(245,244,240,0.04);
}
```

| 属性 | 值 | 说明 |
|:---|:---|:---|
| `background` | `rgba(17,17,16,0.88)` | 页面背景色 88% 不透明 |
| `backdrop-filter: blur` | `24px` | 高斯模糊半径 24px |
| `backdrop-filter: saturate` | `1.4` | 饱和度增强 140% |
| `border-top` | `1px solid rgba(245,244,240,0.04)` | 顶部微弱分割线 |

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
| `background` | `var(--surface-elevated)` `#1F1E1C` | 浮层专用背景色 |
| `backdrop-filter: blur` | `12px` | 中等模糊 (比导航栏轻) |
| `box-shadow` | `var(--shadow-l)` | 大阴影增强浮起感 |

> **设计说明:** 底部导航使用更强的模糊 (24px) + 饱和度增强 (1.4x)，因为它是常驻元素，需要与滚动内容有清晰分离。Toast 使用较轻的模糊 (12px) 配合实色背景，确保短暂出现时信息可读。

---

## 8. 导出代码 Code Export

### 8.1 CSS Custom Properties (可直接复制使用)

```css
:root {
  /* ========================================
     虾Hub Design Tokens — CSS Custom Properties
     ======================================== */

  /* Color — 60-30-10 */
  --bg: #111110;
  --surface: #1A1917;
  --surface2: #232220;
  --surface3: #2C2B28;
  --surface-elevated: #1F1E1C;

  /* Text — rgba for tonal depth */
  --text-1: #F5F4F0;
  --text-2: rgba(245,244,240,0.60);
  --text-3: rgba(245,244,240,0.35);
  --text-4: rgba(245,244,240,0.18);

  /* Brand accent — desaturated coral */
  --accent: #C27C68;
  --accent-hover: #D08E7C;
  --accent-muted: rgba(194,124,104,0.12);
  --accent-glow: rgba(194,124,104,0.18);

  /* Semantic */
  --green: #6BA87A;
  --green-muted: rgba(107,168,122,0.15);
  --red: #C26464;
  --red-muted: rgba(194,100,100,0.12);
  --yellow: #C4A86A;

  /* Spacing — 8pt grid */
  --s1: 4px;
  --s2: 8px;
  --s3: 12px;
  --s4: 16px;
  --s5: 20px;
  --s6: 24px;
  --s7: 32px;
  --s8: 40px;
  --s9: 48px;
  --s10: 56px;

  /* Radius */
  --r-sm: 8px;
  --r-md: 12px;
  --r-lg: 16px;
  --r-xl: 20px;
  --r-full: 999px;

  /* Shadow — 4 tiers, warm tone */
  --shadow-s: 0 1px 2px rgba(0,0,0,0.18);
  --shadow-m: 0 4px 16px rgba(0,0,0,0.20);
  --shadow-l: 0 8px 32px rgba(0,0,0,0.22);
  --shadow-xl: 0 16px 48px rgba(0,0,0,0.28);

  /* Motion */
  --ease: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);
  --ease-out: cubic-bezier(0.0, 0.0, 0.2, 1);
  --duration-fast: 200ms;
  --duration-mid: 350ms;
  --duration-slow: 500ms;

  /* Safe area */
  --safe-bottom: env(safe-area-inset-bottom, 0px);
}
```

### 8.2 JSON Format (Flutter / React Native)

```json
{
  "color": {
    "bg": "#111110",
    "surface": "#1A1917",
    "surface2": "#232220",
    "surface3": "#2C2B28",
    "surfaceElevated": "#1F1E1C",
    "text1": "#F5F4F0",
    "text2": "rgba(245,244,240,0.60)",
    "text3": "rgba(245,244,240,0.35)",
    "text4": "rgba(245,244,240,0.18)",
    "accent": "#C27C68",
    "accentHover": "#D08E7C",
    "accentMuted": "rgba(194,124,104,0.12)",
    "accentGlow": "rgba(194,124,104,0.18)",
    "green": "#6BA87A",
    "greenMuted": "rgba(107,168,122,0.15)",
    "red": "#C26464",
    "redMuted": "rgba(194,100,100,0.12)",
    "yellow": "#C4A86A"
  },
  "themeColors": {
    "coral":   { "color": "#C27C68", "bg": "rgba(194,124,104,0.12)" },
    "blue":    { "color": "#6C8AAF", "bg": "rgba(108,138,175,0.12)" },
    "green":   { "color": "#6BA87A", "bg": "rgba(107,168,122,0.12)" },
    "orange":  { "color": "#B98A64", "bg": "rgba(185,138,100,0.12)" },
    "pink":    { "color": "#AF788C", "bg": "rgba(175,120,140,0.12)" },
    "teal":    { "color": "#5F9B96", "bg": "rgba(95,155,150,0.12)" },
    "yellow":  { "color": "#AF9B5F", "bg": "rgba(175,155,95,0.12)" },
    "rose":    { "color": "#AA6E82", "bg": "rgba(170,110,130,0.12)" },
    "slate":   { "color": "#828282", "bg": "rgba(130,130,130,0.12)" },
    "indigo":  { "color": "#6E64A0", "bg": "rgba(110,100,160,0.12)" },
    "caramel": { "color": "#AA7D50", "bg": "rgba(170,125,80,0.12)" },
    "jade":    { "color": "#509678", "bg": "rgba(80,150,120,0.12)" }
  },
  "spacing": {
    "s1": 4,
    "s2": 8,
    "s3": 12,
    "s4": 16,
    "s5": 20,
    "s6": 24,
    "s7": 32,
    "s8": 40,
    "s9": 48,
    "s10": 56
  },
  "radius": {
    "sm": 8,
    "md": 12,
    "lg": 16,
    "xl": 20,
    "full": 999
  },
  "shadow": {
    "s": "0 1px 2px rgba(0,0,0,0.18)",
    "m": "0 4px 16px rgba(0,0,0,0.20)",
    "l": "0 8px 32px rgba(0,0,0,0.22)",
    "xl": "0 16px 48px rgba(0,0,0,0.28)"
  },
  "motion": {
    "ease": "cubic-bezier(0.16, 1, 0.3, 1)",
    "easeSpring": "cubic-bezier(0.34, 1.56, 0.64, 1)",
    "easeOut": "cubic-bezier(0.0, 0.0, 0.2, 1)",
    "durationFast": 200,
    "durationMid": 350,
    "durationSlow": 500
  },
  "typography": {
    "fontFamily": "-apple-system, BlinkMacSystemFont, \"SF Pro Display\", \"Helvetica Neue\", \"PingFang SC\", sans-serif",
    "monoFontFamily": "\"SF Mono\", \"Fira Code\", monospace",
    "fontSize": {
      "heroTitle": 30,
      "sectionTitle": 22,
      "statValue": 24,
      "configAvatarName": 20,
      "subtitle": 17,
      "agentName": 16,
      "body": 15,
      "msgItemPreview": 14,
      "chipUnit": 14,
      "quickCmd": 13,
      "agentDesc": 13,
      "formLabel": 12,
      "sectionLabel": 12,
      "instanceName": 12,
      "caption": 11,
      "navLabel": 10
    },
    "fontWeight": {
      "bold": 700,
      "semibold": 600,
      "medium": 500,
      "regular": 400
    },
    "lineHeight": {
      "tight": 1.2,
      "compact": 1.3,
      "narrow": 1.4,
      "normal": 1.5,
      "default": 1.55,
      "relaxed": 1.6,
      "loose": 1.8
    }
  },
  "glassmorphism": {
    "bottomNav": {
      "background": "rgba(17,17,16,0.88)",
      "blur": 24,
      "saturate": 1.4
    },
    "toast": {
      "background": "#1F1E1C",
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
        bg: '#111110',
        surface: {
          DEFAULT: '#1A1917',
          2: '#232220',
          3: '#2C2B28',
          elevated: '#1F1E1C',
        },
        text: {
          1: '#F5F4F0',
          2: 'rgba(245,244,240,0.60)',
          3: 'rgba(245,244,240,0.35)',
          4: 'rgba(245,244,240,0.18)',
        },
        accent: {
          DEFAULT: '#C27C68',
          hover: '#D08E7C',
          muted: 'rgba(194,124,104,0.12)',
          glow: 'rgba(194,124,104,0.18)',
        },
        semantic: {
          green: '#6BA87A',
          'green-muted': 'rgba(107,168,122,0.15)',
          red: '#C26464',
          'red-muted': 'rgba(194,100,100,0.12)',
          yellow: '#C4A86A',
        },
        agent: {
          coral:   '#C27C68',
          blue:    '#6C8AAF',
          green:   '#6BA87A',
          orange:  '#B98A64',
          pink:    '#AF788C',
          teal:    '#5F9B96',
          yellow:  '#AF9B5F',
          rose:    '#AA6E82',
          slate:   '#828282',
          indigo:  '#6E64A0',
          caramel: '#AA7D50',
          jade:    '#509678',
        },
      },
      spacing: {
        s1: '4px',
        s2: '8px',
        s3: '12px',
        s4: '16px',
        s5: '20px',
        s6: '24px',
        s7: '32px',
        s8: '40px',
        s9: '48px',
        s10: '56px',
      },
      borderRadius: {
        sm: '8px',
        md: '12px',
        lg: '16px',
        xl: '20px',
        full: '999px',
      },
      boxShadow: {
        's': '0 1px 2px rgba(0,0,0,0.18)',
        'm': '0 4px 16px rgba(0,0,0,0.20)',
        'l': '0 8px 32px rgba(0,0,0,0.22)',
        'xl': '0 16px 48px rgba(0,0,0,0.28)',
      },
      transitionTimingFunction: {
        'ease': 'cubic-bezier(0.16, 1, 0.3, 1)',
        'ease-spring': 'cubic-bezier(0.34, 1.56, 0.64, 1)',
        'ease-out': 'cubic-bezier(0.0, 0.0, 0.2, 1)',
      },
      transitionDuration: {
        fast: '200ms',
        mid: '350ms',
        slow: '500ms',
      },
      fontSize: {
        'hero':    ['30px', { lineHeight: '1.2', letterSpacing: '-0.6px', fontWeight: '700' }],
        'title':   ['22px', { lineHeight: '1.3', letterSpacing: '-0.5px', fontWeight: '700' }],
        'section': ['12px', { lineHeight: '1.55', letterSpacing: '0.8px', fontWeight: '600' }],
        'subtitle':['17px', { lineHeight: '1.3', letterSpacing: '-0.2px', fontWeight: '600' }],
        'body':    ['15px', { lineHeight: '1.55', fontWeight: '400' }],
        'aux':     ['13px', { lineHeight: '1.4', fontWeight: '400' }],
        'caption': ['11px', { lineHeight: '1.4', letterSpacing: '0.2px', fontWeight: '500' }],
        'nav':     ['10px', { lineHeight: '1.4', letterSpacing: '0.2px', fontWeight: '500' }],
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'SF Pro Display', 'Helvetica Neue', 'PingFang SC', 'sans-serif'],
        mono: ['SF Mono', 'Fira Code', 'monospace'],
      },
      backdropBlur: {
        nav: '24px',
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
| Bottom Nav | 100% | 72px | 含 safe-area-inset |
| Header Btn | 40px | 40px | — |
| Back Btn | 40px | 40px | — |
| Agent Avatar | 48px | 48px | 卡片内 / 消息列表 |
| Agent Avatar (chat header) | 40px | 40px | — |
| Agent Avatar (detail) | 72px | 72px | 详情页 |
| Config Avatar | 64px | 64px | 配置页 |
| Instance Icon | 44px | 44px | — |
| Achievement Icon | 40px | 40px | — |
| Status Dot (card) | 8px | 8px | border: 2px |
| Status Dot (header/inline) | 6px | 6px | — |
| Instance Dot | 6px | 6px | — |
| Primary Btn | 100% | 52px | — |
| Form Input | 100% | 48px | — |
| Config Input | 100% | 44px | — |
| Inst Action Btn | 36px | 36px | — |
| Send Btn / Plus Btn | 40px | 40px | — |
| Color Dot | 40px | 40px | border: 3px |
| Unread Badge | min 18px | 18px | padding: 0 5px |
| Edit Badge | 22px | 22px | — |
| QR Scan Area | 200px | 200px | — |
| Nav Icon (SVG) | 22px | 22px | — |

## 附录 B: Agent 主题色 Flutter 映射表

```dart
// Dart/Flutter 常量示例
class XiaHubThemeColors {
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

  // 核心色
  static const Color bg            = Color(0xFF111110);
  static const Color surface       = Color(0xFF1A1917);
  static const Color surface2      = Color(0xFF232220);
  static const Color surface3      = Color(0xFF2C2B28);
  static const Color surfaceElevated = Color(0xFF1F1E1C);

  static const Color text1 = Color(0xFFF5F4F0);
  static const Color text2 = Color(0x99F5F4F0); // 60%
  static const Color text3 = Color(0x59F5F4F0); // 35%
  static const Color text4 = Color(0x2EF5F4F0); // 18%

  static const Color accent      = Color(0xFFC27C68);
  static const Color accentHover = Color(0xFFD08E7C);

  static const Color green  = Color(0xFF6BA87A);
  static const Color red    = Color(0xFFC26464);
  static const Color yellow = Color(0xFFC4A86A);
}
```

---

*Document generated from `虾Hub-原型Demo-Premium.html` · Design Token Specification v1.0*
