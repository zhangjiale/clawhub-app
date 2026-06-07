# Phase 5: ChatRoomPage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ChatRoomPage stub with a full chat UI: message bubble list, input bar, real-time message streaming, and full message lifecycle via SendMessageUseCase.

**Architecture:** A FutureProvider.family (keyed by conversationId) watches a refresh-counter StateProvider to re-fetch messages when new ones arrive. The page subscribes to `messageStream` in initState and increments the counter on each new message. SendMessageUseCase handles the full lifecycle (PENDING → SENDING → SENT → DELIVERED).

**Tech Stack:** Flutter + Riverpod + go_router

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `lib/features/chat_room/providers/chat_providers.dart` | Refresh counter + message list FutureProvider |
| Create | `lib/features/chat_room/widgets/message_bubble.dart` | Message bubble component |
| Create | `lib/features/chat_room/widgets/chat_input_bar.dart` | Chat input bar component |
| Modify | `lib/features/chat_room/chat_room_page.dart` | Full page replacing stub |
| Create | `test/features/chat_room/message_bubble_test.dart` | Bubble tests |
| Create | `test/features/chat_room/chat_input_bar_test.dart` | Input bar tests |
| Create | `test/features/chat_room/chat_room_page_test.dart` | Page tests |

---

### Task 1: Create chat_providers.dart (refresh counter + message list)

**Files:**
- Create: `lib/features/chat_room/providers/chat_providers.dart`

- [ ] **Step 1: Write file**

No separate test file needed — the providers are tested through the page widget tests in Task 4.

Create `lib/features/chat_room/providers/chat_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/app/di/providers.dart';

/// 刷新计数器 — 每次递增时 chatMessagesProvider 重新拉取消息列表
final chatRefreshProvider = StateProvider<int>((ref) => 0);

/// 会话消息列表 Provider
final chatMessagesProvider = FutureProvider.family<List<Message>, String>(
  (ref, conversationId) async {
    ref.watch(chatRefreshProvider); // 监听刷新信号
    return ref.watch(messageRepoProvider).getByConversation(conversationId);
  },
);
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/chat_room/providers/chat_providers.dart
git commit -m "feat(chat_room): add chat providers with refresh pattern"
```

---

### Task 2: Create MessageBubble widget

**Files:**
- Create: `lib/features/chat_room/widgets/message_bubble.dart`
- Create: `test/features/chat_room/message_bubble_test.dart`

- [ ] **Step 1: Write tests for MessageBubble**

Create `test/features/chat_room/message_bubble_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/theme.dart';

void main() {
  group('MessageBubble', () {
    final userMessage = Message(
      clientId: 'c1',
      conversationId: 'conv1',
      agentId: 'agent1',
      role: MessageRole.user,
      content: 'Hello, Agent!',
      type: MessageType.text,
      logicalClock: 1,
      status: MessageStatus.sent,
    );

    final agentMessage = Message(
      clientId: 'c2',
      serverId: 's2',
      conversationId: 'conv1',
      agentId: 'agent1',
      role: MessageRole.agent,
      content: 'Hi! How can I help?',
      type: MessageType.text,
      logicalClock: 2,
      status: MessageStatus.delivered,
    );

    Widget buildBubble(Message message, {String agentName = '产品虾'}) {
      return MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            agentName: agentName,
          ),
        ),
      );
    }

    testWidgets('renders user message content', (tester) async {
      await tester.pumpWidget(buildBubble(userMessage));
      expect(find.text('Hello, Agent!'), findsOneWidget);
    });

    testWidgets('renders agent message content', (tester) async {
      await tester.pumpWidget(buildBubble(agentMessage));
      expect(find.text('Hi! How can I help?'), findsOneWidget);
    });

    testWidgets('user message has right alignment', (tester) async {
      await tester.pumpWidget(buildBubble(userMessage));
      // User messages should not show agent name
      expect(find.text('产品虾'), findsNothing);
    });

    testWidgets('agent message shows agent name', (tester) async {
      await tester.pumpWidget(buildBubble(agentMessage));
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('user message shows status icon', (tester) async {
      await tester.pumpWidget(buildBubble(userMessage));
      // SENT status = check icon
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('failed message shows error icon', (tester) async {
      final failedMsg = userMessage.copyWith(status: MessageStatus.failed);
      await tester.pumpWidget(buildBubble(failedMsg));
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('image type shows placeholder text', (tester) async {
      final imgMsg = userMessage.copyWith(type: MessageType.image, content: null);
      await tester.pumpWidget(buildBubble(imgMsg));
      expect(find.text('[图片]'), findsOneWidget);
    });

    testWidgets('file type shows placeholder text', (tester) async {
      final fileMsg = userMessage.copyWith(type: MessageType.file, content: null);
      await tester.pumpWidget(buildBubble(fileMsg));
      expect(find.text('[文件]'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
flutter test test/features/chat_room/message_bubble_test.dart
```

