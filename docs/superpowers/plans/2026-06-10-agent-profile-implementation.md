# AgentProfilePage + AgentConfigPage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the AgentProfilePage stub with a full detail page + config page, following the prototype's two-page architecture.

**Architecture:** Two pages (AgentProfilePage, AgentConfigPage) share a single `AgentProfileViewModel` (StateNotifier) that handles data loading, save orchestration, and error translation. Two reusable components (EmojiAvatar, ColorGrid) are extracted to `ui_kit/`. All flows follow TDD — write test, verify fail, implement, verify pass, commit.

**Tech Stack:** Flutter 3.44.1, Riverpod (StateNotifierProvider.family), flutter_test + mocktail

---

## File Structure

```
lib/
├── domain/models/
│   └── errors.dart                          ← CREATE (AgentNotFoundError)
├── ui_kit/
│   ├── emoji_avatar.dart                    ← CREATE
│   └── color_grid.dart                      ← CREATE (ColorOption + ColorGrid)
├── features/agent_profile/
│   ├── agent_profile_page.dart              ← MODIFY (stub → full)
│   ├── agent_config_page.dart               ← CREATE
│   ├── viewmodels/
│   │   └── agent_profile_view_model.dart    ← CREATE
│   ├── providers/
│   │   └── agent_profile_providers.dart     ← CREATE
│   └── widgets/
│       ├── profile_header.dart              ← CREATE
│       └── stats_grid.dart                  ← CREATE
├── app/router/
│   └── router.dart                          ← MODIFY (add config route)

test/
├── domain/models/
│   └── errors_test.dart                     ← CREATE or merge into existing
├── features/agent_profile/
│   ├── agent_profile_page_test.dart         ← CREATE
│   ├── agent_config_page_test.dart          ← CREATE
│   ├── viewmodels/
│   │   └── agent_profile_view_model_test.dart ← CREATE
│   └── widgets/
│       ├── profile_header_test.dart         ← CREATE
│       └── stats_grid_test.dart             ← CREATE
├── ui_kit/
│   ├── emoji_avatar_test.dart               ← CREATE
│   └── color_grid_test.dart                 ← CREATE
```

---

### Task 1: AgentNotFoundError

**Files:**
- Create: `lib/domain/models/errors.dart`
- Create: `test/domain/models/errors_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/domain/models/errors_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/errors.dart';

void main() {
  group('AgentNotFoundError', () {
    test('stores agentId', () {
      const error = AgentNotFoundError('test-id');
      expect(error.agentId, 'test-id');
    });

    test('toString includes agentId', () {
      const error = AgentNotFoundError('abc-123');
      expect(error.toString(), contains('abc-123'));
    });

    test('is Exception', () {
      const error = AgentNotFoundError('id');
      expect(error, isA<Exception>());
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/domain/models/errors_test.dart
```
Expected: compilation error — `AgentNotFoundError` not found.

- [ ] **Step 3: Write implementation**

Create `lib/domain/models/errors.dart`:

```dart
/// Agent 不存在异常
/// 当通过 localId 查找 Agent 但记录不存在时抛出
class AgentNotFoundError implements Exception {
  final String agentId;
  const AgentNotFoundError(this.agentId);

  @override
  String toString() => 'Agent not found: $agentId';
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/domain/models/errors_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/errors.dart test/domain/models/errors_test.dart
git commit -m "feat(agent_profile): add AgentNotFoundError domain exception

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: AgentDetailData + AgentProfileState

**Files:**
- Create: `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart` (partial — data models only)
- Create: `test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart` (partial — model tests)

- [ ] **Step 1: Write the failing test**

Create `test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';

