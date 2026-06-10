# Agent Profile Page 设计文档 (v2 — 经架构审查修订)

**日期**：2026-06-10
**修订**：2026-06-10（架构审查 — 5 项问题 + 5 项优化建议全部吸收）
**范围**：AgentProfilePage（详情页）+ AgentConfigPage（配置页）
**关联 US**：US-013（虾个性化配置, P1）、US-019（成长面板, P2 占位）、US-020（成就系统, P2 占位）
**原型参考**：`docs/虾Hub-原型Demo.html` — `page-agent-detail` + `page-agent-config`

---

## 1. 路由

```
/agent-profile/:agentId          → AgentProfilePage (详情/只读)
/agent-profile/:agentId/config   → AgentConfigPage (编辑/保存)
```

导航入口：
- 从 ChatRoomPage AppBar 标题点击或 more_vert 菜单 → push agentProfile
- 从 AgentListPage 点击 → push agentProfile（新入口，待 US 后续添加）
- AgentProfilePage ✏️ 按钮 → push config（config 页与 profile 页共享同一个 ViewModel）
- AgentConfigPage 返回按钮 → pop

---

## 2. ViewModel 与状态管理

### 架构决策：共享 ViewModel

AgentConfigPage 是 AgentProfilePage 的子路由，Config 页的保存结果需要立即反映到 Profile 页。采用**两个页面 watch 同一个 ViewModel** 的架构，而非通过 `ref.invalidate` 隐式耦合。

```
AgentProfileViewModel (StateNotifier<AgentProfileState>)
├── init()      — 加载 agent + instance + messageCount
├── refresh()   — 重新加载（下拉刷新、config pop 后调用）
├── saveProfile(localId, nickname, themeColor) — 保存配置
├── clearSaveResult() — 消费 saveSuccess/saveError 后重置
└── dispose()   — 释放资源

AgentProfilePage  watch → state.detailLoadState + state.saveSuccess
AgentConfigPage   watch → 同一个 VM
                        → state.isSaving / state.saveSuccess / state.saveError
                        → 调用 vm.saveProfile(...)  ← Law 2 合规
```

### State 定义

```dart
/// Agent 资料页的不可变状态快照
/// 同时服务 Profile 页（消费 detailLoadState）和 Config 页（消费 isSaving/saveError/saveSuccess）
class AgentProfileState {
  final LoadState<AgentDetailData> detailLoadState;
  final bool isSaving;       // Config 页：保存中
  final String? saveError;   // Config 页：保存失败文案
  final bool saveSuccess;    // Config 页：保存成功（触发 pop）

  const AgentProfileState({
    this.detailLoadState = const LoadInProgress(),
    this.isSaving = false,
    this.saveError,
    this.saveSuccess = false,
  });

  AgentProfileState copyWith({...});

  @override
  bool operator ==(Object other) => ...;

  @override
  int get hashCode => Object.hash(detailLoadState, isSaving, saveError, saveSuccess);
}
```

### ViewModel

