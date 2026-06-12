# ClawHub 铁律 (Iron Laws)

> 不可违背的编码铁律。每条规则是经历过教训后才成立的 — 违背它你终将付出代价。
>
> AI 协作时，CLAUDE.md 引用此文作为 Code Review 和实现的门禁检查清单。

---

## 🏗️ 架构边界

### Law 1: 领域层零外部依赖

**规则**：`lib/domain/` 下所有文件只能 import `dart:core`、`dart:async`、`dart:convert`、`dart:math` 和同目录文件。禁止 import `package:flutter/`、`web_socket_channel`、`drift`、`riverpod`。

**为什么**：领域层是业务的心脏。一旦引入 Flutter/框架依赖，领域逻辑就无法脱离 UI 层独立测试和演进。明天换框架，领域层应该原封不动能用。

**检查方式**：
```bash
# 在 domain/ 中不应出现 Flutter/Riverpod/数据库 import
grep -r "package:flutter\|riverpod\|drift\|web_socket" lib/domain/
```

**例外**：`debugPrint` 也不行（依赖 `package:flutter/foundation.dart`）。用 `print`（dart:core）或注入 Logger 接口。

---

### Law 2: UI 层只做渲染，不做决策

**规则**：`lib/features/` 下的 Widget 文件只能做：
- 声明 UI 结构（build 方法）
- 绑定 ViewModel/Provider 的状态到 UI
- 转发用户事件到 ViewModel/Provider

**禁止**：
- Widget 里直接调 `_gatewayClient.sendMessage()`
- Widget 里写 if/else 分支决定"先调 A 再调 B"
- Widget 里操作数据库/SharedPreferences

**判断标准**：你的 Widget 能不能在 5 秒内解释清楚它渲染了什么？如果不能，逻辑太多了。

**正确姿势**：
```dart
// ✅ 正确：Widget 只做展示和事件转发
final session = ref.watch(chatViewModelProvider(params));
final vm = ref.read(chatViewModelProvider(params).notifier);
// ...
onPressed: () => vm.send(text),  // 转发，不决策

// ❌ 错误：Widget 里做业务决策
onPressed: () async {
  if (agent.isOnline) {
    await gatewayClient.sendMessage(...);
    setState(() {});
  }
}
```

---

### Law 3: 面向接口编程

**规则**：跨层边界必须通过抽象接口，不能直接依赖具体实现。

**正确姿势**：
```
UI → [Provider<ChatViewModel>] → ChatViewModel
                                    ├── IMessageRepo (接口)
                                    ├── IGatewayClient (接口)
                                    └── SendMessageUseCase (领域逻辑)

Data → InMemoryMessageRepo implements IMessageRepo
ACL  → MockGatewayClient implements IGatewayClient
```

**检查方式**：在 `lib/features/` 搜 `InMemory` — 不应该出现。UI 只知道接口。

---

## 🌊 状态管理

### Law 4: ValueNotifier/setState 桥接禁止

**规则**：任何新代码不得使用以下模式：
```dart
// ❌ 这辈子别再写了
ChatViewModel? _vm;
void initState() {
  _vm = ref.read(xxxProvider);
  _vm!.someNotifier.addListener(_onChanged);
}
void _onChanged() {
  if (mounted) setState(() {});
}
```

**替代方案**：使用 `StateNotifier` / `Notifier` + `ref.watch`。
```dart
// ✅ 正确
final state = ref.watch(chatViewModelProvider(params));
final vm = ref.read(chatViewModelProvider(params).notifier);
```

**为什么**：手动桥接绕过了 Riverpod 的细粒度订阅、自动 dispose、ProviderScope 重载。这是本项目过去最大的技术债来源。

---

### Law 5: 一个 Provider 一个状态源

**规则**：每个 ViewModel/Provider 管理一个不可变的 state 对象。不要用多个分散的 `ValueNotifier`/`StateProvider` 分别管理相关状态。

```dart
// ❌ 分散状态 — 不知道哪个变了、谁先谁后
final isThinking = StateProvider<bool>((ref) => false);
final timeout = StateProvider<bool>((ref) => false);
final connectionState = StateProvider<...>(...);

// ✅ 集中状态 — 单一 source of truth
class ChatSessionState {
  final ThinkingState thinkingState;
  final GatewayConnectionState connectionState;
  // ...
}
```

**例外**：纯 UI 状态（搜索框文字、折叠/展开等）允许在 Widget 本地用 `setState`。

---

## 📊 数据访问

### Law 6: 批量查询替代 N+1

**规则**：涉及多条记录的聚合查询，必须用批量接口一次完成，不得 for 循环逐条查。

