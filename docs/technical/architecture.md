# 技术架构与组件拆解文档：虾Hub（XiaHub）

**版本**：v1.0
**日期**：2026-06-10
**来源**：PRD v1.1 / UserStory v1.0 / Premium 原型
**状态**：初稿

---

## 目录

1. [技术选型建议](#1-技术选型建议-tech-stack-recommendation)
2. [项目结构](#2-项目结构-project-structure)
3. [组件树](#3-组件树-component-tree)
4. [数据模型](#4-数据模型-data-models)
5. [状态管理](#5-状态管理-state-management)
6. [WebSocket 通信层](#6-websocket-通信层-websocket-communication)
7. [本地存储](#7-本地存储-local-storage)
8. [导航架构](#8-导航架构-navigation)
9. [设计系统集成](#9-设计系统集成-design-system-integration)
10. [开发里程碑](#10-开发里程碑-development-milestones)

---

## 1. 技术选型建议 (Tech Stack Recommendation)

### 1.1 跨平台框架对比

| 维度 | Flutter | React Native | 原生 (Swift + Kotlin) |
|------|---------|-------------|---------------------|
| **跨平台能力** | 单一代码库覆盖 iOS/Android，渲染引擎自绘，UI 一致性极高 | 桥接原生组件，两端 UI 可能存在差异 | 需分别维护两套代码库，开发成本翻倍 |
| **WebSocket 支持** | `web_socket_channel` 成熟稳定，支持 wss://，dart:io 底层控制精细 | `ws` / `react-native-websocket` 依赖 JS Bridge，高并发场景性能有瓶颈 | 原生 URLSessionWebSocketTask / OkHttp WebSocket，性能最佳但需双端实现 |
| **Premium UI 控制** | Skia 引擎像素级控制，自绘任意 Widget，动画性能优异（60fps） | 依赖原生组件渲染，深度定制需要编写 Native Module | 完全控制，但需要双端各实现一遍 |
| **安全存储** | `flutter_secure_storage` 封装 Keychain/Keystore，API 统一 | 需自行桥接 Keychain/Keystore，社区库质量参差 | 直接调用系统 API，最可靠 |
| **本地数据库** | Hive（NoSQL）、sqflite/Drift（SQLite）生态完善 | AsyncStorage + SQLite 插件，稳定性一般 | Core Data / Room，各自最优但不可复用 |
| **开发效率** | Hot Reload + Widget Inspector，单人开发效率高 | Hot Reload + 丰富生态，前端开发者上手快 | 无跨平台复用，单人开发周期长 |
| **包体积** | 引擎约 4-6MB，总体可控 | Bridge + Runtime 约 3-5MB | 最小，无额外运行时 |
| **社区与生态** | 2026 年持续增长，插件市场丰富 | 社区庞大，但核心库维护状态不稳定 | 各自生态完善，但无跨平台共享 |
| **性能表现** | 接近原生（自绘引擎），长列表/动画场景表现优秀 | JS Bridge 开销，高频 WebSocket 消息场景可能成为瓶颈 | 最优 |
| **学习曲线** | Dart 语言 + Widget 范式，中等 | JavaScript/TypeScript + React 范式，前端开发者低 | Swift + Kotlin 双语言，高 |

### 1.2 推荐方案：Flutter

**核心决策理由**：

1. **跨平台 UI 一致性**：虾Hub 是暗色主题 + 高度定制的 Premium UI，Flutter 自绘引擎确保 iOS/Android 完全一致的视觉表现，不受原生组件差异影响。
2. **WebSocket 精细控制**：多实例并行 WebSocket 连接是核心技术挑战。Dart 的 `dart:io` WebSocket 提供底层控制能力（心跳间隔、连接超时、二进制帧），优于 RN 的 JS Bridge 方案。
3. **动画与滚动性能**：对话页面的消息列表、成长面板的庆祝动画、虾列表的虚拟滚动等场景，Flutter 的 Skia 引擎提供稳定的 60fps 表现。
4. **单人开发效率**：PRD 规划为 1 名全栈开发者，Flutter 的单一代码库 + Hot Reload 最大化开发效率。
5. **安全存储统一 API**：`flutter_secure_storage` 屏蔽了 iOS Keychain 和 Android Keystore 的差异，Token 加密存储开箱即用。

### 1.3 核心依赖清单

| 类别 | 包名 | 版本建议 | 用途 |
|------|------|---------|------|
| **WebSocket** | `web_socket_channel` | ^3.0 | WebSocket 客户端连接管理 |
| **安全存储** | `flutter_secure_storage` | ^9.0 | Token、敏感配置加密存储（Keychain/Keystore） |
| **本地数据库** | `drift` (原 moor) | ^2.18 | SQLite ORM，消息持久化、对话历史、统计数据 |
| **KV 存储** | `hive_ce` | ^2.5 | 轻量键值存储，Agent 缓存、用户偏好 |
| **状态管理** | `flutter_riverpod` | ^2.5 | 响应式状态管理，Provider 依赖注入 |
| **路由导航** | `go_router` | ^14.0 | 声明式路由、Deep Link、路由守卫 |
| **Markdown 渲染** | `flutter_markdown` | ^0.7 | Agent 消息的 Markdown 渲染（代码高亮、表格） |
| **代码高亮** | `highlight` + `flutter_highlight` | ^0.7 | 代码块语法高亮 |
| **二维码扫描** | `mobile_scanner` | ^5.0 | 扫描 OpenClaw 配置二维码 |
| **图片选择** | `image_picker` | ^1.0 | 虾头像选择（相册/拍照） |
| **网络信息** | `connectivity_plus` | ^6.0 | 网络状态监听，触发重连策略 |
| **本地通知** | `flutter_local_notifications` | ^17.0 | 任务完成推送、状态变化提醒 |
| **生物识别** | `local_auth` | ^2.2 | Face ID / 指纹解锁 |
| **UUID** | `uuid` | ^4.0 | 生成请求 ID、消息 ID |
| **国际化** | `flutter_localizations` + `intl` | 内置 | i18n 框架预留（MVP 仅中文） |

---

## 2. 项目结构 (Project Structure)

### 2.1 目录架构

采用 **Feature-First** 架构，每个功能模块自包含（页面、Widget、状态、模型、服务），`core/` 和 `shared/` 提供横切关注点。

```
xia_hub/
├── android/                          # Android 原生工程
├── ios/                              # iOS 原生工程
├── assets/
│   ├── fonts/                        # 自定义字体（SF Pro 回退到系统默认）
│   ├── icons/                        # SVG/PNG 图标资源
│   ├── animations/                   # Lottie 动画文件（庆祝、加载等）
│   └── images/                       # 图片资源
│
├── lib/
│   ├── main.dart                     # 应用入口，ProviderScope + GoRouter 初始化
│   ├── app.dart                      # MaterialApp.router 配置，Theme 注入
│   │
│   ├── core/                         # ===== 核心基础设施 =====
│   │   ├── theme/
│   │   │   ├── app_theme.dart        # ThemeData 定义（暗色主题，映射 Design Tokens）
│   │   │   ├── design_tokens.dart    # 设计令牌 Dart 常量类（颜色、间距、圆角、阴影）
│   │   │   ├── text_styles.dart      # TextStyle 扩展（标题、正文、标签等）
│   │   │   └── agent_themes.dart     # 12 色 Agent 主题色映射表
│   │   │
│   │   ├── network/
│   │   │   ├── ws_connection.dart    # 单实例 WebSocket 连接封装
│   │   │   ├── ws_manager.dart       # 多实例 WebSocket 连接管理器
│   │   │   ├── ws_protocol.dart      # OpenClaw Gateway 协议解析/构建
│   │   │   ├── ws_message.dart       # WebSocket 消息类型定义
│   │   │   └── reconnect_policy.dart # 指数退避重连策略
│   │   │
│   │   ├── storage/
│   │   │   ├── database.dart         # Drift 数据库定义（表结构、迁移）
│   │   │   ├── daos/
│   │   │   │   ├── instance_dao.dart # 实例配置 CRUD
│   │   │   │   ├── message_dao.dart  # 消息记录 CRUD + 全文搜索
│   │   │   │   ├── agent_dao.dart    # Agent 信息缓存
│   │   │   │   └── stats_dao.dart    # 统计数据聚合查询
│   │   │   ├── secure_storage.dart   # flutter_secure_storage 封装
│   │   │   └── hive_storage.dart     # Hive 偏好设置存储
│   │   │
│   │   ├── utils/
│   │   │   ├── logger.dart           # 统一日志工具
│   │   │   ├── time_utils.dart       # 时间格式化（今天显示时分，更早显示日期）
│   │   │   ├── validators.dart       # URL 校验、名称校验
│   │   │   └── crypto_utils.dart     # 设备 ID 生成、Token 哈希
│   │   │
│   │   └── constants/
│   │       ├── app_constants.dart    # 应用级常量（版本号、超时时间、分页大小）
│   │       └── ws_constants.dart     # WebSocket 协议常量（方法名、消息类型）
│   │
│   ├── features/                     # ===== 功能模块 =====
│   │   │
│   │   ├── home/                     # --- 虾列表（主页）---
│   │   │   ├── pages/
│   │   │   │   └── home_page.dart            # 主页 Scaffold（Header + StatsBar + AgentList + BottomNav）
│   │   │   ├── widgets/
│   │   │   │   ├── stats_bar.dart            # 顶部状态统计栏（3 个 StatChip）
│   │   │   │   ├── stat_chip.dart            # 单个统计卡片
│   │   │   │   ├── instance_group.dart       # 实例分组头 + 折叠/展开控制
│   │   │   │   ├── agent_card.dart           # Agent 卡片（头像、名称、描述、状态）
│   │   │   │   └── agent_list_section.dart   # Agent 列表区域（分组视图 / 扁平视图）
│   │   │   ├── providers/
│   │   │   │   ├── agent_list_provider.dart  # Agent 列表状态 Provider
│   │   │   │   └── stats_provider.dart       # 统计数据 Provider
│   │   │   └── models/
│   │   │       └── home_state.dart           # 主页 UI 状态模型
│   │   │
│   │   ├── chat/                     # --- 对话聊天 ---
│   │   │   ├── pages/
│   │   │   │   └── chat_page.dart            # 对话页面 Scaffold
│   │   │   ├── widgets/
│   │   │   │   ├── chat_header.dart          # 顶部虾信息栏（头像、名称、在线状态）
│   │   │   │   ├── chat_message_list.dart    # 消息列表（CustomScrollView + 虚拟滚动）
│   │   │   │   ├── message_bubble_user.dart  # 用户消息气泡（右侧，accent 色）
│   │   │   │   ├── message_bubble_agent.dart # Agent 消息气泡（左侧，Markdown 渲染）
│   │   │   │   ├── typing_indicator.dart     # "虾思考中" 三点跳动动画
│   │   │   │   ├── tool_call_card.dart       # 工具调用状态卡片
│   │   │   │   ├── date_separator.dart       # 日期分隔线
│   │   │   │   ├── quick_commands_bar.dart   # 快捷指令横向滚动标签
│   │   │   │   ├── chat_input_area.dart      # 底部输入区域
│   │   │   │   ├── message_input.dart        # 多行文本输入框（自动高度）
│   │   │   │   ├── send_button.dart          # 发送按钮（空内容禁用态）
│   │   │   │   └── connection_banner.dart    # 连接状态横幅（断线/重连中/同步中）
│   │   │   ├── providers/
│   │   │   │   ├── chat_provider.dart        # 当前对话会话状态
│   │   │   │   ├── message_list_provider.dart# 消息列表数据 Provider
│   │   │   │   └── pending_queue_provider.dart# 待发送消息队列
│   │   │   └── models/
│   │   │       └── chat_state.dart           # 对话 UI 状态
│   │   │
│   │   ├── messages/                 # --- 消息页（对话列表）---
│   │   │   ├── pages/
│   │   │   │   └── messages_page.dart        # 消息页 Scaffold
│   │   │   ├── widgets/
│   │   │   │   ├── conversation_list.dart    # 对话列表
│   │   │   │   ├── conversation_item.dart    # 单行对话（头像、名称、预览、时间、角标）
│   │   │   │   ├── unread_badge.dart         # 未读消息红色角标
│   │   │   │   └── messages_empty_state.dart # 空状态引导页
│   │   │   └── providers/
│   │   │       └── conversation_list_provider.dart # 对话列表数据 Provider
│   │   │
│   │   ├── instances/                # --- 实例管理 ---
│   │   │   ├── pages/
│   │   │   │   ├── instances_page.dart       # 实例列表页 Scaffold
│   │   │   │   └── add_instance_page.dart    # 添加实例页（扫码 + 手动表单）
│   │   │   ├── widgets/
│   │   │   │   ├── instance_card.dart        # 实例卡片（图标、名称、URL、状态）
│   │   │   │   ├── add_instance_button.dart  # 虚线边框添加按钮
│   │   │   │   ├── scan_qr_view.dart         # 二维码扫描界面
│   │   │   │   ├── manual_form.dart          # 手动添加表单
│   │   │   │   ├── tab_switcher.dart         # 扫码/手动 Tab 切换器
│   │   │   │   └── connection_test_result.dart # 连通性测试结果展示
│   │   │   ├── providers/
│   │   │   │   ├── instance_list_provider.dart # 实例列表 Provider
│   │   │   │   └── add_instance_provider.dart  # 添加实例流程状态
│   │   │   └── models/
│   │   │       └── instance_form_state.dart  # 表单校验状态
│   │   │
│   │   ├── agent_detail/             # --- 虾详情与成长面板 ---
│   │   │   ├── pages/
│   │   │   │   └── agent_detail_page.dart    # 虾详情页 Scaffold（Profile + Stats + Achievements）
│   │   │   ├── widgets/
│   │   │   │   ├── agent_profile_header.dart # 顶部头像 + 名称 + 状态
│   │   │   │   ├── stats_grid.dart           # 6 宫格统计卡片
│   │   │   │   ├── stat_card.dart            # 单个统计卡片
│   │   │   │   ├── achievement_list.dart     # 成就列表
│   │   │   │   ├── achievement_item.dart     # 单个成就行
│   │   │   │   └── milestone_celebration.dart # 里程碑庆祝动画 Overlay
│   │   │   └── providers/
│   │   │       └── agent_profile_providers.dart    # ViewModel + reactive ticker (round 4)
│   │   │
│   │   ├── agent_config/             # --- 虾个性化配置 ---
│   │   │   ├── pages/
│   │   │   │   └── agent_config_page.dart    # 配置页 Scaffold
│   │   │   ├── widgets/
│   │   │   │   ├── avatar_editor.dart        # 头像编辑区（点击更换 emoji/图片）
│   │   │   │   ├── nickname_input.dart       # 昵称输入框
│   │   │   │   ├── color_picker_grid.dart    # 12 色主题色选择器
│   │   │   │   ├── color_dot.dart            # 单个颜色圆点
│   │   │   │   ├── command_list_editor.dart  # 快捷指令列表编辑器
│   │   │   │   ├── command_item_row.dart     # 单行指令（拖拽手柄 + 标签 + 命令 + 删除）
│   │   │   │   └── config_save_button.dart   # 保存按钮
│   │   │   └── providers/
│   │   │       └── agent_config_provider.dart # 配置表单状态
│   │   │
│   │   ├── search/                   # --- 全局搜索（V1.2）---
│   │   │   ├── pages/
│   │   │   │   └── search_page.dart          # 搜索页 Scaffold
│   │   │   ├── widgets/
│   │   │   │   ├── search_bar.dart           # 搜索输入框
│   │   │   │   ├── search_result_item.dart   # 搜索结果行（高亮关键词）
│   │   │   │   └── search_empty_state.dart   # 无结果空状态
│   │   │   └── providers/
│   │   │       └── search_provider.dart      # 搜索状态与结果
│   │   │
│   │   └── settings/                 # --- 设置 ---
│   │       ├── pages/
│   │       │   └── settings_page.dart        # 设置页 Scaffold
│   │       ├── widgets/
│   │       │   ├── setting_row.dart          # 单行设置项（图标 + 标签 + 值）
│   │       │   └── settings_section.dart     # 设置分组区域
│   │       └── providers/
│   │           └── settings_provider.dart    # 应用级设置状态
│   │
│   └── shared/                       # ===== 共享组件与模型 =====
│       ├── widgets/
│       │   ├── bottom_nav_bar.dart           # 底部三 Tab 导航栏
│       │   ├── app_header.dart               # 通用页面头部
│       │   ├── back_button.dart              # 返回按钮
│       │   ├── header_icon_button.dart       # 头部图标按钮
│       │   ├── avatar_widget.dart            # 通用头像组件（emoji + 背景色 + 状态点）
│       │   ├── status_dot.dart               # 在线/离线状态指示灯
│       │   ├── toast_overlay.dart            # Toast 全局提示
│       │   ├── empty_state.dart              # 通用空状态组件
│       │   ├── primary_button.dart           # 主按钮（accent 色）
│       │   ├── secondary_button.dart         # 次按钮（透明底）
│       │   └── confirm_dialog.dart           # 二次确认弹窗
│       │
│       ├── models/
│       │   ├── instance.dart                 # Instance 数据模型
│       │   ├── agent.dart                    # Agent 数据模型
│       │   ├── message.dart                  # Message 数据模型
│       │   ├── quick_command.dart            # QuickCommand 数据模型
│       │   ├── agent_stats.dart              # AgentStats 统计模型
│       │   ├── achievement.dart              # Achievement 成就模型
│       │   └── connection_status.dart        # 连接状态枚举
│       │
│       └── extensions/
│           ├── color_extensions.dart         # Color 工具扩展
│           ├── string_extensions.dart        # 字符串截断、Markdown 清洗
│           └── datetime_extensions.dart      # DateTime 友好格式化
```

### 2.2 架构分层原则

```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                        │
│  features/*/pages/  +  features/*/widgets/  +  shared/widgets│
│  职责：UI 渲染、用户交互、动画                                  │
├─────────────────────────────────────────────────────────────┤
│                    State Layer                               │
│  features/*/providers/  +  Riverpod Provider 定义             │
│  职责：UI 状态管理、业务逻辑编排、数据聚合                       │
├─────────────────────────────────────────────────────────────┤
│                    Domain Layer                              │
│  shared/models/  +  core/utils/                              │
│  职责：数据模型定义、业务规则校验、纯函数计算                     │
├─────────────────────────────────────────────────────────────┤
│                    Data Layer                                │
│  core/network/  +  core/storage/                             │
│  职责：WebSocket 通信、本地持久化、安全存储                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 组件树 (Component Tree)

### 3.1 全局组件层级

```
App (MaterialApp.router)
├── ProviderScope                     # Riverpod 全局 Provider 容器
├── GoRouter                          # 路由配置
│   └── ShellRoute (MainShell)        # 包含 BottomNavBar 的壳路由
│       ├── /home                     # HomePage
│       ├── /messages                 # MessagesPage
│       └── /instances                # InstancesPage
│   ├── /chat/:agentId               # ChatPage (无 BottomNavBar)
│   ├── /instances/add               # AddInstancePage
│   ├── /agent/:agentId/detail       # AgentDetailPage
│   ├── /agent/:agentId/config       # AgentConfigPage
│   ├── /search                      # SearchPage
│   └── /settings                    # SettingsPage
│
└── Overlay (全局覆盖层)
    ├── ToastOverlay                  # Toast 全局提示
    ├── ConnectionBannerOverlay       # 连接状态横幅
    └── MilestoneCelebrationOverlay   # 里程碑庆祝动画
```

### 3.2 各页面组件拆解

#### 3.2.1 HomePage — 虾列表主页

```
HomePage (StatefulWidget — ConsumerStatefulWidget)
├── AppHeader
│   ├── Title ("虾Hub")                          # Text
│   ├── HeaderIconButton (管理实例)               # IconButton → 跳转 /instances
│   └── HeaderIconButton (设置)                   # IconButton → 跳转 /settings
│
├── StatsBar (StatelessWidget)
│   ├── StatChip (活跃实例)                        # 在线数/总数
│   │   ├── Icon ("🖥")
│   │   ├── ChipValue ("2")                       # Text — 22px bold
│   │   ├── ChipUnit ("/ 3")                      # Text — 14px muted
│   │   └── ChipLabel ("活跃实例")                 # Text — 11px
│   ├── StatChip (在线虾)
│   │   └── ... (同上结构)
│   └── StatChip (总消息数)
│       └── ... (同上结构)
│
├── AgentListSection (StatefulWidget)
│   ├── [InstanceGroup × N]                       # 每个实例一个分组
│   │   └── InstanceGroup (StatefulWidget)
│   │       ├── InstanceHeader                    # GestureDetector — 折叠/展开
│   │       │   ├── StatusDot (online/offline)    # 6px 圆点 + 发光
│   │       │   ├── InstanceName                  # Text — 12px uppercase
│   │       │   ├── InstanceCount ("3 只虾")      # Text — 12px muted
│   │       │   └── ChevronIcon                   # 旋转动画
│   │       └── AnimatedCrossFade                 # 折叠/展开过渡
│   │           └── Column
│   │               └── [AgentCard × M]
│   │                   └── AgentCard (StatelessWidget)
│   │                       ├── AvatarWidget      # 48px emoji + 背景色
│   │                       │   └── StatusDot     # 8px 在线状态点
│   │                       ├── AgentInfo
│   │                       │   ├── AgentName     # Text — 16px semibold
│   │                       │   └── AgentDesc     # Text — 13px ellipsis
│   │                       └── AgentMeta
│   │                           └── AgentTime     # Text — 11px muted
│   │
│   └── EmptyState (当无实例时)                    # 共享组件
│       ├── Emoji (48px)
│       ├── Title
│       └── Description
│
└── BottomNavBar (StatelessWidget)                # 共享组件
    ├── NavItem (虾列表) — active                  # Icon + Label
    ├── NavItem (消息)                              # Icon + Label
    └── NavItem (实例)                              # Icon + Label
```

**可复用组件提取**：`StatsBar`、`StatChip`、`AgentCard`、`AvatarWidget`、`StatusDot`、`BottomNavBar`、`EmptyState`

---

#### 3.2.2 ChatPage — 对话聊天页

```
ChatPage (StatefulWidget — ConsumerStatefulWidget)
├── ChatHeader (StatelessWidget)
│   ├── BackButton                                 # 智能返回（根据来源 Tab）
│   ├── AvatarWidget (40px)                        # 虾头像
│   ├── ChatHeaderInfo                             # GestureDetector → 详情页
│   │   ├── ChatHeaderName                         # Text — 17px semibold
│   │   └── ChatHeaderStatus
│   │       ├── StatusDot (6px)
│   │       └── StatusText ("在线"/"离线")
│   └── HeaderIconButton (更多菜单)
│
├── ChatMessageList (StatefulWidget)
│   └── CustomScrollView                          # 虚拟滚动，支持 >50 条消息
│       ├── [DateSeparator × N]
│       │   └── DateSeparator (StatelessWidget)    # "今天" / "昨天" / "2026-06-07"
│       ├── [MessageBubbleUser × N]
│       │   └── MessageBubbleUser (StatelessWidget)
│       │       ├── MessageText                    # Text — 15px, accent 背景
│       │       └── MessageTime (right)            # Text — 11px
│       ├── [MessageBubbleAgent × N]
│       │   └── MessageBubbleAgent (StatelessWidget)
│       │       ├── MarkdownBody                   # Markdown 渲染（粗体、列表、链接）
│       │       ├── CodeBlock (条件渲染)            # 代码块 + 语法高亮
│       │       ├── ToolCallCard (条件渲染)
│       │       │   ├── ToolName                   # 工具名称 + accent 左边框
│       │       │   └── ToolStatus                 # 状态文本（完成/失败/进行中）
│       │       └── MessageTime (left)
│       └── TypingIndicator (条件渲染)              # 三点跳动动画
│           └── [TypingDot × 3]                    # 带延迟的弹跳动画
│
├── ConnectionBanner (条件渲染)                     # Overlay 横幅
│   └── AnimatedSlide + Text                       # "连接已断开，正在重连..."
│
└── ChatInputArea (StatefulWidget)
    ├── QuickCommandsBar (StatelessWidget)
    │   └── SingleChildScrollView (horizontal)
    │       └── [QuickCommandChip × N]
    │           └── QuickCommandChip (StatelessWidget)  # pill 形状，accent 文字
    └── InputRow
        ├── PlusButton                             # "+" 附件按钮
        ├── MessageInput (StatefulWidget)
        │   └── TextField (maxLines: 5)            # 自动高度增长
        └── SendButton                             # 发送按钮（disabled 态）
```

**可复用组件提取**：`ChatHeader`、`MessageBubbleUser`、`MessageBubbleAgent`、`TypingIndicator`、`ToolCallCard`、`QuickCommandsBar`、`MessageInput`、`ConnectionBanner`

---

#### 3.2.3 MessagesPage — 消息页

```
MessagesPage (StatefulWidget — ConsumerStatefulWidget)
├── AppHeader
│   ├── Title ("消息")
│   └── HeaderIconButton (搜索)                    # 跳转 /search
│
├── ConversationList (StatelessWidget)
│   ├── [ConversationItem × N]
│   │   └── ConversationItem (StatelessWidget)
│   │       ├── AvatarWidget (48px)                # 虾头像 + 状态点
│   │       ├── ConversationItemInfo
│   │       │   ├── ConversationItemTop
│   │       │   │   ├── AgentName                  # Text — 16px semibold
│   │       │   │   └── MessageTime                # Text — 12px muted
│   │       │   └── MessagePreview                 # Text — 14px, 截断40字
│   │       │       └── YouPrefix ("你: ")         # 用户消息前缀
│   │       └── UnreadBadge (条件渲染)              # 红色角标 + 数字
│   │
│   └── MessagesEmptyState (当无对话时)
│       ├── Emoji ("💬")
│       ├── Title ("还没有和任何虾对话过")
│       └── Description ("去虾列表找一只开始聊天吧")
│
└── BottomNavBar                                   # 消息 Tab active
```

---

#### 3.2.4 InstancesPage — 实例管理页

```
InstancesPage (StatefulWidget — ConsumerStatefulWidget)
├── AppHeader
│   └── Title ("实例")
│
├── InstanceManagementList (StatelessWidget)
│   ├── [InstanceCard × N]
│   │   └── InstanceCard (StatelessWidget)
│   │       ├── InstanceIcon (44px)                # emoji 图标 + surface2 背景
│   │       ├── InstanceInfo
│   │       │   ├── InstanceName                   # Text — 16px semibold
│   │       │   ├── InstanceUrl                    # Text — 13px mono font
│   │       │   └── InstanceStatusLine
│   │       │       ├── StatusDot (6px)
│   │       │       ├── StatusText ("在线"/"离线")
│   │       │       └── AgentCountText ("· 3 只虾")
│   │       └── InstanceActions
│   │           └── TestConnectionButton            # IconButton — 连通性测试
│   │
│   └── AddInstanceButton (StatelessWidget)         # 虚线边框 + "+" 按钮
│
└── BottomNavBar                                   # 实例 Tab active
```

---

#### 3.2.5 AddInstancePage — 添加实例页

```
AddInstancePage (StatefulWidget)
├── AppHeader
│   ├── BackButton → /instances
│   └── Title ("添加实例")
│
└── ScrollContent
    └── TabSwitcher (扫码添加 | 手动添加)           # 复用组件
        │
        ├── ScanQRView (StatefulWidget)             # 扫码 Tab
        │   ├── QRScanFrame                        # 200×200 扫描框
        │   │   ├── QRScanIcon
        │   │   └── QRScanHint ("将二维码放入框内")
        │   ├── PrimaryButton ("模拟扫码成功")
        │   └── HintText ("在 OpenClaw 终端运行 openclaw pair 获取二维码")
        │
        └── ManualForm (StatefulWidget)             # 手动 Tab
            ├── FormGroup (实例名称)
            │   ├── FormLabel                      # 12px uppercase
            │   └── FormInput                      # 带内阴影边框的输入框
            ├── FormGroup (Gateway URL)
            │   ├── FormLabel
            │   ├── FormInput                      # placeholder: ws://192.168.1.100:18789
            │   └── FormHint                       # "支持 ws:// 和 wss:// 协议"
            ├── FormGroup (访问 Token)
            │   ├── FormLabel
            │   ├── FormInput (obscureText: true)  # password 输入
            │   └── FormHint                       # "Token 将加密后存储在本地安全存储中"
            └── PrimaryButton ("连接测试")
```

---

#### 3.2.6 AgentDetailPage — 虾详情页 / 成长面板

```
AgentDetailPage (StatefulWidget — ConsumerStatefulWidget)
├── AppHeader
│   ├── BackButton → /chat/:agentId
│   ├── Title (虾名称)
│   └── HeaderIconButton (编辑) → /agent/:agentId/config
│
└── ScrollContent
    ├── AgentProfileHeader (StatelessWidget)
    │   ├── AvatarWidget (72px)                    # 大头像
    │   ├── AgentNameBig                           # 24px bold
    │   ├── AgentDesc                              # 14px muted
    │   └── OnlineStatusLine
    │       ├── StatusDot
    │       └── StatusText + InstanceName
    │
    ├── StatsGrid (StatelessWidget)                 # 3×2 Grid
    │   ├── StatCard ("对话", 156)
    │   ├── StatCard ("消息", 1024)
    │   ├── StatCard ("工具", 89)
    │   ├── StatCard ("天数", 42)
    │   ├── StatCard ("连续", 7)
    │   └── StatCard ("首聊", "04-26")
    │
    ├── SectionTitle ("成就")
    │
    └── AchievementList (StatelessWidget)
        └── [AchievementItem × N]
            └── AchievementItem (StatelessWidget)
                ├── AchievementIcon (40px)          # gold/silver/bronze 背景色
                ├── AchievementInfo
                │   ├── AchievementName             # 14px semibold
                │   └── AchievementDesc             # 12px muted
                └── UnlockStatus ("已解锁"/"未解锁") # 条件样式
```

---

#### 3.2.7 AgentConfigPage — 虾个性化配置页

```
AgentConfigPage (StatefulWidget — ConsumerStatefulWidget)
├── AppHeader
│   ├── BackButton → /agent/:agentId/detail
│   └── Title ("个性化配置")
│
└── ScrollContent
    ├── ConfigSection ("基本信息")
    │   └── ConfigCard
    │       ├── AvatarEditor (StatefulWidget)
    │       │   ├── ConfigAvatar (64px)            # 可点击更换
    │       │   │   └── EditBadge ("✎")
    │       │   └── ConfigAvatarInfo
    │       │       ├── AvatarName                 # 20px bold
    │       │       └── AvatarHint ("点击头像更换")
    │       ├── ConfigInputRow (昵称)
    │       │   ├── ConfigLabel
    │       │   └── ConfigInput
    │       └── ConfigInputRow (简介)
    │           ├── ConfigLabel
    │           └── ConfigInput
    │
    ├── ConfigSection ("主题色")
    │   └── ConfigCard
    │       └── ColorPickerGrid (StatefulWidget)
    │           └── [ColorDot × 12]                # 6×2 Grid
    │               └── ColorDot (StatelessWidget)  # 40px, selected 态有边框 + ✓
    │
    ├── ConfigSection ("快捷指令")
    │   └── ConfigCard
    │       ├── CommandListEditor (StatefulWidget)
    │       │   └── [CommandItemRow × N]
    │       │       └── CommandItemRow (StatelessWidget)
    │       │           ├── DragHandle ("⋮⋮")
    │       │           ├── CommandLabelInput       # 标签输入
    │       │           ├── CommandCmdInput         # /命令 输入（mono font）
    │       │           └── DeleteButton            # × 按钮
    │       └── AddCommandButton ("+ 添加指令")
    │
    └── ConfigSaveButton (PrimaryButton)            # "保存配置"
```

---

#### 3.2.8 SettingsPage — 设置页

```
SettingsPage (StatelessWidget)
├── AppHeader
│   ├── BackButton → /home
│   └── Title ("设置")
│
└── ScrollContent
    └── SettingsSection
        ├── SettingRow ("🔔 通知设置", "已开启")
        ├── SettingRow ("🌙 免打扰时段", "22:00 — 08:00")
        ├── SettingRow ("🔐 生物识别解锁", "Face ID")
        ├── SettingRow ("🌐 网络设置", "WiFi")
        ├── SettingRow ("💾 存储管理", "12.3 MB")
        └── SettingRow ("ℹ️ 关于虾Hub", "v1.0")
```

---

### 3.3 共享 Widget 清单

| Widget 名称 | 类型 | 使用页面 | 说明 |
|-------------|------|---------|------|
| `BottomNavBar` | StatelessWidget | Home, Messages, Instances | 三 Tab 导航，高亮当前 Tab |
| `AppHeader` | StatelessWidget | 所有页面 | 统一页面头部（标题 + 操作按钮） |
| `BackButton` | StatelessWidget | Chat, AddInstance, Detail, Config, Settings | 返回按钮，支持智能返回 |
| `HeaderIconButton` | StatelessWidget | Home, Messages, Chat, Detail | 头部圆形图标按钮 |
| `AvatarWidget` | StatelessWidget | Home, Chat, Messages, Detail | 虾头像（emoji + 背景色 + 状态点） |
| `StatusDot` | StatelessWidget | Home, Chat, Messages, Instances, Detail | 在线/离线状态指示灯 |
| `EmptyState` | StatelessWidget | Home, Messages, Search | 通用空状态展示 |
| `PrimaryButton` | StatelessWidget | AddInstance, Config | accent 色主按钮 |
| `SecondaryButton` | StatelessWidget | 对话框辅助 | 透明底次按钮 |
| `ToastOverlay` | Overlay Widget | 全局 | Toast 全局提示动画 |
| `ConnectionBanner` | Overlay Widget | Chat (条件) | 连接状态横幅 |
| `ConfirmDialog` | Dialog Widget | Instances (删除) | 二次确认弹窗 |

---

## 4. 数据模型 (Data Models)

### 4.1 Instance — 实例配置模型

```dart
/// OpenClaw Gateway 实例配置
class Instance {
  final String id;              // 本地生成的唯一 ID (UUID v4)
  final String name;            // 用户自定义名称，如 "我的 MacBook"
  final String gatewayUrl;      // Gateway WebSocket 地址，如 "ws://192.168.1.100:18789"
  final String icon;            // 实例图标 emoji，如 "💻"
  final ConnectionStatus status;// 连接状态枚举
  final DateTime? lastConnected;// 最后一次成功连接时间
  final DateTime createdAt;     // 创建时间
  final DateTime updatedAt;     // 更新时间

  const Instance({
    required this.id,
    required this.name,
    required this.gatewayUrl,
    this.icon = '🖥️',
    this.status = ConnectionStatus.disconnected,
    this.lastConnected,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// 连接状态枚举
enum ConnectionStatus {
  connected,      // 在线 — 绿色
  connecting,     // 连接中 — 黄色
  disconnected,   // 离线 — 灰色
  authFailed,     // 认证失败 — 红色
  unreachable,    // 不可达 — 红色
}
```

**注意**：Token 不存储在 Instance 模型中，而是通过 `flutter_secure_storage` 以 `instance_token_{id}` 为 key 单独加密存储。

### 4.2 Agent — 虾信息模型

```dart
/// OpenClaw Agent（虾）信息
class Agent {
  final String id;              // Gateway 返回的 Agent ID
  final String instanceId;      // 所属实例 ID（关联 Instance.id）
  final String name;            // Agent 名称，如 "产品虾"
  final String emoji;           // Agent 表情符号，如 "🎯"
  final String description;     // Agent 描述，如 "产品规划 · 需求分析 · PRD 撰写"
  final String theme;           // 主题色标识，如 "coral"（映射到 AgentTheme 表）
  final bool online;            // 是否在线
  final DateTime? lastActive;   // 最后活跃时间
  final List<QuickCommand> quickCommands;  // 快捷指令集
  final DateTime createdAt;     // 首次发现时间
  final DateTime updatedAt;     // 最后更新时间

  // --- 本地个性化配置（可覆盖 Gateway 原始值）---
  final String? customName;     // 用户自定义昵称（覆盖 name 显示）
  final String? customEmoji;    // 用户自定义头像 emoji
  final String? customTheme;    // 用户自定义主题色
  final String? avatarPath;     // 用户自定义头像图片路径（本地文件）

  const Agent({
    required this.id,
    required this.instanceId,
    required this.name,
    required this.emoji,
    this.description = '',
    this.theme = 'coral',
    this.online = false,
    this.lastActive,
    this.quickCommands = const [],
    required this.createdAt,
    required this.updatedAt,
    this.customName,
    this.customEmoji,
    this.customTheme,
    this.avatarPath,
  });

  /// 显示名称：优先使用自定义昵称
  String get displayName => customName ?? name;

  /// 显示 emoji：优先使用自定义头像
  String get displayEmoji => customEmoji ?? emoji;

  /// 显示主题色：优先使用自定义主题
  String get displayTheme => customTheme ?? theme;
}
```

### 4.3 Message — 消息模型

```dart
/// 对话消息
class Message {
  final String id;              // 消息唯一 ID（Gateway 生成，本地待发消息用 UUID）
  final String agentId;         // 所属 Agent ID
  final String instanceId;      // 所属实例 ID（冗余，方便跨 Agent 搜索）
  final MessageSender sender;   // 发送者（user / agent）
  final MessageContentType type;// 消息内容类型
  final String text;            // 消息文本内容
  final String? imagePath;      // 图片本地路径（type 为 image 时）
  final String? filePath;       // 文件本地路径（type 为 file 时）
  final String? fileName;       // 文件名
  final ToolCallInfo? toolCall; // 工具调用信息（type 为 toolCall 时）
  final MessageStatus status;   // 消息状态
  final DateTime timestamp;     // 消息时间戳
  final DateTime? syncedAt;     // 同步到 Gateway 的时间

  const Message({
    required this.id,
    required this.agentId,
    required this.instanceId,
    required this.sender,
    this.type = MessageContentType.text,
    required this.text,
    this.imagePath,
    this.filePath,
    this.fileName,
    this.toolCall,
    this.status = MessageStatus.sent,
    required this.timestamp,
    this.syncedAt,
  });
}

/// 消息发送者
enum MessageSender {
  user,   // 用户
  agent,  // Agent（虾）
  system, // 系统消息
}

/// 消息内容类型
enum MessageContentType {
  text,     // 纯文本 / Markdown
  image,    // 图片
  file,     // 文件
  code,     // 代码块（Agent 回复中自动识别）
  toolCall, // 工具调用状态
}

/// 消息状态
enum MessageStatus {
  sent,       // 已发送
  delivered,  // 已送达（Gateway 确认）
  pending,    // 待发送（断线暂存）
  failed,     // 发送失败
}
```

### 4.4 ToolCallInfo — 工具调用信息

```dart
/// Agent 工具调用信息
class ToolCallInfo {
  final String name;            // 工具名称，如 "📊 数据分析工具"
  final ToolCallStatus status;  // 调用状态
  final String? resultSummary;  // 结果摘要，如 "完成 — 处理了 1,247 条数据"
  final String? errorDetail;    // 失败时的错误详情

  const ToolCallInfo({
    required this.name,
    required this.status,
    this.resultSummary,
    this.errorDetail,
  });
}

enum ToolCallStatus {
  running,    // 进行中
  completed,  // 完成
  failed,     // 失败
}
```

### 4.5 QuickCommand — 快捷指令模型

```dart
/// 快捷指令
class QuickCommand {
  final String label;           // 显示标签，如 "📊 分析需求"
  final String command;         // 指令文本，如 "/analyze"

  const QuickCommand({
    required this.label,
    required this.command,
  });
}
```

### 4.6 AgentStats — 虾统计数据模型

```dart
/// 虾成长统计数据
class AgentStats {
  final String agentId;         // 关联 Agent ID
  final int totalDialogs;       // 总对话次数
  final int totalMessages;      // 总消息数（发送 + 接收）
  final int totalToolCalls;     // 工具调用总次数
  final int activeDays;         // 活跃天数（有对话的天数）
  final int currentStreak;      // 当前连续活跃天数
  final DateTime? firstDialogDate; // 首次对话日期
  final DateTime? lastDialogDate;  // 最后对话日期

  const AgentStats({
    required this.agentId,
    this.totalDialogs = 0,
    this.totalMessages = 0,
    this.totalToolCalls = 0,
    this.activeDays = 0,
    this.currentStreak = 0,
    this.firstDialogDate,
    this.lastDialogDate,
  });
}
```

### 4.7 Achievement — 成就模型

```dart
/// 成就徽章
class Achievement {
  final String id;              // 成就唯一标识，如 "first_dialog"
  final String icon;            // 成就图标 emoji，如 "🏆"
  final String name;            // 成就名称，如 "初次对话"
  final String description;     // 成就描述/解锁条件
  final bool unlocked;          // 是否已解锁
  final AchievementTier tier;   // 成就等级
  final DateTime? unlockedAt;   // 解锁时间

  const Achievement({
    required this.id,
    required this.icon,
    required this.name,
    required this.description,
    this.unlocked = false,
    this.tier = AchievementTier.bronze,
    this.unlockedAt,
  });
}

/// 成就等级
enum AchievementTier {
  gold,     // 金色 — rgba(196,168,106,0.15) 背景
  silver,   // 银色 — rgba(245,244,240,0.06) 背景
  bronze,   // 铜色 — accent-muted 背景
}

/// 预设成就定义（硬编码）
const List<AchievementDefinition> achievementDefinitions = [
  AchievementDefinition(id: 'first_dialog',     icon: '🏆', name: '初次对话',     desc: '与虾的第一次对话',           condition: (s) => s.totalDialogs >= 1),
  AchievementDefinition(id: 'hundred_dialogs',  icon: '💬', name: '百次对话',     desc: '累计对话达到 100 次',         condition: (s) => s.totalDialogs >= 100),
  AchievementDefinition(id: 'thousand_dialogs', icon: '💬', name: '千次对话',     desc: '累计对话达到 1000 次',        condition: (s) => s.totalDialogs >= 1000),
  AchievementDefinition(id: 'streak_7',         icon: '🔥', name: '连续活跃 7 天', desc: '连续 7 天与虾互动',           condition: (s) => s.currentStreak >= 7),
  AchievementDefinition(id: 'streak_30',        icon: '🌟', name: '月度伙伴',     desc: '连续活跃 30 天',             condition: (s) => s.currentStreak >= 30),
  AchievementDefinition(id: 'tool_50',          icon: '🛠️', name: '工具达人',     desc: '工具调用达到 50 次',          condition: (s) => s.totalToolCalls >= 50),
  AchievementDefinition(id: 'tool_200',         icon: '🛠️', name: '工具大师',     desc: '工具调用达到 200 次',         condition: (s) => s.totalToolCalls >= 200),
  AchievementDefinition(id: 'msg_1000',         icon: '💎', name: '千条消息',     desc: '累计消息数达到 1000 条',       condition: (s) => s.totalMessages >= 1000),
];
```

### 4.8 Design Tokens — 设计令牌 Dart 类

```dart
/// 设计令牌 — 映射 Premium 原型 CSS Variables
class DT {
  DT._(); // 禁止实例化

  // ===== Color — 60-30-10 =====
  static const Color bg             = Color(0xFF111110);
  static const Color surface        = Color(0xFF1A1917);
  static const Color surface2       = Color(0xFF232220);
  static const Color surface3       = Color(0xFF2C2B28);
  static const Color surfaceElevated = Color(0xFF1F1E1C);

  // ===== Text — rgba tonal depth =====
  static const Color text1          = Color(0xFFF5F4F0);
  static const Color text2          = Color(0x99F5F4F0); // 60%
  static const Color text3          = Color(0x59F5F4F0); // 35%
  static const Color text4          = Color(0x2EF5F4F0); // 18%

  // ===== Brand accent — desaturated coral =====
  static const Color accent         = Color(0xFFC27C68);
  static const Color accentHover    = Color(0xFFD08E7C);
  static const Color accentMuted    = Color(0x1FC27C68); // 12%
  static const Color accentGlow     = Color(0x2EC27C68); // 18%

  // ===== Semantic =====
  static const Color green          = Color(0xFF6BA87A);
  static const Color greenMuted     = Color(0x266BA87A); // 15%
  static const Color red            = Color(0xFFC26464);
  static const Color redMuted       = Color(0x1FC26464); // 12%
  static const Color yellow         = Color(0xFFC4A86A);

  // ===== Spacing — 8pt grid =====
  static const double s1  = 4.0;
  static const double s2  = 8.0;
  static const double s3  = 12.0;
  static const double s4  = 16.0;
  static const double s5  = 20.0;
  static const double s6  = 24.0;
  static const double s7  = 32.0;
  static const double s8  = 40.0;
  static const double s9  = 48.0;
  static const double s10 = 56.0;

  // ===== Radius =====
  static const double rSm   = 8.0;
  static const double rMd   = 12.0;
  static const double rLg   = 16.0;
  static const double rXl   = 20.0;
  static const double rFull = 999.0;

  // ===== Shadow — 4 tiers =====
  static final List<BoxShadow> shadowS = [
    BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static final List<BoxShadow> shadowM = [
    BoxShadow(color: Colors.black.withOpacity(0.20), blurRadius: 16, offset: Offset(0, 4)),
  ];
  static final List<BoxShadow> shadowL = [
    BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 32, offset: Offset(0, 8)),
  ];
  static final List<BoxShadow> shadowXl = [
    BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 48, offset: Offset(0, 16)),
  ];

  // ===== Motion =====
  static const Curve ease       = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Curve easeSpring = Cubic(0.34, 1.56, 0.64, 1.0);
  static const Curve easeOut    = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Duration durationFast = Duration(milliseconds: 200);
  static const Duration durationMid  = Duration(milliseconds: 350);
  static const Duration durationSlow = Duration(milliseconds: 500);

  // ===== Agent 主题色映射 =====
  static const Map<String, AgentThemeColor> agentThemes = {
    'coral':   AgentThemeColor(bg: Color(0x1FC27C68), color: Color(0xFFC27C68)),
    'blue':    AgentThemeColor(bg: Color(0x1F6C8AAF), color: Color(0xFF6C8AAF)),
    'green':   AgentThemeColor(bg: Color(0x1F6BA87A), color: Color(0xFF6BA87A)),
    'orange':  AgentThemeColor(bg: Color(0x1FB98A64), color: Color(0xFFB98A64)),
    'pink':    AgentThemeColor(bg: Color(0x1FAF788C), color: Color(0xFFAF788C)),
    'teal':    AgentThemeColor(bg: Color(0x1F5F9B96), color: Color(0xFF5F9B96)),
    'yellow':  AgentThemeColor(bg: Color(0x1FAF9B5F), color: Color(0xFFAF9B5F)),
    'rose':    AgentThemeColor(bg: Color(0x1FAA6E82), color: Color(0xFFAA6E82)),
    'slate':   AgentThemeColor(bg: Color(0x1F828282), color: Color(0xFF828282)),
    'indigo':  AgentThemeColor(bg: Color(0x1F6E64A0), color: Color(0xFF6E64A0)),
    'caramel': AgentThemeColor(bg: Color(0x1FAA7D50), color: Color(0xFFAA7D50)),
    'jade':    AgentThemeColor(bg: Color(0x1F509678), color: Color(0xFF509678)),
  };
}

/// Agent 主题色配置
class AgentThemeColor {
  final Color bg;    // 12% 不透明度背景色
  final Color color; // 实色

  const AgentThemeColor({required this.bg, required this.color});
}
```

---

## 5. 状态管理 (State Management)

### 5.1 推荐方案：Riverpod

**选择理由**：

- **编译时安全**：Provider 引用关系在编译时检查，避免运行时错误
- **无 BuildContext 依赖**：Provider 可在任意位置访问，适合 WebSocket 回调等非 Widget 场景
- **AutoDispose**：对话页面关闭后自动清理对应 Provider，防止内存泄漏
- **AsyncValue**：原生支持异步数据加载状态（loading/data/error），简化 UI 状态处理
- **可测试性**：Provider 可在测试中轻松 override

### 5.2 Provider 定义清单

```dart
// ===== 全局 Provider =====

/// 数据库实例 Provider（单例）
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

/// WebSocket 管理器 Provider（单例）
final wsManagerProvider = Provider<WebSocketManager>((ref) {
  final db = ref.watch(databaseProvider);
  final manager = WebSocketManager(database: db);
  ref.onDispose(() => manager.disposeAll());
  return manager;
});

// ===== 实例管理 =====

/// 实例列表 Provider — 从本地数据库加载，后台静默检测连通性
final instanceListProvider = StateNotifierProvider<InstanceListNotifier, AsyncValue<List<Instance>>>((ref) {
  final db = ref.watch(databaseProvider);
  final wsManager = ref.watch(wsManagerProvider);
  return InstanceListNotifier(db: db, wsManager: wsManager);
});

/// 单个实例连接状态 Provider — 按实例 ID 参数化
final instanceConnectionProvider = StreamProvider.family<ConnectionStatus, String>((ref, instanceId) {
  final wsManager = ref.watch(wsManagerProvider);
  return wsManager.connectionStatusStream(instanceId);
});

// ===== Agent 管理 =====

/// Agent 列表 Provider — 聚合所有在线实例的 Agent
final agentListProvider = StateNotifierProvider<AgentListNotifier, AgentListState>((ref) {
  final db = ref.watch(databaseProvider);
  final wsManager = ref.watch(wsManagerProvider);
  final instances = ref.watch(instanceListProvider);
  return AgentListNotifier(db: db, wsManager: wsManager, instances: instances);
});

/// 按实例分组的 Agent Provider
final groupedAgentListProvider = Provider<Map<Instance, List<Agent>>>((ref) {
  final agents = ref.watch(agentListProvider);
  final instances = ref.watch(instanceListProvider);
  // 按 instance 分组聚合
  return groupAgentsByInstance(agents, instances);
});

/// 统计数据 Provider — 实时计算
final statsProvider = Provider<GlobalStats>((ref) {
  final instances = ref.watch(instanceListProvider);
  final agents = ref.watch(agentListProvider);
  return GlobalStats(
    activeInstances: instances.where((i) => i.status == ConnectionStatus.connected).length,
    totalInstances: instances.length,
    onlineAgents: agents.where((a) => a.online).length,
    totalAgents: agents.length,
    totalMessages: agents.fold(0, (sum, a) => sum + a.stats.totalMessages),
  );
});

// ===== 对话 =====

/// 当前对话会话 Provider — AutoDispose，离开对话页自动清理
final chatProvider = StateNotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, String>((ref, agentId) {
  final db = ref.watch(databaseProvider);
  final wsManager = ref.watch(wsManagerProvider);
  return ChatNotifier(agentId: agentId, db: db, wsManager: wsManager);
});

/// 消息列表 Provider — 按 Agent ID 参数化
final messageListProvider = StateNotifierProvider.autoDispose
    .family<MessageListNotifier, List<Message>, String>((ref, agentId) {
  final db = ref.watch(databaseProvider);
  return MessageListNotifier(agentId: agentId, db: db);
});

/// 待发送消息队列 Provider
final pendingQueueProvider = StateNotifierProvider.autoDispose
    .family<PendingQueueNotifier, List<Message>, String>((ref, agentId) {
  final db = ref.watch(databaseProvider);
  return PendingQueueNotifier(agentId: agentId, db: db);
});

// ===== 对话列表（消息页）=====

/// 对话列表 Provider — 所有有消息记录的 Agent，按最后消息时间排序
final conversationListProvider = StateNotifierProvider<ConversationListNotifier, List<ConversationItem>>((ref) {
  final db = ref.watch(databaseProvider);
  return ConversationListNotifier(db: db);
});

// ===== 虾详情 =====

// Round 3B: 删除 `agent_stats` 缓存表后,以下 Provider / DAO 全部下线。
// AgentStats 统计由 EvaluateAchievementsUseCase 全量实时聚合,不再有
// 单独的 statsDao。下方代码片段保留为历史伪代码,仅供架构叙事参考,
// 实际实现见 `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart`。
// (历史伪代码)
// final agentStatsProvider = FutureProvider.family<AgentStats, String>((ref, agentId) async {
//   final db = ref.watch(databaseProvider);
//   return db.statsDao.getStatsForAgent(agentId);
// });

/// 成就列表 Provider
final achievementListProvider = Provider.family<List<Achievement>, String>((ref, agentId) {
  // Round 3B: stats 来自 use case 实时聚合,不再 watch agentStatsProvider。
  // 实际接线见 AgentProfileViewModel._safeEvaluateAchievements。
  // 根据统计数据判断成就解锁状态
  return evaluateAchievements(stats);
});

// ===== 虾个性化配置 =====

/// Agent 配置表单 Provider
final agentConfigProvider = StateNotifierProvider.autoDispose
    .family<AgentConfigNotifier, AgentConfigState, String>((ref, agentId) {
  final db = ref.watch(databaseProvider);
  return AgentConfigNotifier(agentId: agentId, db: db);
});

// ===== 设置 =====

/// 应用设置 Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

// ===== 导航状态 =====

/// 当前来源 Tab Provider — 用于智能返回
final sourceTabProvider = StateProvider<String>((ref) => '/home');
```

### 5.3 关键用户旅程状态流

#### 5.3.1 添加实例 → 浏览 Agent → 进入对话

```
用户操作                          Provider 状态变化
─────────                        ─────────────────
1. 点击 "添加实例"
   └─→ AddInstancePage          addInstanceProvider: idle → formEditing

2. 填写表单，点击 "连接测试"
   └─→ addInstanceProvider:    formEditing → testing
       ├─ 连接成功 → testing → success
       │   ├─ instanceListProvider: 追加新 Instance
       │   ├─ wsManager.connect(instanceId)
       │   ├─ agentListProvider: 自动拉取新实例的 Agent
       │   └─ 导航回 InstancesPage
       └─ 连接失败 → testing → error(errorMessage)

3. 切换到 "虾列表" Tab
   └─→ homePage 渲染
       ├─ statsProvider: 重算全局统计
       └─ groupedAgentListProvider: 展示新实例的 Agent 分组

4. 点击 Agent 卡片
   └─→ sourceTabProvider = '/home'
       chatProvider(agentId): 初始化
       ├─ 加载本地历史消息 → messageListProvider
       ├─ wsManager 建立实时通道
       └─ 加载快捷指令
```

#### 5.3.2 发送消息 → 接收回复 → 消息页查看

```
用户操作                          Provider 状态变化
─────────                        ─────────────────
1. 输入文字，点击发送
   └─→ chatProvider:
       ├─ 创建 Message(pending)
       ├─ messageListProvider: 追加用户消息
       ├─ wsManager.send(agentId, text)
       ├─ Message 状态: pending → sent
       ├─ isTyping = true (显示 TypingIndicator)
       └─ statsProvider: totalMessages++

2. Agent 返回回复
   └─→ wsManager.onMessage 回调:
       ├─ chatProvider: 追加 Agent 消息
       ├─ isTyping = false (隐藏 TypingIndicator)
       ├─ messageListProvider: 追加 Agent 消息
       ├─ conversationListProvider: 更新该 Agent 的最后消息和时间
       └─ statsProvider: totalMessages++

3. 点击返回（智能返回到虾列表）
   └─→ 导航到 sourceTabProvider 值 ('/home')
       chatProvider: autoDispose

4. 切换到 "消息" Tab
   └─→ conversationListProvider: 自动刷新排序
       该 Agent 排在最前，显示最新消息预览
```

#### 5.3.3 网络断开 → 消息暂存 → 重连同步

```
事件                              Provider 状态变化
────                              ─────────────────
1. 网络断开（connectivity_plus 监听）
   └─→ wsManager.onDisconnect(instanceId):
       ├─ instanceConnectionProvider: connected → disconnected
       ├─ connectionBannerProvider: show "网络已断开"
       └─ statsProvider: 在线数更新

2. 用户在断线期间发送消息
   └─→ chatProvider:
       ├─ Message 状态: pending
       ├─ pendingQueueProvider: 追加待发消息
       ├─ messageListProvider: 显示 "待发送" 图标
       └─ 消息写入本地 pending_messages 表

3. 网络恢复
   └─→ wsManager.onReconnect(instanceId):
       ├─ instanceConnectionProvider: disconnected → connecting → connected
       ├─ connectionBannerProvider: show "正在同步..."
       ├─ pendingQueueProvider: 按时间顺序逐条发送
       │   └─ 每条: Message 状态 pending → sent
       ├─ wsManager.fetchMissedMessages(instanceId, since: lastSyncTime)
       ├─ messageListProvider: 增量合并新消息（按 ID 去重）
       ├─ conversationListProvider: 更新排序
       └─ connectionBannerProvider: hide
```

---

## 6. WebSocket 通信层 (WebSocket Communication)

### 6.1 连接管理器架构

```
┌──────────────────────────────────────────────────────┐
│                 WebSocketManager                      │
│                                                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │  connections: Map<String, WebSocketConnection>   │  │
│  │  ┌───────────────┐ ┌───────────────┐            │  │
│  │  │ WSConnection   │ │ WSConnection   │  ...      │  │
│  │  │ (MacBook)      │ │ (Cloud·BJ)     │           │  │
│  │  │ ws://192...    │ │ wss://bj...    │           │  │
│  │  │ ● connected    │ │ ● connected    │           │  │
│  │  └───────────────┘ └───────────────┘            │  │
│  └─────────────────────────────────────────────────┘  │
│                                                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │  ReconnectPolicy (指数退避)                       │  │
│  │  initialDelay: 1s, maxDelay: 30s, factor: 2     │  │
│  └─────────────────────────────────────────────────┘  │
│                                                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │  MessageQueue (离线消息暂存)                      │  │
│  │  pendingMessages: List<PendingMessage>           │  │
│  └─────────────────────────────────────────────────┘  │
│                                                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │  EventBus (消息分发)                              │  │
│  │  onMessage / onToolCall / onStatusChange         │  │
│  └─────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

### 6.2 WebSocketConnection 类设计

```dart
/// 单实例 WebSocket 连接封装
class WebSocketConnection {
  final String instanceId;
  final String gatewayUrl;
  final String token;
  final String deviceId;

  WebSocket? _socket;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  // Streams
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<WsMessage>.broadcast();

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<WsMessage> get messageStream => _messageController.stream;
  ConnectionStatus get status => _status;

  /// 建立连接
  Future<void> connect() async {
    _updateStatus(ConnectionStatus.connecting);
    try {
      _socket = await WebSocket.connect(
        gatewayUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'X-Device-Id': deviceId,
        },
      ).timeout(const Duration(seconds: 10));

      _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );

      _reconnectAttempts = 0;
      _updateStatus(ConnectionStatus.connected);
      _startHeartbeat();
      _authenticate();
    } on TimeoutException {
      _updateStatus(ConnectionStatus.unreachable);
      _scheduleReconnect();
    } catch (e) {
      _updateStatus(ConnectionStatus.authFailed);
      _scheduleReconnect();
    }
  }

  /// 发送消息
  void send(WsMessage message) {
    if (_status == ConnectionStatus.connected && _socket != null) {
      _socket!.add(jsonEncode(message.toJson()));
    }
  }

  /// 发送聊天消息到指定 Agent
  void sendChatMessage({
    required String agentId,
    required String text,
    required String requestId,
  }) {
    send(WsMessage(
      type: 'req',
      id: requestId,
      method: 'agent.send_message',
      params: {
        'agent_id': agentId,
        'content': text,
      },
    ));
  }

  /// 拉取 Agent 列表
  void fetchAgents({required String requestId}) {
    send(WsMessage(
      type: 'req',
      id: requestId,
      method: 'agent.list',
      params: {},
    ));
  }

  /// 拉取消息历史（断线恢复）
  void fetchMessageHistory({
    required String agentId,
    required DateTime since,
    required String requestId,
  }) {
    send(WsMessage(
      type: 'req',
      id: requestId,
      method: 'session.get_messages',
      params: {
        'agent_id': agentId,
        'since': since.toIso8601String(),
      },
    ));
  }

  /// 心跳保活
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_status == ConnectionStatus.connected) {
        send(WsMessage(type: 'ping', id: '', method: '', params: {}));
      }
    });
  }

  /// 指数退避重连
  void _scheduleReconnect() {
    if (_reconnectAttempts >= 3) {
      // 超过 3 次，停止自动重连，等待用户手动触发
      return;
    }
    final delay = Duration(
      seconds: min(1 * pow(2, _reconnectAttempts).toInt(), 30),
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      connect();
    });
  }

  /// 数据处理
  void _onData(dynamic data) {
    try {
      final json = jsonDecode(data as String);
      final message = WsMessage.fromJson(json);
      _messageController.add(message);
    } catch (e) {
      Logger.error('WebSocket message parse error: $e');
    }
  }

  void _onError(dynamic error) {
    Logger.error('WebSocket error on $instanceId: $error');
    _updateStatus(ConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _onDone() {
    _heartbeatTimer?.cancel();
    _updateStatus(ConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _updateStatus(ConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  /// 认证握手
  void _authenticate() {
    send(WsMessage(
      type: 'req',
      id: const Uuid().v4(),
      method: 'auth.pair',
      params: {
        'token': token,
        'device_id': deviceId,
        'pairing_code': '', // 首次配对时由 OpenClaw 侧确认
      },
    ));
  }

  /// 断开连接
  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    _updateStatus(ConnectionStatus.disconnected);
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _statusController.close();
    _messageController.close();
  }
}
```

### 6.3 消息协议格式

```dart
/// WebSocket 消息封装
class WsMessage {
  final String type;       // "req" | "res" | "event" | "ping" | "pong"
  final String id;         // 请求唯一 ID (UUID v4)
  final String method;     // 方法名
  final Map<String, dynamic> params;  // 参数

  const WsMessage({
    required this.type,
    required this.id,
    required this.method,
    required this.params,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    'method': method,
    'params': params,
  };

  factory WsMessage.fromJson(Map<String, dynamic> json) => WsMessage(
    type: json['type'] as String,
    id: json['id'] as String? ?? '',
    method: json['method'] as String? ?? '',
    params: json['params'] as Map<String, dynamic>? ?? {},
  );
}
```

### 6.4 协议方法清单

| 方向 | method | 说明 | params |
|------|--------|------|--------|
| Client → Server | `auth.pair` | 认证握手（Token + Device ID + Pairing Code） | `{token, device_id, pairing_code}` |
| Client → Server | `agent.list` | 拉取实例下所有 Agent | `{}` |
| Client → Server | `agent.send_message` | 发送聊天消息到指定 Agent | `{agent_id, content}` |
| Client → Server | `session.get_messages` | 拉取 Session 历史消息（支持增量） | `{agent_id, since, limit?}` |
| Client → Server | `session.list` | 拉取所有 Session 列表 | `{}` |
| Server → Client | `event.message` | Agent 回复消息推送 | `{agent_id, message}` |
| Server → Client | `event.tool_call` | Agent 工具调用状态推送 | `{agent_id, tool_name, status, result}` |
| Server → Client | `event.agent_status` | Agent 在线状态变化推送 | `{agent_id, online}` |
| Client → Server | `ping` | 心跳请求 | `{}` |
| Server → Client | `pong` | 心跳响应 | `{}` |

### 6.5 认证流程

```
App                                          OpenClaw Gateway
 │                                                │
 │──── WebSocket Connect ─────────────────────────→│
 │     Headers: Authorization: Bearer <token>      │
 │              X-Device-Id: <uuid>                │
 │                                                │
 │←─── Connection Established ────────────────────│
 │                                                │
 │──── auth.pair ─────────────────────────────────→│
 │     { token, device_id, pairing_code }          │
 │                                                │
 │←─── auth.success / auth.failed ────────────────│
 │     { status: "ok" }  or  { error: "..." }     │
 │                                                │
 │     [认证成功后开始正常通信]                      │
```

### 6.6 多实例并行连接策略

```dart
/// WebSocketManager — 多实例连接管理
class WebSocketManager {
  final Map<String, WebSocketConnection> _connections = {};
  final AppDatabase database;

  /// 启动时连接所有已保存的在线实例
  Future<void> connectAll(List<Instance> instances) async {
    await Future.wait(instances.map((inst) async {
      if (inst.status == ConnectionStatus.connected ||
          inst.status == ConnectionStatus.disconnected) {
        await connectInstance(inst);
      }
    }));
  }

  /// 连接单个实例
  Future<void> connectInstance(Instance instance) async {
    // 防止重复连接
    _connections[instance.id]?.disconnect();

    final token = await SecureStorageService.getToken(instance.id);
    if (token == null) {
      Logger.warn('No token found for instance ${instance.id}');
      return;
    }

    final connection = WebSocketConnection(
      instanceId: instance.id,
      gatewayUrl: instance.gatewayUrl,
      token: token,
      deviceId: CryptoUtils.getDeviceId(),
    );

    _connections[instance.id] = connection;
    await connection.connect();
  }

  /// 断开单个实例
  void disconnectInstance(String instanceId) {
    _connections[instanceId]?.disconnect();
    _connections.remove(instanceId);
  }

  /// 获取所有连接状态流
  Stream<Map<String, ConnectionStatus>> get allStatusesStream {
    return StreamGroup.merge(
      _connections.values.map((c) => c.statusStream.map(
        (status) => {c.instanceId: status}
      )),
    ).scan<Map<String, ConnectionStatus>>(
      {},
      (acc, update) => {...acc, ...update},
      {},
    );
  }

  /// 发送消息到指定实例的指定 Agent
  void sendMessage(String instanceId, String agentId, String text) {
    final connection = _connections[instanceId];
    if (connection == null || connection.status != ConnectionStatus.connected) {
      // 存入待发送队列
      _enqueuePending(instanceId, agentId, text);
      return;
    }
    connection.sendChatMessage(
      agentId: agentId,
      text: text,
      requestId: const Uuid().v4(),
    );
  }

  /// 释放所有连接
  void disposeAll() {
    for (final conn in _connections.values) {
      conn.dispose();
    }
    _connections.clear();
  }
}
```

### 6.7 错误处理与离线队列

```dart
/// 离线消息暂存
class PendingMessageQueue {
  final AppDatabase _db;

  /// 消息发送失败时暂存
  Future<void> enqueue(PendingMessage msg) async {
    await _db.pendingMessageDao.insert(msg);
  }

  /// 重连后按时间顺序发送队列中的消息
  Future<void> flush(String instanceId, WebSocketConnection connection) async {
    final pending = await _db.pendingMessageDao.getByInstance(instanceId);
    for (final msg in pending) {
      connection.sendChatMessage(
        agentId: msg.agentId,
        text: msg.text,
        requestId: msg.requestId,
      );
      await _db.pendingMessageDao.delete(msg.id);
      // 短暂延迟防止 Gateway 过载
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 队列大小检查
  Future<int> count(String instanceId) async {
    return _db.pendingMessageDao.countByInstance(instanceId);
  }
}
```

---

## 7. 本地存储 (Local Storage)

### 7.1 存储策略总览

| 数据类型 | 存储方案 | 原因 |
|---------|---------|------|
| **实例配置** (name, url, icon, status) | Drift (SQLite) | 结构化数据，支持 CRUD + 排序查询 |
| **访问 Token** | flutter_secure_storage (Keychain/Keystore) | 安全加密，系统级保护 |
| **Agent 信息缓存** | Drift (SQLite) | 结构化数据，支持按 instanceId 查询 |
| **对话消息** | Drift (SQLite) + FTS5 | 大量结构化数据，需要全文搜索 |
| **Agent 个性化配置** (昵称、主题色、头像) | Hive (KV) | 轻量配置，key-value 形式足够 |
| **快捷指令** | Drift (SQLite) | 关联 Agent，需要 CRUD |
| **应用设置** (通知开关、免打扰时段) | Hive (KV) | 简单键值对 |
| **成就解锁状态** | Drift (SQLite) | 关联 Agent + 时间戳 |
| **未读消息计数** | Drift (SQLite) | 实时计算，关联消息表 |
| **设备 ID** | flutter_secure_storage | 持久化设备标识 |

### 7.2 Drift 数据库表结构

```dart
/// Drift 数据库定义
@DriftDatabase(tables: [
  Instances,
  Agents,
  Messages,
  PendingMessages,
  QuickCommands,
  Achievements,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // 创建 FTS5 虚拟表用于全文搜索
      await customStatement('''
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
          text,
          content='messages',
          content_rowid='id'
        )
      ''');
    },
  );
}

/// 实例表
class Instances extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get gatewayUrl => text()();
  TextColumn get icon => text().withDefault(const Constant('🖥️'))();
  IntColumn get status => intEnum<ConnectionStatus>()();
  DateTimeColumn get lastConnected => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Agent 表
class Agents extends Table {
  TextColumn get id => text()();
  TextColumn get instanceId => text().references(Instances, #id)();
  TextColumn get name => text()();
  TextColumn get emoji => text().withDefault(const Constant('🦐'))();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get theme => text().withDefault(const Constant('coral'))();
  BoolColumn get online => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastActive => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // 个性化配置
  TextColumn get customName => text().nullable()();
  TextColumn get customEmoji => text().nullable()();
  TextColumn get customTheme => text().nullable()();
  TextColumn get avatarPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 消息表
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get agentId => text().references(Agents, #id)();
  TextColumn get instanceId => text().references(Instances, #id)();
  IntColumn get sender => intEnum<MessageSender>()();
  IntColumn get type => intEnum<MessageContentType>()();
  TextColumn get text => text()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get filePath => text().nullable()();
  TextColumn get fileName => text().nullable()();
  IntColumn get status => intEnum<MessageStatus>()();
  DateTimeColumn get timestamp => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 待发送消息队列表
class PendingMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get agentId => text()();
  TextColumn get instanceId => text()();
  TextColumn get text => text()();
  TextColumn get requestId => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// 快捷指令表
class QuickCommands extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get agentId => text().references(Agents, #id)();
  TextColumn get label => text()();
  TextColumn get command => text()();
  IntColumn get sortOrder => integer()();
}

/// 成就解锁状态表
class Achievements extends Table {
  TextColumn get achievementId => text()();
  TextColumn get agentId => text().references(Agents, #id)();
  BoolColumn get unlocked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get unlockedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {achievementId, agentId};
}
```

### 7.3 存储容量管理

```dart
/// 存储容量管理策略
class StorageManager {
  static const int maxMessagesPerAgent = 1000;   // 每个 Agent 最多缓存 1000 条消息
  static const int maxTotalMessages = 5000;       // 全局消息上限

  /// 清理超限消息（保留最新的，删除最早的）
  Future<void> trimMessages(String agentId, AppDatabase db) async {
    final count = await db.messageDao.countByAgent(agentId);
    if (count > maxMessagesPerAgent) {
      final deleteCount = count - maxMessagesPerAgent;
      await db.messageDao.deleteOldest(agentId, deleteCount);
    }
  }

  /// 全局清理
  Future<void> trimAll(AppDatabase db) async {
    final totalCount = await db.messageDao.countAll();
    if (totalCount > maxTotalMessages) {
      // 按 Agent 维度均衡清理
      final agents = await db.agentDao.getAll();
      for (final agent in agents) {
        await trimMessages(agent.id, db);
      }
    }
  }
}
```

---

## 8. 导航架构 (Navigation)

### 8.1 GoRouter 路由定义

```dart
/// 路由配置
final appRouter = GoRouter(
  initialLocation: '/home',
  debugLogDiagnostics: kDebugMode,
  redirect: _globalRedirect,
  routes: [
    // ===== Shell Route — 包含 BottomNavBar =====
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        // 虾列表（主页）
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const HomePage(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        // 消息页
        GoRoute(
          path: '/messages',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const MessagesPage(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        // 实例管理页
        GoRoute(
          path: '/instances',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const InstancesPage(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
      ],
    ),

    // ===== 独立页面（无 BottomNavBar）=====

    // 添加实例
    GoRoute(
      path: '/instances/add',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const AddInstancePage(),
        transitionsBuilder: _slideTransition,
      ),
    ),

    // 对话页面
    GoRoute(
      path: '/chat/:agentId',
      pageBuilder: (context, state) {
        final agentId = state.pathParameters['agentId']!;
        return CustomTransitionPage(
          key: state.pageKey,
          child: ChatPage(agentId: agentId),
          transitionsBuilder: _slideTransition,
        );
      },
    ),

    // 虾详情页
    GoRoute(
      path: '/agent/:agentId/detail',
      pageBuilder: (context, state) {
        final agentId = state.pathParameters['agentId']!;
        return CustomTransitionPage(
          key: state.pageKey,
          child: AgentDetailPage(agentId: agentId),
          transitionsBuilder: _slideTransition,
        );
      },
    ),

    // 虾个性化配置页
    GoRoute(
      path: '/agent/:agentId/config',
      pageBuilder: (context, state) {
        final agentId = state.pathParameters['agentId']!;
        return CustomTransitionPage(
          key: state.pageKey,
          child: AgentConfigPage(agentId: agentId),
          transitionsBuilder: _slideTransition,
        );
      },
    ),

    // 搜索页
    GoRoute(
      path: '/search',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const SearchPage(),
        transitionsBuilder: _slideTransition,
      ),
    ),

    // 设置页
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const SettingsPage(),
        transitionsBuilder: _slideTransition,
      ),
    ),
  ],
);
```

### 8.2 路由守卫

```dart
/// 全局路由守卫 — 生物识别解锁检查
Future<String?> _globalRedirect(BuildContext context, GoRouterState state) async {
  final settings = context.read(settingsProvider);

  // 生物识别解锁检查
  if (settings.biometricEnabled && !AuthService.isUnlocked) {
    // 排除已在解锁页的情况
    if (state.matchedLocation != '/unlock') {
      return '/unlock';
    }
  }

  return null; // 不拦截，正常导航
}
```

### 8.3 Deep Link 支持

```dart
/// Deep Link 路由映射
/// 
/// xiahub://chat/{agentId}           → 直接进入对话
/// xiahub://agent/{agentId}/detail   → 进入虾详情
/// xiahub://instances/add            → 添加实例页
/// 
/// 通知点击跳转也使用 Deep Link 机制：
/// flutter_local_notifications → onDidReceiveNotificationResponse
///   → GoRouter.go('xiahub://chat/$agentId')
```

### 8.4 智能返回实现

```dart
/// MainShell — 底部导航壳组件
class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavBar(
        currentIndex: _calculateIndex(context),
        onTap: (index) {
          final routes = ['/home', '/messages', '/instances'];
          // 更新来源 Tab
          context.read(sourceTabProvider.notifier).state = routes[index];
          context.go(routes[index]);
        },
      ),
    );
  }

  int _calculateIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/messages')) return 1;
    if (location.startsWith('/instances')) return 2;
    return 0; // 默认 home
  }
}

/// 对话页面返回逻辑
class ChatPage extends ConsumerWidget {
  // ...
  void _handleBack(BuildContext context) {
    final sourceTab = context.read(sourceTabProvider);
    context.go(sourceTab); // 返回到来源 Tab
  }
}
```

### 8.5 导航流程图

```
┌──────────────────────────────────────────────────────┐
│                    MainShell                          │
│  ┌─────────┐  ┌───────────┐  ┌────────────┐         │
│  │  /home   │  │ /messages  │  │ /instances │  ← Tab │
│  │ 虾列表   │  │ 消息       │  │ 实例       │         │
│  └────┬────┘  └─────┬─────┘  └──────┬─────┘         │
│       │              │               │                │
└───────┼──────────────┼───────────────┼────────────────┘
        │              │               │
        ▼              ▼               ▼
   /chat/:id      /chat/:id      /instances/add
   (from home)    (from msgs)    (添加实例)
        │              │
        ▼              ▼
  /agent/:id/     /search
  detail          (全局搜索)
        │
        ▼
  /agent/:id/
  config
  (个性化配置)

  /settings  ← 从任意 Header 图标进入
```

---

## 9. 设计系统集成 (Design System Integration)

### 9.1 ThemeData 实现

```dart
/// Flutter ThemeData 映射 — 暗色 Premium 主题
class AppTheme {
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: DT.bg,
    canvasColor: DT.bg,

    // 色彩方案
    colorScheme: const ColorScheme.dark(
      primary: DT.accent,
      onPrimary: Colors.white,
      secondary: DT.accent,
      surface: DT.surface,
      onSurface: DT.text1,
      error: DT.red,
      onError: Colors.white,
    ),

    // 文本样式
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: DT.text1,
        letterSpacing: -0.6,
        height: 1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: DT.text1,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: DT.text1,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: DT.text1,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: DT.text1,
        letterSpacing: -0.2,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: DT.text1,
        height: 1.6,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: DT.text3,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: DT.text3,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: DT.text3,
        letterSpacing: 0.8,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: DT.text4,
        letterSpacing: 0.3,
      ),
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: DT.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: DT.text1,
      ),
      iconTheme: IconThemeData(color: DT.text2),
    ),

    // Input
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DT.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DT.rMd),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DT.rMd),
        borderSide: const BorderSide(color: DT.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DT.s5,
        vertical: DT.s3,
      ),
      hintStyle: TextStyle(color: DT.text4, fontSize: 15),
    ),

    // 字体
    fontFamily: null, // 使用系统默认（SF Pro on iOS, Roboto on Android）
  );
}
```

### 9.2 自定义 Widget Catalog

| Widget | 对应原型 CSS Class | Flutter 实现要点 |
|--------|-------------------|-----------------|
| `StatChip` | `.stat-chip` | Container + Column，flex: 1，surface 背景，rLg 圆角 |
| `StatusDot` | `.instance-dot` / `.status-dot` | Container 6-8px 圆点，在线时加 BoxShadow 发光 |
| `AgentCard` | `.agent-card` | Container + Row，surface 背景，scale(0.98) 点击反馈 |
| `ConversationItem` | `.msg-item` | InkWell + Row，底部 4% 白色分隔线 |
| `UnreadBadge` | `.msg-unread` | Container 18px 圆形，accent 背景，白色数字 |
| `MessageBubbleUser` | `.msg.user` | Container，accent 背景，白色文字，右下角 rSm |
| `MessageBubbleAgent` | `.msg.agent` | Container，surface 背景，shadowS，左下角 rSm |
| `TypingIndicator` | `.typing-indicator` | Row + 3 个 AnimatedContainer，交错 AnimationController |
| `ToolCallCard` | `.tool-card` | Container，surface2 背景，左侧 3px accent 边框 |
| `QuickCommandChip` | `.quick-cmd` | ActionChip 样式，surface2 背景，accent 文字，rFull |
| `MessageInput` | `.msg-input` | TextField，maxLines: 5，surface 背景，rLg，自动高度 |
| `BottomNavBar` | `.bottom-nav` | BottomNavigationBar，毛玻璃效果：`ClipRRect + BackdropFilter` |
| `InstanceCard` | `.inst-card` | Container + Row，surface 背景，rLg |
| `AddInstanceButton` | `.add-inst-btn` | OutlinedButton，虚线边框（CustomPainter），accent 文字 |
| `TabSwitcher` | `.tab-row` | 自定义 segmented control，surface 背景 + 3px padding |
| `FormInput` | `.form-input` | TextField，surface 背景，内阴影（boxShadow inset 模拟） |
| `PrimaryButton` | `.primary-btn` | ElevatedButton，accent 背景，accent glow boxShadow |
| `ColorDot` | `.color-dot` | GestureDetector + Container 40px，selected 态 border + check icon |
| `CommandItemRow` | `.cmd-item` | Row + ReorderableListView 拖拽手柄 |
| `AchievementItem` | `.achievement` | Container + Row，locked 态 opacity 0.35 |
| `SettingRow` | `.setting-row` | ListTile 样式，底部 4% 白色分隔线 |
| `ToastOverlay` | `.toast` | Overlay + AnimatedOpacity，rFull，backdrop-filter blur |
| `ConnectionBanner` | `.conn-banner` | SlideTransition + Container，黄色/accent 背景 |

### 9.3 毛玻璃 BottomNavBar 实现

```dart
/// 毛玻璃效果底部导航栏
class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 72 + MediaQuery.of(context).padding.bottom,
          decoration: BoxDecoration(
            color: DT.bg.withOpacity(0.88),
            border: Border(
              top: BorderSide(
                color: DT.text1.withOpacity(0.04),
                width: 1,
              ),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home,
                       label: '虾列表', index: 0),
              _NavItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble,
                       label: '消息', index: 1),
              _NavItem(icon: Icons.dns_outlined, activeIcon: Icons.dns,
                       label: '实例', index: 2),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 9.4 响应式适配

| 屏幕 | 策略 | 说明 |
|------|------|------|
| **小屏 (iPhone SE, 375px)** | 默认适配 | 所有间距使用 Design Token，自动收缩 |
| **标准 (iPhone 14/15, 390-393px)** | 最佳体验 | 原型设计基准尺寸 |
| **大屏 (iPhone Pro Max, 430px)** | 内容区自然扩展 | 消息气泡 maxWidth 78%，列表自然填充 |
| **Android 主流机型** | 自适应 | MediaQuery 获取安全区域，StatusBar 适配 |
| **Safe Area** | 全面支持 | `SafeArea` Widget 包裹，底部导航 + 输入区域适配 |

```dart
/// 消息气泡最大宽度自适应
class MessageBubbleUser extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.78;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: DT.s5, vertical: DT.s3),
          decoration: BoxDecoration(
            color: DT.accent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(DT.rXl),
              topRight: Radius.circular(DT.rXl),
              bottomLeft: Radius.circular(DT.rXl),
              bottomRight: Radius.circular(DT.rSm), // 小圆角
            ),
          ),
          child: Text(text, style: TextStyle(color: Colors.white, fontSize: 15, height: 1.6)),
        ),
      ),
    );
  }
}
```

---

## 10. 开发里程碑 (Development Milestones)

### Phase 1：项目基建 + 设计系统（第 1-2 周）

**目标**：搭建项目脚手架，实现设计系统和核心基础设施

| 任务 | 工时 | 交付物 | 对应 User Story |
|------|------|--------|----------------|
| Flutter 项目初始化 + 依赖配置 | 0.5d | 可运行空项目 | US-012 |
| Design Tokens 实现（`design_tokens.dart`） | 0.5d | 完整色彩/间距/圆角/阴影常量 | — |
| ThemeData 配置（`app_theme.dart`） | 0.5d | 暗色主题生效 | — |
| Drift 数据库表定义 + Migration | 1d | 所有表结构就绪 | — |
| `flutter_secure_storage` 封装 | 0.5d | Token 存取 API | — |
| GoRouter 路由配置 + 导航框架 | 1d | 三 Tab 导航可切换 | US-006 |
| `BottomNavBar` 毛玻璃组件 | 0.5d | 底部导航栏 | US-006 |
| 共享 Widget 库（Avatar、StatusDot、EmptyState、Buttons） | 1d | 可复用组件集 | — |
| Hive 偏好设置封装 | 0.5d | 设置读写 API | — |
| **里程碑验收** | — | App 可启动，三 Tab 导航正常切换，暗色主题生效 | — |

### Phase 2：WebSocket 通信层 + 实例管理（第 3-4 周）

**目标**：实现 WebSocket 连接管理器，完成实例增删改查

| 任务 | 工时 | 交付物 | 对应 User Story |
|------|------|--------|----------------|
| `WebSocketConnection` 单连接封装 | 1.5d | 连接/断开/心跳/重连 | US-012 |
| `WebSocketManager` 多实例管理器 | 1d | 并行连接管理 | — |
| 协议解析（`WsMessage` + 方法路由） | 1d | 消息收发通路 | — |
| 扫码添加实例（`mobile_scanner`） | 1d | QR 扫描 + 解析 | US-001 |
| 手动添加实例表单 + URL 校验 | 0.5d | 表单页 UI + 验证 | US-002 |
| 连通性测试 + 错误处理 | 1d | 成功/失败/超时/认证错误 | US-001, US-002 |
| 实例列表页（`InstanceCard` + 状态展示） | 1d | 实例管理 UI | US-003 |
| 实例删除（二次确认 + 级联清理） | 0.5d | 删除功能 | US-003 |
| 应用启动静默连通性检测 | 0.5d | 启动时自动检测 | US-003 |
| 网络状态监听（`connectivity_plus`） | 0.5d | 网络变化感知 | — |
| **里程碑验收** | — | 可扫码/手动添加实例，连通性测试通过，实例列表正常展示 | — |

### Phase 3：Agent 列表 + 对话界面（第 5-6 周）

**目标**：实现核心对话功能，完成 MVP 的主体功能

| 任务 | 工时 | 交付物 | 对应 User Story |
|------|------|--------|----------------|
| Agent 列表从 Gateway 拉取 + 本地缓存 | 1d | Agent 数据通路 | US-004 |
| `InstanceGroup` 分组折叠/展开 | 0.5d | 分组列表 UI | US-004 |
| `AgentCard` 组件（头像、名称、状态） | 0.5d | Agent 卡片 | US-004 |
| `StatsBar` 顶部统计栏 | 0.5d | 全局统计数据 | US-005 |
| 下拉刷新 + 离线缓存展示 | 0.5d | 刷新 + 降级策略 | US-004 |
| `ChatPage` 整体布局 | 0.5d | 对话页面框架 | US-007 |
| 消息发送 + WebSocket 通信 | 1d | 消息收发核心 | US-007 |
| `MessageBubbleUser` + `MessageBubbleAgent` | 0.5d | 消息气泡 UI | US-007 |
| `MarkdownBody` 渲染（代码高亮） | 1.5d | Markdown 支持 | US-007 |
| `TypingIndicator` 加载动画 | 0.5d | 三点跳动动画 | US-007 |
| `ToolCallCard` 工具调用卡片 | 0.5d | 工具状态展示 | US-008 |
| `QuickCommandsBar` 快捷指令 | 0.5d | 横向标签 + 点击发送 | US-009 |
| `ChatInputArea` + 多行输入 | 0.5d | 输入框 + 发送按钮 | US-007 |
| `ConnectionBanner` 连接状态横幅 | 0.5d | 断线/重连提示 | US-007 |
| 消息超时处理（60s） | 0.5d | 超时提示 + 取消选项 | US-007 |
| **里程碑验收** | — | 可选择 Agent 进入对话，发送/接收消息，Markdown 正确渲染 | — |

### Phase 4：消息页 + 智能返回 + MVP 收尾（第 7 周）

**目标**：完成 MVP 全部 P0 功能

| 任务 | 工时 | 交付物 | 对应 User Story |
|------|------|--------|----------------|
| 消息页（对话列表）UI + 排序 | 1.5d | 微信式消息列表 | US-010 |
| 消息预览 + 时间格式化 | 0.5d | 最后消息摘要 | US-010 |
| `UnreadBadge` 未读角标 | 0.5d | 红色角标 | US-010 |
| 空状态引导页 | 0.5d | 无对话历史引导 | US-010 |
| 智能返回逻辑（`sourceTabProvider`） | 0.5d | 返回到来源 Tab | US-011 |
| 消息本地持久化 + 历史加载 | 1d | 对话记录不丢失 | — |
| 联调 + 集成测试 | 1.5d | 全链路测试 | — |
| **里程碑验收** | — | MVP 全部 P0 功能可用，可提交 TestFlight / APK | — |

### Phase 5：个性化 + 离线增强（第 8-9 周，V1.1）

**目标**：完成 P1 功能，提升用户体验

| 任务 | 工时 | 交付物 | 对应 User Story |
|------|------|--------|----------------|
| 虾个性化配置页 UI | 1.5d | 配置页面完整 | US-013 |
| `AvatarEditor`（emoji 更换 + 图片选择） | 1d | 头像编辑 | US-013 |
| `ColorPickerGrid`（12 色选择器） | 0.5d | 主题色选择 | US-013 |
| 主题色应用（对话页导航栏 + 气泡色调） | 0.5d | 主题色生效 | US-013 |
| `CommandListEditor`（指令增删排序） | 1d | 快捷指令管理 | US-014 |
| 离线消息暂存（`PendingMessageQueue`） | 1.5d | 断线消息不丢失 | US-015 |
| 指数退避重连 + 手动重试 | 1d | 自动/手动重连 | US-016 |
| 断线消息增量同步 + 去重 | 1.5d | 消息自动合并 | US-016 |
| V1.1 测试 + Bug 修复 | 1.5d | 稳定版本 | — |
| **里程碑验收** | — | 个性化配置生效，断线消息不丢失，重连自动同步 | — |

### Phase 6：搜索 + 通知 + 成长面板（第 10-12 周，V1.2）

**目标**：完成 P2 增值功能，发布正式版

| 任务 | 工时 | 交付物 | 对应 User Story |
|------|------|--------|----------------|
| 全局搜索页 + FTS5 全文搜索 | 1.5d | 搜索结果展示 | US-017 |
| 搜索高亮 + 跳转到对话定位 | 1d | 消息定位 | US-017 |
| 本地推送通知（`flutter_local_notifications`） | 1.5d | 任务完成提醒 | US-018 |
| 免打扰时段 + 通知开关 | 1d | 通知偏好 | US-018 |
| iOS 后台保活技术预研 + 实现 | 1.5d | 后台 WebSocket | US-018 |
| 虾成长面板（统计卡片 + 时间线） | 1d | 成长数据展示 | US-019 |
| 成就系统（解锁逻辑 + 庆祝动画） | 1d | 成就徽章 | US-020 |
| 生物识别解锁（`local_auth`） | 0.5d | Face ID / 指纹 | — |
| V1.2 全面测试 + 修复 | 2d | 稳定版本 | — |
| 应用商店审核材料 + 发布 | 1d | 上架准备 | — |
| **里程碑验收** | — | 全部功能完成，提交 App Store / Google Play 审核 | — |

### 里程碑总览

```
Week 1-2    ████░░░░░░░░░░░░░░░░░░  Phase 1: 项目基建 + 设计系统
Week 3-4    ░░░░████░░░░░░░░░░░░░░  Phase 2: WebSocket + 实例管理
Week 5-6    ░░░░░░░░████░░░░░░░░░░  Phase 3: Agent 列表 + 对话界面
Week 7      ░░░░░░░░░░░░██░░░░░░░░  Phase 4: 消息页 + MVP 收尾
                                              ▲ MVP 发布
Week 8-9    ░░░░░░░░░░░░░░░░████░░  Phase 5: 个性化 + 离线增强
                                              ▲ V1.1 发布
Week 10-12  ░░░░░░░░░░░░░░░░░░████  Phase 6: 搜索 + 通知 + 成长面板
                                              ▲ V1.2 正式发布
```

---

## 附录 A：技术风险与缓解措施

| 风险 | 影响 | 概率 | 缓解方案 |
|------|------|------|---------|
| OpenClaw Gateway API 版本间 breaking change | 高 | 中 | 在 `ws_protocol.dart` 中设计 API 适配层，隔离协议变化；订阅 OpenClaw release 通知 |
| iOS 后台 WebSocket 保活受限 | 中 | 高 | 使用 BGTaskScheduler + 合理心跳间隔（后台 60s）；降级方案：下次打开时同步；评估 APNs 远程推送 |
| 多实例 WebSocket 连接内存占用 | 中 | 中 | 限制同时活跃连接数（最多 5 个）；非活跃连接降频心跳；监控内存使用 |
| Markdown 渲染移动端适配复杂 | 低 | 中 | `flutter_markdown` + 自定义 StyleSheet；代码块使用 `flutter_highlight`；表格降级为横向滚动 |
| 内网实例外网不可达 | 高 | 高 | MVP 文档引导用户配置 Tailscale / 端口转发；V1.1 集成 openclaw-bridge 中继 |

## 附录 B：与 PRD 验收标准映射

| 验收标准 | 技术实现 | 所在 Phase |
|---------|---------|-----------|
| AC-01 扫码添加实例 | `mobile_scanner` + QR 解析 + `WebSocketConnection.connect()` | Phase 2 |
| AC-02 手动添加实例 | `ManualForm` + `validators.dart` URL 校验 | Phase 2 |
| AC-03 连接失败处理 | `WebSocketConnection` TimeoutException 处理 | Phase 2 |
| AC-04 查看 Agent 列表 | `groupedAgentListProvider` + `InstanceGroup` + `AgentCard` | Phase 3 |
| AC-05 查看消息列表 | `conversationListProvider` + `ConversationItem` | Phase 4 |
| AC-06 发送文字消息 | `ChatNotifier.send()` + `WebSocketConnection.sendChatMessage()` | Phase 3 |
| AC-07 Markdown 渲染 | `flutter_markdown` + `flutter_highlight` | Phase 3 |
| AC-08 工具调用展示 | `ToolCallCard` + `event.tool_call` 事件监听 | Phase 3 |
| AC-09 从消息页进入对话 | `GoRouter.push('/chat/$agentId')` + `sourceTabProvider` | Phase 4 |
| AC-10 智能返回 | `sourceTabProvider` + `GoRouter.go(sourceTab)` | Phase 4 |
| AC-11 断线消息暂存 | `PendingMessageQueue` + `pendingQueueProvider` | Phase 5 |
| AC-12 重连自动同步 | `WebSocketConnection._scheduleReconnect()` + `flush()` | Phase 5 |
| AC-13 个性化配置 | `AgentConfigPage` + `agentConfigProvider` | Phase 5 |
| AC-14 快捷指令使用 | `QuickCommandsBar` + `ChatNotifier.sendQuickCommand()` | Phase 3 |
| AC-15 全局搜索 | Drift FTS5 + `SearchPage` + `searchProvider` | Phase 6 |
| AC-16 推送通知 | `flutter_local_notifications` + WebSocket 后台监听 | Phase 6 |
| AC-17 成长面板 | `agentStatsProvider` + `StatsGrid` + `AchievementList` | Phase 6 |
| AC-18 里程碑庆祝 | `MilestoneCelebrationOverlay` + `achievementProvider` | Phase 6 |
| AC-19 删除实例 | `InstanceListNotifier.delete()` + 级联清理 | Phase 2 |
| AC-20 生物识别解锁 | `local_auth` + GoRouter redirect guard | Phase 6 |

---

*文档结束。本文档将随开发进展持续更新。*
