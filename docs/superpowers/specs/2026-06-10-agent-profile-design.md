# Agent Profile Page 设计文档

**日期**：2026-06-10
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
- AgentProfilePage ✏️ 按钮 → push config
- AgentConfigPage 返回按钮 → pop

---

## 2. AgentProfilePage（详情页）

### 组件树

```
AgentProfilePage (ConsumerStatefulWidget)
├── AppBar
│   ├── BackButton (smart back: chat page or source tab)
│   ├── Title: agent.displayName
│   └── EditButton (✏️ → push config page with agent as extra)
├── ProfileHeader
│   ├── EmojiAvatar (大圆圈, 主题色背景+边框, displayName 首字符)
│   ├── AgentName + ⚡PinBadge (isPinned 时显示)
│   ├── Description text (灰色, max 2 lines)
│   └── StatusRow (green/gray dot + 在线/离线 + 实例名)
├── StatsGrid (3 columns × 2 rows)
│   ├── Row 1: 对话次数 / 消息总数 / 工具调用 ← 实数
│   └── Row 2: 活跃天数 / 连续天数 / 首次对话 ← "--" 占位
├── FutureBanner ("📊 完整成长数据将在 V1.2 上线后可用")
└── AchievementsPlaceholder ("更多数据积累后解锁成就系统…")
```

### 状态管理

```dart
// Provider (feature providers/agent_profile_providers.dart)
final agentProfilePageProvider = FutureProvider.family<AgentDetailData, String>(
  (ref, agentId) async {
    final agentRepo = ref.watch(agentRepoProvider);
    final instanceRepo = ref.watch(instanceRepoProvider);
    final messageRepo = ref.watch(messageRepoProvider);
    final conversationRepo = ref.watch(conversationRepoProvider);

    final agent = await agentRepo.getById(agentId);
    if (agent == null) throw AgentNotFoundError(agentId);

    final instance = await instanceRepo.getById(agent.instanceId);
    final messageCount = await messageRepo.getMessageCount(agentId);
    final conversation = await conversationRepo.getOrCreate(
      agent.instanceId,
      agentId,
    );

    return AgentDetailData(
      agent: agent,
      instance: instance,
      messageCount: messageCount,
      conversation: conversation,
    );
  },
);
```

### 数据模型

```dart
class AgentDetailData {
  final Agent agent;
  final Instance? instance;
  final int messageCount;
  final Conversation conversation;
}
```

### 错误处理

| 场景 | UI 行为 |
|------|--------|
| Agent 不存在 | ErrorBoundary "虾不存在或已被删除" |
| 实例不存在 | StatusRow 显示 "未知实例" |
| 网络/加载失败 | ErrorBoundary + retry |

---

## 3. AgentConfigPage（配置页）

### 组件树

```
AgentConfigPage (ConsumerStatefulWidget)
├── AppBar
│   ├── BackButton
│   └── Title: "{agent.displayName} · 个性化配置"
├── ListView
│   ├── Section: 🦐 基本信息
│   │   ├── CurrentAvatar (只读展示，首字符 + 主题色)
│   │   └── NicknameField (TextField, maxLength: 20)
│   │   (Emoji 头像更换与 description 本地编辑延后至 US-013 完整版)
│   ├── Section: 🎨 主题色
│   │   └── ColorGrid (12色, 6×2 grid, 选中: 白色边框+外环)
│   └── SaveButton
│       ├── idle: "💾 保存配置"
│       ├── saving: CircularProgressIndicator
│       ├── success: pop() → 详情页自动刷新
│       └── error: SnackBar "保存失败，请重试"
```

### 状态管理

配置页使用本地 `StatefulWidget` 状态管理表单字段（Law 5 例外：UI-only 状态）：

