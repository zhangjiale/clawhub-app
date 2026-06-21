# ComponentSpec - 虾Hub 组件标注与交互规范

**版本**: v2.0
**日期**: 2026-06-15
**对应原型**: 虾Hub-原型Demo-V2.html
**对应PRD**: PRD-虾Hub多OpenClaw移动端管理客户端.md v1.1

---

## 目录

1. [Design Tokens（设计令牌）](#1-design-tokens设计令牌)
2. [Page 1: 虾列表（page-home）](#2-page-1-虾列表page-home)
3. [Page 2: 消息（page-messages）](#3-page-2-消息page-messages)
4. [Page 3: 聊天（page-chat）](#4-page-3-聊天page-chat)
5. [Page 4: 虾详情（page-agent-detail）](#5-page-4-虾详情page-agent-detail)
6. [Page 5: 虾编辑（page-agent-edit）](#6-page-5-虾编辑page-agent-edit)
7. [Page 6: 实例管理（page-instances）](#7-page-6-实例管理page-instances)
8. [Page 7: 添加实例（page-add-instance）](#8-page-7-添加实例page-add-instance)
9. [Page 8: 设置（page-settings）](#9-page-8-设置page-settings)
10. [Page 9: 搜索（page-search）](#10-page-9-搜索page-search)
11. [Cross-Cutting 全局交互规范](#11-cross-cutting-全局交互规范)
12. [Edge Cases 与异常状态](#12-edge-cases-与异常状态)

---

## 1. Design Tokens（设计令牌）

### 1.1 Color System（色彩体系）

采用 60-30-10 比例分配：60% 深色冷调背景、30% 表面色（hairline border 分隔）、10% 强调色（宝石蓝 + 紫罗兰）。

| Token | 值 | 用途 |
|---|---|---|
| `--bg` | `#08090D` | 全局最底层背景（冷暗调） |
| `--surface` | `#0E1016` | 卡片/气泡一级表面 |
| `--surface2` | `#15171E` | 二级表面（嵌套卡片、工具卡片） |
| `--surface3` | `#1C1F28` | 三级表面（禁用态、装饰） |
| `--surface-elevated` | `#12141B` | 浮层表面（Toast、Banner） |
| `--border` | `rgba(255,255,255,0.06)` | **V2 新增** hairline 边框色，核心视觉分隔 |
| `--border-accent` | `rgba(79,131,255,0.30)` | **V2 新增** 强调边框（选中态、激活态） |
| `--text-1` | `#EBEFFA` | 主文本（标题、正文） |
| `--text-2` | `rgba(235,239,250,0.55)` | 次级文本（描述、标签） |
| `--text-3` | `rgba(235,239,250,0.30)` | 三级文本（预览、占位） |
| `--text-4` | `rgba(235,239,250,0.14)` | 最弱文本（时间戳、禁用） |
| `--accent` | `#4F83FF` | 品牌强调色（sapphire blue 宝石蓝） |
| `--accent-hover` | `#6B9AFF` | 强调色 hover 态 |
| `--accent-muted` | `rgba(79,131,255,0.10)` | 强调色透明底 |
| `--accent-glow` | `rgba(79,131,255,0.20)` | 强调色发光（按钮阴影） |
| `--accent2` | `#9B7AFF` | **V2 新增** 次级强调色（violet 紫罗兰） |
| `--accent2-muted` | `rgba(155,122,255,0.10)` | 紫罗兰轻量背景 |
| `--gold` | `#E8C574` | **V2 新增** 金色高光（里程碑、成就徽章） |
| `--green` | `#4ADE80` | 语义色：在线/成功 |
| `--green-muted` | `rgba(74,222,128,0.10)` | 绿色透明底 |
| `--red` | `#F87171` | 语义色：错误/删除 |
| `--red-muted` | `rgba(248,113,113,0.08)` | 红色透明底 |
| `--yellow` | `#FBBF24` | 语义色：警告 |

#### Theme Color Map（虾主题色映射）

每只虾根据 `theme` 字段映射到一组 `bg`（头像底色）和 `color`（强调色）。V2 采用冷色调基底、中等饱和度：

| theme | bg | color | 名称 |
|---|---|---|---|
| sapphire | `rgba(79,131,255,0.10)` | `#4F83FF` | 宝蓝（默认） |
| violet | `rgba(155,122,255,0.10)` | `#9B7AFF` | 紫罗兰 |
| cyan | `rgba(34,211,238,0.10)` | `#22D3EE` | 青碧 |
| emerald | `rgba(52,211,153,0.10)` | `#34D399` | 翡翠绿 |
| amber | `rgba(251,191,36,0.10)` | `#FBBF24` | 琥珀 |
| rose | `rgba(251,113,133,0.10)` | `#FB7185` | 玫瑰 |
| teal | `rgba(45,212,191,0.10)` | `#2DD4BF` | 湖蓝 |
| orange | `rgba(251,146,60,0.10)` | `#FB923C` | 暖橙 |
| indigo | `rgba(129,140,248,0.10)` | `#818CF8` | 靛蓝 |
| pink | `rgba(244,114,182,0.10)` | `#F472B6` | 烟粉 |
| lime | `rgba(163,230,53,0.10)` | `#A3E635` | 青柠 |
| slate | `rgba(148,163,184,0.10)` | `#94A3B8` | 石墨 |

### 1.2 Spacing System（间距系统）

基于 4pt 网格，使用 `--s1` 至 `--s8`：

| Token | 值 | 常见用途 |
|---|---|---|
| `--s1` | 2px | 极微间距 |
| `--s2` | 6px | 紧凑间距 |
| `--s3` | 8px | 元素间距 |
| `--s4` | 12px | 标准内边距 |
| `--s5` | 16px | 较大内边距 |
| `--s6` | 16px | 页面水平 padding |
| `--s7` | 24px | Section 间距 |
| `--s8` | 32px | 大区块间距 |

### 1.3 Border Radius（圆角系统）

| Token | 值 | 常见用途 |
|---|---|---|
| `--r-xs` | 4px | hairline 分隔符、微型标签 |
| `--r-sm` | 6px | 小按钮、状态徽章 |
| `--r-md` | 8px | 头像、输入框、次要按钮 |
| `--r-lg` | 10px | 主要卡片（Agent 卡、实例卡） |
| `--r-xl` | 14px | 聊天气泡 |
| `--r-full` | 999px | 胶囊按钮、统计点、badge |

### 1.4 Shadow System（阴影系统）

V2 减少阴影使用（深色背景上阴影几乎不可见），改用 hairline border 和微弱发光：

| Token | 值 | 用途 |
|---|---|---|
| `--shadow-m` | `0 4px 12px rgba(0,0,0,0.25)` | 浮层用 |
| `--shadow-l` | `0 8px 24px rgba(0,0,0,0.30)` | Toast 浮层 |
| `--shadow-glow` | `0 0 20px rgba(79,131,255,0.15)` | **V2 新增** 主按钮蓝色发光 |

注意：V2 移除了 `--shadow-s`（卡片不再用阴影，改用 border）。

### 1.5 Motion System（动效系统）

V2 动效整体更快、更克制，移除弹性缓动：

| Token | 值 | 用途 |
|---|---|---|
| `--ease` | `cubic-bezier(0.16, 1, 0.3, 1)` | 通用缓动（expo out） |
| `--ease-out` | `cubic-bezier(0.0, 0.0, 0.2, 1)` | 减速缓动 |
| `--dur-fast` | 150ms | 按压反馈、hover |
| `--dur-mid` | 250ms | 消息入场、Toast 显隐 |
| `--dur-slow` | 400ms | 页面转场 |

注意：V2 移除了 `--ease-spring`（弹性缓动），传达更克制的工具感。

### 1.6 Typography（字体系统）

| 属性 | 值 |
|---|---|
| font-family | `-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", "PingFang SC", sans-serif` |
| Code font | `"SF Mono", "Fira Code", monospace` |
| Base font-size | 14px |
| Base line-height | 1.45 |
| font-feature-settings | `"ss01", "cv11"` |
| -webkit-font-smoothing | `antialiased` |

#### 字号层级

| 层级 | 字号 | 字重 | 用途 |
|---|---|---|---|
| H1 | 24px | 700 | 页面标题 |
| H2 | 18px | 600 | 详情页名称 |
| Agent 名称 | 15px | 600 | 卡片名称 |
| Body | 14px | 400 | 消息正文、输入框、气泡 |
| Caption | 13px | 500 | 描述、辅助标签 |
| Caption-sm | 12px | 400/500 | 虾描述、时间戳、分组标题 |
| Micro | 11px | 500/600 | 标签、badge、URL |
| Micro-sm | 10px | 500 | 底部导航标签、时间戳 |

### 1.7 Safe Area（安全区域）

| Token | 值 |
|---|---|
| `--safe-bottom` | `env(safe-area-inset-bottom, 0px)` |

所有底部固定元素（bottom nav、chat input）的 `padding-bottom` 必须加上 `var(--safe-bottom)`。

### 1.8 Phone Frame（设备框架）

| 属性 | 值 |
|---|---|
| 宽度 | 393px |
| 高度 | 852px |
| 圆角 | 48px |
| 边框 | `3px solid rgba(255,255,255,0.08)` |
| 背景 | `var(--bg)` |
| Notch 宽 | 126px |
| Notch 高 | 34px |
| Notch 圆角 | `0 0 20px 20px` |
| Status Bar 高 | 54px |

**响应式**: 当视口宽度 <= 420px 时，phone frame 全屏展示（width:100%, height:100%, border-radius:0, border:none, box-shadow:none）。

---

## 2. Page 1: 虾列表（page-home）

### 2.1 Header 区域

**结构**: 两行布局——第一行 `[标题 h1] [搜索按钮] [添加实例按钮]`，第二行 inline 统计指标

| 属性 | 值 |
|---|---|
| padding | `8px var(--s6) 10px` = 8px 16px 10px |
| background | `var(--bg)` |
| z-index | 10 |
| flex-shrink | 0（不压缩） |

**标题 `h1`**:
- font-size: 24px, font-weight: 700
- letter-spacing: -0.5px, line-height: 1.15
- color: `var(--text-1)`

**Header 按钮 `.header-btn`**:
- 尺寸: 36px x 36px
- border-radius: `var(--r-md)` = 8px
- background: `var(--surface)`
- border: `1px solid var(--border)`
- 图标: 18px x 18px, color: `var(--text-2)`
- 布局: flex center
- **Press 态**: transform: scale(0.93), background: `var(--surface3)`
- **Transition**: `all var(--dur-fast) var(--ease)`

**Header Actions 容器**: display: flex, gap: 6px, align-items: center

**搜索按钮**: 图标为放大镜 SVG，onclick 跳转 `page-search`。
**添加实例按钮**: 图标为十字加号，onclick 跳转 `page-instances` 并打开添加实例页。

### 2.2 Inline Stats Row（行内统计栏）

V2 将 3 张大统计卡片替换为行内联排小指标，大幅节省空间。

**容器 `.stats-inline`**:

| 属性 | 值 |
|---|---|
| display | flex |
| align-items | center |
| gap | 10px |
| margin-top | 6px |
| padding | 0 2px |

**统计项 `.stat-item`**:

| 属性 | 值 |
|---|---|
| display | flex |
| align-items | center |
| gap | 4px |
| font-size | 13px |
| color | `var(--text-2)` |
| font-variant-numeric | tabular-nums |

**内部结构**: `[状态点(可选)] [数值] [单位文字]`

| 元素 | 样式 |
|---|---|
| `.stat-val` | color: `var(--text-1)`, font-weight: 600 |
| `.stat-dot` | 5x5px, border-radius: 999px; `.online`: background `var(--green)`, box-shadow `0 0 6px var(--green)`; `.offline`: background `var(--text-4)` |
| `.stat-sep` | color: `var(--text-4)`, font-size: 12px, 分隔符 `·` |

**三个指标**:
1. `[绿点] 2/3` — 活跃实例数
2. `5/8 在线` — 在线虾数
3. `142 消息` — 总消息数

### 2.3 Instance Group Header（实例分组头）

**容器 `.instance-group`**:
- margin-bottom: `var(--s3)` = 8px

**分组头 `.group-header`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| min-height | 44px ← 满足移动端最小触控目标 (Apple HIG 44pt / MD 48dp) |
| padding | `10px var(--s6)` = 10px 16px |
| gap | 6px |
| cursor | pointer |
| user-select | none |
| -webkit-tap-highlight-color | transparent |
| transition | `opacity var(--dur-fast) var(--ease)` |

**Press 态**:
- 整体 **opacity: 0.5**（含状态点、文字、箭头一起变淡）
- chevron 颜色变为 `var(--text-3)`
- 松开后 transition 恢复

```css
.group-header:active {
  opacity: 0.5;
}
.group-header:active .chevron {
  color: var(--text-3);
}
```

**内部结构**: `[状态点] [实例名] [数量] [折叠箭头]`

| 元素 | 样式 |
|---|---|
| `.group-dot` | 6x6px, border-radius: 999px, flex-shrink: 0 |
| `.group-dot.online` | background: `var(--green)`, box-shadow: `0 0 6px var(--green)` |
| `.group-dot.offline` | background: `var(--text-4)` |
| `.group-name` | font-size: 11px, font-weight: 600, color: `var(--text-2)`, letter-spacing: 0.8px, text-transform: uppercase, flex: 1 |
| `.group-count` | font-size: 11px, color: `var(--text-3)`, font-variant-numeric: tabular-nums, margin-right: 2px |
| `.chevron` | 14x14px, color: `var(--text-4)`, transition: transform/color `var(--dur-fast) var(--ease)`, flex-shrink: 0 |
| `.chevron.collapsed` | transform: rotate(-90deg) |

**Collapse/Expand 行为**:
- 点击分组头 -> toggle `.agent-list` 的展开/收起
- 同时 toggle chevron 的 `.collapsed` class
- **动画实现**：使用 `max-height` + `overflow: hidden` + `transition: max-height var(--dur-mid) var(--ease)` 替代原来的 display 切换
  - 展开时：`max-height` 设为足够大的值（如 `1000px`，或动态计算子项总高度）
  - 收起时：`max-height: 0`
  - 避免使用 display:none 切换（无法做过渡动画）

### 2.4 Agent Card（虾卡片）

**列表容器 `.agent-list`**:
- padding: `0 var(--s6)` = 0 16px
- transition: `max-height var(--dur-mid) var(--ease)`, overflow: hidden

**卡片 `.agent-card`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `10px 12px` |
| background | `var(--surface)` |
| border | `1px solid var(--border)` |
| border-radius | `var(--r-lg)` = 10px |
| margin-bottom | 6px |
| cursor | pointer |
| gap | 10px |
| transition | `all var(--dur-fast) var(--ease)` |

**Press 态**:
- transform: scale(0.97)
- background: `var(--surface2)`

**Navigation**: onclick 调用 `openChat(agentId)` 进入 page-chat

**内部结构**: `[头像 36px] [信息区(flex:1) 含 name-row + desc]`

#### 2.4.1 Agent Avatar（虾头像）`.agent-avatar`

| 属性 | 值 |
|---|---|
| 尺寸 | 36px x 36px |
| border-radius | `var(--r-md)` = 8px |
| display | flex, center |
| font-size | 16px（emoji） |
| flex-shrink | 0 |
| background | 根据虾 theme 映射（见 1.1 Theme Color Map） |
| position | relative |

**Status Dot（在线状态点）`.online-pulse`**:
- position: absolute, bottom: -1px, right: -1px
- 尺寸: 10px x 10px
- border-radius: 999px
- border: `2px solid var(--bg)`（与卡片背景融合形成间隔效果）
- `.on`: background `var(--green)`
- `.off`: background `var(--text-4)`

#### 2.4.2 Agent Info（信息区）`.agent-info`

| 属性 | 值 |
|---|---|
| flex | 1 |
| min-width | 0（防溢出） |

**Name Row `.name-row`**: display: flex, align-items: center, justify-content: space-between

| 元素 | 样式 |
|---|---|
| `.agent-name` | font-size: 15px, font-weight: 600, color: `var(--text-1)`, letter-spacing: -0.2px, line-height: 1.3, white-space: nowrap, overflow: hidden, text-overflow: ellipsis |
| `.agent-time` | font-size: 10px, color: `var(--text-3)`, font-variant-numeric: tabular-nums, flex-shrink: 0, margin-left: 8px |
| `.agent-desc` | font-size: 12px, color: `var(--text-3)`, line-height: 1.4, white-space: nowrap, overflow: hidden, text-overflow: ellipsis, margin-top: 2px |

### 2.5 Bottom Navigation（底部导航栏）

**容器 `.bottom-nav`**:

| 属性 | 值 |
|---|---|
| position | absolute, bottom: 0, left: 0, right: 0 |
| height | 56px |
| background | `rgba(8,9,13,0.92)` |
| backdrop-filter | `blur(20px) saturate(1.3)` |
| display | flex, align-items: center, justify-content: space-around |
| padding-bottom | `var(--safe-bottom)` |
| z-index | 10 |
| border-top | `1px solid var(--border)` |
| flex-shrink | 0 |

**导航项 `.nav-item`**:

| 属性 | 值 |
|---|---|
| flex | 1 |
| display | flex, flex-direction: column, align-items: center |
| gap | 2px |
| cursor | pointer |
| padding | 6px 0 |
| position | relative |
| transition | `all var(--dur-fast) var(--ease)` |
| -webkit-tap-highlight-color | transparent |

| 元素 | Inactive | Active |
|---|---|---|
| SVG 图标 (20x20px, stroke-width: 1.8) | stroke: `var(--text-3)` | stroke: `var(--accent)` |
| 标签文字 | font-size: 10px, color: `var(--text-3)`, font-weight: 500, letter-spacing: 0.2px | color: `var(--accent)`, font-weight: 600 |

**Active 指示器**: `::after` 伪元素，position: absolute, top: 0, left: 50%, transform: translateX(-50%), width: 20px, height: 2px, background: `var(--accent)`, border-radius: `0 0 2px 2px`（2px 底部线条指示器）

**Press 态**: opacity: 0.6

**Nav Badge（角标）**: position: absolute, top: 2px, right: calc(50% - 18px), min-width: 14px, height: 14px, padding: 0 4px, border-radius: 999px, background: `var(--red)`, color: #fff, font-size: 9px, font-weight: 700

**三个 Tab**:
1. `虾列表` — Layers icon — data-page: `page-home`
2. `消息` — Message icon — data-page: `page-messages`
3. `实例` — Server icon — data-page: `page-instances`

**行为**: 点击触发 `navTo(pageId)` -> 更新 `lastMainTab` + `showPage` + `updateNavActive`。所有主 Tab 页的 bottom nav 同步高亮状态。

### 2.6 Scroll Content（滚动内容区）

**容器 `.scroll-content`**:

| 属性 | 值 |
|---|---|
| flex | 1 |
| overflow-y | auto |
| -webkit-overflow-scrolling | touch |
| padding-bottom | `calc(64px + var(--safe-bottom))`（为 bottom nav 留空间） |
| scrollbar | 隐藏（`::-webkit-scrollbar { display: none }`） |

### 2.7 入场动画（Staggered Animation）

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

- `@keyframes slideUp`: from `translateY(16px), opacity:0` to `translateY(0), opacity:1`
- 每个 instance-group 使用 `.animate-in`
- group 内的 agent-card 使用递增 delay

---

## 3. Page 2: 消息（page-messages）

### 3.1 Header 区域

与 page-home header 结构一致（使用 `.page-header`），区别：
- 标题文字: "消息"
- 无右侧操作按钮

### 3.2 Message List Item（消息列表项）

**列表容器 `.msg-list`**:
- padding: 0（列表项自身包含 padding）

**消息项 `.msg-item`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `10px var(--s6)` = 10px 16px |
| gap | 10px |
| cursor | pointer |
| border-bottom | `1px solid var(--border)`（hairline 分隔） |
| transition | `all var(--dur-fast) var(--ease)` |

**Press 态**: background 变为 `var(--surface)`

**Navigation**: onclick 调用 `openChat(agentId)` 进入 page-chat

**内部结构**: `[头像 36px] [信息区(flex:1)] [未读 badge]`

#### 3.2.1 Message Avatar（消息头像）

| 属性 | 值 |
|---|---|
| 尺寸 | 36px x 36px |
| font-size | 16px |
| border-radius | `var(--r-md)` = 8px |
| background | 根据虾 theme 映射 |
| flex-shrink | 0 |
| position | relative |

**Status Dot**: position: absolute, bottom: -1px, right: -1px, 8x8px, border-radius: 999px, border: `1.5px solid var(--bg)`; 在线: `var(--green)` / 离线: `var(--text-4)`

#### 3.2.2 Message Info（信息区）`.msg-item-info`

| 属性 | 值 |
|---|---|
| flex | 1 |
| min-width | 0 |

**Top Row `.msg-item-top`**:
- display: flex, align-items: center, justify-content: space-between

| 元素 | 样式 |
|---|---|
| `.msg-item-name` | font-size: 14px, font-weight: 600, color: `var(--text-1)`, white-space: nowrap, overflow: hidden, text-overflow: ellipsis |
| `.msg-item-time` | font-size: 10px, color: `var(--text-4)`, flex-shrink: 0, font-variant-numeric: tabular-nums, margin-left: 8px |

**Preview Row `.msg-item-preview`**:
- font-size: 12px, color: `var(--text-3)`, line-height: 1.4
- white-space: nowrap, overflow: hidden, text-overflow: ellipsis
- margin-top: 2px

**截断规则**: 原始文本去除 Markdown 标记（`*`, `` ` ``, `#`, `[`, `]`），换行替换为空格，超过 **38 字符** 截断并追加 `...`

**"你:"前缀**: 当最后一条消息 type 为 user 时，preview 前插入 `<span class="you">你：</span>`，`.you` 样式为 `color: var(--text-2)`

**空消息**: 显示 "暂无消息"

#### 3.2.3 Unread Badge（未读角标）`.msg-badge`

| 属性 | 值 |
|---|---|
| min-width | 16px |
| height | 16px |
| border-radius | `var(--r-full)` = 999px |
| background | `var(--red)` |
| color | `#fff` |
| font-size | 10px |
| font-weight | 600 |
| display | flex, center |
| flex-shrink | 0 |
| padding | `0 5px` |

**条件渲染**: unread > 0 时显示，否则不渲染。

### 3.3 排序逻辑

消息列表按 `recentAgents` 数组顺序排列（最近交互的虾排最前）。不在 recentAgents 中的虾排在最后。

### 3.4 Bottom Navigation

与 page-home 相同结构，Active tab 为 "消息"。

---

## 4. Page 3: 聊天（page-chat）

### 4.1 Chat Header（聊天头部）

**容器 `.chat-header`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `6px var(--s5)` = 6px 16px |
| background | `var(--bg)` |
| gap | 8px |
| height | 52px |
| border-bottom | `1px solid var(--border)` |
| flex-shrink | 0 |
| position | relative, z-index: 10 |

**内部结构**: `[返回按钮 32px] [头像 32px] [信息区(flex:1)] [更多按钮]`

#### 4.1.1 Back Button（返回按钮）`.back-btn`

| 属性 | 值 |
|---|---|
| 尺寸 | 32px x 32px |
| border-radius | `var(--r-md)` = 8px |
| background | transparent |
| 图标 | 20x20px, 左箭头 chevron, stroke-width: 2 |
| color | `var(--text-2)` |
| flex-shrink | 0 |

**Press 态**: background `var(--surface2)`, transform: scale(0.93)

**行为**: `goBack()` — 智能返回到来源 Tab

#### 4.1.2 Chat Avatar（聊天头像）

| 属性 | 值 |
|---|---|
| 尺寸 | 32px x 32px |
| font-size | 14px |
| border-radius | 8px |
| background | 根据虾 theme 映射 |

**注意**: 聊天头部头像尺寸(32px)比其他场景(36px)更小。

#### 4.1.3 Chat Header Info（头部信息区）

| 属性 | 值 |
|---|---|
| flex | 1 |
| min-width | 0 |
| **点击行为** | onclick 跳转 `page-agent-detail` |

| 元素 | 样式 |
|---|---|
| `.chat-header-name` | font-size: 15px, font-weight: 600, letter-spacing: -0.2px, display: flex, align-items: center, gap: 6px |
| name 内 mini-dot | 6x6px, border-radius: 999px, 在线: `var(--green)` + box-shadow `0 0 5px var(--green)` / 离线: `var(--text-4)` |
| `.chat-header-sub` | font-size: 11px, color: `var(--text-3)`, margin-top: 1px |

#### 4.1.4 More Button（更多按钮）

复用 `.header-btn` 样式（32x32px），图标为三点竖排（more-vertical, 16x16px）。
onclick 跳转 `page-agent-detail`。

### 4.2 Chat Messages（消息流区域）

**容器 `.chat-messages`**:

| 属性 | 值 |
|---|---|
| flex | 1 |
| overflow-y | auto |
| padding | `10px var(--s6)` = 10px 16px |
| display | flex, flex-direction: column |
| gap | 8px |
| -webkit-overflow-scrolling | touch |
| scrollbar | 隐藏 |

#### 4.2.1 Date Separator（日期分隔线）`.date-separator`

| 属性 | 值 |
|---|---|
| text-align | center |
| font-size | 11px |
| color | `var(--text-4)` |
| padding | `var(--s3) 0` = 8px 0 |
| font-weight | 500 |
| letter-spacing | 0.5px |

#### 4.2.2 Message Bubble（消息气泡）`.msg`

**通用属性**:

| 属性 | 值 |
|---|---|
| max-width | 78% |
| padding | `9px 13px` |
| border-radius | `var(--r-xl)` = 14px |
| font-size | 14px |
| line-height | 1.5 |
| word-break | break-word |
| 入场动画 | `msgIn var(--dur-mid) var(--ease) both` |

`@keyframes msgIn`: from `opacity:0, translateY(10px)` to `opacity:1, translateY(0)`

**User Message（用户消息）`.msg.user`**:

| 属性 | 值 |
|---|---|
| align-self | flex-end |
| background | `var(--accent)` = `#4F83FF` |
| color | `#fff` |
| border-bottom-right-radius | 4px（右下角收尖） |

**Agent Message（虾消息）`.msg.agent`**:

| 属性 | 值 |
|---|---|
| align-self | flex-start |
| background | `var(--surface2)` |
| color | `var(--text-1)` |
| border | `1px solid var(--border)` |
| border-bottom-left-radius | 4px（左下角收尖） |

**Agent 消息内的 Markdown 渲染**:

| 元素 | 样式 |
|---|---|
| `code`（行内） | background: `rgba(255,255,255,0.06)`, padding: `1px 5px`, border-radius: 3px, font-family: `"SF Mono", "Fira Code", monospace`, font-size: 12px |
| `pre`（代码块） | background: `var(--surface2)`, padding: `var(--s4)` = 12px, border-radius: `var(--r-md)`, margin: `var(--s2) 0` = 6px 0, overflow-x: auto, font-size: 12px, line-height: 1.5 |
| `strong` | `<strong>` 标签，bold |
| `em` | `<em>` 标签，italic |

#### 4.2.3 Tool Card（工具调用卡片）

**位置**: 独立元素（`align-self: flex-start`），不在气泡内部

**容器 `.tool-card`**:

| 属性 | 值 |
|---|---|
| background | `var(--surface)` |
| border | `1px solid var(--border)` |
| border-left | `2px solid var(--accent2)`（紫罗兰色） |
| border-radius | `var(--r-md)` = 8px |
| padding | `8px 12px` |
| font-size | 12px |
| color | `var(--text-2)` |
| max-width | 78% |

| 元素 | 样式 |
|---|---|
| `.tool-name` | font-weight: 600, color: `var(--accent2)`（紫罗兰） |
| `.tool-status` | margin-top: 3px |
| `.tool-status.done` | color: `var(--green)` |

#### 4.2.4 Message Time（消息时间戳）`.msg-time`

| 属性 | 值 |
|---|---|
| font-size | 10px |
| color | `var(--text-4)` |
| margin-top | 3px |
| font-variant-numeric | tabular-nums |

- 用户消息时间: text-align: right
- Agent 消息时间: text-align: left

**注意**: 时间戳是独立于气泡之外的元素，紧跟在气泡后面。

### 4.3 Typing Indicator（输入中指示器）

**容器 `.typing-indicator`**:

| 属性 | 值 |
|---|---|
| align-self | flex-start |
| padding | `12px 16px` |
| background | `var(--surface2)` |
| border | `1px solid var(--border)` |
| border-radius | `var(--r-xl)` = 14px |
| border-bottom-left-radius | 4px |
| display | flex, gap: 4px, align-items: center |

**Typing Dot（跳动圆点）`.typing-dot`**:

| 属性 | 值 |
|---|---|
| 尺寸 | 6px x 6px |
| border-radius | 999px |
| background | `var(--accent2)`（紫罗兰色） |
| 动画 | `typingBounce 800ms ease infinite` |

**动画定义**:
```css
@keyframes typingBounce {
  0%, 80%, 100% { transform: translateY(0); }
  40% { transform: translateY(-6px); }
}
```

**三个圆点的延迟**:
- 第 1 个: animation-delay: 0s
- 第 2 个: animation-delay: 0.15s
- 第 3 个: animation-delay: 0.3s

**生命周期**: 用户发送消息后插入 DOM，Agent 回复后 remove()。模拟延迟 1200ms + random(0~800ms)。

### 4.4 Quick Commands（快捷指令栏）

**容器 `.quick-cmds`**:

| 属性 | 值 |
|---|---|
| display | flex |
| gap | 6px |
| padding | `6px var(--s6)` = 6px 16px |
| overflow-x | auto |
| flex-shrink | 0 |
| scrollbar-width | none |
| scrollbar | 隐藏 |

**指令 Pill `.quick-cmd`**:

| 属性 | 值 |
|---|---|
| white-space | nowrap |
| padding | `5px 12px` |
| border-radius | `var(--r-full)` = 999px（全圆角胶囊） |
| font-size | 12px |
| background | `var(--accent-muted)` |
| color | `var(--accent)` |
| border | `1px solid var(--border-accent)` |
| cursor | pointer |
| flex-shrink | 0 |
| transition | `all var(--dur-fast) var(--ease)` |

**Press 态**: transform: scale(0.93), background `rgba(79,131,255,0.18)`

**行为**: 点击 -> 指令文本填入输入框 -> 自动触发发送（`sendQuickCmd`）

### 4.5 Chat Input Area（输入区域）

**容器 `.input-bar`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: flex-end |
| padding | `6px var(--s5) calc(6px + var(--safe-bottom))` = 6px 16px |
| gap | 6px |
| border-top | `1px solid var(--border)` |
| flex-shrink | 0 |
| background | `var(--bg)` |

**内部结构**:
```
[快捷指令栏（上方横向滚动）]
[输入行: Textarea + Send按钮]
```

#### 4.5.1 Input Row（输入行）`.input-bar`

| 属性 | 值 |
|---|---|
| display | flex, align-items: flex-end |
| gap | 6px |

注意：V2 移除了 Plus Button（加号按钮），简化输入栏。

#### 4.5.2 Textarea（文本输入框）`.input-bar textarea`

| 属性 | 值 |
|---|---|
| flex | 1 |
| background | `var(--surface2)` |
| border | `1px solid var(--border)` |
| border-radius | `var(--r-xl)` = 14px |
| color | `var(--text-1)` |
| padding | `9px 14px` |
| font-size | 14px |
| outline | none |
| resize | none |
| max-height | 100px |
| line-height | 1.4 |
| font-family | inherit |
| transition | `border-color var(--dur-fast) var(--ease)` |

**Focus 态**: border-color 变为 `var(--accent)`

**Placeholder**: color `var(--text-4)`, 文字 "发消息..."

**Auto-resize 行为**: `oninput` 时 `style.height = auto` -> `style.height = min(scrollHeight, 100px)`

**Enter 键行为**: Enter 发送消息，Shift+Enter 换行

#### 4.5.3 Send Button（发送按钮）`.send-btn`

| 属性 | 值 |
|---|---|
| 尺寸 | 36px x 36px |
| border-radius | 999px（全圆） |
| background | `var(--accent)` |
| color | `#fff` |
| 图标 | 18x18px 纸飞机 fill |
| flex-shrink | 0 |
| box-shadow | `var(--shadow-glow)` |

**Press 态**: transform: scale(0.88), filter: brightness(0.88)

---

## 5. Page 4: 虾详情（page-agent-detail）

### 5.1 Header 区域

**容器**: 复用 `.chat-header` 样式

**结构**: `[返回按钮 32px] [标题"虾详情"] [编辑按钮]`
- 返回目标: 上一页（`goBackFromSub()`）

**编辑按钮**: 复用 `.header-btn`（32x32px），图标为编辑铅笔（16x16px），onclick 跳转 `page-agent-edit`。

### 5.2 Hero Section（个人信息区）

**容器 `.detail-hero`**:
- display: flex, flex-direction: column, align-items: center
- padding: `16px var(--s5) 12px` = 16px 16px 12px

**内部结构** (从上到下居中排列):

#### 5.2.1 Detail Avatar（详情头像）

| 属性 | 值 |
|---|---|
| 尺寸 | 56px x 56px |
| font-size | 24px |
| border-radius | `var(--r-lg)` = 10px |
| background | 根据虾 theme 映射 |
| margin-bottom | 8px |
| position | relative |

**Status Dot**: position: absolute, bottom: -1px, right: -1px, 12x12px, border-radius: 999px, border: `2px solid var(--bg)`; 在线: `var(--green)` / 离线: `var(--text-4)`

#### 5.2.2 Detail Name（详情名称）

| 属性 | 值 |
|---|---|
| font-size | 18px |
| font-weight | 700 |
| color | `var(--text-1)` |

#### 5.2.3 Detail Description（详情描述）

| 属性 | 值 |
|---|---|
| font-size | 13px |
| color | `var(--text-3)` |
| margin-top | 2px |

#### 5.2.4 Detail Instance（详情实例信息）

| 属性 | 值 |
|---|---|
| font-size | 11px |
| color | `var(--text-4)` |
| margin-top | 4px |
| display | flex, align-items: center, gap: 4px |

**内容**: `[状态点 5x5px] 实例名 · 在线/离线`

### 5.3 Tabs（标签切换）

**容器 `.detail-tabs`**:

| 属性 | 值 |
|---|---|
| display | flex |
| padding | `0 var(--s5)` = 0 16px |
| border-bottom | `1px solid var(--border)` |
| flex-shrink | 0 |

**标签项 `.detail-tab`**:

| 属性 | 值 |
|---|---|
| flex | 1 |
| text-align | center |
| padding | 8px 0 |
| font-size | 13px |
| font-weight | 500 |
| color | `var(--text-3)` |
| cursor | pointer |
| position | relative |
| transition | `color var(--dur-fast) var(--ease)` |

**Active 态** `.detail-tab.active`:
- color: `var(--accent)`, font-weight: 600
- `::after`: position: absolute, bottom: -1px, left: 30%, right: 30%, height: 2px, background: `var(--accent)`, border-radius: 1px

**Press 态**: opacity: 0.6

**两个 Tab**:
1. "成长面板" — 显示统计 + 时间线 + 操作按钮
2. "成就" — 显示成就列表

**Tab Content `.detail-tab-content`**: display: none 默认; `.active` 时 display: block/flex

### 5.4 Stats Grid（数据网格）— 成长面板 Tab

**容器 `.stats-grid`**:

| 属性 | 值 |
|---|---|
| display | grid |
| grid-template-columns | repeat(3, 1fr) |
| gap | 6px |
| padding | `10px var(--s5)` = 10px 16px |

**数据卡片 `.stat-card`** (共 6 张，3列 x 2行):

| 属性 | 值 |
|---|---|
| background | `var(--surface)` |
| border | `1px solid var(--border)` |
| border-radius | `var(--r-md)` = 8px |
| padding | `10px 6px` |
| text-align | center |

| 元素 | 样式 |
|---|---|
| `.stat-value` | font-size: 18px, font-weight: 700, color: `var(--text-1)`, font-variant-numeric: tabular-nums |
| `.stat-label` | font-size: 10px, color: `var(--text-3)`, margin-top: 2px |

**6 个数据卡片内容**:
1. 对话（dialogs 数）
2. 消息（messages 数）
3. 工具调用（toolCalls 数）
4. 活跃天数（days 数）
5. 连续活跃（streak 数）
6. 初次对话（firstDay 取 MM-DD 部分，字号可缩为 13px）

### 5.5 Timeline（近期活动时间线）— 成长面板 Tab

**Section Divider `.section-divider`**:
- font-size: 11px, font-weight: 600, color: `var(--text-3)`
- text-transform: uppercase, letter-spacing: 0.8px
- padding: `12px var(--s5) 6px`

**时间线容器 `.timeline`**:
- padding: `8px var(--s5)` = 8px 16px

**时间线项 `.timeline-item`**:

| 属性 | 值 |
|---|---|
| display | flex |
| gap | 10px |
| padding | 6px 0 |
| font-size | 12px |

| 元素 | 样式 |
|---|---|
| `.timeline-date` | color: `var(--text-4)`, width: 48px, flex-shrink: 0, font-variant-numeric: tabular-nums |
| `.timeline-text` | color: `var(--text-2)`, line-height: 1.5 |

### 5.6 Achievement List（成就列表）— 成就 Tab

**容器 `.achievement-list`**:
- padding: `8px var(--s5)` = 8px 16px

**成就项 `.achievement-item`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| gap | 10px |
| padding | 8px 0 |
| border-bottom | `1px solid var(--border)` |

**Locked 态** `.achievement-item.locked`:
- 图标: background `var(--surface3)`, opacity: 0.4
- 名称: color `var(--text-3)`

**Unlocked 态** `.achievement-item.unlocked`:
- 图标: background `var(--accent2-muted)`, border: `1px solid rgba(155,122,255,0.25)`

#### 5.6.1 Achievement Icon（成就图标）`.achievement-icon`

| 属性 | 值 |
|---|---|
| 尺寸 | 32px x 32px |
| border-radius | `var(--r-md)` = 8px |
| display | flex, center |
| font-size | 16px |
| flex-shrink | 0 |

#### 5.6.2 Achievement Info（成就信息）`.achievement-info`

| 元素 | 样式 |
|---|---|
| `.achievement-name` | font-size: 13px, font-weight: 600, color: `var(--text-1)` |
| `.achievement-desc` | font-size: 11px, color: `var(--text-3)`, margin-top: 1px |

### 5.7 Detail Actions（操作按钮）— 成长面板 Tab

**容器 `.detail-actions`**:
- padding: `12px var(--s5)` = 12px 16px
- display: flex, flex-direction: column, gap: 6px

**按钮**:
1. "进入对话" — 复用 `.secondary-btn`，width: 100%，onclick 跳转 `page-chat`
2. "清除本地缓存" — 复用 `.secondary-btn`，color: `var(--red)`, border-color: `rgba(248,113,113,0.2)`，onclick 显示确认对话框

---

## 6. Page 5: 虾编辑（page-agent-edit）

### 6.1 Header 区域

**容器**: 复用 `.chat-header` 样式

**结构**: `[返回按钮 32px] [标题 "编辑虾"] [保存文本按钮]`
- 返回目标: `page-agent-detail`

**保存按钮**: header-actions 内的文本按钮，font-size: 14px, color: `var(--accent)`, font-weight: 600, cursor: pointer

### 6.2 Avatar Editor（头像编辑器）

**容器 `.edit-avatar-area`**:
- display: flex, flex-direction: column, align-items: center
- padding: `16px var(--s5) 12px` = 16px 16px 12px
- gap: 6px

**Edit Avatar `.edit-avatar`**:

| 属性 | 值 |
|---|---|
| 尺寸 | 64px x 64px |
| border-radius | `var(--r-lg)` = 10px |
| display | flex, center |
| font-size | 28px |
| cursor | pointer |
| background | 根据虾 theme 映射 |
| transition | `all var(--dur-fast) var(--ease)` |

**Press 态**: transform: scale(0.95)

**点击行为**: 显示选择头像选项（拍照或从相册选择）

**Edit Avatar Hint `.edit-avatar-hint`**: font-size: 11px, color: `var(--text-4)`, 文字 "点击更换头像"

### 6.3 Nickname Input（昵称输入）

**容器**: 复用 `.form-group` 样式
- padding: `0 var(--s5)`, margin-bottom: 14px

**Form Label**: font-size: 12px, color: `var(--text-2)`, margin-bottom: 5px, font-weight: 500

**Form Input `.form-input`**:

| 属性 | 值 |
|---|---|
| width | 100% |
| background | `var(--surface2)` |
| border | `1px solid var(--border)` |
| border-radius | `var(--r-md)` = 8px |
| padding | `10px 12px` |
| font-size | 14px |
| color | `var(--text-1)` |
| outline | none |
| font-family | inherit |
| transition | `border-color var(--dur-fast) var(--ease)` |

**Focus 态**: border-color 变为 `var(--accent)`
**Placeholder**: color `var(--text-4)`, 文字 "给虾起个名字"
**Form Hint**: font-size: 11px, color: `var(--text-4)`, margin-top: 4px, 文字 "最多 20 个字符，仅本地显示"

### 6.4 Color Picker（主题色选择器）

**Section Divider `.section-divider`**: font-size: 11px, font-weight: 600, color: `var(--text-3)`, text-transform: uppercase, letter-spacing: 0.8px, padding: `12px var(--s5) 6px`

**容器 `.color-picker`**:

| 属性 | 值 |
|---|---|
| display | grid |
| grid-template-columns | repeat(6, 1fr) |
| gap | 8px |
| padding | `4px var(--s5)` = 4px 16px |

**颜色块 `.color-swatch`**:

| 属性 | 值 |
|---|---|
| width | 100% |
| aspect-ratio | 1 |
| max-width | 40px |
| margin | 0 auto |
| border-radius | `var(--r-md)` = 8px |
| cursor | pointer |
| border | `2px solid transparent` |
| transition | `all var(--dur-fast) var(--ease)` |

**Press 态**: transform: scale(0.9)

**Selected 态** `.color-swatch.selected`:
- border-color: `#fff`
- box-shadow: `0 0 0 2px var(--accent)`

**行为**: 点击切换选中状态（单选），同时更新 avatar 的 background 预览。

**12 种颜色**: sapphire、violet、cyan、emerald、amber、rose、teal、orange、indigo、pink、lime、slate（详见 1.1 Theme Color Map）。

### 6.5 Command List（快捷指令列表）

**Section Divider**: "快捷指令"

**容器 `.cmd-list`**:
- padding: `0 var(--s5)` = 0 16px

**指令项 `.cmd-item`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `7px 10px` |
| background | `var(--surface)` |
| border | `1px solid var(--border)` |
| border-radius | `var(--r-md)` = 8px |
| margin-bottom | 5px |
| gap | 8px |

**内部结构**: `[指令文本] [名称(margin-left:auto)] [删除按钮]`

| 元素 | 样式 |
|---|---|
| `.cmd-text` | font-size: 13px, color: `var(--accent)`, font-family: `"SF Mono", monospace` |
| `.cmd-name` | font-size: 12px, color: `var(--text-3)`, margin-left: auto |
| `.cmd-del` | 18x18px, display: flex, center, color: `var(--text-4)`, cursor: pointer, font-size: 12px, flex-shrink: 0 |

**Delete Press 态**: color `var(--red)`

**Add Command Button `.cmd-add`**:
- padding: 7px, border: `1px dashed var(--border)`, border-radius: `var(--r-md)`, text-align: center
- font-size: 12px, color: `var(--text-4)`, cursor: pointer
- margin: `4px var(--s5) 0`
- **Press 态**: border-color `var(--accent)`, color `var(--accent)`
- **行为**: 追加一条空指令，prompt 输入指令文本和名称

---

## 7. Page 6: 实例管理（page-instances）

### 7.1 Header 区域

**结构**: `[标题 "实例"] [设置按钮]`（主 Tab 页，无返回按钮）
- 标题: 24px, font-weight: 700
- 设置按钮: 齿轮图标，onclick 跳转 `page-settings`

### 7.2 Instance Card（实例卡片）

**列表容器**: scroll-content，padding-top: 4px

**卡片 `.inst-card`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `12px 14px` |
| background | `var(--surface)` |
| border | `1px solid var(--border)` |
| border-radius | `var(--r-lg)` = 10px |
| margin | `0 var(--s6) 8px` = 0 16px 8px |
| gap | 10px |
| cursor | pointer |
| transition | `all var(--dur-fast) var(--ease)` |

**Press 态**: transform: scale(0.97), background: `var(--surface2)`

**内部结构**: `[图标 36px] [信息区(flex:1)]`

#### 7.2.1 Instance Icon（实例图标）`.inst-icon`

| 属性 | 值 |
|---|---|
| 尺寸 | 36px x 36px |
| border-radius | `var(--r-md)` = 8px |
| background | `var(--surface3)` |
| display | flex, center |
| flex-shrink | 0 |
| 图标 | 20x20px SVG, stroke: `var(--text-2)`, fill: none, stroke-width: 1.5 |

#### 7.2.2 Instance Info（实例信息）`.inst-info`

| 属性 | 值 |
|---|---|
| flex | 1 |
| min-width | 0 |

| 元素 | 样式 |
|---|---|
| `.inst-name-row` | display: flex, align-items: center, justify-content: space-between |
| `.inst-name` | font-size: 14px, font-weight: 600, color: `var(--text-1)` |
| `.inst-status` | font-size: 11px, font-weight: 500, padding: `2px 8px`, border-radius: 999px |
| `.inst-status.online` | background: `var(--green-muted)`, color: `var(--green)` |
| `.inst-status.offline` | background: `rgba(255,255,255,0.04)`, color: `var(--text-4)` |
| `.inst-url` | font-size: 11px, color: `var(--text-3)`, font-family: `"SF Mono", monospace`, margin-top: 2px, white-space: nowrap, overflow: hidden, text-overflow: ellipsis |
| `.inst-meta` | font-size: 11px, color: `var(--text-3)`, margin-top: 2px |

**inst-meta 内容**: `{count} 只虾 · 延迟 {ms}ms` 或 `{count} 只虾 · 最后在线: {time}`

### 7.3 Add Instance Button（添加实例按钮）`.add-inst-btn`

| 属性 | 值 |
|---|---|
| margin | `8px var(--s6) 16px` = 8px 16px 16px |
| padding | 10px |
| border | `1px dashed var(--border)` |
| border-radius | `var(--r-lg)` = 10px |
| text-align | center |
| font-size | 13px |
| color | `var(--text-3)` |
| cursor | pointer |
| transition | `all var(--dur-fast) var(--ease)` |

**Press 态**: border-color `var(--accent)`, color `var(--accent)`, background `var(--accent-muted)`

**内容**: "+ 添加新实例"

**行为**: onclick 跳转 `page-add-instance`

### 7.4 Bottom Navigation

与 page-home 相同结构，Active tab 为 "实例"。

---

## 8. Page 7: 添加实例（page-add-instance）

### 8.1 Header 区域

**容器**: 复用 `.chat-header` 样式

**结构**: `[返回按钮 32px] [标题 "添加实例" + 副标题 "连接 OpenClaw Gateway"]`
- 返回目标: `page-instances`

### 8.2 Tab Switcher（方法切换器）

**容器 `.filter-tabs`**:

| 属性 | 值 |
|---|---|
| display | flex |
| padding | `4px var(--s5) 8px` = 4px 16px 8px |
| gap | 6px |
| flex-shrink | 0 |

**Tab Item `.filter-tab`**:

| 属性 | 值 |
|---|---|
| padding | 4px 12px |
| border-radius | `var(--r-full)` = 999px |
| font-size | 12px |
| color | `var(--text-3)` |
| cursor | pointer |
| border | `1px solid transparent` |
| transition | `all var(--dur-fast) var(--ease)` |

**Active 态** `.filter-tab.active`:
- background: `var(--accent-muted)`
- color: `var(--accent)`
- border-color: `var(--border-accent)`

**Press 态**: transform: scale(0.95)

**两个 Tab**:
1. "手动添加" — 控制 `addMethodManual` 显示
2. "扫码添加" — 控制 `addMethodScan` 显示

**切换行为**: toggle active class，切换对应内容 div 的 display

### 8.3 Manual Tab（手动添加标签页）

**Form Group `.form-group`**:
- padding: `0 var(--s5)`, margin-bottom: 14px

**Form Label `.form-label`**:

| 属性 | 值 |
|---|---|
| font-size | 12px |
| font-weight | 500 |
| color | `var(--text-2)` |
| margin-bottom | 5px |
| display | block |

**Form Input `.form-input`**:

| 属性 | 值 |
|---|---|
| width | 100% |
| background | `var(--surface2)` |
| border | `1px solid var(--border)` |
| border-radius | `var(--r-md)` = 8px |
| padding | `10px 12px` |
| font-size | 14px |
| color | `var(--text-1)` |
| outline | none |
| font-family | inherit |
| transition | `border-color var(--dur-fast) var(--ease)` |

**Mono 变体** `.form-input.mono`: font-family `"SF Mono", monospace`, font-size: 13px

**Focus 态**: border-color 变为 `var(--accent)`

**Placeholder**: color `var(--text-4)`

**Form Hint `.form-hint`**:
- font-size: 11px, color: `var(--text-4)`, margin-top: 4px
- **Error 变体** `.form-hint.error`: color `var(--red)`

**三个表单字段**:
1. Label: "实例名称", placeholder: "例如：我的 MacBook"
2. Label: "Gateway 地址", placeholder: "ws://192.168.1.100:18789", hint: "以 ws:// 或 wss:// 开头，包含端口号", input class: mono
3. Label: "访问令牌", placeholder: "粘贴 Token...", type: password, hint: "Token 将加密存储在设备安全区域", input class: mono

**Connection Result `.conn-result`**:

| 属性 | 值 |
|---|---|
| margin | `10px var(--s5) 0` |
| padding | `8px 12px` |
| border-radius | `var(--r-md)` = 8px |
| font-size | 12px |
| display | none（默认隐藏） |

**Success 态** `.conn-result.success`: background `var(--green-muted)`, color `var(--green)`, display: block
**Error 态** `.conn-result.error`: background `var(--red-muted)`, color `var(--red)`, display: block

**Primary Button `.primary-btn`**:
- margin: `16px var(--s5) 0`, padding: 12px
- background: `var(--accent)`, color: #fff
- border: none, border-radius: `var(--r-lg)` = 10px
- font-size: 14px, font-weight: 600
- width: calc(100% - 32px), display: block
- box-shadow: `var(--shadow-glow)`
- **Press 态**: transform: scale(0.97), filter: brightness(0.9)
- **Disabled 态**: opacity: 0.4, cursor: default, box-shadow: none
- 文字: "连接测试"

**Secondary Button `.secondary-btn`**:
- margin: `8px var(--s5) 0`, padding: 11px
- background: transparent, color: `var(--accent)`
- border: `1px solid var(--border-accent)`, border-radius: `var(--r-lg)` = 10px
- font-size: 14px, font-weight: 500
- width: calc(100% - 32px), display: block
- **Press 态**: transform: scale(0.97), background `var(--accent-muted)`
- 文字: "添加到列表"（初始 disabled，连接成功后启用）

**Validation 规则**:
- 实例名称不能空
- Gateway URL 必须以 `ws://` 或 `wss://` 开头
- Token 不能空
- 校验失败时显示 `.conn-result.error`

### 8.4 Scan Tab（扫码标签页）

**Camera Mock Area**:
- 180px x 180px, border: `2px dashed var(--border-accent)`, border-radius: `var(--r-lg)`
- background: `var(--surface)`, margin-bottom: 16px
- 内含相机图标 (40px emoji) + 提示文字 "原型演示 摄像头扫码不可用" (12px, `var(--text-3)`)

**说明文字**: font-size: 13px, color: `var(--text-2)`, line-height: 1.5
- 内容: "扫描 OpenClaw 实例生成的配置二维码 自动解析 Gateway 地址和令牌"

**模拟按钮**: 复用 `.secondary-btn`, margin-top: 16px, width: auto, padding: `10px 24px`
- 文字: "模拟扫码"
- 行为: alert + 自动切换到手动 Tab + 填充表单

---

## 9. Page 8: 设置（page-settings）

### 9.1 Header 区域

**容器**: 复用 `.chat-header` 样式

**结构**: `[返回按钮 32px] [标题 "设置"]`
- 返回目标: 上一页（`goBackFromSub()`）

### 9.2 Settings Section（设置分区）

**容器 `.settings-section`**:
- margin-bottom: 20px

**Section Title `.settings-section-title`**:

| 属性 | 值 |
|---|---|
| font-size | 11px |
| font-weight | 600 |
| color | `var(--text-3)` |
| text-transform | uppercase |
| letter-spacing | 0.8px |
| padding | `0 var(--s5) 6px` = 0 16px 6px |

### 9.3 Settings Item（设置行）`.settings-item`

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `11px var(--s5)` = 11px 16px |
| gap | 10px |
| border-bottom | `1px solid var(--border)` |
| cursor | pointer |
| transition | `background var(--dur-fast) var(--ease)` |

**Press 态**: background `var(--surface)`

**内部结构**: `[标签(flex:1)] [值/chevron-right]` 或 `[标签(flex:1)] [Toggle 开关]`

| 元素 | 样式 |
|---|---|
| `.settings-item-label` | flex: 1, font-size: 14px, color: `var(--text-1)` |
| `.settings-item-value` | font-size: 13px, color: `var(--text-3)` |
| `.chevron-right` | 14x14px, color: `var(--text-4)`, flex-shrink: 0 |

### 9.4 Toggle Switch（开关组件）`.toggle`

| 属性 | 值 |
|---|---|
| width | 40px |
| height | 22px |
| border-radius | 11px |
| background | `var(--surface3)`（关闭态） |
| position | relative |
| cursor | pointer |
| flex-shrink | 0 |
| transition | `background var(--dur-fast) var(--ease)` |

**On 态** `.toggle.on`: background `var(--accent)`

**Knob（圆点）**:
- `::after`: position: absolute, top: 2px, left: 2px, width: 18px, height: 18px, border-radius: 999px, background: #fff, box-shadow: `0 1px 3px rgba(0,0,0,0.2)`
- transition: `transform var(--dur-fast) var(--ease)`
- `.toggle.on::after`: transform: `translateX(18px)`

**点击行为**: toggle `on` class

### 9.5 Settings Sections 详情

**Section 1: 通知**

| 项目 | 类型 | 标签 | 值/状态 |
|---|---|---|---|
| 1 | Toggle | 通知总开关 | on |
| 2 | Chevron | 免打扰时段 | 22:00 – 08:00 |
| 3 | Toggle | 任务完成通知 | on |
| 4 | Toggle | 错误告警通知 | on |
| 5 | Toggle | 实例状态变更 | off |

**Section 2: 隐私与安全**

| 项目 | 类型 | 标签 | 值/状态 |
|---|---|---|---|
| 1 | Toggle | 生物识别锁 | off |
| 2 | Chevron | 数据统计 | 仅本地 |

**Section 3: 存储**

| 项目 | 类型 | 标签 | 值/状态 |
|---|---|---|---|
| 1 | Chevron | 本地缓存 | 12.4 MB |
| 2 | Chevron | 清除全部缓存 | label color: `var(--red)` |

**Section 4: 关于**

| 项目 | 类型 | 标签 | 值/状态 |
|---|---|---|---|
| 1 | Static | 版本 | 0.1.0-beta |
| 2 | Chevron | 源代码 | (链接) |
| 3 | Chevron | 检查更新 | (操作) |

### 9.6 Footer（页脚信息）

底部 spacer: height: 24px

---

## 10. Page 9: 搜索（page-search）

### 10.1 Search Bar（搜索栏）

**容器 `.search-bar`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `6px var(--s5)` = 6px 16px |
| gap | 8px |
| flex-shrink | 0 |

**搜索输入框 `.search-bar input`**:

| 属性 | 值 |
|---|---|
| flex | 1 |
| background | `var(--surface2)` |
| border | `1px solid var(--border)` |
| border-radius | `var(--r-full)` = 999px |
| padding | `9px 14px` |
| font-size | 14px |
| color | `var(--text-1)` |
| outline | none |
| font-family | inherit |
| transition | `border-color var(--dur-fast) var(--ease)` |

**Focus 态**: border-color `var(--accent)`
**Placeholder**: color `var(--text-4)`, 文字 "搜索虾、消息、实例..."

**取消按钮 `.search-cancel`**:
- font-size: 14px, color: `var(--accent)`, cursor: pointer, white-space: nowrap, flex-shrink: 0
- **Press 态**: opacity: 0.5
- **行为**: `goBackFromSub()` 返回上一页

### 10.2 Filter Tabs（筛选标签）

**容器 `.filter-tabs`**:

| 属性 | 值 |
|---|---|
| display | flex |
| padding | `4px var(--s5) 8px` = 4px 16px 8px |
| gap | 6px |
| flex-shrink | 0 |

**标签项 `.filter-tab`**:

| 属性 | 值 |
|---|---|
| padding | 4px 12px |
| border-radius | `var(--r-full)` = 999px |
| font-size | 12px |
| color | `var(--text-3)` |
| cursor | pointer |
| border | `1px solid transparent` |
| transition | `all var(--dur-fast) var(--ease)` |

**Active 态** `.filter-tab.active`:
- background: `var(--accent-muted)`
- color: `var(--accent)`
- border-color: `var(--border-accent)`

**Press 态**: transform: scale(0.95)

**四个 Tab**: 全部 / 虾 / 消息 / 实例

### 10.3 Search Results（搜索结果）

**结果项 `.search-result-item`**:

| 属性 | 值 |
|---|---|
| padding | `10px var(--s6)` = 10px 16px |
| cursor | pointer |
| border-bottom | `1px solid var(--border)` |
| transition | `background var(--dur-fast) var(--ease)` |

**Press 态**: background `var(--surface)`

**内部结构**:

| 元素 | 样式 |
|---|---|
| `.search-result-top` | display: flex, align-items: center, gap: 6px, margin-bottom: 3px |
| `.search-result-agent` | font-size: 12px, font-weight: 600, color: `var(--accent)` |
| `.search-result-time` | font-size: 10px, color: `var(--text-4)`, margin-left: auto |
| `.search-result-text` | font-size: 13px, color: `var(--text-2)`, line-height: 1.5 |
| `.search-result-text mark` | background: `rgba(79,131,255,0.25)`, color: `var(--text-1)`, border-radius: 2px, padding: 0 2px |

**Navigation**: onclick 跳转 `page-chat` 并打开对应虾的对话

### 10.4 Empty States（空状态）

**容器 `.empty-state`**:

| 属性 | 值 |
|---|---|
| display | flex, flex-direction: column, align-items: center, justify-content: center |
| padding | 48px 32px |
| text-align | center |

| 元素 | 样式 |
|---|---|
| `.empty-icon` | font-size: 48px, margin-bottom: 12px, opacity: 0.6 |
| `.empty-title` | font-size: 15px, font-weight: 600, color: `var(--text-2)`, margin-bottom: 6px |
| `.empty-desc` | font-size: 12px, color: `var(--text-3)`, line-height: 1.5 |

**初始空状态**: icon "🔍", title "搜索全部虾的对话", desc "输入关键词，在所有对话历史中查找"
**无结果空状态**: icon "🔍", title "没有找到包含「{query}」的消息", desc "换个关键词试试？"

---

## 11. Cross-Cutting 全局交互规范

### 11.1 Page Transition（页面转场）

**实现方式**: 通过 CSS class 切换 + transition

| CSS Class | transform | opacity | pointer-events | 用途 |
|---|---|---|---|---|
| `.page` (默认) | none | 1 | auto | 当前可见页 |
| `.page.hidden` | `translateX(100%)` | 0 | none | 目标页在右侧（正向导航前的隐藏态） |
| `.page.hidden-left` | `translateX(-30%)` | 0 | none | 当前页在左侧（被新页推开） |
| `.page.hidden-right` | `translateX(100%)` | 0 | none | 目标页在右侧 |

**Transition 参数**:
- transform: `var(--dur-slow) var(--ease)` = 400ms（expo-out）
- opacity: `var(--dur-mid) var(--ease)` = 250ms

**页面层级顺序 `pageOrder`**:
```
page-home -> page-messages -> page-instances -> page-chat -> page-search -> page-add-instance -> page-settings -> page-agent-detail -> page-agent-edit
```

**转场逻辑**:
- 目标页 index > 当前页 index: 当前页添加 `hidden-left`（向左推出），目标页变为 `page`（从右侧滑入）
- 目标页 index < 当前页 index: 当前页添加 `hidden`（向右推出），目标页变为 `page`（从左侧滑入）

**will-change**: `transform, opacity`（GPU 加速）

### 11.2 Smart Return（智能返回）

**核心变量**: `lastMainTab` — 记录用户最后所在的主 Tab 页

**逻辑**:
- `navTo(pageId)` 调用时更新 `lastMainTab = pageId`
- 从 chat 页面返回时: `showPage(lastMainTab); updateNavActive(lastMainTab)`
- 确保从消息页进入聊天后返回消息页，从虾列表进入后返回虾列表

**主 Tab 列表**: `['page-home', 'page-messages', 'page-instances']`
- 切换到主 Tab 时同步更新所有 bottom nav 组件的 active 状态

### 11.3 Toast Notification（轻提示）

**容器 `.toast`**:

| 属性 | 值 |
|---|---|
| position | absolute, top: 72px, left: 50% |
| transform | `translateX(-50%) translateY(-20px)`（初始） |
| background | `var(--surface-elevated)` = `#12141B` |
| color | `var(--text-1)` = `#EBEFFA` |
| padding | `var(--s3) var(--s6)` = 8px 16px |
| border-radius | `var(--r-full)` = 999px（全圆角胶囊） |
| font-size | 13px |
| font-weight | 500 |
| z-index | 200 |
| white-space | nowrap |
| box-shadow | `var(--shadow-l)` |
| backdrop-filter | `blur(12px)` |
| pointer-events | none |

**显示态** `.toast.show`:
- opacity: 1
- transform: `translateX(-50%) translateY(0)`

**隐藏态** (默认):
- opacity: 0
- transform: `translateX(-50%) translateY(-20px)`

**Transition**: `all var(--dur-mid) var(--ease)` = 250ms

**Auto-dismiss**: 2500ms 后自动移除 `.show` class
**Queue 机制**: 新 Toast 清除旧 timer，确保不冲突

### 11.4 Connection Banner（连接状态横幅）

**容器 `.conn-banner`**:

| 属性 | 值 |
|---|---|
| padding | `6px var(--s6)` = 6px 16px |
| font-size | 12px |
| font-weight | 500 |
| text-align | center |
| flex-shrink | 0 |

**类型**:
| class | background | color |
|---|---|---|
| `.warning` | `rgba(251,191,36,0.08)` | `var(--yellow)` |
| `.info` | `var(--accent-muted)` | `var(--accent)` |

### 11.5 Touch Swipe Gesture（触摸滑动手势）

**绑定范围**: `page-chat` 元素

**TouchStart**: 记录 `touchStartX = e.touches[0].clientX`
**TouchEnd**: 计算 `diff = e.changedTouches[0].clientX - touchStartX`

**触发条件**:
- `diff > 80px`（向右滑动超过 80px）
- `touchStartX < 40px`（从左边缘 40px 内开始）

**触发行为**: `showPage(lastMainTab); updateNavActive(lastMainTab)` — 与 back button 行为一致

**Event options**: `{passive: true}`（不阻止默认行为）

### 11.6 Empty State（空状态）

**容器 `.empty-state`**:

| 属性 | 值 |
|---|---|
| display | flex, flex-direction: column, align-items: center, justify-content: center |
| padding | 48px 32px |
| color | `var(--text-4)` |

| 元素 | 样式 |
|---|---|
| `.empty-icon` | font-size: 48px, margin-bottom: 12px, opacity: 0.6 |
| `.empty-title` | font-size: 15px, font-weight: 600, color: `var(--text-2)`, margin-bottom: 6px |
| `.empty-desc` | font-size: 12px, color: `var(--text-3)`, text-align: center, line-height: 1.5 |

**虾列表空状态**: emoji "🦐", title "还没有虾", desc "添加一个 OpenClaw 实例开始养虾之旅"

---

## 12. Edge Cases 与异常状态

### 12.1 Agent Card 文字溢出

- `.agent-desc`: 单行截断，`text-overflow: ellipsis`
- `.agent-name`: 不截断，允许换行（line-height: 1.3）

### 12.2 Message Preview 截断

- 消息预览去除所有 Markdown 标记后截断至 38 字符
- 换行符替换为空格
- 截断后追加 `...`

### 12.3 离线虾处理

- 头像 status-dot 显示灰色 `var(--text-4)`
- 实例分组头 dot 无 box-shadow
- 聊天页发送消息时检测 online 状态，离线时显示 Toast "该虾当前离线，消息将在重连后发送"

### 12.4 Chat 消息入场

- 每条消息使用 `msgIn` 动画: `opacity:0, translateY(10px)` -> `opacity:1, translateY(0)`
- 动画时长: `var(--dur-mid)` = 250ms `var(--ease)`
- 仅新渲染的消息触发动画，历史消息不重播

### 12.5 Auto-scroll 行为

- 发送消息后: `setTimeout(() => el.scrollTop = el.scrollHeight, 60)` 滚动到底部
- 打开聊天后: `setTimeout(() => scrollChat(), 100)` 滚动到底部
- Typing indicator 出现后也触发 scroll

### 12.6 输入框自动增长

```javascript
function autoResize(el) {
  el.style.height = 'auto';
  el.style.height = Math.min(el.scrollHeight, 100) + 'px';
}
```
- 最大高度: 100px
- 超过后输入框内部可滚动

### 12.7 Form Input Border

V2 表单输入框使用 `border: 1px solid var(--border)` 替代 V1 的 `box-shadow: inset`：
- 默认: `border: 1px solid var(--border)`
- Focus: `border-color: var(--accent)`
- 优势: V2 使用 border 而非 inset shadow，更精确、更符合冷色调设计语言

### 12.8 Token 安全处理

- 输入 type: password
- PRD 要求: Token 以加密形式存储在 iOS Keychain / Android Keystore
- 不在界面明文展示 Token 值

### 12.9 实例连通性测试流程

1. 点击"连接测试"按钮
2. Toast: "正在连接 {name}..."
3. 模拟 1500ms 延迟
4. 成功: Toast "连接成功！已添加到实例列表" -> 800ms 后跳转 `page-instances`
5. 失败（校验不通过）: 对应字段 Toast 提示

### 12.10 扫码流程

1. 点击"模拟扫码成功"
2. Toast: "扫码成功！发现实例：我的 MacBook Pro"
3. 1200ms 后 Toast: "连接测试通过，已添加到实例列表"
4. 800ms 后跳转 `page-instances`

### 12.11 Primary Button（通用主按钮）`.primary-btn`

| 属性 | 值 |
|---|---|
| margin | `16px var(--s5) 0` |
| padding | 12px |
| background | `var(--accent)` = `#4F83FF` |
| color | `#fff` |
| border | none |
| border-radius | `var(--r-lg)` = 10px |
| font-size | 14px |
| font-weight | 600 |
| cursor | pointer |
| width | calc(100% - 32px), display: block |
| box-shadow | `var(--shadow-glow)` = `0 0 20px rgba(79,131,255,0.15)` |
| transition | `all var(--dur-fast) var(--ease)` |

**Press 态**: transform: scale(0.97), filter: brightness(0.9)
**Disabled 态**: opacity: 0.4, cursor: default, box-shadow: none

### 12.12 Secondary Button（通用次按钮）`.secondary-btn`

| 属性 | 值 |
|---|---|
| margin | `8px var(--s5) 0` |
| padding | 11px |
| background | transparent |
| color | `var(--accent)` |
| border | `1px solid var(--border-accent)` |
| border-radius | `var(--r-lg)` = 10px |
| font-size | 14px |
| font-weight | 500 |
| cursor | pointer |
| width | calc(100% - 32px), display: block |
| transition | `all var(--dur-fast) var(--ease)` |

**Press 态**: transform: scale(0.97), background `var(--accent-muted)`

---

## 附录 A: 完整组件尺寸速查表

| 组件 | 宽 | 高 | 圆角 | 图标尺寸 |
|---|---|---|---|---|
| Agent Avatar (列表) | 36px | 36px | 8px | 16px |
| Agent Avatar (聊天头) | 32px | 32px | 8px | 14px |
| Agent Avatar (详情) | 56px | 56px | 10px | 24px |
| Agent Avatar (编辑) | 64px | 64px | 10px | 28px |
| Agent Avatar (消息列表) | 36px | 36px | 8px | 16px |
| Online Pulse | 10px | 10px | 999px | — |
| Status Dot (头部/分组) | 6px | 6px | 999px | — |
| Stat Dot (inline) | 5px | 5px | 999px | — |
| Header Button | 36px | 36px | 8px | 18px |
| Back Button | 32px | 32px | 8px | 20px |
| Instance Icon | 36px | 36px | 8px | 20px SVG |
| Achievement Icon | 32px | 32px | 8px | 16px |
| Nav Item Icon | — | — | — | 20px |
| Send Button | 36px | 36px | 999px | 18px |
| Color Swatch | max 40px | aspect 1:1 | 8px | — |
| Unread Badge | min 16px | 16px | 999px | — |
| Nav Badge | min 14px | 14px | 999px | — |
| Form Input | 100% | auto | 8px | — |
| Primary Button | calc(100% - 32px) | auto | 10px | — |
| Secondary Button | calc(100% - 32px) | auto | 10px | — |
| Bottom Nav | 100% | 56px | — | — |
| QR Scanner Mock | 180px | 180px | 10px | 40px emoji |
| Chat Bubble | max 78% | auto | 14px (corner: 4px) | — |
| Tool Card | max 78% | auto | 8px | — |
| Toggle | 40px | 22px | 11px | — |
| Toggle Knob | — | — | 999px (18px) | — |

## 附录 B: 导航关系图

```
                    ┌──────────────────────────────┐
                    │      Bottom Navigation        │
                    │  [虾列表] [消息] [实例]         │
                    └──┬────────┬────────┬──────────┘
                       │        │        │
                ┌──────┘    ┌───┘    ┌───┘
                ▼           ▼        ▼
           page-home   page-msg  page-instances
                │           │        │
                │           │        │
                │      ┌────┘        ▼
                │      │        page-add-instance
                └──┬───┘
                   ▼
              page-chat
                   │
                   ├──(more btn)──> page-agent-detail
                   │                    │
                   │                    ▼
                   │              page-agent-edit
                   │
        page-home ──(search btn)──> page-search
        page-instances ──(settings btn)──> page-settings
```

## 附录 C: 开发注意事项

1. **所有 padding/margin 值必须使用 Design Token CSS 变量**，禁止硬编码像素值，确保主题系统可维护。

2. **font-variant-numeric: tabular-nums** 应用于所有数字展示（统计值、时间戳、消息数），确保等宽数字对齐。

3. **Safe Area 适配**: 所有底部固定元素必须加上 `var(--safe-bottom)`，适配 iPhone 刘海屏。

4. **Touch 优化**: 所有可点击元素设置 `-webkit-tap-highlight-color: transparent`（已在全局 Reset 中设置）。

5. **性能**: 页面使用 `will-change: transform, opacity` 进行 GPU 加速。消息列表超过 50 条时应实现虚拟滚动。

6. **无障碍**: 所有按钮需有 `title` 属性或 `aria-label`。颜色对比度需满足 WCAG AA 标准（深色模式下尤其注意 `--text-3` 和 `--text-4` 的对比度）。

7. **动效降级**: 需尊重用户的 `prefers-reduced-motion` 系统设置，在该设置开启时禁用所有 transition 和 animation。

8. **消息气泡圆角规律**: 用户消息右下角收尖（4px），虾消息左下角收尖（4px），其余三角保持 14px。这是区分消息方向的关键视觉线索。

9. **V2 边框替代填充**: V2 大量使用 `border: 1px solid var(--border)` 替代 V1 的 surface 层叠填充色来区分层级。卡片、列表项、输入框均使用 hairline border 而非阴影或 inset box-shadow。

10. **V2 冷色调**: 所有颜色值已全面转向冷色基底（蓝灰调），确保不与 V1 暖色值混用。accent 色已从珊瑚色(#C27C68)替换为宝石蓝(#4F83FF)，次级强调色为紫罗兰(#9B7AFF)。

11. **accent2 (紫罗兰) 使用范围**: Agent 在线脉冲动画、工具调用卡片左竖条、typing indicator 跳动点、成就图标背景、quote block 左竖条、选中态复选框/单选框。

---

*文档结束。所有标注均基于 V2 原型 Demo（虾Hub-原型Demo-V2.html）的 CSS 精确提取，如有设计变更以最新 Figma 为准。*