```dart
class AgentProfileViewModel extends StateNotifier<AgentProfileState> {
  final IAgentRepo _agentRepo;
  final IInstanceRepo _instanceRepo;
  final IMessageRepo _messageRepo;
  final String agentId;

  Agent? _agent; // 缓存，供 Config 页读取初始值

  Agent? get agent => _agent;

  AgentProfileViewModel({
    required IAgentRepo agentRepo,
    required IInstanceRepo instanceRepo,
    required IMessageRepo messageRepo,
    required this.agentId,
  })  : _agentRepo = agentRepo,
       _instanceRepo = instanceRepo,
       _messageRepo = messageRepo,
       super(const AgentProfileState());

  /// 初始化：加载 agent 详情 + 实例信息 + 消息统计
  Future<void> init() async {
    await refresh();
  }

  /// 重新加载数据（外部触发：下拉刷新、config 保存后）
  Future<void> refresh() async {
    _updateState((s) => s.copyWith(detailLoadState: const LoadInProgress()));

    try {
      final agent = await _agentRepo.getById(agentId);
      if (agent == null) throw AgentNotFoundError(agentId);

      _agent = agent;

      Instance? instance;
      try {
        instance = await _instanceRepo.getById(agent.instanceId);
      } catch (_) {
        // instance 可能不存在（实例被删除），非致命错误
      }

      final messageCount = await _messageRepo.getMessageCount(agentId);

      _updateState((s) => s.copyWith(
        detailLoadState: LoadData(AgentDetailData(
          agent: agent,
          instance: instance,
          messageCount: messageCount,
        )),
      ));
    } catch (error, stackTrace) {
      _updateState((s) => s.copyWith(
        detailLoadState: LoadError(error, stackTrace),
      ));
    }
  }

  /// 保存个性化配置（由 Config 页调用）
  Future<void> saveProfile(String localId, String? nickname, String themeColor) async {
    _updateState((s) => s.copyWith(isSaving: true, saveError: null, saveSuccess: false));
    try {
      await _agentRepo.updateLocalProfile(
        localId,
        nickname: nickname,
        themeColor: themeColor,
      );
      // 保存成功后刷新详情数据，让 Profile 页看到最新值
      await refresh();
      _updateState((s) => s.copyWith(isSaving: false, saveSuccess: true));
    } catch (error, stackTrace) {
      debugPrint('AgentConfig save failed: $error\n$stackTrace');
      _updateState((s) => s.copyWith(
        isSaving: false,
        saveError: '保存失败，请重试',
      ));
    }
  }

  /// 消费保存结果（Config 页 pop 后或 SnackBar 展示后调用）
  void clearSaveResult() {
    _updateState((s) => s.copyWith(saveSuccess: false, saveError: null));
  }

  void _updateState(AgentProfileState Function(AgentProfileState) transform) {
    state = transform(state);
  }

  @override
  void dispose() {
    super.dispose();
  }
}
```

### Provider

```dart
// lib/features/agent_profile/providers/agent_profile_providers.dart

final agentProfileViewModelProvider =
    StateNotifierProvider.family<AgentProfileViewModel, AgentProfileState, String>(
  (ref, agentId) {
    final vm = AgentProfileViewModel(
      agentRepo: ref.watch(agentRepoProvider),
      instanceRepo: ref.watch(instanceRepoProvider),
      messageRepo: ref.watch(messageRepoProvider),
      agentId: agentId,
    );
    vm.init();
    ref.onDispose(() => vm.dispose());
    return vm;
  },
);
```

### 数据模型

```dart
/// Agent 详情聚合数据（不可变值对象）
class AgentDetailData {
  final Agent agent;
  final Instance? instance;    // null = 实例不存在/已删除
  final int messageCount;

  const AgentDetailData({
    required this.agent,
    this.instance,
    required this.messageCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentDetailData &&
          agent == other.agent &&
          instance == other.instance &&
          messageCount == other.messageCount;

  @override
  int get hashCode => Object.hash(agent, instance, messageCount);
}
```

> **注意**：AgentDetailData **不**包含 `Conversation` 字段。`getOrCreate` 是有副作用的写操作（会创建"幽灵会话"），不应在纯读取页面调用。未来 US-019 需要"对话次数"时通过专用查询返回。

### 错误处理

| 场景 | ViewModel 行为 | UI 行为 |
|------|---------------|--------|
| Agent 不存在 | `LoadError(AgentNotFoundError)` | ErrorBoundary "虾不存在或已被删除" |
| 实例不存在 | `instance = null`（非致命） | StatusRow 显示 "未知实例" |
| 网络/加载失败 | `LoadError(error, stackTrace)` | ErrorBoundary + retry |
| 保存失败 | `saveError = '...'` | SnackBar 展示后调用 `clearSaveResult()` |

### AgentNotFoundError

```dart
// lib/domain/models/errors.dart（或在 agent.dart 同级新建）
class AgentNotFoundError implements Exception {
  final String agentId;
  const AgentNotFoundError(this.agentId);

  @override
  String toString() => 'Agent not found: $agentId';
}
```

