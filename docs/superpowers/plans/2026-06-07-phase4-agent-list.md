# Phase 4: AgentListPage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the AgentListPage stub with a full implementation showing agents grouped by instance, with search/filter and navigation to chat.

**Architecture:** Follows the exact Riverpod + Clean Architecture pattern established by InstanceListPage. A FutureProvider fetches agents from all instances via the gateway, syncs to the local InMemory repo, and returns an `AgentListData` record containing sorted agents and an instance-name lookup map. The page groups by instance, supports local search filtering, and uses an AgentCard widget styled after InstanceCard.

**Tech Stack:** Flutter + Riverpod + go_router

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `lib/domain/models/agent.dart` | Add optional `description` field |
| Modify | `lib/core/acl/mock_gateway_client.dart` | Parse `description` from agents.json |
| Create | `lib/features/agent_list/providers/agent_providers.dart` | `AgentListData` class + `agentListProvider` |
| Create | `lib/features/agent_list/widgets/agent_card.dart` | Agent card UI component |
| Modify | `lib/features/agent_list/agent_list_page.dart` | Full page replacing stub |
| Modify | `test/domain/models/agent_test.dart` | Add description field tests |
| Create | `test/features/agent_list/agent_card_test.dart` | Card rendering tests |
| Create | `test/features/agent_list/agent_list_test.dart` | Page rendering tests |
| Create | `test/features/agent_list/agent_providers_test.dart` | Provider data flow tests |

---

### Task 1: Add `description` field to Agent model

**Files:**
- Modify: `lib/domain/models/agent.dart`
- Modify: `test/domain/models/agent_test.dart`

- [ ] **Step 1: Add test for description field**

Insert into `test/domain/models/agent_test.dart`, inside the `group('Agent', () { ... })` block, before the closing `});`:

```dart
    test('description 可选字段默认为 null', () {
      final agent = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
      );
      expect(agent.description, isNull);
    });

    test('copyWith 保留 description 字段', () {
      final original = Agent(
        localId: 'local-a1',
        remoteId: 'r1',
        instanceId: 'inst-001',
        name: '产品虾',
        description: '产品规划、需求分析',
      );
      expect(original.description, '产品规划、需求分析');

      final updated = original.copyWith(name: '新名称');
      expect(updated.description, '产品规划、需求分析'); // 未被覆盖
    });
```

- [ ] **Step 2: Run test to verify failure**

```bash
flutter test test/domain/models/agent_test.dart
```

Expected: compilation errors — `description` getter not defined.

- [ ] **Step 3: Add `description` to Agent model**

In `lib/domain/models/agent.dart`, add `this.description` to the constructor parameter list (after `this.themeColor`):

```dart
  Agent({
    required this.localId,
    required this.remoteId,
    required this.instanceId,
    required this.name,
    this.nickname,
    this.avatarUrl,
    this.themeColor = '#007AFF',
    this.description,
    this.isPinned = false,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 {
    _validate();
  }
```

Add the field declaration (after `themeColor` on line 13):

```dart
  final String? description; // Gateway 同步的描述，如"产品规划、需求分析"
```

Add `String? description,` to the `copyWith` parameter list and `description: description ?? this.description,` to the return body.

Update `toString` to include `description`.

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/domain/models/agent_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/agent.dart test/domain/models/agent_test.dart
git commit -m "feat(domain): add optional description field to Agent model"
```

---

### Task 2: Parse `description` in MockGatewayClient

**Files:**
- Modify: `lib/core/acl/mock_gateway_client.dart`

- [ ] **Step 1: Parse description in fetchAgents**

In `fetchAgents`, inside the `.map()` callback, add `description` to the Agent constructor:

```dart
          (a) => Agent(
            localId: _uuid.v4(),
            remoteId: a['remoteId'] as String,
            instanceId: a['instanceId'] as String,
            name: a['name'] as String,
            themeColor: a['themeColor'] as String? ?? '#007AFF',
            description: a['description'] as String?,
          ),
```

- [ ] **Step 2: Verify with existing tests**

```bash
flutter test test/core/acl/mock_gateway_client_test.dart
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/core/acl/mock_gateway_client.dart
git commit -m "feat(acl): parse description field from mock agents.json"
```

---

### Task 3: Create agentListProvider with AgentListData

**Files:**
- Create: `lib/features/agent_list/providers/agent_providers.dart`
- Create: `test/features/agent_list/agent_providers_test.dart`

- [ ] **Step 1: Write tests for agentListProvider**

Create `test/features/agent_list/agent_providers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';

