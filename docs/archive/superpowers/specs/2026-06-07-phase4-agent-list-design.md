# Phase 4: AgentListPage 设计

**日期**: 2026-06-07
**状态**: 已批准

## 概述

实现 Claws Tab 的 Agent 列表页，替换当前 stub。从 MockGateway 拉取 Agent 数据，按实例分组展示，支持搜索过滤，点击进入聊天。

## Agent 模型扩展

在 `Agent` 模型中添加可选的 `description` 字段：

```dart
final String? description; // Gateway 同步的描述
```

同步更新 `copyWith`、`==`/`hashCode`、`toString`。

MockGatewayClient 的 `fetchAgents()` 解析 `agents.json` 中的 `description` 字段。

`quickCommands` 留到 Phase 5 处理。

## 数据流

```
AgentListPage (UI)
  └─ ref.watch(agentListProvider)         ← 新 FutureProvider
       ├─ instanceRepo.getAll()            ← 获取所有实例
       ├─ gatewayClient.fetchAgents(id)    ← 每个实例拉取 Agent
       ├─ agentRepo.syncFromGateway(...)   ← 同步到本地仓库
       └─ agentRepo.getAll()              ← 返回全量排序列表
```

Provider 放入 `lib/features/agent_list/providers/agent_providers.dart`，风格对齐 `instance_providers.dart`。

## UI 结构

```
AgentListPage
├── AppBar (title: "Claws", 右侧搜索按钮)
├── SearchBar (可展开/收起，按名称+描述过滤)
├── body: AsyncValue.when(
│   ├── loading → LoadingSkeleton(count: 3)
│   ├── error   → ErrorBoundary
│   └── data    → 按实例分组的 Agent 列表
│        └── 每组:
│             ├── Instance 名称 header
│             └── AgentCard × N
│                  ├── 头像圆 (首字 + themeColor 背景)
│                  ├── 名称 + 置顶图钉
│                  ├── 描述文字 (单行截断)
│                  └── 点击 → ChatRoomPage
└── EmptyState (无 Agent 时)
```

## 分组策略

Agent 按 `instanceId` 分组，每组显示所属实例名称（通过 `instanceRepo.getById()` 查找）。实例已删除但 Agent 未清理时，归入 "Unknown Instance" 组。

## 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `lib/features/agent_list/providers/agent_providers.dart` | `agentListProvider` |
| 新建 | `lib/features/agent_list/widgets/agent_card.dart` | Agent 卡片组件 |
| 修改 | `lib/features/agent_list/agent_list_page.dart` | 替换 stub |
| 修改 | `lib/domain/models/agent.dart` | 添加 `description` |
| 修改 | `lib/core/acl/mock_gateway_client.dart` | 解析 `description` |

## 测试

- `agent_card_test.dart` — 卡片渲染、置顶显示、长按事件
- `agent_list_test.dart` — 列表渲染、分组、搜索过滤、空状态
- `agent_providers_test.dart` — Provider 数据流
- `agent_test.dart` — 补充 description 字段测试