---

## 3. AgentProfilePage（详情页）

### 组件树

```
AgentProfilePage (ConsumerStatefulWidget)
├── AppBar
│   ├── BackButton (smart back: chat page or source tab)
│   ├── Title: agent.displayName
│   └── EditButton (✏️ → push config page)
├── Body: ref.watch(agentProfileViewModelProvider(agentId))
│   ├── loading → LoadingSkeleton
│   ├── error  → ErrorBoundary with retry
│   └── data   → ListView
│       ├── ProfileHeader
│       │   ├── EmojiAvatar (大圆圈, 主题色背景+边框, displayName 首字符)
│       │   ├── AgentName + ⚡PinBadge (isPinned 时显示)
│       │   ├── Description text (灰色, max 2 lines)
│       │   └── StatusRow (green/gray dot + 在线/离线 + 实例名)
│       ├── StatsGrid (3 columns × 2 rows)
│       │   ├── Row 1: 对话次数 / 消息总数 / 工具调用
│       │   │   (仅消息总数为实数，其余 "--" 占位)
│       │   └── Row 2: 活跃天数 / 连续天数 / 首次对话
│       │       (全部 "--" 占位)
│       ├── FutureBanner ("📊 完整成长数据将在 V1.2 上线后可用")
│       └── AchievementsPlaceholder ("更多数据积累后解锁成就系统…")

// Widget 仅转发事件 (Law 2)
// 详情页不直接操作 Repo — 所有操作通过 ViewModel
```

### Widget 伪代码

```dart
class AgentProfilePage extends ConsumerStatefulWidget {
  final String agentId;
  final String? source;
  const AgentProfilePage({required this.agentId, this.source});

  @override
  ConsumerState<AgentProfilePage> createState() => _AgentProfilePageState();
}

class _AgentProfilePageState extends ConsumerState<AgentProfilePage> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProfileViewModelProvider(widget.agentId));

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _handleBack),
        title: Text(/* agent.displayName */),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // push config — config 页 watch 同一个 VM
              context.push(
                AppRoutes.agentConfigWithParams(widget.agentId),
              );
            },
          ),
        ],
      ),
      body: switch (state.detailLoadState) {
        LoadInProgress() => const LoadingSkeleton(count: 3),
        LoadError(:final error) => ErrorBoundary(error: error, onRetry: () {
            ref.read(agentProfileViewModelProvider(widget.agentId).notifier).refresh();
          }),
        LoadData(:final value) => ListView(
            children: [
              ProfileHeader(agent: value.agent, instance: value.instance),
              StatsGrid(messageCount: value.messageCount),
              // ... banner + placeholder
            ],
          ),
      },
    );
  }
}
```

---

## 4. AgentConfigPage（配置页）

### 组件树

```
AgentConfigPage (ConsumerStatefulWidget)
├── PopScope (canPop: !state.isSaving)
│   └── Scaffold
│       ├── AppBar
│       │   ├── BackButton
│       │   └── Title: "{agent.displayName} · 个性化配置"
│       └── ListView
│           ├── Section: 🦐 基本信息
│           │   ├── CurrentAvatar (只读展示，首字符 + 主题色)
│           │   └── NicknameField (TextField, maxLength: 20)
│           ├── Section: 🎨 主题色
│           │   └── ColorGrid (12色, 6×2 grid)
│           └── SaveButton
│               ├── idle: "💾 保存配置"
│               ├── saving: CircularProgressIndicator + "保存中..."
│               └── → 调用 vm.saveProfile(...)
// Widget 仅转发事件 (Law 2)
// save 成功 → state.saveSuccess = true → pop
// save 失败 → state.saveError = '...' → show SnackBar + clearSaveResult()
```

### 状态管理

表单字段（nickname, themeColor）使用 `ConsumerState` 本地字段（Law 5 例外：纯 UI 状态）。保存操作委托给 ViewModel（Law 2 合规）：

