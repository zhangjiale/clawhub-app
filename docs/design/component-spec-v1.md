# ComponentSpec - 虾Hub 组件标注与交互规范

**版本**: v1.0
**日期**: 2026-06-10
**对应原型**: 虾Hub-原型Demo-Premium.html
**对应PRD**: PRD-虾Hub多OpenClaw移动端管理客户端.md v1.1

---

## 目录

1. [Design Tokens（设计令牌）](#1-design-tokens设计令牌)
2. [Page 1: 虾列表（page-home）](#2-page-1-虾列表page-home)
3. [Page 2: 消息（page-messages）](#3-page-2-消息page-messages)
4. [Page 3: 聊天（page-chat）](#4-page-3-聊天page-chat)
5. [Page 4: 虾详情（page-agent-detail）](#5-page-4-虾详情page-agent-detail)
6. [Page 5: 个性化配置（page-agent-config）](#6-page-5-个性化配置page-agent-config)
7. [Page 6: 实例管理（page-instances）](#7-page-6-实例管理page-instances)
8. [Page 7: 添加实例（page-add-instance）](#8-page-7-添加实例page-add-instance)
9. [Page 8: 设置（page-settings）](#9-page-8-设置page-settings)
10. [Cross-Cutting 全局交互规范](#10-cross-cutting-全局交互规范)
11. [Edge Cases 与异常状态](#11-edge-cases-与异常状态)

---

## 1. Design Tokens（设计令牌）

### 1.1 Color System（色彩体系）

采用 60-30-10 比例分配：60% 深色背景、30% 表面色、10% 强调色。

| Token | 值 | 用途 |
|---|---|---|
| `--bg` | `#111110` | 全局最底层背景 |
| `--surface` | `#1A1917` | 卡片/气泡一级表面 |
| `--surface2` | `#232220` | 二级表面（嵌套卡片、工具卡片） |
| `--surface3` | `#2C2B28` | 三级表面（输入框内描边、禁用态） |
| `--surface-elevated` | `#1F1E1C` | 浮层表面（Toast、Banner） |
| `--text-1` | `#F5F4F0` | 主文本（标题、正文） |
| `--text-2` | `rgba(245,244,240,0.60)` | 次级文本（描述、标签） |
| `--text-3` | `rgba(245,244,240,0.35)` | 三级文本（预览、占位） |
| `--text-4` | `rgba(245,244,240,0.18)` | 最弱文本（时间戳、禁用） |
| `--accent` | `#C27C68` | 品牌强调色（desaturated coral） |
| `--accent-hover` | `#D08E7C` | 强调色 hover 态 |
| `--accent-muted` | `rgba(194,124,104,0.12)` | 强调色透明底 |
| `--accent-glow` | `rgba(194,124,104,0.18)` | 强调色发光（按钮阴影） |
| `--green` | `#6BA87A` | 语义色：在线/成功 |
| `--green-muted` | `rgba(107,168,122,0.15)` | 绿色透明底 |
| `--red` | `#C26464` | 语义色：错误/删除 |
| `--red-muted` | `rgba(194,100,100,0.12)` | 红色透明底 |
| `--yellow` | `#C4A86A` | 语义色：警告 |

#### Theme Color Map（虾主题色映射）

每只虾根据 `theme` 字段映射到一组 `bg`（头像底色）和 `color`（强调色）：

| theme | bg | color | 名称 |
|---|---|---|---|
| coral | `rgba(194,124,104,0.12)` | `#C27C68` | 珊瑚 |
| blue | `rgba(108,138,175,0.12)` | `#6C8AAF` | 雾蓝 |
| green | `rgba(107,168,122,0.12)` | `#6BA87A` | 薄荷 |
| orange | `rgba(185,138,100,0.12)` | `#B98A64` | 暖橙 |
| pink | `rgba(175,120,140,0.12)` | `#AF788C` | 烟粉 |
| teal | `rgba(95,155,150,0.12)` | `#5F9B96` | 湖蓝 |
| yellow | `rgba(175,155,95,0.12)` | `#AF9B5F` | 暖黄 |
| rose | `rgba(170,110,130,0.12)` | `#AA6E82` | 玫瑰 |
| slate | `rgba(130,130,130,0.12)` | `#828282` | 石墨 |
| indigo | `rgba(110,100,160,0.12)` | `#6E64A0` | 靛蓝 |
| caramel | `rgba(170,125,80,0.12)` | `#AA7D50` | 焦糖 |
| jade | `rgba(80,150,120,0.12)` | `#509678` | 翡翠 |

### 1.2 Spacing System（间距系统）

基于 8pt 网格，使用 `--s1` 至 `--s10`：

| Token | 值 | 常见用途 |
|---|---|---|
| `--s1` | 4px | 图标与文字间微间距 |
| `--s2` | 8px | 紧凑元素间距 |
| `--s3` | 12px | 列表项间距、卡片 gap |
| `--s4` | 16px | 卡片内 padding、分组间距 |
| `--s5` | 20px | 列表项垂直 padding、卡片 padding |
| `--s6` | 24px | 页面水平 padding |
| `--s7` | 32px | Section 间距 |
| `--s8` | 40px | 大区块间距 |
| `--s9` | 48px | 空状态 padding |
| `--s10` | 56px | 预留 |

### 1.3 Border Radius（圆角系统）

| Token | 值 | 常见用途 |
|---|---|---|
| `--r-sm` | 8px | 小按钮、状态点、头像(聊天页) |
| `--r-md` | 12px | 卡片内头像、输入框、卡片 |
| `--r-lg` | 16px | 大卡片、agent card、底部 nav |
| `--r-xl` | 20px | 消息气泡 |
| `--r-full` | 999px | 胶囊按钮、统计点、badge |

### 1.4 Shadow System（阴影系统）

所有阴影使用暖色调（纯黑 rgba）：

| Token | 值 | 用途 |
|---|---|---|
| `--shadow-s` | `0 1px 2px rgba(0,0,0,0.18)` | Agent 消息气泡、typing indicator |
| `--shadow-m` | `0 4px 16px rgba(0,0,0,0.20)` | 中层级 |
| `--shadow-l` | `0 8px 32px rgba(0,0,0,0.22)` | Toast 浮层 |
| `--shadow-xl` | `0 16px 48px rgba(0,0,0,0.28)` | Phone frame |

### 1.5 Motion System（动效系统）

| Token | 值 | 用途 |
|---|---|---|
| `--ease` | `cubic-bezier(0.16, 1, 0.3, 1)` | 通用缓动（expo out） |
| `--ease-spring` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | 弹性缓动 |
| `--ease-out` | `cubic-bezier(0.0, 0.0, 0.2, 1)` | 减速缓动 |
| `--duration-fast` | 200ms | 按压反馈、hover |
| `--duration-mid` | 350ms | 消息入场、Toast 显隐 |
| `--duration-slow` | 500ms | 页面转场 |

### 1.6 Typography（字体系统）

| 属性 | 值 |
|---|---|
| font-family | `-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", "PingFang SC", sans-serif` |
| Code font | `"SF Mono", "Fira Code", monospace` |
| Base font-size | 15px |
| Base line-height | 1.55 |
| font-feature-settings | `"ss01", "cv11"` |
| -webkit-font-smoothing | `antialiased` |

#### 字号层级

| 层级 | 字号 | 字重 | 用途 |
|---|---|---|---|
| H1 | 30px | 700 | 页面标题 |
| H2 | 24px | 700 | 详情页名称 |
| H3 | 22px | 700 | 二级页面标题 |
| Body-lg | 17px | 600 | 聊天头部名称 |
| Body | 16px | 600 | 卡片名称 |
| Body-sm | 15px | 400 | 消息正文、输入框 |
| Caption | 14px | 500 | 消息预览、描述 |
| Caption-sm | 13px | 400 | 虾描述、快捷指令 |
| Micro | 12px | 500/600 | 标签、时间戳 |
| Micro-sm | 11px | 500/700 | 最小说明文字、badge |
| Micro-xs | 10px | 500 | 底部导航标签 |

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
| 边框 | `2px solid rgba(255,255,255,0.06)` |
| 背景 | `var(--bg)` |
| Notch 宽 | 126px |
| Notch 高 | 34px |
| Notch 圆角 | `0 0 20px 20px` |
| Status Bar 高 | 54px |

**响应式**: 当视口宽度 <= 500px 时，phone frame 全屏展示（width:100%, height:100%, border-radius:0, border:none）。

---

## 2. Page 1: 虾列表（page-home）

### 2.1 Header 区域

**结构**: 水平排列 `[标题 h1] [实例管理按钮] [设置按钮]`

| 属性 | 值 |
|---|---|
| padding | `var(--s3) var(--s6) var(--s4)` = 12px 24px 16px |
| gap | `var(--s3)` = 12px |
| background | `var(--bg)` |
| z-index | 10 |
| flex-shrink | 0（不压缩） |

**标题 `h1`**:
- font-size: 30px, font-weight: 700
- letter-spacing: -0.6px, line-height: 1.2
- color: `var(--text-1)`
- flex: 1（占满剩余空间）

**Header 按钮 `.header-btn`**:
- 尺寸: 40px x 40px
- border-radius: `var(--r-md)` = 12px
- background: `var(--surface2)`
- 图标: 20px x 20px, color: `var(--text-2)`
- 布局: flex center
- **Press 态**: background 变为 `var(--surface3)`, transform: scale(0.95)
- **Transition**: `all 200ms var(--ease)`

**实例管理按钮**: 图标为窗口/服务器样式（rect + line + 2 circles），onclick 跳转 `page-instances`。
**设置按钮**: 图标为齿轮，onclick 跳转 `page-settings`。

### 2.2 Stats Bar（状态统计栏）

**容器 `.stats-bar`**:

| 属性 | 值 |
|---|---|
| display | flex |
| gap | `var(--s3)` = 12px |
| padding | `0 var(--s6) var(--s5)` = 0 24px 20px |

**统计 Chip `.stat-chip`** (共 3 个，等宽):

| 属性 | 值 |
|---|---|
| flex | 1（三等分） |
| display | flex, align-items: center, justify-content: center |
| gap | `var(--s3)` = 12px |
| padding | `var(--s4) var(--s3)` = 16px 12px |
| background | `var(--surface)` |
| border-radius | `var(--r-lg)` = 16px |
| white-space | nowrap |
| min-width | 0（防溢出） |

**内部结构**: `[emoji icon 18px] [数值组(纵向)]`

| 元素 | 样式 |
|---|---|
| `.chip-icon` | font-size: 18px |
| `.chip-value` | font-size: 22px, font-weight: 700, color: `var(--text-1)`, letter-spacing: -0.5px, line-height: 1, font-variant-numeric: tabular-nums |
| `.chip-unit` | font-size: 14px, font-weight: 400, color: `var(--text-3)`（嵌套在 chip-value 内） |
| `.chip-label` | font-size: 11px, color: `var(--text-3)`, margin-top: 2px, font-weight: 500, letter-spacing: 0.3px |

**三个 Chip 内容**:
1. `🖥` — `{onlineInst} / {totalInst}` — "活跃实例"
2. `🦐` — `{onlineAgents} / {totalAgents}` — "在线虾"
3. `💬` — `{totalMsgs}` (toLocaleString) — "总消息数"

### 2.3 Instance Group Header（实例分组头）

**容器 `.instance-group`**:
- margin-bottom: `var(--s3)` = 12px

**分组头 `.instance-header`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| min-height | 44px ← 满足移动端最小触控目标 (Apple HIG 44pt / MD 48dp) |
| padding | `var(--s4) var(--s6)` = 16px 24px |
| gap | `var(--s2)` = 8px |
| cursor | pointer |
| user-select | none |
| -webkit-tap-highlight-color | transparent |
| transition | opacity 200ms var(--ease) |
| border-radius | `var(--r-sm)` = 8px ← 仅用于内部布局，不用于按压背景 |

**Press 态**:
- **不使用** background 变色或圆角矩形高亮（分组头是结构性元素，不是按钮/卡片）
- 按压时整体 **opacity: 0.5**（含状态点、文字、箭头一起变淡），视觉反馈自然且不产生额外形状
- chevron 颜色变为 `var(--text-3)`（稍微提亮，暗示可交互）
- 松开后 200ms ease 恢复

```css
.instance-header:active {
  opacity: 0.5;
}
.instance-header:active .chevron {
  color: var(--text-3);
}
```

**内部结构**: `[状态点] [实例名] [数量] [折叠箭头]`

| 元素 | 样式 |
|---|---|
| `.instance-dot` | 6x6px, border-radius: 999px, flex-shrink: 0 |
| `.instance-dot.online` | background: `var(--green)`, box-shadow: `0 0 8px var(--green)` |
| `.instance-dot.offline` | background: `var(--text-4)` |
| `.instance-name` | font-size: 12px, font-weight: 600, color: `var(--text-3)`, letter-spacing: 0.8px, text-transform: uppercase, flex: 1 |
| `.instance-count` | font-size: 12px, color: `var(--text-4)`, font-variant-numeric: tabular-nums |
| `.chevron` | 16x16px, color: `var(--text-4)`, transition: transform 200ms var(--ease) |
| `.chevron.collapsed` | transform: rotate(-90deg) |

**Collapse/Expand 行为**:
- 点击分组头 -> toggle `.agent-list` 的展开/收起
- 同时 toggle chevron 的 `.collapsed` class
- **动画实现**：使用 `max-height` + `overflow: hidden` + `transition: max-height 350ms var(--ease)` 替代原来的 display 切换
  - 展开时：`max-height` 设为足够大的值（如 `1000px`，或动态计算子项总高度）
  - 收起时：`max-height: 0`
  - 避免使用 display:none 切换（无法做过渡动画）

### 2.4 Agent Card（虾卡片）

**列表容器 `.agent-list`**:
- padding: `0 var(--s6)` = 0 24px

**卡片 `.agent-card`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `var(--s4) var(--s5)` = 16px 20px |
| background | `var(--surface)` |
| border-radius | `var(--r-lg)` = 16px |
| margin-bottom | `var(--s3)` = 12px |
| cursor | pointer |
| position | relative, overflow: hidden |
| transition | `all 200ms var(--ease)` |

**Press 态**:
- transform: scale(0.98)
- background: `var(--surface2)`

**Navigation**: onclick 调用 `openChat(agentId)` 进入 page-chat

**内部结构**: `[头像 48px] [信息区(flex:1)] [元信息区]`

#### 2.4.1 Agent Avatar（虾头像）`.agent-avatar`

| 属性 | 值 |
|---|---|
| 尺寸 | 48px x 48px |
| border-radius | `var(--r-md)` = 12px |
| display | flex, center |
| font-size | 24px（emoji） |
| flex-shrink | 0 |
| background | 根据虾 theme 映射（见 1.1 Theme Color Map） |
| position | relative |

**Status Dot（在线状态点）`.status-dot`**:
- position: absolute, bottom: 2px, right: 2px
- 尺寸: 8px x 8px
- border-radius: 999px
- border: `2px solid var(--surface)`（与卡片背景融合形成间隔效果）
- `.online`: background `var(--green)`
- `.offline`: background `var(--text-4)`

#### 2.4.2 Agent Info（信息区）`.agent-info`

| 属性 | 值 |
|---|---|
| flex | 1 |
| margin-left | `var(--s4)` = 16px |
| min-width | 0（防溢出） |

| 元素 | 样式 |
|---|---|
| `.agent-name` | font-size: 16px, font-weight: 600, color: `var(--text-1)`, letter-spacing: -0.2px, line-height: 1.3 |
| `.agent-desc` | font-size: 13px, color: `var(--text-3)`, line-height: 1.4, white-space: nowrap, overflow: hidden, text-overflow: ellipsis, margin-top: 2px |

#### 2.4.3 Agent Meta（元信息区）`.agent-meta`

| 属性 | 值 |
|---|---|
| display | flex, flex-direction: column, align-items: flex-end |
| gap | `var(--s1)` = 4px |

| 元素 | 样式 |
|---|---|
| `.agent-time` | font-size: 11px, color: `var(--text-4)`, font-variant-numeric: tabular-nums, letter-spacing: 0.2px |

### 2.5 Bottom Navigation（底部导航栏）

**容器 `.bottom-nav`**:

| 属性 | 值 |
|---|---|
| position | absolute, bottom: 0, left: 0, right: 0 |
| height | 72px |
| background | `rgba(17,17,16,0.88)` |
| backdrop-filter | `blur(24px) saturate(1.4)` |
| display | flex, align-items: center, justify-content: space-around |
| padding-bottom | `var(--safe-bottom)` |
| z-index | 50 |
| border-top | `1px solid rgba(245,244,240,0.04)` |

**导航项 `.nav-item`**:

| 属性 | 值 |
|---|---|
| display | flex, flex-direction: column, align-items: center |
| gap | 3px |
| cursor | pointer |
| padding | `var(--s2) var(--s6)` = 8px 24px |
| transition | `all 200ms var(--ease)` |

| 元素 | Inactive | Active |
|---|---|---|
| SVG 图标 (22x22px) | color: `var(--text-4)` | color: `var(--accent)` |
| 标签文字 | font-size: 10px, color: `var(--text-4)`, font-weight: 500, letter-spacing: 0.2px | color: `var(--accent)` |

**三个 Tab**:
1. `虾列表` — Home icon — data-page: `page-home`
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
| padding-bottom | `calc(80px + var(--safe-bottom))`（为 bottom nav 留空间） |
| scrollbar | 隐藏（`::-webkit-scrollbar { display: none }`） |

### 2.7 入场动画（Staggered Animation）

```css
.animate-in { animation: slideUp 350ms var(--ease) both; }
.delay-1 { animation-delay: 0.04s; }
.delay-2 { animation-delay: 0.08s; }
.delay-3 { animation-delay: 0.12s; }
.delay-4 { animation-delay: 0.16s; }
.delay-5 { animation-delay: 0.20s; }
```

- `@keyframes slideUp`: from `translateY(20px), opacity:0` to `translateY(0), opacity:1`
- 每个 instance-group 使用 `.animate-in`
- group 内的 agent-card 使用递增 delay

---

## 3. Page 2: 消息（page-messages）

### 3.1 Header 区域

与 page-home 结构一致，区别：
- 标题文字: "消息"
- 右侧按钮: 搜索图标（放大镜 SVG），onclick 跳转 `page-settings`（原型临时绑定）

### 3.2 Message List Item（消息列表项）

**列表容器 `.msg-list`**:
- padding: `0 var(--s6)` = 0 24px

**消息项 `.msg-item`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `var(--s5) var(--s2)` = 20px 8px |
| gap | `var(--s4)` = 16px |
| cursor | pointer |
| border-radius | `var(--r-md)` = 12px |
| border-bottom | `1px solid rgba(245,244,240,0.04)` |
| transition | `all 200ms var(--ease)` |

**最后一项**: `border-bottom: none`

**Press 态**: background 变为 `var(--surface2)`

**Navigation**: onclick 调用 `openChat(agentId)` 进入 page-chat

**内部结构**: `[头像 48px] [信息区(flex:1)] [未读 badge]`

#### 3.2.1 Message Avatar（消息头像）

| 属性 | 值 |
|---|---|
| 尺寸 | 48px x 48px |
| font-size | 22px |
| border-radius | `var(--r-md)` = 12px |
| background | 根据虾 theme 映射 |
| flex-shrink | 0 |

内含 status-dot（同 Agent Card 定义）。

#### 3.2.2 Message Info（信息区）`.msg-item-info`

| 属性 | 值 |
|---|---|
| flex | 1 |
| min-width | 0 |

**Top Row `.msg-item-top`**:
- display: flex, align-items: baseline, justify-content: space-between

| 元素 | 样式 |
|---|---|
| `.msg-item-name` | font-size: 16px, font-weight: 600, color: `var(--text-1)`, letter-spacing: -0.2px |
| `.msg-item-time` | font-size: 12px, color: `var(--text-4)`, flex-shrink: 0, font-variant-numeric: tabular-nums, margin-left: `var(--s2)` = 8px |

**Preview Row `.msg-item-preview`**:
- font-size: 14px, color: `var(--text-3)`, line-height: 1.5
- white-space: nowrap, overflow: hidden, text-overflow: ellipsis
- margin-top: 4px

**截断规则**: 原始文本去除 Markdown 标记（`*`, `` ` ``, `#`, `[`, `]`），换行替换为空格，超过 **38 字符** 截断并追加 `...`

**"你:"前缀**: 当最后一条消息 type 为 user 时，preview 前插入 `<span class="you">你：</span>`，`.you` 样式为 `color: var(--text-2)`

**空消息**: 显示 "暂无消息"

#### 3.2.3 Unread Badge（未读角标）`.msg-unread`

| 属性 | 值 |
|---|---|
| min-width | 18px |
| height | 18px |
| border-radius | `var(--r-full)` = 999px |
| background | `var(--accent)` |
| color | `#fff` |
| font-size | 11px |
| font-weight | 700 |
| display | flex, center |
| flex-shrink | 0 |
| margin-left | `var(--s2)` = 8px |
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
| padding | `var(--s3) var(--s5) var(--s4)` = 12px 20px 16px |
| background | `var(--bg)` |
| gap | `var(--s3)` = 12px |
| flex-shrink | 0 |
| position | relative, z-index: 10 |

**内部结构**: `[返回按钮] [头像 40px] [信息区(flex:1)] [更多按钮]`

#### 4.1.1 Back Button（返回按钮）`.back-btn`

| 属性 | 值 |
|---|---|
| 尺寸 | 40px x 40px |
| border-radius | `var(--r-md)` = 12px |
| background | transparent |
| 图标 | 22x22px, 左箭头 chevron, stroke-width: 2 |
| color | `var(--text-2)` |

**Press 态**: background `var(--surface2)`, transform: scale(0.95)

**行为**: `showPage(lastMainTab); updateNavActive(lastMainTab)` — 智能返回到来源 Tab

#### 4.1.2 Chat Avatar（聊天头像）

| 属性 | 值 |
|---|---|
| 尺寸 | 40px x 40px |
| font-size | 18px（注意与其他页面不同） |
| border-radius | `var(--r-sm)` = 8px（注意与其他页面不同） |
| background | 根据虾 theme 映射 |

**注意**: 聊天头部头像尺寸(40px)和圆角(8px)比其他场景(48px/12px)更小。

#### 4.1.3 Chat Header Info（头部信息区）

| 属性 | 值 |
|---|---|
| flex | 1 |
| **点击行为** | onclick 跳转 `page-agent-detail` |

| 元素 | 样式 |
|---|---|
| `.chat-header-name` | font-size: 17px, font-weight: 600, letter-spacing: -0.2px |
| `.chat-header-status` | font-size: 12px, display: flex, gap: `var(--s1)` = 4px, color: `var(--text-3)` |
| status dot | 6x6px, border-radius: 999px; 在线: `var(--green)` / 离线: `var(--text-4)` |

#### 4.1.4 More Button（更多按钮）

复用 `.header-btn` 样式（40x40px, surface2 bg, r-md），图标为三点竖排（more-vertical）。
onclick 跳转 `page-agent-detail`。

### 4.2 Chat Messages（消息流区域）

**容器 `.chat-messages`**:

| 属性 | 值 |
|---|---|
| flex | 1 |
| overflow-y | auto |
| padding | `var(--s4) var(--s6)` = 16px 24px |
| display | flex, flex-direction: column |
| gap | `var(--s3)` = 12px |
| -webkit-overflow-scrolling | touch |
| scrollbar | 隐藏 |

#### 4.2.1 Date Separator（日期分隔线）`.date-separator`

| 属性 | 值 |
|---|---|
| text-align | center |
| font-size | 12px |
| color | `var(--text-4)` |
| padding | `var(--s4) 0` = 16px 0 |
| font-weight | 500 |
| letter-spacing | 0.5px |

#### 4.2.2 Message Bubble（消息气泡）`.msg`

**通用属性**:

| 属性 | 值 |
|---|---|
| max-width | 78% |
| padding | `var(--s3) var(--s5)` = 12px 20px |
| border-radius | `var(--r-xl)` = 20px |
| font-size | 15px |
| line-height | 1.6 |
| word-break | break-word |
| 入场动画 | `msgIn 350ms var(--ease)` |

`@keyframes msgIn`: from `opacity:0, translateY(12px)` to `opacity:1, translateY(0)`

**User Message（用户消息）`.msg.user`**:

| 属性 | 值 |
|---|---|
| align-self | flex-end |
| background | `var(--accent)` = `#C27C68` |
| color | `#fff` |
| border-bottom-right-radius | `var(--r-sm)` = 8px（右下角收尖） |

**Agent Message（虾消息）`.msg.agent`**:

| 属性 | 值 |
|---|---|
| align-self | flex-start |
| background | `var(--surface)` |
| color | `var(--text-1)` |
| border-bottom-left-radius | `var(--r-sm)` = 8px（左下角收尖） |
| box-shadow | `var(--shadow-s)` |

**Agent 消息内的 Markdown 渲染**:

| 元素 | 样式 |
|---|---|
| `code`（行内） | background: `rgba(245,244,240,0.06)`, padding: `1px 6px`, border-radius: `var(--r-sm)`, font-family: `"SF Mono", "Fira Code", monospace`, font-size: 13px |
| `pre`（代码块） | background: `var(--surface2)`, padding: `var(--s4)` = 16px, border-radius: `var(--r-md)`, margin: `var(--s2) 0` = 8px 0, overflow-x: auto, font-size: 12px, line-height: 1.5 |
| `strong` | `<strong>` 标签，bold |
| `em` | `<em>` 标签，italic |

#### 4.2.3 Tool Card（工具调用卡片）

**位置**: 嵌套在 `.msg.agent` 内部

**容器 `.tool-card`**:

| 属性 | 值 |
|---|---|
| background | `var(--surface2)` |
| border-radius | `var(--r-md)` = 12px |
| padding | `var(--s3) var(--s4)` = 12px 16px |
| margin-top | `var(--s3)` = 12px |
| font-size | 12px |
| border-left | `3px solid var(--accent)` |

| 元素 | 样式 |
|---|---|
| `.tool-name` | font-weight: 600, color: `var(--accent)`, display: flex, align-items: center, gap: `var(--s1)` = 4px |
| `.tool-status` | color: `var(--green)`, font-size: 11px, margin-top: `var(--s1)` = 4px |

#### 4.2.4 Message Time（消息时间戳）`.msg-time`

| 属性 | 值 |
|---|---|
| font-size | 11px |
| color | `var(--text-4)` |
| margin-top | `var(--s1)` = 4px |
| padding | `0 var(--s1)` = 0 4px |
| font-variant-numeric | tabular-nums |

- `.msg-time.left`: align-self: flex-start（虾消息的时间）
- `.msg-time.right`: align-self: flex-end（用户消息的时间）

**注意**: 时间戳是独立于气泡之外的元素，紧跟在气泡后面。

### 4.3 Typing Indicator（输入中指示器）

**容器 `.typing-indicator`**:

| 属性 | 值 |
|---|---|
| align-self | flex-start |
| padding | `var(--s4) var(--s5)` = 16px 20px |
| background | `var(--surface)` |
| border-radius | `var(--r-xl)` = 20px |
| border-bottom-left-radius | `var(--r-sm)` = 8px |
| display | flex, gap: `var(--s1)` = 4px, align-items: center |
| box-shadow | `var(--shadow-s)` |

**Typing Dot（跳动圆点）`.typing-dot`**:

| 属性 | 值 |
|---|---|
| 尺寸 | 6px x 6px |
| border-radius | 999px |
| background | `var(--text-3)` |
| 动画 | `typingBounce 0.8s infinite var(--ease)` |

**动画定义**:
```css
@keyframes typingBounce {
  0%, 80%, 100% { transform: translateY(0); }
  40% { transform: translateY(-8px); }
}
```

**三个圆点的延迟**:
- 第 1 个: animation-delay: 0s
- 第 2 个: animation-delay: 0.15s
- 第 3 个: animation-delay: 0.3s

**生命周期**: 用户发送消息后插入 DOM，Agent 回复后 remove()。模拟延迟 1200ms + random(0~800ms)。

### 4.4 Quick Commands（快捷指令栏）

**容器 `.quick-commands`**:

| 属性 | 值 |
|---|---|
| display | flex, gap: `var(--s2)` = 8px |
| overflow-x | auto |
| padding-bottom | `var(--s3)` = 12px |
| scrollbar-width | none |
| scrollbar | 隐藏 |

**指令 Pill `.quick-cmd`**:

| 属性 | 值 |
|---|---|
| white-space | nowrap |
| padding | `var(--s2) var(--s4)` = 8px 16px |
| border-radius | `var(--r-full)` = 999px（全圆角胶囊） |
| font-size | 13px |
| background | `var(--surface2)` |
| color | `var(--accent)` |
| border | none |
| cursor | pointer |
| flex-shrink | 0 |
| font-weight | 500 |
| letter-spacing | -0.1px |
| transition | `all 200ms var(--ease)` |

**Press 态**: background `var(--accent-muted)`, transform: scale(0.95)

**行为**: 点击 -> 指令文本填入输入框 -> 自动触发发送（`sendQuickCmd`）

### 4.5 Chat Input Area（输入区域）

**容器 `.chat-input-area`**:

| 属性 | 值 |
|---|---|
| padding | `var(--s3) var(--s6)` = 12px 24px |
| padding-bottom | `calc(var(--s3) + var(--safe-bottom))` |
| background | `var(--bg)` |
| flex-shrink | 0 |

**内部结构**:
```
[快捷指令栏（上方横向滚动）]
[输入行: Plus按钮 + Textarea + Send按钮]
```

#### 4.5.1 Input Row（输入行）`.input-row`

| 属性 | 值 |
|---|---|
| display | flex, align-items: flex-end |
| gap | `var(--s3)` = 12px |

#### 4.5.2 Plus Button（加号按钮）`.plus-btn`

| 属性 | 值 |
|---|---|
| 尺寸 | 40px x 40px |
| border-radius | `var(--r-md)` = 12px |
| background | `var(--surface2)` |
| color | `var(--text-3)` |
| 图标 | 20x20px 十字加号, stroke-width: 1.5 |
| flex-shrink | 0 |

**Press 态**: background `var(--surface3)`, transform: scale(0.95)
**行为**: 显示 Toast "附件功能开发中"

#### 4.5.3 Textarea（文本输入框）`.msg-input`

| 属性 | 值 |
|---|---|
| flex | 1 |
| background | `var(--surface)` |
| border | none |
| border-radius | `var(--r-lg)` = 16px |
| color | `var(--text-1)` |
| padding | `var(--s3) var(--s5)` = 12px 20px |
| font-size | 15px |
| outline | none |
| resize | none |
| max-height | 100px |
| line-height | 1.5 |
| font-family | inherit |

**Placeholder**: color `var(--text-4)`, 文字 "写点什么..."

**Auto-resize 行为**: `oninput` 时 `style.height = auto` -> `style.height = min(scrollHeight, 100px)`

**Enter 键行为**: Enter 发送消息，Shift+Enter 换行

#### 4.5.4 Send Button（发送按钮）`.send-btn`

| 属性 | 值 |
|---|---|
| 尺寸 | 40px x 40px |
| border-radius | `var(--r-md)` = 12px |
| background | `var(--accent)` |
| color | `#fff` |
| 图标 | 18x18px 纸飞机 fill |
| flex-shrink | 0 |

**Press 态**: transform: scale(0.92)

**Disabled 态** `.send-btn.disabled`:
- opacity: 0.3
- cursor: default
- 当输入框内容为空时添加

**Toggle 逻辑**: 输入框 oninput 时根据 trim().length 切换 disabled class

---

## 5. Page 4: 虾详情（page-agent-detail）

### 5.1 Header 区域

**结构**: `[返回按钮] [标题(虾名)] [编辑按钮]`

| 属性 | 值 |
|---|---|
| 标题 | 动态取虾名 |
| 标题 font-size | 22px |
| 返回目标 | `page-chat` |

**编辑按钮**: 复用 `.header-btn`，图标为编辑铅笔，margin-left: auto，onclick 跳转 `page-agent-config`。

### 5.2 Profile Section（个人信息区）

**容器**: text-align: center, padding: `0 var(--s6) var(--s6)` = 0 24px 24px

**内部结构** (从上到下居中排列):

#### 5.2.1 Detail Avatar（详情头像）

| 属性 | 值 |
|---|---|
| 尺寸 | 72px x 72px |
| font-size | 36px |
| border-radius | `var(--r-lg)` = 16px |
| background | 根据虾 theme 映射 |
| margin | `0 auto var(--s4)` = 0 auto 16px |

#### 5.2.2 Detail Name（详情名称）

| 属性 | 值 |
|---|---|
| font-size | 24px |
| font-weight | 700 |
| margin-bottom | `var(--s1)` = 4px |
| letter-spacing | -0.5px |

#### 5.2.3 Detail Description（详情描述）

| 属性 | 值 |
|---|---|
| font-size | 14px |
| color | `var(--text-3)` |
| margin-bottom | `var(--s3)` = 12px |
| line-height | 1.5 |

#### 5.2.4 Detail Status（详情状态）

| 属性 | 值 |
|---|---|
| display | inline-flex, align-items: center |
| gap | `var(--s1)` = 4px |
| font-size | 13px |
| font-weight | 500 |
| color | 在线: `var(--green)` / 离线: `var(--text-4)` |

**内容**: `[状态点 6x6px] 在线/离线 · 所属实例名`

### 5.3 Stats Grid（数据网格）

**容器 `.stats-grid`**:

| 属性 | 值 |
|---|---|
| display | grid |
| grid-template-columns | repeat(3, 1fr) |
| gap | `var(--s3)` = 12px |
| padding | `0 var(--s6)` = 0 24px |
| margin-bottom | `var(--s6)` = 24px |

**数据卡片 `.stat-card`** (共 6 张，3列 x 2行):

| 属性 | 值 |
|---|---|
| background | `var(--surface)` |
| border-radius | `var(--r-md)` = 12px |
| padding | `var(--s5) var(--s3)` = 20px 12px |
| text-align | center |

| 元素 | 样式 |
|---|---|
| `.stat-value` | font-size: 24px, font-weight: 700, color: `var(--text-1)`, letter-spacing: -0.5px, font-variant-numeric: tabular-nums |
| `.stat-label` | font-size: 11px, color: `var(--text-3)`, margin-top: `var(--s1)` = 4px, letter-spacing: 0.3px, font-weight: 500 |

**6 个数据卡片内容**:
1. 对话（dialogs 数）
2. 消息（messages 数）
3. 工具（toolCalls 数）
4. 天数（days 数）
5. 连续（streak 数）
6. 首聊（firstDay 取 MM-DD 部分）

### 5.4 Achievement List（成就列表）

**Section Header**:
- font-size: 12px, font-weight: 600, color: `var(--text-3)`
- letter-spacing: 0.8px, text-transform: uppercase
- padding: `0 var(--s6) var(--s4)` = 0 24px 16px
- 文字: "成就"

**列表容器 `.achievement-list`**:
- padding: `0 var(--s6)` = 0 24px

**成就项 `.achievement`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| gap | `var(--s4)` = 16px |
| padding | `var(--s4) var(--s5)` = 16px 20px |
| background | `var(--surface)` |
| border-radius | `var(--r-md)` = 12px |
| margin-bottom | `var(--s2)` = 8px |
| transition | `all 200ms var(--ease)` |

**Locked 态** `.achievement.locked`: opacity: 0.35

**内部结构**: `[图标 40px] [信息区(flex:1)] [状态标签]`

#### 5.4.1 Achievement Icon（成就图标）`.ach-icon`

| 属性 | 值 |
|---|---|
| 尺寸 | 40px x 40px |
| border-radius | `var(--r-sm)` = 8px |
| display | flex, center |
| font-size | 20px |
| flex-shrink | 0 |

**类型背景**:
| class | background |
|---|---|
| `.ach-icon.gold` | `rgba(196,168,106,0.15)` |
| `.ach-icon.silver` | `rgba(245,244,240,0.06)` |
| `.ach-icon.bronze` | `var(--accent-muted)` |

#### 5.4.2 Achievement Info（成就信息）`.ach-info`

| 元素 | 样式 |
|---|---|
| `.ach-name` | font-size: 14px, font-weight: 600, letter-spacing: -0.1px |
| `.ach-desc` | font-size: 12px, color: `var(--text-3)`, margin-top: 1px, line-height: 1.4 |

#### 5.4.3 Achievement Status（成就状态标签）

- 已解锁: color `var(--green)`, font-size: 11px, font-weight: 600, letter-spacing: 0.2px, 文字 "已解锁"
- 未解锁: color `var(--text-4)`, font-size: 11px, 文字 "未解锁"

---

## 6. Page 5: 个性化配置（page-agent-config）

### 6.1 Header 区域

**结构**: `[返回按钮] [标题 "个性化配置"]`
- 标题 font-size: 22px
- 返回目标: `page-agent-detail`

**滚动内容区**: `padding: var(--s2) var(--s6) var(--s8)` = 8px 24px 40px

### 6.2 Config Section（配置分区）

**容器 `.config-section`**:
- margin-bottom: `var(--s7)` = 32px

**Section Title `.config-section-title`**:

| 属性 | 值 |
|---|---|
| font-size | 12px |
| font-weight | 600 |
| color | `var(--text-3)` |
| margin-bottom | `var(--s4)` = 16px |
| padding-left | `var(--s1)` = 4px |
| letter-spacing | 0.8px |
| text-transform | uppercase |
| display | flex, align-items: center, gap: `var(--s2)` = 8px |

**配置卡片 `.config-card`**:
- background: `var(--surface)`
- border-radius: `var(--r-lg)` = 16px
- padding: `var(--s5)` = 20px

### 6.3 Avatar Editor（头像编辑器）

**容器 `.config-avatar-area`**:
- display: flex, align-items: center
- gap: `var(--s5)` = 20px
- margin-bottom: `var(--s5)` = 20px

**Config Avatar `.config-avatar`**:

| 属性 | 值 |
|---|---|
| 尺寸 | 64px x 64px |
| border-radius | `var(--r-lg)` = 16px |
| display | flex, center |
| font-size | 30px |
| cursor | pointer |
| background | 根据虾 theme 映射 |
| transition | `all 200ms var(--ease)` |

**Press 态**: transform: scale(0.95)

**Edit Badge（编辑标记）`.edit-badge`**:

| 属性 | 值 |
|---|---|
| position | absolute, bottom: -3px, right: -3px |
| 尺寸 | 22px x 22px |
| border-radius | `var(--r-sm)` = 8px |
| background | `var(--accent)` |
| color | `#fff` |
| font-size | 10px |
| display | flex, center |
| border | `2px solid var(--surface)` |
| font-weight | 700 |
| 内容 | "✎" (编辑图标) |

**点击行为**: `changeAvatar()` — 从预设 emoji 数组中循环切换下一个 emoji：
```
['🦐','🎯','💻','🎨','🌍','✍️','📊','🔧','🤖','🚀','⚡','🌟','🔮','🎪','🦄','🐙','🧠','🎭','🔬','🎵']
```
切换后显示 Toast "头像已更换为 {emoji}"。

**Avatar Info（头像信息区）`.config-avatar-info`**:

| 元素 | 样式 |
|---|---|
| `.config-avatar-name` | font-size: 20px, font-weight: 700, letter-spacing: -0.3px |
| `.config-avatar-hint` | font-size: 12px, color: `var(--text-4)`, margin-top: 2px, 文字 "点击头像更换表情" |

### 6.4 Nickname/Desc Input Fields（昵称/简介输入）

**Input Row `.config-input-row`**:
- display: flex, align-items: center
- gap: `var(--s4)` = 16px
- margin-bottom: `var(--s4)` = 16px
- 最后一行: margin-bottom: 0

| 元素 | 样式 |
|---|---|
| `.config-label` | font-size: 13px, color: `var(--text-3)`, width: 52px, flex-shrink: 0, font-weight: 500 |
| `.config-input` | flex: 1, height: 44px, border-radius: `var(--r-sm)` = 8px, background: `var(--surface2)`, color: `var(--text-1)`, padding: `0 var(--s4)` = 0 16px, font-size: 15px, outline: none, box-shadow: `inset 0 0 0 1px var(--surface3)` |

**Focus 态**: box-shadow 变为 `inset 0 0 0 1px var(--accent)`

**Placeholder**: color `var(--text-4)`

**两个字段**:
1. Label: "昵称", placeholder: "给你的虾取个名字", value: agent.name
2. Label: "简介", placeholder: "描述一下这只虾的专长", value: agent.desc

### 6.5 Color Grid（主题色选择器）

**容器 `.color-grid`**:

| 属性 | 值 |
|---|---|
| display | grid |
| grid-template-columns | repeat(6, 1fr) |
| gap | `var(--s3)` = 12px |
| padding | `var(--s1) 0` = 4px 0 |

**颜色点 `.color-dot`**:

| 属性 | 值 |
|---|---|
| 尺寸 | 40px x 40px |
| border-radius | `var(--r-sm)` = 8px |
| cursor | pointer |
| border | `3px solid transparent` |
| display | flex, center |
| transition | `all 200ms var(--ease)` |

**Press 态**: transform: scale(0.9)

**Selected 态** `.color-dot.selected`:
- border-color: `var(--text-1)`
- box-shadow: `0 0 16px rgba(245,244,240,0.15)`
- 内部显示白色对勾: `::after { content: '✓'; color: #fff; font-size: 14px; font-weight: 800; text-shadow: 0 1px 3px rgba(0,0,0,0.4); }`

**行为**: 点击切换选中状态（单选），同时更新 avatar 的 background 和 border-color 预览。

**12 种颜色**: 珊瑚、雾蓝、薄荷、暖橙、烟粉、湖蓝、暖黄、玫瑰、石墨、翡翠、靛蓝、焦糖（详见 1.1 Theme Color Map）。

### 6.6 Command List（快捷指令列表）

**容器 `.cmd-list`**:
- display: flex, flex-direction: column
- gap: `var(--s2)` = 8px

**指令项 `.cmd-item`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| gap | `var(--s3)` = 12px |
| padding | `var(--s3) var(--s4)` = 12px 16px |
| background | `var(--surface2)` |
| border-radius | `var(--r-sm)` = 8px |
| transition | `all 200ms var(--ease)` |

**内部结构**: `[拖拽手柄] [标签输入(flex:1)] [命令输入 88px] [删除按钮 28px]`

#### 6.6.1 Drag Handle（拖拽手柄）`.cmd-handle`

| 属性 | 值 |
|---|---|
| color | `var(--text-4)` |
| cursor | grab |
| font-size | 14px |
| user-select | none |
| 内容 | "⋮⋮" |

#### 6.6.2 Label Input（标签输入）`.cmd-label-input`

| 属性 | 值 |
|---|---|
| flex | 1 |
| background | transparent |
| border | none |
| color | `var(--text-1)` |
| font-size | 14px |
| font-weight | 500 |
| outline | none |

#### 6.6.3 Command Input（命令输入）`.cmd-cmd-input`

| 属性 | 值 |
|---|---|
| width | 88px |
| background | `var(--surface3)` |
| border | none |
| color | `var(--accent)` |
| font-size | 12px |
| padding | `var(--s1) var(--s3)` = 4px 12px |
| border-radius | `var(--r-sm)` = 8px |
| outline | none |
| font-family | `"SF Mono", monospace` |
| text-align | right |

#### 6.6.4 Delete Button（删除按钮）`.cmd-delete`

| 属性 | 值 |
|---|---|
| 尺寸 | 28px x 28px |
| border-radius | `var(--r-sm)` = 8px |
| background | transparent |
| border | none |
| color | `var(--text-4)` |
| cursor | pointer |
| display | flex, center |
| transition | `all 200ms var(--ease)` |
| 图标 | 14x14px X 符号, stroke-width: 2 |

**Hover/Press 态**: color `var(--red)`, background `var(--red-muted)`

**删除动画**: item 整体 transition 250ms `var(--ease)` -> opacity: 0, transform: translateX(16px) -> 250ms 后 remove()

#### 6.6.5 Add Command Button（添加指令按钮）`.cmd-add-btn`

| 属性 | 值 |
|---|---|
| display | flex, center |
| gap | `var(--s2)` = 8px |
| padding | `var(--s3)` = 12px |
| background | transparent |
| border | none |
| border-radius | `var(--r-sm)` = 8px |
| color | `var(--accent)` |
| font-size | 13px |
| font-weight | 600 |
| cursor | pointer |
| margin-top | `var(--s2)` = 8px |

**Press 态**: background `var(--accent-muted)`

**行为**: 追加一条空指令（label: '', cmd: '/'），自动 focus 到 label input。

### 6.7 Save Button（保存按钮）`.config-save-btn`

| 属性 | 值 |
|---|---|
| width | 100% |
| height | 52px |
| border-radius | `var(--r-md)` = 12px |
| border | none |
| background | `var(--accent)` |
| color | `#fff` |
| font-size | 15px |
| font-weight | 600 |
| cursor | pointer |
| letter-spacing | -0.1px |
| box-shadow | `0 4px 20px var(--accent-glow)` |
| margin-top | `var(--s4)` = 16px |

**Press 态**: transform: scale(0.97), filter: brightness(0.92)

**行为**:
1. 收集 nickname、desc、selectedTheme、cmds、avatar emoji
2. 更新 currentAgent 数据
3. 显示 Toast "配置已保存"
4. 600ms 后跳转 `page-agent-detail`
5. 同步刷新 statsBar、agentList、messageList

---

## 7. Page 6: 实例管理（page-instances）

### 7.1 Header 区域

**结构**: `[标题 "实例"]`（无返回按钮，主 Tab 页）

### 7.2 Instance Card（实例卡片）

**列表容器 `.instance-mgmt`**:
- padding: `0 var(--s6)` = 0 24px

**卡片 `.inst-card`**:

| 属性 | 值 |
|---|---|
| display | flex, align-items: center |
| padding | `var(--s5)` = 20px |
| background | `var(--surface)` |
| border-radius | `var(--r-lg)` = 16px |
| margin-bottom | `var(--s3)` = 12px |
| gap | `var(--s4)` = 16px |
| transition | `all 200ms var(--ease)` |

**Press 态**: transform: scale(0.98)

**内部结构**: `[图标 44px] [信息区(flex:1)] [操作按钮组]`

#### 7.2.1 Instance Icon（实例图标）`.inst-icon`

| 属性 | 值 |
|---|---|
| 尺寸 | 44px x 44px |
| border-radius | `var(--r-md)` = 12px |
| background | `var(--surface2)` |
| display | flex, center |
| font-size | 22px |
| flex-shrink | 0 |

#### 7.2.2 Instance Info（实例信息）`.inst-info`

| 属性 | 值 |
|---|---|
| flex | 1 |
| min-width | 0 |

| 元素 | 样式 |
|---|---|
| `.inst-name` | font-size: 16px, font-weight: 600, letter-spacing: -0.2px |
| `.inst-url` | font-size: 13px, color: `var(--text-3)`, margin-top: 2px, white-space: nowrap, overflow: hidden, text-overflow: ellipsis, font-family: `"SF Mono", monospace`, letter-spacing: -0.3px |
| `.inst-status` | display: flex, align-items: center, gap: `var(--s1)` = 4px, font-size: 12px, margin-top: `var(--s1)` = 4px, color: `var(--text-3)` |

**Status dot**: 6x6px, border-radius: 999px; 在线: `var(--green)` / 离线: `var(--text-4)`
**Status 文字**: 在线时绿色"在线" / 离线时三级色"离线"
**虾计数**: `· {count} 只虾`，color: `var(--text-4)`

#### 7.2.3 Instance Actions（实例操作按钮组）`.inst-actions`

| 属性 | 值 |
|---|---|
| display | flex, gap: `var(--s2)` = 8px |

**Action Button `.inst-action-btn`**:

| 属性 | 值 |
|---|---|
| 尺寸 | 36px x 36px |
| border-radius | `var(--r-sm)` = 8px |
| background | `var(--surface2)` |
| border | none |
| color | `var(--text-3)` |
| display | flex, center |
| cursor | pointer |
| 图标 | 16x16px 对勾符号, stroke-width: 1.5 |
| transition | `all 200ms var(--ease)` |

**Press 态**: background `var(--surface3)`, color `var(--text-2)`

**行为**: 显示 Toast "正在测试连通性..."

### 7.3 Add Instance Button（添加实例按钮）`.add-inst-btn`

| 属性 | 值 |
|---|---|
| display | flex, center |
| gap | `var(--s3)` = 12px |
| padding | `var(--s5)` = 20px |
| background | transparent |
| border-radius | `var(--r-lg)` = 16px |
| margin-bottom | `var(--s3)` = 12px |
| cursor | pointer |
| color | `var(--accent)` |
| font-size | 14px |
| font-weight | 600 |
| letter-spacing | -0.1px |
| position | relative |

**虚线边框**: 通过 `::before` 伪元素实现
```css
.add-inst-btn::before {
  content: '';
  position: absolute;
  inset: 0;
  border: 1.5px dashed var(--surface3);
  border-radius: var(--r-lg);
  transition: border-color 200ms var(--ease);
}
```

**Press 态**: `::before` border-color 变为 `var(--accent)`

**内容**: [+] 图标(20x20px) + "添加新实例"

**行为**: onclick 跳转 `page-add-instance`

### 7.4 Bottom Navigation

与 page-home 相同结构，Active tab 为 "实例"。

---

## 8. Page 7: 添加实例（page-add-instance）

### 8.1 Header 区域

**结构**: `[返回按钮] [标题 "添加实例"]`
- 返回目标: `page-instances`

### 8.2 Tab Switcher（标签切换器）

**容器 `.tab-row`**:

| 属性 | 值 |
|---|---|
| display | flex, gap: 0 |
| margin-bottom | `var(--s6)` = 24px |
| background | `var(--surface)` |
| border-radius | `var(--r-md)` = 12px |
| padding | 3px |

**Tab Item `.tab-item`**:

| 属性 | 值 |
|---|---|
| flex | 1 |
| text-align | center |
| padding | `var(--s3)` = 12px |
| border-radius | `var(--r-sm)` = 8px |
| font-size | 14px |
| font-weight | 600 |
| cursor | pointer |
| color | `var(--text-3)` |
| transition | `all 200ms var(--ease)` |

**Active 态** `.tab-item.active`:
- background: `var(--accent)`
- color: `#fff`

**两个 Tab**:
1. "扫码添加" — 控制 `addTab-scan` 显示
2. "手动添加" — 控制 `addTab-manual` 显示

**切换行为**: toggle active class，切换对应内容 div 的 display

### 8.3 Scan Tab（扫码标签页）

**QR Scanner Mock**:

| 属性 | 值 |
|---|---|
| 尺寸 | 200px x 200px |
| margin | `0 auto` |
| background | `var(--surface)` |
| border-radius | `var(--r-xl)` = 20px |
| display | flex, flex-direction: column, center |

**QR 图标**: 48x48px SVG, stroke: `var(--text-4)`, stroke-width: 1.2
**提示文字**: color `var(--text-3)`, font-size: 13px, font-weight: 500, margin-top: `var(--s4)`, 内容 "将二维码放入框内"

**Primary Button**:
- margin-top: `var(--s6)` = 24px
- 复用 `.primary-btn` 样式
- 文字: "模拟扫码成功"
- 行为: 触发 simulateScan()

**Help Text**:
- font-size: 12px, color: `var(--text-4)`, margin-top: `var(--s3)`, line-height: 1.5
- 内容: "在 OpenClaw 终端运行 `openclaw pair` 获取二维码"
- `code`: background `var(--surface)`, padding `2px 8px`, border-radius `var(--r-sm)`, font-size: 12px

### 8.4 Manual Tab（手动添加标签页）

**Form Group `.form-group`**:
- margin-bottom: `var(--s5)` = 20px

**Form Label `.form-label`**:

| 属性 | 值 |
|---|---|
| font-size | 12px |
| font-weight | 600 |
| color | `var(--text-2)` |
| margin-bottom | `var(--s2)` = 8px |
| display | block |
| letter-spacing | 0.5px |
| text-transform | uppercase |

**Form Input `.form-input`**:

| 属性 | 值 |
|---|---|
| width | 100% |
| height | 48px |
| border-radius | `var(--r-md)` = 12px |
| border | none |
| background | `var(--surface)` |
| color | `var(--text-1)` |
| padding | `0 var(--s5)` = 0 20px |
| font-size | 15px |
| outline | none |
| box-shadow | `inset 0 0 0 1.5px var(--surface3)`（内描边） |
| transition | `all 200ms var(--ease)` |

**Focus 态**: box-shadow 变为 `inset 0 0 0 1.5px var(--accent)`, background 变为 `var(--surface2)`

**Placeholder**: color `var(--text-4)`

**Form Hint `.form-hint`**:
- font-size: 12px, color: `var(--text-4)`, margin-top: `var(--s1)` = 4px, line-height: 1.4

**三个表单字段**:
1. Label: "实例名称", placeholder: "如：我的 MacBook"
2. Label: "Gateway URL", placeholder: "ws://192.168.1.100:18789", hint: "支持 ws:// 和 wss:// 协议"
3. Label: "访问 Token", placeholder: "粘贴你的 Gateway Token", type: password, hint: "Token 将加密后存储在本地安全存储中"

**Connect Button**:
- 复用 `.primary-btn` 样式
- 文字: "连接测试"
- 行为: `addInstanceManual()` -> 校验字段 -> Toast "正在连接 {name}..." -> 1500ms 后 Toast "连接成功" -> 800ms 后跳转 `page-instances`

**Validation 规则**:
- 实例名称不能为空
- Gateway URL 必须以 `ws://` 或 `wss://` 开头
- Token 不能为空

---

## 9. Page 8: 设置（page-settings）

### 9.1 Header 区域

**结构**: `[返回按钮] [标题 "设置"]`
- 标题 font-size: 22px
- 返回目标: `page-home`

### 9.2 Settings Container

**外层容器**:
- background: `var(--surface)`
- border-radius: `var(--r-lg)` = 16px
- overflow: hidden

**内容 padding**: `var(--s2) var(--s6)` = 8px 24px（scroll content）

### 9.3 Setting Row（设置行）`.setting-row`

| 属性 | 值 |
|---|---|
| display | flex, align-items: center, justify-content: space-between |
| padding | `var(--s5) var(--s5)` = 20px 20px |
| cursor | pointer |
| font-size | 15px |
| border-bottom | `1px solid rgba(245,244,240,0.04)` |
| transition | `background 200ms var(--ease)` |

**最后一行**: border-bottom: none

**Press 态**: background `var(--surface2)`

**内部结构**: `[左侧: emoji + 标签] [右侧: 当前值]`

**左侧**: 直接文本，含 emoji 前缀
**右侧值**: color `var(--text-3)`

**6 个设置项**:

| 项目 | 图标 | 标签 | 右侧值 | 点击行为 |
|---|---|---|---|---|
| 1 | 🔔 | 通知设置 | 已开启 | Toast "通知已开启" |
| 2 | 🌙 | 免打扰时段 | 22:00 — 08:00 | Toast "免打扰时段：22:00 — 08:00" |
| 3 | 🔐 | 生物识别解锁 | Face ID | Toast "已开启 Face ID 解锁" |
| 4 | 🌐 | 网络设置 | WiFi | Toast "当前使用 WiFi 连接" |
| 5 | 💾 | 存储管理 | 12.3 MB | Toast "已使用 12.3 MB / 500 MB" |
| 6 | ℹ️ | 关于虾Hub | v1.0 | Toast "虾Hub v1.0 Premium Edition" |

### 9.4 Footer（页脚信息）

| 属性 | 值 |
|---|---|
| text-align | center |
| padding | `var(--s7) var(--s6)` = 32px 24px |
| color | `var(--text-4)` |
| font-size | 12px |
| line-height | 1.8 |
| letter-spacing | 0.2px |

**内容**:
```
虾Hub — 你的 AI 虾群移动管理中心
Powered by OpenClaw Gateway Protocol
```

---

## 10. Cross-Cutting 全局交互规范

### 10.1 Page Transition（页面转场）

**实现方式**: 通过 CSS class 切换 + transition

| CSS Class | transform | opacity | pointer-events | 用途 |
|---|---|---|---|---|
| `.page` (默认) | none | 1 | auto | 当前可见页 |
| `.page.hidden` | `translateX(100%)` | 0 | none | 目标页在右侧（正向导航前的隐藏态） |
| `.page.hidden-left` | `translateX(-30%)` | 0 | none | 当前页在左侧（被新页推开） |

**Transition 参数**:
- transform: `500ms var(--ease)` = `500ms cubic-bezier(0.16, 1, 0.3, 1)`（expo-out）
- opacity: `350ms var(--ease)`

**页面层级顺序 `pageOrder`**:
```
page-home -> page-messages -> page-chat -> page-agent-detail -> page-agent-config -> page-instances -> page-add-instance -> page-settings
```

**转场逻辑**:
- 目标页 index > 当前页 index: 当前页添加 `hidden-left`（向左推出），目标页变为 `page`（从右侧滑入）
- 目标页 index < 当前页 index: 当前页添加 `hidden`（向右推出），目标页变为 `page`（从左侧滑入）

**will-change**: `transform, opacity`（GPU 加速）

### 10.2 Smart Return（智能返回）

**核心变量**: `lastMainTab` — 记录用户最后所在的主 Tab 页

**逻辑**:
- `navTo(pageId)` 调用时更新 `lastMainTab = pageId`
- 从 chat 页面返回时: `showPage(lastMainTab); updateNavActive(lastMainTab)`
- 确保从消息页进入聊天后返回消息页，从虾列表进入后返回虾列表

**主 Tab 列表**: `['page-home', 'page-messages', 'page-instances']`
- 切换到主 Tab 时同步更新所有 bottom nav 组件的 active 状态

### 10.3 Toast Notification（轻提示）

**容器 `.toast`**:

| 属性 | 值 |
|---|---|
| position | absolute, top: 72px, left: 50% |
| transform | `translateX(-50%) translateY(-20px)`（初始） |
| background | `var(--surface-elevated)` |
| color | `var(--text-1)` |
| padding | `var(--s3) var(--s6)` = 12px 24px |
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

**Transition**: `all 350ms var(--ease)`

**Auto-dismiss**: 2500ms 后自动移除 `.show` class
**Queue 机制**: 新 Toast 清除旧 timer，确保不冲突

### 10.4 Connection Banner（连接状态横幅）

**容器 `.conn-banner`**:

| 属性 | 值 |
|---|---|
| position | absolute, top: 54px, left: 0, right: 0 |
| padding | `var(--s2) var(--s6)` = 8px 24px |
| font-size | 13px |
| font-weight | 500 |
| text-align | center |
| z-index | 40 |
| transform | `translateY(-100%)`（默认隐藏） |
| transition | `transform 350ms var(--ease)` |

**显示态** `.conn-banner.show`: transform: `translateY(0)`

**类型**:
| class | background | color |
|---|---|---|
| `.warning` | `rgba(196,168,106,0.12)` | `var(--yellow)` |
| `.info` | `var(--accent-muted)` | `var(--accent)` |

### 10.5 Touch Swipe Gesture（触摸滑动手势）

**绑定范围**: `page-chat` 元素

**TouchStart**: 记录 `touchStartX = e.touches[0].clientX`
**TouchEnd**: 计算 `diff = e.changedTouches[0].clientX - touchStartX`

**触发条件**:
- `diff > 80px`（向右滑动超过 80px）
- `touchStartX < 40px`（从左边缘 40px 内开始）

**触发行为**: `showPage(lastMainTab); updateNavActive(lastMainTab)` — 与 back button 行为一致

**Event options**: `{passive: true}`（不阻止默认行为）

### 10.6 Empty State（空状态）

**容器 `.empty-state`**:

| 属性 | 值 |
|---|---|
| display | flex, flex-direction: column, center |
| padding | `var(--s9) var(--s6)` = 48px 24px |
| color | `var(--text-4)` |

| 元素 | 样式 |
|---|---|
| `.emoji` | font-size: 48px, margin-bottom: `var(--s5)` = 20px, opacity: 0.7 |
| `.title` | font-size: 17px, font-weight: 600, color: `var(--text-2)`, margin-bottom: `var(--s2)` = 8px |
| `.desc` | font-size: 14px, color: `var(--text-3)`, text-align: center, line-height: 1.6 |

**虾列表空状态**: emoji "🦐", title "还没有虾", desc "添加一个 OpenClaw 实例开始养虾之旅"

---

## 11. Edge Cases 与异常状态

### 11.1 Agent Card 文字溢出

- `.agent-desc`: 单行截断，`text-overflow: ellipsis`
- `.agent-name`: 不截断，允许换行（line-height: 1.3）

### 11.2 Message Preview 截断

- 消息预览去除所有 Markdown 标记后截断至 38 字符
- 换行符替换为空格
- 截断后追加 `...`

### 11.3 离线虾处理

- 头像 status-dot 显示灰色 `var(--text-4)`
- 实例分组头 dot 无 box-shadow
- 聊天页发送消息时检测 online 状态，离线时显示 Toast "该虾当前离线，消息将在重连后发送"

### 11.4 Chat 消息入场

- 每条消息使用 `msgIn` 动画: `opacity:0, translateY(12px)` -> `opacity:1, translateY(0)`
- 动画时长: 350ms `var(--ease)`
- 仅新渲染的消息触发动画，历史消息不重播

### 11.5 Auto-scroll 行为

- 发送消息后: `setTimeout(() => el.scrollTop = el.scrollHeight, 60)` 滚动到底部
- 打开聊天后: `setTimeout(() => scrollChat(), 100)` 滚动到底部
- Typing indicator 出现后也触发 scroll

### 11.6 输入框自动增长

```javascript
function autoResize(el) {
  el.style.height = 'auto';
  el.style.height = Math.min(el.scrollHeight, 100) + 'px';
}
```
- 最大高度: 100px
- 超过后输入框内部可滚动

### 11.7 Form Input Inset Border

表单输入框使用 `box-shadow: inset` 替代 border 实现内描边：
- 默认: `inset 0 0 0 1.5px var(--surface3)`
- Focus: `inset 0 0 0 1.5px var(--accent)`
- 优势: 不增加盒模型尺寸，避免布局偏移

### 11.8 Token 安全处理

- 输入 type: password
- PRD 要求: Token 以加密形式存储在 iOS Keychain / Android Keystore
- 不在界面明文展示 Token 值

### 11.9 实例连通性测试流程

1. 点击"连接测试"按钮
2. Toast: "正在连接 {name}..."
3. 模拟 1500ms 延迟
4. 成功: Toast "连接成功！已添加到实例列表" -> 800ms 后跳转 `page-instances`
5. 失败（校验不通过）: 对应字段 Toast 提示

### 11.10 扫码流程

1. 点击"模拟扫码成功"
2. Toast: "扫码成功！发现实例：我的 MacBook Pro"
3. 1200ms 后 Toast: "连接测试通过，已添加到实例列表"
4. 800ms 后跳转 `page-instances`

### 11.11 Primary Button（通用主按钮）`.primary-btn`

| 属性 | 值 |
|---|---|
| width | 100% |
| height | 52px |
| border-radius | `var(--r-md)` = 12px |
| border | none |
| background | `var(--accent)` |
| color | `#fff` |
| font-size | 15px |
| font-weight | 600 |
| cursor | pointer |
| letter-spacing | -0.1px |
| box-shadow | `0 4px 20px var(--accent-glow)` |

**Press 态**: transform: scale(0.97), filter: brightness(0.92)

### 11.12 Secondary Button（通用次按钮）`.secondary-btn`

| 属性 | 值 |
|---|---|
| width | 100% |
| height | 52px |
| border-radius | `var(--r-md)` = 12px |
| border | none |
| background | transparent |
| color | `var(--text-2)` |
| font-size | 15px |
| font-weight | 500 |
| cursor | pointer |
| margin-top | `var(--s2)` = 8px |

**Press 态**: background `var(--surface)`

---

## 附录 A: 完整组件尺寸速查表

| 组件 | 宽 | 高 | 圆角 | 图标尺寸 |
|---|---|---|---|---|
| Agent Avatar (列表) | 48px | 48px | 12px | 24px |
| Agent Avatar (聊天头) | 40px | 40px | 8px | 18px |
| Agent Avatar (详情) | 72px | 72px | 16px | 36px |
| Agent Avatar (配置) | 64px | 64px | 16px | 30px |
| Agent Avatar (消息列表) | 48px | 48px | 12px | 22px |
| Status Dot | 8px | 8px | 999px | — |
| Status Dot (头部/分组) | 6px | 6px | 999px | — |
| Header Button | 40px | 40px | 12px | 20px |
| Back Button | 40px | 40px | 12px | 22px |
| Instance Icon | 44px | 44px | 12px | 22px |
| Achievement Icon | 40px | 40px | 8px | 20px |
| Instance Action Button | 36px | 36px | 8px | 16px |
| Nav Item Icon | — | — | — | 22px |
| Plus/Send Button | 40px | 40px | 12px | 20px/18px |
| Color Dot | 40px | 40px | 8px | — |
| Edit Badge | 22px | 22px | 8px | 10px |
| Unread Badge | min 18px | 18px | 999px | — |
| Delete Button (cmd) | 28px | 28px | 8px | 14px |
| Form Input | 100% | 48px | 12px | — |
| Config Input | flex:1 | 44px | 8px | — |
| Command Input | 88px | auto | 8px | — |
| Primary Button | 100% | 52px | 12px | — |
| Secondary Button | 100% | 52px | 12px | — |
| Save Button | 100% | 52px | 12px | — |
| Bottom Nav | 100% | 72px | — | — |
| QR Scanner Mock | 200px | 200px | 20px | 48px |
| Chat Bubble | max 78% | auto | 20px (corner: 8px) | — |

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
                │      ┌────┘        │
                │      │             │
                └──┬───┘             │
                   ▼                 ▼
              page-chat        page-add-instance
                   │
                   ▼
           page-agent-detail
                   │
                   ▼
           page-agent-config

        page-home ──(header btn)──> page-settings
        page-msg  ──(header btn)──> page-settings
```

## 附录 C: 开发注意事项

1. **所有 padding/margin 值必须使用 Design Token CSS 变量**，禁止硬编码像素值，确保主题系统可维护。

2. **font-variant-numeric: tabular-nums** 应用于所有数字展示（统计值、时间戳、消息数），确保等宽数字对齐。

3. **Safe Area 适配**: 所有底部固定元素必须加上 `var(--safe-bottom)`，适配 iPhone 刘海屏。

4. **Touch 优化**: 所有可点击元素设置 `-webkit-tap-highlight-color: transparent`（已在全局 Reset 中设置）。

5. **性能**: 页面使用 `will-change: transform, opacity` 进行 GPU 加速。消息列表超过 50 条时应实现虚拟滚动。

6. **无障碍**: 所有按钮需有 `title` 属性或 `aria-label`。颜色对比度需满足 WCAG AA 标准（深色模式下尤其注意 `--text-3` 和 `--text-4` 的对比度）。

7. **动效降级**: 需尊重用户的 `prefers-reduced-motion` 系统设置，在该设置开启时禁用所有 transition 和 animation。

8. **消息气泡圆角规律**: 用户消息右下角收尖（8px），虾消息左下角收尖（8px），其余三角保持 20px。这是区分消息方向的关键视觉线索。

---

*文档结束。所有标注均基于原型 Demo 的 CSS 精确提取，如有设计变更以最新 Figma 为准。*