Expected: compilation error — MessageBubble not defined.

- [ ] **Step 3: Create MessageBubble widget**

Create `lib/features/chat_room/widgets/message_bubble.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/ui_kit/status_icon.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 消息气泡组件
/// 用户消息右对齐蓝色气泡，Agent 消息左对齐灰色气泡
class MessageBubble extends StatelessWidget {
  final Message message;
  final String agentName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.agentName,
  });

  bool get _isUser => message.role == MessageRole.user;

  String get _displayContent {
    if (message.content != null && message.content!.isNotEmpty) {
      return message.content!;
    }
    return switch (message.type) {
      MessageType.image => '[图片]',
      MessageType.file => '[文件]',
      MessageType.toolCall => '[工具调用]',
      MessageType.text => '',
    };
  }

  Color _bubbleColor(ThemeData theme) {
    if (_isUser) return AppColors.primaryBlue;
    return theme.colorScheme.surfaceContainerHighest;
  }

  Color _textColor(ThemeData theme) {
    if (_isUser) return Colors.white;
    return theme.colorScheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment:
            _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!_isUser) ...[
            // Agent avatar
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary.withAlpha(40),
              child: Text(
                agentName.characters.first,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!_isUser)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      agentName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _bubbleColor(theme),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(_isUser ? 16 : 4),
                      bottomRight: Radius.circular(_isUser ? 4 : 16),
                    ),
                    border: message.status == MessageStatus.failed
                        ? Border.all(color: AppColors.messageFailed, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    _displayContent,
                    style: TextStyle(color: _textColor(theme)),
                  ),
                ),
              ],
            ),
          ),
          if (_isUser) ...[
            const SizedBox(width: 4),
            StatusIcon(status: message.status, size: 14),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/features/chat_room/message_bubble_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat_room/widgets/message_bubble.dart test/features/chat_room/message_bubble_test.dart
git commit -m "feat(chat_room): add MessageBubble widget"
```

---

### Task 3: Create ChatInputBar widget

**Files:**
- Create: `lib/features/chat_room/widgets/chat_input_bar.dart`
- Create: `test/features/chat_room/chat_input_bar_test.dart`

- [ ] **Step 1: Write tests for ChatInputBar**

Create `test/features/chat_room/chat_input_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';

void main() {
  group('ChatInputBar', () {
    Widget buildBar({ValueChanged<String>? onSend}) {
      return MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            onSend: onSend ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('renders text field', (tester) async {
      await tester.pumpWidget(buildBar());
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders send button', (tester) async {
      await tester.pumpWidget(buildBar());
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('clears text after send', (tester) async {
      await tester.pumpWidget(buildBar());
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.tap(find.byIcon(Icons.send));
      // Text field should be cleared
      expect(find.text('Hello'), findsNothing);
    });

    testWidgets('calls onSend with entered text', (tester) async {
      String? sent;
      await tester.pumpWidget(buildBar(onSend: (text) => sent = text));
      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.tap(find.byIcon(Icons.send));
      expect(sent, 'Test message');
    });

    testWidgets('does not call onSend when text is empty', (tester) async {
      String? sent;
      await tester.pumpWidget(buildBar(onSend: (text) => sent = text));
      await tester.tap(find.byIcon(Icons.send));
      expect(sent, isNull);
    });

    testWidgets('trims whitespace before sending', (tester) async {
      String? sent;
      await tester.pumpWidget(buildBar(onSend: (text) => sent = text));
      await tester.enterText(find.byType(TextField), '  hello  ');
      await tester.tap(find.byIcon(Icons.send));
      expect(sent, 'hello');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
flutter test test/features/chat_room/chat_input_bar_test.dart
```