```dart
class _AgentConfigPageState extends ConsumerState<AgentConfigPage> {
  late String _nickname;
  late String _themeColor;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nickname = widget.agent.nickname ?? '';
    _themeColor = widget.agent.themeColor;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(agentRepoProvider).updateLocalProfile(
        widget.agent.localId,
        nickname: _nickname.trim().isEmpty ? null : _nickname.trim(),
        themeColor: _themeColor,
      );
      ref.invalidate(agentProfilePageProvider(widget.agent.localId));
      if (mounted) context.pop();
    } catch (e, st) {
      debugPrint('AgentConfig save failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
```

### 边界校验

| 场景 | 处理 |
|------|------|
| 昵称超过 20 字符 | `maxLength: 20` + 字符计数器 |
| 昵称全空格 | 保存时 trim 后为空 → `nickname: null`（不覆盖） |
| 配置页未做任何修改就保存 | 允许，`updateLocalProfile` 幂等 |
| 保存中用户点返回 | `_isSaving` 为 true 时不响应返回手势 |

### 本次不包括

| 功能 | 原因 |
|------|------|
| Emoji 头像更换 | Agent 模型暂不存储 emoji，需模型扩展 |
| Description 本地编辑 | IAgentRepo.updateLocalProfile 不支持，且 description 语义上由 Gateway 同步 |
| 快捷指令编辑 | 属 US-014 (P1)，不在本次范围 |
| 统计网格完整 6 项数据 | US-019 (P2) 需要对话历史聚合查询 |
| 成就系统 | US-020 (P2) 依赖 US-019 |

---

## 4. IAgentRepo 接口扩展

当前 `updateLocalProfile` 签名：

```dart
Future<Agent> updateLocalProfile(
  String localId, {
  String? nickname,
  String? avatarUrl,
  String? themeColor,
});
```

需扩展支持 `description`（如果 description 允许本地覆盖）或保持 description 由 Gateway 同步（只读）。暂时保持 description 只读，本地仅存 nickname + themeColor。

---

## 5. 文件清单

| 文件 | 类型 | 说明 |
|------|------|------|
| `lib/features/agent_profile/agent_profile_page.dart` | 修改 | 从 stub 实现为完整详情页 |
| `lib/features/agent_profile/agent_config_page.dart` | 新建 | 个性化配置页 |
| `lib/features/agent_profile/widgets/profile_header.dart` | 新建 | Profile 头部组件 |
| `lib/features/agent_profile/widgets/stats_grid.dart` | 新建 | 统计网格 |
| `lib/features/agent_profile/widgets/color_grid.dart` | 新建 | 主题色选择器 |
| `lib/features/agent_profile/providers/agent_profile_providers.dart` | 新建 | Provider 定义 |
| `lib/app/router/router.dart` | 修改 | 添加 config 路由 |

---

## 6. 测试用例

| Widget | 测试 |
|--------|------|
| `AgentProfilePage` | ✓ 渲染 Agent 名称、描述、在线状态 |
| | ✓ 点击编辑按钮 push config 路由 |
| | ✓ Agent 不存在时显示错误状态 |
| `AgentConfigPage` | ✓ 编辑昵称并保存成功 |
| | ✓ 选择主题色后保存成功 |
| | ✓ 保存失败显示 SnackBar |
| `ProfileHeader` | ✓ 在线 Agent 显示绿色状态点 |
| | ✓ 离线 Agent 显示灰色状态点 |
| `StatsGrid` | ✓ 已实现统计显示实数 |
| | ✓ 未实现统计显示 "--" |
| `ColorGrid` | ✓ 当前主题色选中高亮 |
| | ✓ 点击后调用 onColorSelected 回调 |

**总计：至少 12 个新增测试**

---

## 7. 未纳入范围（后续 US）

| 功能 | 关联 US | 当前处理 |
|------|--------|---------|
| 6 格统计完整数据 | US-019 (P2) | 后 3 格灰显 "--" + Banner 说明 |
| 成就系统 | US-020 (P2) | 空状态占位文字 |
| 快捷指令编辑 | US-014 (P1) | 本次不涉及（AgentConfigPage 仅含基本信息+主题色） |
| 头像更换 (图片) | US-013 | 本次仅用 Emoji 首字符头像，不上传图片 |