```dart
// ❌ N+1 — Drift 下 50 agents = 50 条 SQL
for (final agent in agents) {
  total += await repo.getMessageCount(agent.id);
}

// ✅ 批量 — 1 条 SQL
final counts = await repo.getMessageCountsByAgent(agentIds);
```

**检查方式**：搜 `for.*await.*repo\.` — 在非初始化代码中不应出现。

---

### Law 7: Repository 方法必须是完整事务

**规则**：Repository 的每个 public 方法必须自包含、完整执行它所承诺的操作。不允许"先调 insert、再调 updateLastMessage，两步之间可能被打断"的模式。

```dart
// ❌ 调用方要编排多步
await repo.insert(msg);
await conversationRepo.updateLastMessage(...);

// ✅ 正确（但可接受在 UseCase 层编排 —
// 因为 SendMessageUseCase 代表一个完整的"发送消息"业务操作）
// 当迁移到 Drift 后，UseCase 内的多步 repo 调用
// 应考虑合并为一个 repository 方法 + 数据库事务。
```

**MVP 阶段可接受** UseCase 层编排多步，但转到 Drift 后必须重新评估。

---

## 🛡️ 错误处理

### Law 8: 禁止空 catch

**规则**：任何 `catch` 块必须至少包含 `debugPrint`（UI/ViewModel 层）或 `print`（领域层）输出异常信息。

```dart
// ❌ 永远的盲区
} catch (_) {
  // silently ignore
}

// ✅ 最小要求
} catch (error, stackTrace) {
  debugPrint('History fetch failed: $error\n$stackTrace');
}
```

**例外**：硬件能力缺失且不影响功能（如手电筒不可用）允许静默。

---

### Law 9: 异常必须被翻译成用户能理解的状态

**规则**：底层异常不要在 UI 层直接暴露原始错误消息。状态应通过 `LoadError`/`AsyncValue.error` 传递，UI 根据状态类型展示友好提示，不是直接 `Text('Error: $e')`。

```dart
// ✅ 领域/数据层抛出的异常 → ViewModel 捕获 → 转为状态
_updateState((s) => s.copyWith(messages: LoadError(error, stackTrace)));

// Widget 中：
LoadError(:final error) => Center(child: Text('Failed to load messages: $error')),
```

---

## 🧩 UI 组件

### Law 10: 面向组合，不面向继承

**规则**：UI 复用靠 Widget 组合（has-a），不靠继承（is-a）。一个 Widget 超过两种职责时拆分。

**拆分信号**：
- build 方法超过 50 行 → 考虑拆分子 Widget
- 同一段 UI 出现在 2 个以上地方 → 提取到 `ui_kit/`
- 私有的 `_buildXxx` helper 方法被多处调用 → 提成独立 StatelessWidget

**提取 ui_kit 的判断标准**：组件是否有参数化意义（不耦合特定业务 model），且对项目内其他页面有复用潜力。满足任一条件就提。

---

### Law 11: 列表必须用 builder 构造函数

**规则**：任何长度不可预知或超过 20 项的列表，必须使用 `ListView.builder`（或 `ListView.separated`），禁止 `ListView(children: [...])` 预构建所有 Widget。

```dart
// ❌ 500 条消息 = 500 个 Widget 常驻内存
ListView(children: messages.map((m) => MessageBubble(...)).toList());

// ✅ 按需构建
ListView.builder(
  itemCount: messages.length,
  itemBuilder: (_, i) => MessageBubble(message: messages[i]),
);
```

**例外**：固定小巧的列表（如底部导航 3 个 tab、设置菜单 <10 项）可以用 `children:`。

---

## 🔗 依赖注入

### Law 12: Provider 分层注册

**规则**：所有 Provider 在 `lib/app/di/providers.dart` 中定义，按以下顺序：
1. 基础设施层（Gateway Client）
2. 数据层（Repository 实现）
3. 业务层（UseCase）
4. Feature Provider 在各 feature 的 `providers/` 文件夹中

接口 provider 和实现 provider 分开注册：
```dart
// 接口 provider — 面向接口
final gatewayClientProvider = Provider<IGatewayClient>((ref) {
  return ref.watch(mockGatewayClientProvider); // 后期换真实实现只改这里
});

// 实现 provider — 具体类型
final mockGatewayClientProvider = Provider<MockGatewayClient>((ref) {
  final client = MockGatewayClient();
  ref.onDispose(() => client.dispose());
  return client;
});
```

---

### Law 13: ref.watch 和 ref.read 区分明确

**规则**：
- `ref.watch` — 用于读取响应式状态，值变化时触发重建（build 方法里用）
- `ref.read` — 用于读取不响应式追踪的值（回调/事件处理器里用）