```dart
class AgentConfigPage extends ConsumerStatefulWidget {
  final String agentId;
  const AgentConfigPage({required this.agentId});

  @override
  ConsumerState<AgentConfigPage> createState() => _AgentConfigPageState();
}

class _AgentConfigPageState extends ConsumerState<AgentConfigPage> {
  late String _nickname;
  late String _themeColor;

  @override
  void initState() {
    super.initState();
    // 从 ViewModel 缓存读取初始值
    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);
    final agent = vm.agent!;
    _nickname = agent.nickname ?? '';
    _themeColor = agent.themeColor;
  }

  void _save() {
    // 只转发，不做决策 (Law 2)
    final nickname = _nickname.trim().isEmpty ? null : _nickname.trim();
    ref.read(agentProfileViewModelProvider(widget.agentId).notifier)
        .saveProfile(widget.agentId, nickname, _themeColor);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProfileViewModelProvider(widget.agentId));

    // 响应 ViewModel 状态变化
    if (state.saveSuccess) {
      // Schedule pop after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(agentProfileViewModelProvider(widget.agentId).notifier)
              .clearSaveResult();
          context.pop();
        }
      });
    }

    if (state.saveError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.saveError!)),
          );
          ref.read(agentProfileViewModelProvider(widget.agentId).notifier)
              .clearSaveResult();
        }
      });
    }

    return PopScope(
      canPop: !state.isSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.pop()),
          title: Text(/* agent.displayName + ' · 个性化配置' */),
        ),
        body: ListView(
          children: [
            // NicknameField
            // ColorGrid
            SaveButton(
              isSaving: state.isSaving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
```

### 边界校验

| 场景 | 处理 |
|------|------|
| 昵称超过 20 字符 | `maxLength: 20` + 字符计数器 |
| 昵称全空格 | 保存时 trim 后为空 → `nickname: null` |
| 配置页未做任何修改就保存 | 允许，`updateLocalProfile` 幂等 |
| 保存中用户点返回 | `PopScope(canPop: !state.isSaving)` 阻止 |
| 保存中用户点系统返回 | 同上，PopScope 拦截 |

---

## 5. UI 组件提取到 ui_kit/

| 组件 | 提取理由 | 参数 |
|------|---------|------|
| `EmojiAvatar` | ChatRoomPage AppBar 和 ProfileHeader 都用了相同模式（CircleAvatar + first char + themeColor），完全参数化、不耦合业务 Model | `displayName`, `themeColor`, `radius` |
| `ColorGrid` | 12 色圆形选择器，参数化为 `colors: List<ColorOption>` + `selectedColor` + `onColorSelected` 回调。未来其他页面挑选主题色也能复用 | `colors`, `selectedColor`, `onColorSelected` |

> **Law 10 判断**：两个组件均有参数化意义（不耦合特定业务 model），且对项目内其他页面有复用潜力。满足 ui_kit 提取标准。

### ColorOption 模型

```dart
// lib/ui_kit/color_grid.dart
class ColorOption {
  final String hex;  // e.g. '#6c5ce7'
  final String label; // e.g. '紫罗兰'
  const ColorOption({required this.hex, required this.label});
}
```

---

## 6. 文件清单

| 文件 | 类型 | 说明 |
|------|------|------|
| `lib/features/agent_profile/agent_profile_page.dart` | 修改 | 从 stub 实现为完整详情页 |
| `lib/features/agent_profile/agent_config_page.dart` | 新建 | 个性化配置页 |
| `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart` | 新建 | ViewModel（管理 Profile + Config 两种状态） |
| `lib/features/agent_profile/providers/agent_profile_providers.dart` | 新建 | Provider 定义 |
| `lib/features/agent_profile/widgets/profile_header.dart` | 新建 | Profile 头部组件 |
| `lib/features/agent_profile/widgets/stats_grid.dart` | 新建 | 统计网格 |
| `lib/ui_kit/color_grid.dart` | 新建 | 主题色选择器（提取到 ui_kit） |
| `lib/ui_kit/emoji_avatar.dart` | 新建 | Emoji 头像组件（提取到 ui_kit） |
| `lib/domain/models/errors.dart` | 新建 | AgentNotFoundError 异常类 |
| `lib/app/router/router.dart` | 修改 | 添加 config 路由 |