void main() {
  group('AgentDetailData', () {
    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划',
      themeColor: '#6c5ce7',
    );

    const testInstance = Instance(
      id: 'inst-1',
      name: '我的MacBook',
      gatewayUrl: 'ws://192.168.1.1:18789',
      tokenRef: 'key-1',
    );

    test('equality — same fields are equal', () {
      final a = AgentDetailData(agent: testAgent, messageCount: 10);
      final b = AgentDetailData(agent: testAgent, messageCount: 10);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equality — different messageCount are not equal', () {
      final a = AgentDetailData(agent: testAgent, messageCount: 10);
      final b = AgentDetailData(agent: testAgent, messageCount: 20);
      expect(a, isNot(b));
    });

    test('instance is optional (null)', () {
      final data = AgentDetailData(agent: testAgent, messageCount: 0);
      expect(data.instance, isNull);
    });

    test('instance can be provided', () {
      final data = AgentDetailData(
        agent: testAgent,
        instance: testInstance,
        messageCount: 5,
      );
      expect(data.instance, testInstance);
    });
  });

  group('AgentProfileState', () {
    test('default state has LoadInProgress', () {
      const state = AgentProfileState();
      expect(state.detailLoadState, isA<LoadInProgress>());
      expect(state.isSaving, false);
      expect(state.saveError, isNull);
      expect(state.saveSuccess, false);
    });

    test('copyWith preserves unchanged fields', () {
      const state = AgentProfileState();
      final updated = state.copyWith(isSaving: true);
      expect(updated.isSaving, true);
      expect(updated.detailLoadState, state.detailLoadState);
      expect(updated.saveError, state.saveError);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart
```
Expected: compilation error — file not found.

- [ ] **Step 3: Write implementation**

Create `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/errors.dart';
import 'package:claw_hub/domain/repositories/repositories.dart';

/// Agent 详情聚合数据（不可变值对象）
class AgentDetailData {
  final Agent agent;
  final Instance? instance;
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

/// Agent 资料页的不可变状态快照
///
/// 同时服务 AgentProfilePage（消费 [detailLoadState]）和
/// AgentConfigPage（消费 [isSaving]/[saveError]/[saveSuccess]）。
class AgentProfileState {
  final LoadState<AgentDetailData> detailLoadState;
  final bool isSaving;
  final String? saveError;
  final bool saveSuccess;

  const AgentProfileState({
    this.detailLoadState = const LoadInProgress(),
    this.isSaving = false,
    this.saveError,
    this.saveSuccess = false,
  });

  /// Sentinel 用于区分 "未传参" 和 "显式传 null"
  static const _sentinel = Object();

  AgentProfileState copyWith({
    LoadState<AgentDetailData>? detailLoadState,
    bool? isSaving,
    Object? saveError = _sentinel,
    bool? saveSuccess,
  }) {
    return AgentProfileState(
      detailLoadState: detailLoadState ?? this.detailLoadState,
      isSaving: isSaving ?? this.isSaving,
      saveError:
          identical(saveError, _sentinel) ? this.saveError : saveError as String?,
      saveSuccess: saveSuccess ?? this.saveSuccess,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentProfileState &&
          detailLoadState == other.detailLoadState &&
          isSaving == other.isSaving &&
          saveError == other.saveError &&
          saveSuccess == other.saveSuccess;

  @override
  int get hashCode =>
      Object.hash(detailLoadState, isSaving, saveError, saveSuccess);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/agent_profile/viewmodels/agent_profile_view_model.dart test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart
git commit -m "feat(agent_profile): add AgentDetailData + AgentProfileState models

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: AgentProfileViewModel

**Files:**
- Modify: `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart` (add ViewModel class)
- Modify: `test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart` (add ViewModel tests)

- [ ] **Step 1: Write the failing tests**

Append to `test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart`:

```dart
// Add these imports at the top:
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/domain/models/errors.dart';

// Mock repos
class MockAgentRepo extends Mock implements IAgentRepo {}
class MockInstanceRepo extends Mock implements IInstanceRepo {}
class MockMessageRepo extends Mock implements IMessageRepo {}

void main() {
  // ... existing model tests ...

  group('AgentProfileViewModel', () {
    late MockAgentRepo agentRepo;
    late MockInstanceRepo instanceRepo;
    late MockMessageRepo messageRepo;
    late ProviderContainer container;

    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划、需求分析',
      themeColor: '#6c5ce7',
    );

    setUp(() {
      agentRepo = MockAgentRepo();
      instanceRepo = MockInstanceRepo();
      messageRepo = MockMessageRepo();
    });

    AgentProfileViewModel createVM() {
      return AgentProfileViewModel(
        agentRepo: agentRepo,
        instanceRepo: instanceRepo,
        messageRepo: messageRepo,
        agentId: 'local-1',
      );
    }

    test('init() loads agent and sets LoadData on success', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 42);

      final vm = createVM();
      await vm.init();

      final state = vm.state;
      expect(state.detailLoadState, isA<LoadData<AgentDetailData>>());
      final data = (state.detailLoadState as LoadData<AgentDetailData>).value;
      expect(data.agent, testAgent);
      expect(data.messageCount, 42);
      expect(data.instance, isNull);
    });

    test('init() sets LoadError when agent not found', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => null);

      final vm = createVM();
      await vm.init();

      final state = vm.state;
      expect(state.detailLoadState, isA<LoadError>());
      expect(
        (state.detailLoadState as LoadError).error,
        isA<AgentNotFoundError>(),
      );
    });

    test('init() does not fail when instance is not found', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenThrow(Exception('DB error'));
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      final state = vm.state;
      expect(state.detailLoadState, isA<LoadData<AgentDetailData>>());
      final data = (state.detailLoadState as LoadData<AgentDetailData>).value;
      expect(data.instance, isNull);
    });

    test('saveProfile updates state on success', () async {
      // First init to load agent
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);
      when(() => agentRepo.updateLocalProfile(
        'local-1',
        nickname: '我的产品虾',
        themeColor: '#0984e3',
      )).thenAnswer((_) async => testAgent.copyWith(
        nickname: '我的产品虾',
        themeColor: '#0984e3',
      ));

      final vm = createVM();
      await vm.init();

      // Clear mocks for second agentRepo.getById call inside saveProfile → refresh
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent.copyWith(
        nickname: '我的产品虾',
        themeColor: '#0984e3',
      ));
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      await vm.saveProfile('local-1', '我的产品虾', '#0984e3');

      final state = vm.state;
      expect(state.saveSuccess, true);
      expect(state.isSaving, false);
    });

    test('saveProfile sets saveError on failure', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      when(() => agentRepo.updateLocalProfile(
        'local-1',
        nickname: any(named: 'nickname'),
        themeColor: any(named: 'themeColor'),
      )).thenThrow(Exception('Save failed'));

      await vm.saveProfile('local-1', 'nick', '#0984e3');

      final state = vm.state;
      expect(state.saveError, isNotNull);
      expect(state.isSaving, false);
      expect(state.saveSuccess, false);
    });

    test('clearSaveResult resets save flags', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      // Use saveProfile failure to set saveError, then clear it
      when(() => agentRepo.updateLocalProfile(
        'local-1',
        nickname: any(named: 'nickname'),
        themeColor: any(named: 'themeColor'),
      )).thenThrow(Exception('Save failed'));
      await vm.saveProfile('local-1', 'nick', '#0984e3');
      expect(vm.state.saveError, isNotNull);

      vm.clearSaveResult();
      expect(vm.state.saveError, isNull);
      expect(vm.state.saveSuccess, false);
    });

    test('agent getter returns loaded agent', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();

      expect(vm.agent, isNotNull);
      expect(vm.agent!.name, '产品虾');
    });

    test('dispose can be called safely', () async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1')).thenAnswer((_) async => null);
      when(() => messageRepo.getMessageCount('local-1')).thenAnswer((_) async => 0);

      final vm = createVM();
      await vm.init();
      vm.dispose();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart
```
Expected: compilation errors — `AgentProfileViewModel` not defined in file.

- [ ] **Step 3: Write AgentProfileViewModel**

Open `lib/features/agent_profile/viewmodels/agent_profile_view_model.dart` and append the ViewModel class after the State definition:

```dart
/// Agent 资料页的 ViewModel
///
/// 拥有 agent 详情加载、实例查询、消息统计、个性化配置保存的全部编排逻辑。
/// AgentProfilePage 和 AgentConfigPage 共享同一个 ViewModel 实例
///（通过同一个 StateNotifierProvider.family 的 agentId 参数）。
class AgentProfileViewModel extends StateNotifier<AgentProfileState> {
  final IAgentRepo _agentRepo;
  final IInstanceRepo _instanceRepo;
  final IMessageRepo _messageRepo;
  final String agentId;

  Agent? _agent;

  /// 缓存已加载的 Agent，供 Config 页读取初始表单值。
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

  /// 初始化：加载 agent 详情 + 实例信息 + 消息统计。
  Future<void> init() async {
    await refresh();
  }

  /// 重新加载数据（外部触发：下拉刷新、config 保存后）。
  Future<void> refresh() async {
    _updateState((s) => s.copyWith(detailLoadState: const LoadInProgress()));

    try {
      final agent = await _agentRepo.getById(agentId);
      if (agent == null) throw const AgentNotFoundError(agentId);

      _agent = agent;

      Instance? instance;
      try {
        instance = await _instanceRepo.getById(agent.instanceId);
      } catch (error, stackTrace) {
        debugPrint(
          'Instance lookup failed for ${agent.instanceId}: $error\n$stackTrace',
        );
        // instance 不存在是非致命错误
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

  /// 保存个性化配置（由 AgentConfigPage 调用）。
  Future<void> saveProfile(
    String localId,
    String? nickname,
    String themeColor,
  ) async {
    _updateState((s) => s.copyWith(
      isSaving: true,
      saveError: null,
      saveSuccess: false,
    ));
    try {
      await _agentRepo.updateLocalProfile(
        localId,
        nickname: nickname,
        themeColor: themeColor,
      );
      // 保存后刷新详情数据，Profile 页自动看到最新值
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

  /// 消费保存结果（Config 页 pop 后或 SnackBar 展示后调用）。
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

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/agent_profile/viewmodels/agent_profile_view_model.dart test/features/agent_profile/viewmodels/agent_profile_view_model_test.dart
git commit -m "feat(agent_profile): add AgentProfileViewModel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: AgentProfileViewModelProvider

**Files:**
- Create: `lib/features/agent_profile/providers/agent_profile_providers.dart`

- [ ] **Step 1: Write implementation**

Create `lib/features/agent_profile/providers/agent_profile_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';

/// Agent 资料页 ViewModel Provider
///
/// AgentProfilePage 和 AgentConfigPage 通过同一个 agentId 参数共享
/// 同一个 ViewModel 实例。Config 页调用 vm.saveProfile(...) 后，
/// Profile 页自动重建（因为 watch 同一个 state 对象）。
final agentProfileViewModelProvider = StateNotifierProvider.family<
    AgentProfileViewModel, AgentProfileState, String>(
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

- [ ] **Step 2: Run analyze to verify no issues**

```bash
flutter analyze lib/features/agent_profile/
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/agent_profile/providers/agent_profile_providers.dart
git commit -m "feat(agent_profile): add agentProfileViewModelProvider

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: EmojiAvatar (ui_kit)

**Files:**
- Create: `lib/ui_kit/emoji_avatar.dart`
- Create: `test/ui_kit/emoji_avatar_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui_kit/emoji_avatar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

void main() {
  group('EmojiAvatar', () {
    Widget buildAvatar({
      String displayName = '产品虾',
      String themeColor = '#6c5ce7',
      double radius = 36,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: EmojiAvatar(
            displayName: displayName,
            themeColor: themeColor,
            radius: radius,
          ),
        ),
      );
    }

    testWidgets('renders first character of displayName', (tester) async {
      await tester.pumpWidget(buildAvatar());
      expect(find.text('产'), findsOneWidget);
    });

    testWidgets('uses themeColor background', (tester) async {
      await tester.pumpWidget(buildAvatar(themeColor: '#0984e3'));
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundColor, const Color(0xFF0984E3));
    });

    testWidgets('respects radius parameter', (tester) async {
      await tester.pumpWidget(buildAvatar(radius: 24));
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, 24.0);
    });

    testWidgets('handles empty displayName', (tester) async {
      await tester.pumpWidget(buildAvatar(displayName: ''));
      expect(find.text(''), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/ui_kit/emoji_avatar_test.dart
```
Expected: compilation error — `EmojiAvatar` not found.

- [ ] **Step 3: Write implementation**

Create `lib/ui_kit/emoji_avatar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 通用 Emoji/首字符头像组件
///
/// 显示 displayName 的首字符，背景为 themeColor，可配置半径。
/// 在 ChatRoomPage AppBar 和 AgentProfilePage 的 ProfileHeader 中复用。
class EmojiAvatar extends StatelessWidget {
  final String displayName;
  final String themeColor;
  final double radius;

  const EmojiAvatar({
    super.key,
    required this.displayName,
    required this.themeColor,
    this.radius = 36,
  });

  @override
  Widget build(BuildContext context) {
    final color = ColorExtension.fromHex(themeColor);
    final firstChar = displayName.isNotEmpty ? displayName.characters.first : '';

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundColor: color.contrastingTextColor(),
      child: Text(
        firstChar,
        style: TextStyle(
          fontSize: radius * 0.55,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/ui_kit/emoji_avatar_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/ui_kit/emoji_avatar.dart test/ui_kit/emoji_avatar_test.dart
git commit -m "feat(ui_kit): extract EmojiAvatar component

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: ColorGrid (ui_kit)

**Files:**
- Create: `lib/ui_kit/color_grid.dart`
- Create: `test/ui_kit/color_grid_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui_kit/color_grid_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/color_grid.dart';

void main() {
  group('ColorOption', () {
    test('stores hex and label', () {
      const option = ColorOption(hex: '#6c5ce7', label: '紫罗兰');
      expect(option.hex, '#6c5ce7');
      expect(option.label, '紫罗兰');
    });

    test('equality', () {
      const a = ColorOption(hex: '#6c5ce7', label: '紫罗兰');
      const b = ColorOption(hex: '#6c5ce7', label: '紫罗兰');
      expect(a, b);
    });
  });

  group('ColorGrid', () {
    const colors = [
      ColorOption(hex: '#6c5ce7', label: '紫罗兰'),
      ColorOption(hex: '#0984e3', label: '海洋蓝'),
      ColorOption(hex: '#00b894', label: '薄荷绿'),
    ];

    Widget buildGrid({
      required String selectedColor,
      ValueChanged<String>? onColorSelected,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ColorGrid(
            colors: colors,
            selectedColor: selectedColor,
            onColorSelected: onColorSelected ?? (_) {},
          ),
        ),
      );
    }

    testWidgets('renders all color dots', (tester) async {
      await tester.pumpWidget(buildGrid(selectedColor: '#6c5ce7'));
      // Each color dot is a GestureDetector wrapping a Container
      expect(find.byType(GestureDetector), findsNWidgets(3));
    });

    testWidgets('selected color has highlight border', (tester) async {
      await tester.pumpWidget(buildGrid(selectedColor: '#0984e3'));
      // Verify selected color dot has the selection indicator
      // The selected color's outer Container gets a white border + shadow
      final containers = tester.widgetList<Container>(find.byType(Container));
      // At least one Container has a BoxDecoration with a border
      bool foundSelected = false;
      for (final container in containers) {
        final decoration = container.decoration as BoxDecoration?;
        if (decoration != null && decoration.border != null) {
          foundSelected = true;
          break;
        }
      }
      expect(foundSelected, isTrue);
    });

    testWidgets('calls onColorSelected when tapped', (tester) async {
      String? selected;
      await tester.pumpWidget(buildGrid(
        selectedColor: '#6c5ce7',
        onColorSelected: (color) => selected = color,
      ));
      // Tap the second color dot
      await tester.tap(find.byType(GestureDetector).at(1));
      expect(selected, '#0984e3');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/ui_kit/color_grid_test.dart
```

- [ ] **Step 3: Write implementation**

Create `lib/ui_kit/color_grid.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 颜色选项
class ColorOption {
  final String hex;
  final String label;

  const ColorOption({required this.hex, required this.label});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorOption && hex == other.hex && label == other.label;

  @override
  int get hashCode => Object.hash(hex, label);
}

/// 12 色圆形主题色选择器
///
/// 以 6×2 网格展示颜色圆形，选中项显示白色边框 + 外环高亮。
/// 参数化为 [colors] + [selectedColor] + [onColorSelected] 回调，
/// 不耦合任何业务 Model，可在项目中复用。
class ColorGrid extends StatelessWidget {
  final List<ColorOption> colors;
  final String selectedColor;
  final ValueChanged<String> onColorSelected;

  const ColorGrid({
    super.key,
    required this.colors,
    required this.selectedColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: colors.map((option) {
        final color = ColorExtension.fromHex(option.hex);
        final isSelected = option.hex.toUpperCase() == selectedColor.toUpperCase();

        return GestureDetector(
          onTap: () => onColorSelected(option.hex),
          child: Tooltip(
            message: option.label,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: isSelected
                    ? Border.all(color: Colors.white, width: 3)
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withAlpha(150),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/ui_kit/color_grid_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/ui_kit/color_grid.dart test/ui_kit/color_grid_test.dart
git commit -m "feat(ui_kit): extract ColorGrid component

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: ProfileHeader Widget

**Files:**
- Create: `lib/features/agent_profile/widgets/profile_header.dart`
- Create: `test/features/agent_profile/widgets/profile_header_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/agent_profile/widgets/profile_header_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/agent_profile/widgets/profile_header.dart';

void main() {
  group('ProfileHeader', () {
    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划、需求分析',
      themeColor: '#6c5ce7',
      isPinned: false,
    );

    final testInstance = Instance(
      id: 'inst-1',
      name: '我的MacBook',
      gatewayUrl: 'ws://192.168.1.1:18789',
      tokenRef: 'key-1',
    );

    final onlineInstance = Instance(
      id: 'inst-1',
      name: '我的MacBook',
      gatewayUrl: 'ws://192.168.1.1:18789',
      tokenRef: 'key-1',
      healthStatus: HealthStatus.online,
    );

    Widget buildHeader({
      required Agent agent,
      Instance? instance,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ProfileHeader(agent: agent, instance: instance),
        ),
      );
    }

    testWidgets('renders agent displayName', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('renders agent description', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('产品规划、需求分析'), findsOneWidget);
    });

    testWidgets('renders avatar with first character', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('产'), findsOneWidget);
    });

    testWidgets('shows pin badge when pinned', (tester) async {
      final pinned = testAgent.copyWith(isPinned: true);
      await tester.pumpWidget(buildHeader(agent: pinned));
      expect(find.text('已置顶'), findsOneWidget);
    });

    testWidgets('no pin badge when not pinned', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('已置顶'), findsNothing);
    });

    testWidgets('shows instance name when instance provided', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent, instance: testInstance));
      expect(find.text('我的MacBook'), findsOneWidget);
    });

    testWidgets('shows "未知实例" when instance is null', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('未知实例'), findsOneWidget);
    });

    testWidgets('shows green online status when instance is online', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent, instance: onlineInstance));
      expect(find.text('在线'), findsOneWidget);
    });

    testWidgets('shows "离线" when instance is absent', (tester) async {
      await tester.pumpWidget(buildHeader(agent: testAgent));
      expect(find.text('离线'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/agent_profile/widgets/profile_header_test.dart
```

- [ ] **Step 3: Write implementation**

Create `lib/features/agent_profile/widgets/profile_header.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// Agent Profile 头部组件
///
/// 展示大头像、名称、描述、在线状态和所属实例。
/// 完全参数化 — 不依赖任何 Provider。
class ProfileHeader extends StatelessWidget {
  final Agent agent;
  final Instance? instance;

  const ProfileHeader({
    super.key,
    required this.agent,
    this.instance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOnline = instance?.healthStatus.isConnectable ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          // Avatar with theme color border
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ColorExtension.fromHex(agent.themeColor),
                width: 4,
              ),
            ),
            child: EmojiAvatar(
              displayName: agent.displayName,
              themeColor: agent.themeColor,
              radius: 36,
            ),
          ),
          const SizedBox(height: 12),
          // Name + pin badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  agent.displayName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (agent.isPinned) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '已置顶',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Description
          if (agent.description != null && agent.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              agent.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          // Status row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppColors.statusOnline
                      : AppColors.statusOffline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                isOnline ? '在线' : '离线',
                style: TextStyle(
                  fontSize: 12,
                  color: isOnline
                      ? AppColors.statusOnline
                      : AppColors.statusOffline,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '·',
                style: TextStyle(
                  color: theme.colorScheme.outline,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  instance?.name ?? '未知实例',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/agent_profile/widgets/profile_header_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/agent_profile/widgets/profile_header.dart test/features/agent_profile/widgets/profile_header_test.dart
git commit -m "feat(agent_profile): add ProfileHeader widget

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: StatsGrid Widget

**Files:**
- Create: `lib/features/agent_profile/widgets/stats_grid.dart`
- Create: `test/features/agent_profile/widgets/stats_grid_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/agent_profile/widgets/stats_grid_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_profile/widgets/stats_grid.dart';

void main() {
  group('StatsGrid', () {
    Widget buildGrid({required int messageCount}) {
      return MaterialApp(
        home: Scaffold(body: StatsGrid(messageCount: messageCount)),
      );
    }

    testWidgets('renders message count as real value', (tester) async {
      await tester.pumpWidget(buildGrid(messageCount: 1024));
      expect(find.text('1,024'), findsOneWidget);
    });

    testWidgets('renders "消息总数" label', (tester) async {
      await tester.pumpWidget(buildGrid(messageCount: 0));
      expect(find.text('消息总数'), findsOneWidget);
    });

    testWidgets('renders placeholder "--" for unavailable stats', (tester) async {
      await tester.pumpWidget(buildGrid(messageCount: 5));
      // 5 placeholder "--" items: 对话次数, 工具调用, 活跃天数, 连续天数, 首次对话
      expect(find.text('--'), findsNWidgets(5));
    });

    testWidgets('renders 3 columns × 2 rows = 6 stat cells', (tester) async {
      await tester.pumpWidget(buildGrid(messageCount: 100));
      // Each stat cell is a Column inside a SizedBox
      final columns = tester.widgetList<Column>(find.byType(Column));
      // There are 6 stat cells + potentially other Columns. Check exact.
      expect(columns.length, greaterThanOrEqualTo(6));
    });

    testWidgets('shows zero correctly', (tester) async {
      await tester.pumpWidget(buildGrid(messageCount: 0));
      expect(find.text('0'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/agent_profile/widgets/stats_grid_test.dart
```

- [ ] **Step 3: Write implementation**

Create `lib/features/agent_profile/widgets/stats_grid.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// 统计网格组件
///
/// 展示 Agent 的 6 项统计（3×2 布局）。
/// 当前仅 messageCount 有真实数据，其余 5 项显示 "--" 占位
/// （等待 US-019 成长面板实现）。
class StatsGrid extends StatelessWidget {
  final int messageCount;

  const StatsGrid({super.key, required this.messageCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = [
      _StatItem(label: '对话次数', value: '--', isPlaceholder: true),
      _StatItem(
        label: '消息总数',
        value: _formatNumber(messageCount),
        isPlaceholder: false,
      ),
      _StatItem(label: '工具调用', value: '--', isPlaceholder: true),
      _StatItem(label: '活跃天数', value: '--', isPlaceholder: true),
      _StatItem(label: '连续天数', value: '--', isPlaceholder: true),
      _StatItem(label: '首次对话', value: '--', isPlaceholder: true),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.6,
          crossAxisSpacing: 1,
          mainAxisSpacing: 1,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: item.isPlaceholder
                          ? theme.colorScheme.outline
                          : AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 格式化数字：添加千位分隔符
  String _formatNumber(int n) {
    if (n < 1000) return n.toString();
    final chars = n.toString().split('').reversed.toList();
    final buffer = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(',');
      buffer.write(chars[i]);
    }
    return buffer.toString().split('').reversed.join();
  }
}

class _StatItem {
  final String label;
  final String value;
  final bool isPlaceholder;

  const _StatItem({
    required this.label,
    required this.value,
    required this.isPlaceholder,
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/agent_profile/widgets/stats_grid_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/agent_profile/widgets/stats_grid.dart test/features/agent_profile/widgets/stats_grid_test.dart
git commit -m "feat(agent_profile): add StatsGrid widget

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: AgentProfilePage (replace stub)

**Files:**
- Modify: `lib/features/agent_profile/agent_profile_page.dart`
- Create: `test/features/agent_profile/agent_profile_page_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/agent_profile/agent_profile_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/features/agent_profile/agent_profile_page.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';

class MockAgentRepo extends Mock implements IAgentRepo {}
class MockInstanceRepo extends Mock implements IInstanceRepo {}
class MockMessageRepo extends Mock implements IMessageRepo {}

void main() {
  group('AgentProfilePage', () {
    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划、需求分析',
      themeColor: '#6c5ce7',
    );

    final testInstance = Instance(
      id: 'inst-1',
      name: '我的MacBook',
      gatewayUrl: 'ws://192.168.1.1:18789',
      tokenRef: 'key-1',
      healthStatus: HealthStatus.online,
    );

    late MockAgentRepo agentRepo;
    late MockInstanceRepo instanceRepo;
    late MockMessageRepo messageRepo;

    setUp(() {
      agentRepo = MockAgentRepo();
      instanceRepo = MockInstanceRepo();
      messageRepo = MockMessageRepo();

      when(() => agentRepo.getById('local-1'))
          .thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1'))
          .thenAnswer((_) async => testInstance);
      when(() => messageRepo.getMessageCount('local-1'))
          .thenAnswer((_) async => 1024);
    });

    Widget buildPage() {
      return ProviderScope(
        overrides: [
          agentProfileViewModelProvider('local-1').overrideWith(
            (ref) => AgentProfileViewModel(
              agentRepo: agentRepo,
              instanceRepo: instanceRepo,
              messageRepo: messageRepo,
              agentId: 'local-1',
            )..init(),
          ),
        ],
        child: const MaterialApp(
          home: AgentProfilePage(agentId: 'local-1'),
        ),
      );
    }

    testWidgets('renders agent name on success', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('renders agent description', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text('产品规划、需求分析'), findsOneWidget);
    });

    testWidgets('shows loading skeleton while loading', (tester) async {
      // Delay the repo calls to keep state in loading
      when(() => agentRepo.getById('local-1'))
          .thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 1));
        return testAgent;
      });
      await tester.pumpWidget(buildPage());
      // LoadingSkeleton should be visible
      expect(find.text('产品虾'), findsNothing);
    });

    testWidgets('shows edit button in AppBar', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/agent_profile/agent_profile_page_test.dart
```
Expected: tests fail — stub doesn't render agent name/description.

- [ ] **Step 3: Rewrite AgentProfilePage**

Replace `lib/features/agent_profile/agent_profile_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/widgets/profile_header.dart';
import 'package:claw_hub/features/agent_profile/widgets/stats_grid.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';

/// Agent 详情页 — 展示 Agent 信息、统计、成就占位
///
/// 与 AgentConfigPage 共享同一个 AgentProfileViewModel。
/// 从 ChatRoomPage AppBar 或 AgentListPage 进入。
class AgentProfilePage extends ConsumerStatefulWidget {
  final String agentId;
  final String? source;

  const AgentProfilePage({
    super.key,
    required this.agentId,
    this.source,
  });

  @override
  ConsumerState<AgentProfilePage> createState() => _AgentProfilePageState();
}

class _AgentProfilePageState extends ConsumerState<AgentProfilePage> {
  void _handleBack() {
    if (mounted && context.canPop()) {
      context.pop();
    } else if (mounted) {
      final source = widget.source;
      if (source == 'messages') {
        context.go(AppRoutes.messages);
      } else {
        context.go(AppRoutes.claws);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProfileViewModelProvider(widget.agentId));
    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          title: switch (state.detailLoadState) {
            LoadData(:final value) => Text(value.agent.displayName),
            _ => const Text('虾详情'),
          },
          actions: [
            if (state.detailLoadState is LoadData<AgentDetailData>)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '个性化配置',
                onPressed: () {
                  context.push(
                    AppRoutes.agentConfigWithParams(widget.agentId),
                  );
                },
              ),
          ],
        ),
        body: switch (state.detailLoadState) {
          LoadInProgress() => const LoadingSkeleton(count: 3),
          LoadError(:final error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '无法加载虾信息',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$error',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => vm.refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          LoadData(:final value) => ListView(
              children: [
                ProfileHeader(agent: value.agent, instance: value.instance),
                StatsGrid(messageCount: value.messageCount),
                const SizedBox(height: 12),
                // Future banner
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.primary.withAlpha(60),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text('📊'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '完整成长数据将在 V1.2 上线后可用',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Achievements placeholder
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🏆 成就',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            '更多数据积累后解锁成就系统…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/agent_profile/agent_profile_page_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/agent_profile/agent_profile_page.dart test/features/agent_profile/agent_profile_page_test.dart
git commit -m "feat(agent_profile): replace stub with full AgentProfilePage

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: AgentConfigPage

**Files:**
- Create: `lib/features/agent_profile/agent_config_page.dart`
- Create: `test/features/agent_profile/agent_config_page_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/agent_profile/agent_config_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/features/agent_profile/agent_config_page.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/ui_kit/color_grid.dart';

class MockAgentRepo extends Mock implements IAgentRepo {}
class MockInstanceRepo extends Mock implements IInstanceRepo {}
class MockMessageRepo extends Mock implements IMessageRepo {}

void main() {
  group('AgentConfigPage', () {
    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划',
      themeColor: '#6c5ce7',
    );

    final testInstance = Instance(
      id: 'inst-1',
      name: '我的MacBook',
      gatewayUrl: 'ws://192.168.1.1:18789',
      tokenRef: 'key-1',
      healthStatus: HealthStatus.online,
    );

    late MockAgentRepo agentRepo;
    late MockInstanceRepo instanceRepo;
    late MockMessageRepo messageRepo;

    setUp(() {
      agentRepo = MockAgentRepo();
      instanceRepo = MockInstanceRepo();
      messageRepo = MockMessageRepo();

      when(() => agentRepo.getById('local-1'))
          .thenAnswer((_) async => testAgent);
      when(() => instanceRepo.getById('inst-1'))
          .thenAnswer((_) async => testInstance);
      when(() => messageRepo.getMessageCount('local-1'))
          .thenAnswer((_) async => 42);
    });

    Widget buildPage() {
      return ProviderScope(
        overrides: [
          agentProfileViewModelProvider('local-1').overrideWith(
            (ref) => AgentProfileViewModel(
              agentRepo: agentRepo,
              instanceRepo: instanceRepo,
              messageRepo: messageRepo,
              agentId: 'local-1',
            )..init(),
          ),
        ],
        child: const MaterialApp(
          home: AgentConfigPage(agentId: 'local-1'),
        ),
      );
    }

    testWidgets('renders nickname TextField', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      // The nickname field is pre-filled with agent's name or nickname
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('renders ColorGrid', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.byType(ColorGrid), findsOneWidget);
    });

    testWidgets('renders save button', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text('💾 保存配置'), findsOneWidget);
    });

    testWidgets('renders section title for basic info', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text('🦐 基本信息'), findsOneWidget);
    });

    testWidgets('renders section title for theme color', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text('🎨 主题色'), findsOneWidget);
    });

    testWidgets('save button shows progress indicator when saving', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Set up save to delay
      when(() => agentRepo.updateLocalProfile(
        'local-1',
        nickname: any(named: 'nickname'),
        themeColor: any(named: 'themeColor'),
      )).thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 1));
        return testAgent;
      });

      // Tap save
      await tester.tap(find.text('💾 保存配置'));
      await tester.pump();

      // Should show saving indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/features/agent_profile/agent_config_page_test.dart
```

- [ ] **Step 3: Write implementation**

Create `lib/features/agent_profile/agent_config_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/ui_kit/color_grid.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// 12 色主题色选项（与原型一致的中文标签）
const _themeColorOptions = [
  ColorOption(hex: '#6C5CE7', label: '紫罗兰'),
  ColorOption(hex: '#0984E3', label: '海洋蓝'),
  ColorOption(hex: '#FD79A8', label: '樱花粉'),
  ColorOption(hex: '#00B894', label: '薄荷绿'),
  ColorOption(hex: '#E17055', label: '活力橙'),
  ColorOption(hex: '#00CEC9', label: '湖蓝'),
  ColorOption(hex: '#FDCB6E', label: '柠檬黄'),
  ColorOption(hex: '#E84393', label: '玫瑰红'),
  ColorOption(hex: '#636E72', label: '石墨灰'),
  ColorOption(hex: '#2D3436', label: '深灰'),
  ColorOption(hex: '#6AB04C', label: '草绿'),
  ColorOption(hex: '#5352ED', label: '靛蓝'),
];

/// 个性化配置页
///
/// 允许用户修改 Agent 的昵称和主题色。
/// 与 AgentProfilePage 共享同一个 AgentProfileViewModel。
class AgentConfigPage extends ConsumerStatefulWidget {
  final String agentId;

  const AgentConfigPage({super.key, required this.agentId});

  @override
  ConsumerState<AgentConfigPage> createState() => _AgentConfigPageState();
}

class _AgentConfigPageState extends ConsumerState<AgentConfigPage> {
  late String _nickname;
  late String _themeColor;
  final _nicknameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 从 ViewModel 缓存读取初始值
    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);
    final agent = vm.agent!;
    _nickname = agent.nickname ?? '';
    _themeColor = agent.themeColor;
    _nicknameController.text = _nickname;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  /// 转发到 ViewModel，Widget 不做决策 (Law 2)
  void _save() {
    final nickname = _nickname.trim().isEmpty ? null : _nickname.trim();
    ref.read(agentProfileViewModelProvider(widget.agentId).notifier)
        .saveProfile(widget.agentId, nickname, _themeColor);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProfileViewModelProvider(widget.agentId));
    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);
    final agent = vm.agent!;
    final theme = Theme.of(context);

    // 响应 saveSuccess → pop
    if (state.saveSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          vm.clearSaveResult();
          context.pop();
        }
      });
    }

    // 响应 saveError → SnackBar
    if (state.saveError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.saveError!)),
          );
          vm.clearSaveResult();
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: Text('${agent.displayName} · 个性化配置'),
        ),
        body: ListView(
          children: [
            // Section: 基本信息
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '🦐 基本信息',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Current avatar (read-only)
                  Row(
                    children: [
                      EmojiAvatar(
                        displayName: agent.displayName,
                        themeColor: _themeColor,
                        radius: 28,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              agent.displayName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '头像暂不支持更换',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Nickname field
                  TextFormField(
                    controller: _nicknameController,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      hintText: '给你的虾取个名字',
                    ),
                    onChanged: (value) => _nickname = value,
                    enabled: !state.isSaving,
                  ),
                ],
              ),
            ),

            // Section: 主题色
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '🎨 主题色',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ColorGrid(
                colors: _themeColorOptions,
                selectedColor: _themeColor,
                onColorSelected: state.isSaving
                    ? (_) {}
                    : (color) => setState(() => _themeColor = color),
              ),
            ),

            // Save button
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: state.isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: state.isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '💾 保存配置',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/agent_profile/agent_config_page_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/agent_profile/agent_config_page.dart test/features/agent_profile/agent_config_page_test.dart
git commit -m "feat(agent_profile): add AgentConfigPage for nickname + theme color editing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: Router — Add Config Route

**Files:**
- Modify: `lib/app/router/router.dart`

- [ ] **Step 1: Add route path and helper**

Open `lib/app/router/router.dart`. Add to `AppRoutes`:

```dart
// Add below the existing agentProfile path:
static const String agentConfig = 'agent-profile/config/:agentId';

// Add helper method beside agentProfileWithParams:
static String agentConfigWithParams(String agentId) {
  return 'agent-profile/config/$agentId';
}
```

Add config route inside the Claws branch, as a sibling to the existing agent-profile route:

```dart
// Inside the Claws StatefulShellBranch, after the agent-profile route:
GoRoute(
  path: 'agent-profile/config/:agentId',
  builder: (context, state) {
    final agentId = state.pathParameters['agentId']!;
    return AgentConfigPage(agentId: agentId);
  },
),
```

- [ ] **Step 2: Run analyze**

```bash
flutter analyze lib/app/router/router.dart
```

- [ ] **Step 3: Commit**

```bash
git add lib/app/router/router.dart
git commit -m "feat(router): add agent config route

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 12: Final Verification

- [ ] **Step 1: Run all new tests**

```bash
flutter test test/domain/models/errors_test.dart test/features/agent_profile/
```

- [ ] **Step 2: Run full test suite**

```bash
flutter test
```

- [ ] **Step 3: Run static analysis**

```bash
flutter analyze
```

- [ ] **Step 4: Fix any issues found in Steps 2-3**

- [ ] **Step 5: Commit final fixes (if any)**

```bash
git add -A
git commit -m "chore(agent_profile): final test + analyze fixes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Dependency Order

```
Task 1 (AgentNotFoundError)
  └── Task 2 (AgentDetailData + AgentProfileState)
        └── Task 3 (AgentProfileViewModel)
              ├── Task 4 (Provider)
              ├── Task 9 (AgentProfilePage)
              │     └── Task 7 (ProfileHeader) + Task 8 (StatsGrid)
              │           └── Task 5 (EmojiAvatar)
              └── Task 10 (AgentConfigPage)
                    └── Task 6 (ColorGrid) + Task 5 (EmojiAvatar)
                          └── Task 11 (Router)
                                └── Task 12 (Final verification)
```

Tasks 5 and 6 (ui_kit) can run in parallel with Tasks 7-8 (widgets). Tasks 7-8 can run in parallel with each other. Tasks 9-11 are sequential.