```dart
// ✅ 正确
Widget build(BuildContext context, WidgetRef ref) {
  final state = ref.watch(stateProvider);      // watch — 状态变了要重建
  return ElevatedButton(
    onPressed: () => ref.read(notifierProvider.notifier).doSomething(), // read — 回调里不需要追踪
  );
}
```

**禁止**：在 build 方法中用 `ref.read` 读状态值（会导致状态变化时不重建）。

---

## 🧪 测试

### Law 14: 每新增 Widget 至少 2 个测试

**规则**：每个新增的可视 Widget 至少覆盖：
1. 基础渲染（组件出现在 widget tree 中）
2. 一个关键交互或边界条件

已有 248 个测试建立的安全网不应被稀释。

---

### Law 15: 测试不直接操作 Provider 内部状态

**规则**：测试通过 Provider 的 public API 驱动，不直接访问 ViewModel 内部字段。

```dart
// ❌ 直接改内部状态
vm.state = someState;

// ✅ 通过 Provider 覆盖 + public API 驱动
ProviderScope(
  overrides: [chatViewModelProvider(params).overrideWith((ref) => vm)],
  child: ...
);
```

**例外**：`@visibleForTesting` 标记的 `state` setter 允许在测试中直接赋值初始化状态。

---

### Law 16: 不可见输出必须可验证

**规则**：以下两类"编译器不检查、lint 不报、UI 上不易察觉"的输出，必须有测试直接断言：

**A. 参数化路径/URL/字符串方法** — 接受参数并返回路径、URL 或编码字符串的方法，必须对返回值写精确断言。

```dart
// ❌ 只测了常量，没测参数化方法
expect(AppRoutes.addInstance, '/instances/add');
// editInstanceWithParams 返回 'edit/xxx'（少了 /instances/ 前缀）
// — 编译器不报错，lint 不报，运行时 go_router 抛 GoException

// ✅ 必须覆盖参数化方法的返回值
expect(AppRoutes.editInstanceWithParams('abc'), '/instances/edit/abc');
expect(AppRoutes.chatWithParams('a', 'i', source: 'claws'), startsWith('chat/a?'));
```

**B. 内部集合/状态机** — 操作内部 `Set`/`Map` 或状态机的方法，必须用 Fake 注入 + 调用计数断言其副作用。

```dart
// ❌ ConnectionOrchestrator._connect() 的去重锁 _connecting 泄漏
// — 成功了不释放，后续重连被静默跳过，UI 上完全看不出原因

// ✅ Fake 注入 → 调用两次 onInstanceSaved → 断言 gateway.connect() 被调用了两次
final gateway = _FakeGatewayClient();
final orch = ConnectionOrchestrator(gatewayClient: gateway, ...);
await orch.onInstanceSaved(onlineInstance);
await orch.onInstanceSaved(onlineInstance); // 编辑后重新保存
expect(gateway.connectCounts['inst-1'], 2,
    reason: '第二次保存应触发重连（_connecting 未泄漏）');
```

**为什么**：路径拼接错误和状态泄漏不会导致编译失败或崩溃，只产生"看起来正常但行为不对"的 bug。这类 bug 在手动测试中极难发现，唯一可靠的防线是自动化断言。

**检查方式**：
- Code Review 时，每个返回字符串/URL 的参数化方法 → 搜对应测试文件有无对该方法返回值的断言
- Code Review 时，每个操作内部 Set/Map 状态的类 → 搜对应测试文件有无 Fake + 调用计数

---

## 🔍 Code Review 门禁清单

合并前逐条检查：

- [ ] **Law 1**: domain/ 下无 Flutter/Riverpod/drift import
- [ ] **Law 2**: feature/ 下 Widget 不直接调 Gateway/DB API
- [ ] **Law 4**: 无新增 ValueNotifier + addListener + setState 桥接
- [ ] **Law 6**: 无 for + await repo 的 N+1 查询
- [ ] **Law 8**: 无空 `catch (_)` 块
- [ ] **Law 11**: 新增列表使用 builder 构造函数
- [ ] **Law 12**: 新增 Provider 注册在 di/providers.dart 或 feature/providers/
- [ ] **Law 16**: 新增参数化路径方法有返回值断言；新增状态机有 Fake 注入测试
- [ ] **测试**: 新增 Widget 至少有 2 个测试用例
- [ ] `flutter analyze` 零 error/warning
- [ ] `flutter test` 全通过

---

> **最后一条铁律**：这份文件本身不是摆设。每违反一条，在 commit message 里解释原因。连续违反三次 → 停下来重构。