void main() {
  group('Agent Providers', () {
    ProviderContainer createContainer({
      InMemoryInstanceRepo? instanceRepo,
      InMemoryAgentRepo? agentRepo,
      MockGatewayClient? gatewayClient,
    }) {
      final container = ProviderContainer(
        overrides: [
          instanceRepoProvider.overrideWith(
            (ref) => instanceRepo ?? InMemoryInstanceRepo(),
          ),
          agentRepoProvider.overrideWith(
            (ref) => agentRepo ?? InMemoryAgentRepo(),
          ),
          gatewayClientProvider.overrideWith(
            (ref) => gatewayClient ?? MockGatewayClient(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('agentListProvider returns empty when no instances', () async {
      final container = createContainer();
      final data = await container.read(agentListProvider.future);
      expect(data.agents, isEmpty);
      expect(data.instanceNames, isEmpty);
    });

    test('agentListProvider returns agents sorted (pinned first, then name)', () async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      // Seed an instance
      await instanceRepo.save(Instance(
        id: 'inst-1', name: 'My MacBook',
        gatewayUrl: 'wss://test.com:18789', tokenRef: 'ref',
      ));

      // Seed agents directly into repo (simulating post-sync state)
      final agentB = Agent(
        localId: 'local-b', remoteId: 'r-b',
        instanceId: 'inst-1', name: 'B虾', isPinned: false,
      );
      final agentA = Agent(
        localId: 'local-a', remoteId: 'r-a',
        instanceId: 'inst-1', name: 'A虾', isPinned: false,
      );
      final agentPinned = Agent(
        localId: 'local-p', remoteId: 'r-p',
        instanceId: 'inst-1', name: 'Z虾', isPinned: true,
      );
      await agentRepo.syncFromGateway('inst-1', [agentB, agentA, agentPinned]);

      // Mock gateway returns empty — agents are already seeded in repo
      final gateway = MockGatewayClient();

      final container = createContainer(
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        gatewayClient: gateway,
      );

      final data = await container.read(agentListProvider.future);
      expect(data.agents.length, 3);
      expect(data.agents[0].isPinned, isTrue);
      expect(data.agents[1].name, 'A虾');
      expect(data.agents[2].name, 'B虾');
    });

    test('agentListProvider builds instance name map', () async {
      final agentRepo = InMemoryAgentRepo();
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

      final container = createContainer(
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        gatewayClient: MockGatewayClient(),
      );

      final data = await container.read(agentListProvider.future);
      expect(data.instanceNames['inst-1'], 'My MacBook');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
flutter test test/features/agent_list/agent_providers_test.dart
```

Expected: compilation error — `agentListProvider` / `AgentListData` not defined.

- [ ] **Step 3: Create AgentListData and agentListProvider**

Create directory `lib/features/agent_list/providers/` and file `agent_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/app/di/providers.dart';

/// Provider 返回的数据结构，包含 Agent 列表和实例名称映射
class AgentListData {
  final List<Agent> agents;
  final Map<String, String> instanceNames; // instanceId → instanceName

  const AgentListData({
    required this.agents,
    required this.instanceNames,
  });
}

/// Agent 列表 Provider
/// 从所有实例拉取 Agent，同步到本地仓库后返回排序列表及实例名映射
final agentListProvider = FutureProvider<AgentListData>((ref) async {
  final instanceRepo = ref.watch(instanceRepoProvider);
  final agentRepo = ref.watch(agentRepoProvider);
  final gatewayClient = ref.watch(gatewayClientProvider);

  final instances = await instanceRepo.getAll();

  // Build instance name map and fetch agents
  final instanceNames = <String, String>{};
  for (final instance in instances) {
    instanceNames[instance.id] = instance.name;
    try {
      final remoteAgents = await gatewayClient.fetchAgents(instance.id);
      await agentRepo.syncFromGateway(instance.id, remoteAgents);
    } catch (_) {
      // Skip instances that fail to connect — show what we have locally
    }
  }

  final agents = await agentRepo.getAll();
  return AgentListData(agents: agents, instanceNames: instanceNames);
});
```

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/features/agent_list/agent_providers_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/agent_list/providers/agent_providers.dart test/features/agent_list/agent_providers_test.dart
git commit -m "feat(agent_list): add agentListProvider with AgentListData"
```

---

### Task 4: Create AgentCard widget

**Files:**
- Create: `lib/features/agent_list/widgets/agent_card.dart`
- Create: `test/features/agent_list/agent_card_test.dart`

- [ ] **Step 1: Write tests for AgentCard**

Create `test/features/agent_list/agent_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_list/widgets/agent_card.dart';
import 'package:claw_hub/domain/models/agent.dart';

void main() {
  group('AgentCard', () {
    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划、需求分析、PRD撰写',
      themeColor: '#6c5ce7',
    );

    Widget buildCard({Agent? agent, VoidCallback? onTap}) {
      return MaterialApp(
        home: Scaffold(
          body: AgentCard(
            agent: agent ?? testAgent,
            onTap: onTap ?? () {},
          ),
        ),
      );
    }

    testWidgets('renders agent name', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('renders agent description', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('产品规划、需求分析、PRD撰写'), findsOneWidget);
    });

    testWidgets('renders avatar circle with first character', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('产'), findsOneWidget);
    });

    testWidgets('shows pin icon when pinned', (tester) async {
      final pinnedAgent = testAgent.copyWith(isPinned: true);
      await tester.pumpWidget(buildCard(agent: pinnedAgent));
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });

    testWidgets('no pin icon when not pinned', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.byIcon(Icons.push_pin), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildCard(onTap: () => tapped = true));
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('uses themeColor for avatar background', (tester) async {
      await tester.pumpWidget(buildCard());
      final circleAvatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(circleAvatar.backgroundColor, const Color(0xFF6C5CE7));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
flutter test test/features/agent_list/agent_card_test.dart
```

Expected: compilation error — `AgentCard` not defined.

- [ ] **Step 3: Create AgentCard widget**

Create directory `lib/features/agent_list/widgets/` and file `agent_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// Agent 卡片组件
/// 对齐: InstanceCard 模式，显示头像圆、名称、描述、置顶状态
class AgentCard extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;

  const AgentCard({
    super.key,
    required this.agent,
    required this.onTap,
  });

  Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final intValue = int.parse(cleaned, radix: 16);
    return Color(intValue | 0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _parseColor(agent.themeColor);
    final firstChar = agent.displayName.characters.first;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar circle with theme color
              CircleAvatar(
                backgroundColor: color,
                foregroundColor: color.contrastingTextColor(),
                child: Text(
                  firstChar,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            agent.displayName,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (agent.isPinned) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.push_pin,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                    if (agent.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        agent.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/features/agent_list/agent_card_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/agent_list/widgets/agent_card.dart test/features/agent_list/agent_card_test.dart
git commit -m "feat(agent_list): add AgentCard widget with theme color avatar"
```

---

### Task 5: Replace AgentListPage stub with full implementation

**Files:**
- Modify: `lib/features/agent_list/agent_list_page.dart`
- Create: `test/features/agent_list/agent_list_test.dart`

- [ ] **Step 1: Write tests for AgentListPage**

Create `test/features/agent_list/agent_list_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_list/agent_list_page.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';

void main() {
  group('AgentListPage', () {
    testWidgets('shows empty state when no agents', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Agents'), findsOneWidget);
    });

    testWidgets('shows agent cards when agents exist', (tester) async {
      final agentRepo = InMemoryAgentRepo();
      final instanceRepo = InMemoryInstanceRepo();

      await instanceRepo.save(Instance(
        id: 'inst-1', name: 'My MacBook',
        gatewayUrl: 'wss://test.com:18789', tokenRef: 'ref',
      ));
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1', remoteId: 'r-1',
          instanceId: 'inst-1', name: '产品虾',
          description: '产品规划', themeColor: '#6c5ce7',
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instanceRepoProvider.overrideWith((ref) => instanceRepo),
            agentRepoProvider.overrideWith((ref) => agentRepo),
            gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('产品虾'), findsOneWidget);
      expect(find.text('产品规划'), findsOneWidget);
    });

    testWidgets('shows instance group headers', (tester) async {
      final agentRepo = InMemoryAgentRepo();
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
            instanceRepoProvider.overrideWith((ref) => instanceRepo),
            agentRepoProvider.overrideWith((ref) => agentRepo),
            gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My MacBook'), findsOneWidget);
    });

    testWidgets('filters agents by search query', (tester) async {
      final agentRepo = InMemoryAgentRepo();
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
        Agent(
          localId: 'local-2', remoteId: 'r-2',
          instanceId: 'inst-1', name: '代码虾',
          description: '编程助手',
          themeColor: '#0984e3',
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instanceRepoProvider.overrideWith((ref) => instanceRepo),
            agentRepoProvider.overrideWith((ref) => agentRepo),
            gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('产品虾'), findsOneWidget);
      expect(find.text('代码虾'), findsOneWidget);

      // Tap search to reveal search field
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField), '产品');
      await tester.pumpAndSettle();

      expect(find.text('产品虾'), findsOneWidget);
      expect(find.text('代码虾'), findsNothing);
    });

    testWidgets('shows no match message when search yields nothing', (tester) async {
      final agentRepo = InMemoryAgentRepo();
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
            instanceRepoProvider.overrideWith((ref) => instanceRepo),
            agentRepoProvider.overrideWith((ref) => agentRepo),
            gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Open search and type non-matching query
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '不存在的虾');
      await tester.pumpAndSettle();

      expect(find.textContaining('No agents match'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
flutter test test/features/agent_list/agent_list_test.dart
```

Expected: empty-state test passes (stub says "No agents yet" but test expects "No Agents" — it should fail), others fail on missing UI.

- [ ] **Step 3: Write the full AgentListPage**

Replace `lib/features/agent_list/agent_list_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/features/agent_list/widgets/agent_card.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';

/// Agent 列表页 (P0 MVP Phase 4)
/// 按实例分组展示所有 Agent，支持搜索过滤，点击进入聊天
class AgentListPage extends ConsumerStatefulWidget {
  const AgentListPage({super.key});

  @override
  ConsumerState<AgentListPage> createState() => _AgentListPageState();
}

class _AgentListPageState extends ConsumerState<AgentListPage> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  List<Agent> _filter(List<Agent> agents) {
    if (_query.isEmpty) return agents;
    final lower = _query.toLowerCase();
    return agents.where((a) {
      return a.displayName.toLowerCase().contains(lower) ||
          (a.description?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(agentListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search agents...',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('Claws'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const LoadingSkeleton(count: 3),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text('Failed to load agents',
                    style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        data: (data) {
          final filtered = _filter(data.agents);
          if (filtered.isEmpty && _query.isEmpty) {
            return const EmptyState(
              icon: Icons.pets,
              title: 'No Agents',
              subtitle: 'Connect to an OpenClaw instance to see agents',
            );
          }
          if (filtered.isEmpty) {
            return Center(
              child: Text(
                'No agents match "$_query"',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            );
          }

          // Group by instanceId
          final groups = <String?, List<Agent>>{};
          for (final agent in filtered) {
            final name = data.instanceNames[agent.instanceId];
            groups.putIfAbsent(name, () => []).add(agent);
          }

          final sortedKeys = groups.keys.toList()
            ..sort((a, b) {
              if (a == null) return 1;
              if (b == null) return -1;
              return a.compareTo(b);
            });

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sortedKeys.length,
            itemBuilder: (context, index) {
              final key = sortedKeys[index];
              final groupAgents = groups[key]!;
              final header = key ?? 'Unknown Instance';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      header,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  ...groupAgents.map(
                    (agent) => AgentCard(
                      agent: agent,
                      onTap: () {
                        context.push(
                          AppRoutes.chatWithParams(
                            agent.localId,
                            agent.instanceId,
                            source: 'claws',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
flutter test test/features/agent_list/agent_list_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Run full test suite**

```bash
flutter test
```

Expected: All tests pass (159 existing + new ones).

- [ ] **Step 6: Commit**

```bash
git add lib/features/agent_list/agent_list_page.dart test/features/agent_list/agent_list_test.dart
git commit -m "feat(agent_list): implement AgentListPage with grouping and search"
```

---

### Self-Review Checklist

1. **Spec coverage:** ✅ All 5 files from the design spec are covered. Agent model extension (Task 1), MockGateway parsing (Task 2), provider (Task 3), AgentCard widget (Task 4), page implementation (Task 5).
2. **No placeholders:** ✅ Every step has explicit code. No TBD/TODO.
3. **Type consistency:** ✅ `AgentListData.agents` (List<Agent>) matches usage in Task 5 `data.agents`. `AgentListData.instanceNames` (Map<String, String>) matches `data.instanceNames[agent.instanceId]`.
4. **Pattern alignment:** ✅ AgentCard follows InstanceCard pattern. agentListProvider follows instanceListProvider pattern. Tests follow existing test patterns.