Expected: compilation error — ChatInputBar not defined.

- [ ] **Step 3: Create ChatInputBar widget**

Create `lib/features/chat_room/widgets/chat_input_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 聊天输入栏
/// 固定底部，多行输入，发送按钮
class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;

  const ChatInputBar({
    super.key,
    required this.onSend,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  bool _get hasText => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomInset),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withAlpha(50)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: hasText ? _send : null,
            icon: Icon(Icons.send),
            color: hasText
                ? AppColors.primaryBlue
                : theme.colorScheme.outline,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/features/chat_room/chat_input_bar_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat_room/widgets/chat_input_bar.dart test/features/chat_room/chat_input_bar_test.dart
git commit -m "feat(chat_room): add ChatInputBar widget"
```

---

### Task 4: Replace ChatRoomPage stub with full implementation

**Files:**
- Modify: `lib/features/chat_room/chat_room_page.dart`
- Create: `test/features/chat_room/chat_room_page_test.dart`

- [ ] **Step 1: Write tests for ChatRoomPage**

Create `test/features/chat_room/chat_room_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';

void main() {
  group('ChatRoomPage', () {
    testWidgets('renders app bar with agent name', (tester) async {
      final agentRepo = InMemoryAgentRepo();
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1', remoteId: 'r-1',
          instanceId: 'inst-1', name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentRepoProvider.overrideWith((ref) => agentRepo),
          ],
          child: MaterialApp(
            home: ChatRoomPage(
              agentId: 'local-1',
              instanceId: 'inst-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('renders message list when messages exist', (tester) async {
      final agentRepo = InMemoryAgentRepo();
      final messageRepo = InMemoryMessageRepo();

      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1', remoteId: 'r-1',
          instanceId: 'inst-1', name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      await messageRepo.insert(Message(
        clientId: 'c1',
        conversationId: 'conv1',
        agentId: 'local-1',
        role: MessageRole.user,
        content: 'Hello!',
        type: MessageType.text,
        logicalClock: 1,
        status: MessageStatus.sent,
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentRepoProvider.overrideWith((ref) => agentRepo),
            messageRepoProvider.overrideWith((ref) => messageRepo),
            gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          ],
          child: MaterialApp(
            home: ChatRoomPage(
              agentId: 'local-1',
              instanceId: 'inst-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello!'), findsOneWidget);
    });

    testWidgets('renders chat input bar', (tester) async {
      final agentRepo = InMemoryAgentRepo();
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1', remoteId: 'r-1',
          instanceId: 'inst-1', name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentRepoProvider.overrideWith((ref) => agentRepo),
          ],
          child: MaterialApp(
            home: ChatRoomPage(
              agentId: 'local-1',
              instanceId: 'inst-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('sends message when input is submitted', (tester) async {
      final agentRepo = InMemoryAgentRepo();
      final messageRepo = InMemoryMessageRepo();
      final instanceRepo = InMemoryInstanceRepo();

      await instanceRepo.save(Instance(
        id: 'inst-1', name: 'My MacBook',
        gatewayUrl: 'wss://test.com:18789', tokenRef: 'ref',
      ));
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1', remoteId: 'r-1',
          instanceId: 'inst-1', name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentRepoProvider.overrideWith((ref) => agentRepo),
            messageRepoProvider.overrideWith((ref) => messageRepo),
            instanceRepoProvider.overrideWith((ref) => instanceRepo),
            gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          ],
          child: MaterialApp(
            home: ChatRoomPage(
              agentId: 'local-1',
              instanceId: 'inst-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Type and send a message
      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // The sent message should appear in the list
      expect(find.text('Test message'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
flutter test test/features/chat_room/chat_room_page_test.dart
```

Expected: Some tests fail — the page is still a stub.

- [ ] **Step 3: Write the full ChatRoomPage**

