# Phase 5: ChatRoomPage 设计

**日期**: 2026-06-07
**状态**: 已批准

## 概述

实现聊天页，替换当前 stub。支持消息气泡列表（用户/Agent 双端展示）、底部输入栏发送消息、通过 SendMessageUseCase 走完整消息生命周期、订阅 messageStream 实时接收 Agent 回复、消息状态流转展示。

## 架构概览

```
ChatRoomPage (ConsumerStatefulWidget)
├── AppBar: Agent 名称 + 头像色圆 + 实例名副标题
├── Body: 消息列表 (reverse: true, 底部对齐)
│   ├── 加载历史: fetchMessageHistory → 批量写入本地 repo
│   ├── 实时消息: messageStream 订阅 → 写入本地 repo → UI 刷新
│   └── 空状态: "Send a message to start"
├── MessageBubble
│   ├── 用户消息: 右对齐, 蓝色气泡, 右下角 StatusIcon
│   ├── Agent 消息: 左对齐, 灰色气泡, 头像圆
│   └── 失败状态: 红色边框, 点击重试
└── ChatInputBar
    ├── TextField (多行, maxLines=5)
    └── 发送按钮 (内容为空时 disabled)
```

## 数据流

```
ChatRoomPage
  ├─ ref.watch(chatMessagesProvider(conversationId))  ← FutureProvider
  │    └─ messageRepo.getByConversation(conversationId)
  ├─ 初始化时:
  │    ├─ conversationRepo.getOrCreate(instanceId, agentId)
  │    ├─ gatewayClient.fetchMessageHistory(instanceId, agentId)
  │    │    └─ messageRepo.insert() 逐条写入
  │    └─ gatewayClient.messageStream(instanceId).listen()
  │         └─ 收到新消息 → messageRepo.insert() + 刷新
  └─ 发送时:
       └─ sendMessageUseCase.execute(...)
            └─ 返回最终 Message → 手动刷新列表
```

## 消息气泡规则

| 场景 | 对齐 | 颜色 | 额外 |
|------|------|------|------|
| 用户消息 | 右 | 主色蓝 `primaryBlue` | 右下 StatusIcon |
| Agent 消息 | 左 | `surfaceContainerHighest` | 左上 头像圆 + 名称 |
| 发送失败 | 右 | 主色蓝, 红色边框 | 点击重试 |
| 图片/文件 | — | — | 占位文字 `[图片]` / `[文件]` |

## ChatInputBar

- 固定在底部，键盘弹出时上移（padding 跟随 viewInsets.bottom）
- 输入框圆角药丸形状，最多 5 行
- 发送按钮：文字为空时灰色，有内容时主色
- 单行时按回车发送

## 文件变更清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `lib/features/chat_room/providers/chat_providers.dart` | 消息列表 provider + 初始化 |
| 新建 | `lib/features/chat_room/widgets/message_bubble.dart` | 消息气泡组件 |
| 新建 | `lib/features/chat_room/widgets/chat_input_bar.dart` | 底部输入栏 |
| 修改 | `lib/features/chat_room/chat_room_page.dart` | 替换 stub |
| 新建 | `test/features/chat_room/chat_room_page_test.dart` | 页面测试 |
| 新建 | `test/features/chat_room/message_bubble_test.dart` | 气泡测试 |
| 新建 | `test/features/chat_room/chat_input_bar_test.dart` | 输入栏测试 |

## 延期内容

- 工具调用（ToolCall）展示 → 后续 Phase
- 图片/文件消息真实发送 → 仅展示占位文字
- 历史消息分页加载（滚动到顶加载更多）→ 后续