---

## 7. 测试用例

| 被测对象 | 测试 |
|---------|------|
| `AgentProfileViewModel` | ✓ init() 成功后 state.detailLoadState = LoadData |
| | ✓ agent 不存在时 state.detailLoadState = LoadError(AgentNotFoundError) |
| | ✓ instance 不存在时 instance=null 但整体仍成功 |
| | ✓ saveProfile 成功后 state.saveSuccess = true |
| | ✓ saveProfile 失败后 state.saveError 非 null |
| `AgentProfilePage` | ✓ loading 态展示 LoadingSkeleton |
| | ✓ 成功态渲染 Agent 名称、描述、在线状态 |
| | ✓ 点击编辑按钮 push config 路由 |
| | ✓ 错误态展示 ErrorBoundary + retry |
| `AgentConfigPage` | ✓ 编辑昵称 → 调用 vm.saveProfile |
| | ✓ 选择主题色 → 调用 vm.saveProfile |
| | ✓ 保存中 isSaving=true → PopScope 阻止返回 |
| | ✓ saveError 展示 SnackBar |
| `ProfileHeader` | ✓ 在线 Agent 显示绿色状态点 |
| | ✓ 离线 Agent 显示灰色状态点 |
| `StatsGrid` | ✓ 消息数显示实数 |
| | ✓ 不可用统计显示 "--" |
| `ColorGrid` | ✓ 当前主题色选中高亮 |
| | ✓ 点击触发 onColorSelected |
| `EmojiAvatar` | ✓ 正确渲染首字符 + 主题色 |

**总计：至少 16 个新增测试**（含 ViewModel 单元测试）

---

## 8. 架构合规检查

| Iron Law | 如何满足 |
|----------|---------|
| Law 1 (域层零外部依赖) | AgentNotFoundError 在 domain/models/，无 Flutter 依赖 |
| Law 2 (UI 只做渲染) | Config 页 `_save()` 只转发到 VM；VM 处理异常翻译、状态转换 |
| Law 3 (面向接口) | VM 依赖 IAgentRepo/IInstanceRepo/IMessageRepo 接口 |
| Law 4 (禁 setState 桥接) | Profile + Config 均用 `ref.watch` 响应状态 |
| Law 5 (单状态源) | AgentProfileState 一个不可变对象服务两个页面 |
| Law 6 (批量查询) | 当前无 N+1 风险（3 个独立仓库调用，各自单次查询） |
| Law 8 (禁空 catch) | 所有 catch 块含 `debugPrint` + stackTrace |
| Law 10 (组合优于继承) | EmojiAvatar/ColorGrid 提取到 ui_kit |
| Law 12 (Provider 分层) | VM 在 feature/providers/，DI 在 app/di/ |
| Law 13 (watch/read) | build 中用 watch，回调中用 read |
| Law 14 (最少 2 测试) | 每个新 Widget 至少 2 个测试用例 |
| Law 15 (测试不操作内部) | 测试通过 VM public API + ProviderScope override |

---

## 9. 未纳入范围（后续 US）

| 功能 | 关联 US | 当前处理 |
|------|--------|---------|
| 6 格统计完整数据 | US-019 (P2) | 后 5 格灰显 "--" + Banner 说明 |
| 成就系统 | US-020 (P2) | 空状态占位文字 |
| 快捷指令编辑 | US-014 (P1) | 本次不涉及 |
| Emoji 头像更换 | US-013 | Agent 模型暂不存储 emoji，需模型扩展 |
| Description 本地编辑 | US-013 | IAgentRepo.updateLocalProfile 不支持，且 description 语义上由 Gateway 同步 |