Replace `lib/features/chat_room/chat_room_page.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/widgets/message_bubble.dart';
import 'package:claw_hub/features/chat_room/widgets/chat_input_bar.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';

/// 聊天页 (P0 MVP Phase 5)
/// 消息列表 + 输入栏 + 实时消息接收
class ChatRoomPage extends ConsumerStatefulWidget {
  final String agentId;
  final String instanceId;
  final String? source;

  const ChatRoomPage({
    super.key,
    required this.agentId,
    required this.instanceId,
    this.source,
  });

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  final _scrollController = ScrollController();
  StreamSubscription<Message>? _messageSubscription;
  Agent? _agent;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    // Look up the agent
    final agentRepo = ref.read(agentRepoProvider);
    _agent = await agentRepo.getById(widget.agentId);
    if (!mounted) return;
    setState(() {});

    // Get or create conversation
    final conversationRepo = ref.read(conversationRepoProvider);
    await conversationRepo.getOrCreate(widget.instanceId, widget.agentId);

    // Fetch message history
    final gatewayClient = ref.read(gatewayClientProvider);
    final messageRepo = ref.read(messageRepoProvider);
    try {
      final history = await gatewayClient.fetchMessageHistory(
        instanceId: widget.instanceId,
        agentId: _agent?.remoteId ?? '',
      );
      for (final msg in history.messages) {
        await messageRepo.insert(msg);
      }
      ref.read(chatRefreshProvider.notifier).state++;
    } catch (_) {
      // History fetch failed — proceed with local messages
    }

    // Subscribe to real-time messages
    _messageSubscription = gatewayClient
        .messageStream(widget.instanceId)
        .listen((msg) async {
      await messageRepo.insert(msg);
      if (mounted) {
        ref.read(chatRefreshProvider.notifier).state++;
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (_agent == null) return;

    final useCase = ref.read(sendMessageUseCaseProvider);
    await useCase.execute(
      instanceId: widget.instanceId,
      agent: _agent!,
      content: text,
      type: MessageType.text,
    );

    // Refresh UI
    ref.read(chatRefreshProvider.notifier).state++;
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final intValue = int.parse(cleaned, radix: 16);
    return Color(intValue | 0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversationRepo = ref.watch(conversationRepoProvider);
    final conversationId = Conversation.generateId(
      widget.instanceId,
      widget.agentId,
    );
    final messagesAsync = ref.watch(chatMessagesProvider(conversationId));

    return Scaffold(
      appBar: AppBar(
        title: _agent != null
            ? Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _parseColor(_agent!.themeColor),
                    foregroundColor: _parseColor(_agent!.themeColor)
                        .contrastingTextColor(),
                    child: Text(
                      _agent!.displayName.characters.first,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _agent!.displayName,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (_agent!.description != null)
                        Text(
                          _agent!.description!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ],
              )
            : const Text('Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const LoadingSkeleton(count: 3),
              error: (err, _) => Center(
                child: Text('Failed to load messages: $err'),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          'Send a message to start',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    return MessageBubble(
                      message: message,
                      agentName: _agent?.displayName ?? 'Agent',
                    );
                  },
                );
              },
            ),
          ),
          ChatInputBar(onSend: _sendMessage),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/features/chat_room/chat_room_page_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Run full test suite**

```bash
flutter test
```

Expected: All tests pass (176 existing + new ones).

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat_room/chat_room_page.dart test/features/chat_room/chat_room_page_test.dart
git commit -m "feat(chat_room): implement ChatRoomPage with messaging and real-time stream"
```

---

### Self-Review Checklist

1. **Spec coverage:** ✅ All design requirements covered: chat providers (Task 1), MessageBubble (Task 2), ChatInputBar (Task 3), ChatRoomPage with stream subscription (Task 4).
2. **No placeholders:** ✅ Every step has explicit code.
3. **Type consistency:** ✅ `chatMessagesProvider(conversationId)` matches `ref.watch(chatMessagesProvider(conversationId))`. MessageBubble `agentName` matches `_agent?.displayName`. ChatInputBar `onSend: (String) => void` matches `_sendMessage(String text)`.
4. **Pattern alignment:** ✅ Follows existing widget patterns. Uses StatusIcon component. Uses LoadingSkeleton. Riverpod refresh pattern is clean.
