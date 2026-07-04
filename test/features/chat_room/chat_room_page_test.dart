import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/core/i_attachment_picker_service.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/attachment_pick_result.dart';
import 'package:claw_hub/domain/models/conversation.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/core/i_achievement_checker.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:go_router/go_router.dart';

import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/features/chat_room/widgets/tool_call_card.dart';
import 'package:claw_hub/features/settings/providers/clear_cache_guard.dart';
import 'package:claw_hub/ui_kit/async_state.dart';

class _MockOrchestrator extends Mock implements ConnectionOrchestrator {}

class _MockAchievementChecker extends Mock implements IAchievementChecker {}

/// 模拟附件选择失败：pickImage / pickFile 都抛 [error]。
///
/// 用于验证 `_handlePickAttachment` 的 `on Exception` 捕获覆盖三类原本会
/// 逃逸为未处理异步异常的失败（'+' 按钮无 toast 反馈）：
/// - PlatformException（review #10）
/// - FileSystemException（#11）
/// - MissingPluginException（#12）
class _ThrowingAttachmentPicker implements IAttachmentPickerService {
  _ThrowingAttachmentPicker(this.error);
  final Object error;

  @override
  Future<AttachmentPickResult?> pickImage({
    required ImageSource source,
    int imageQuality = 85,
  }) async {
    throw error;
  }

  @override
  Future<AttachmentPickResult?> pickFile() async {
    throw error;
  }
}

/// 共用脚手架：注入一个抛 [error] 的 picker，打开附件 sheet 并点「拍照」。
///
/// 三条 toast 回归测试（review #10 / #11 / #12）唯一变量就是被抛异常的
/// 类型——`_handlePickAttachment` 经 `on Exception` 统一捕获，无需按类型
/// 分支，故共享同一套 pump + tap 序列。
Future<void> _pumpAndTapCameraWithThrowingPicker(
  WidgetTester tester,
  Object error,
) async {
  final agentRepo = InMemoryAgentRepo();
  await agentRepo.syncFromGateway('inst-1', [
    Agent(
      localId: 'local-1',
      remoteId: 'r-1',
      instanceId: 'inst-1',
      name: '产品虾',
    ),
  ]);
  final messageRepo = InMemoryMessageRepo();
  final conversationRepo = InMemoryConversationRepo();
  final instanceRepo = InMemoryInstanceRepo();
  final gateway = MockGatewayClient();
  final vm = ChatViewModel(
    agentRepo: agentRepo,
    conversationRepo: conversationRepo,
    messageRepo: messageRepo,
    instanceRepo: instanceRepo,
    gatewayClient: gateway,
    sendMessageUseCase: SendMessageUseCase(
      messageRepo: messageRepo,
      conversationRepo: conversationRepo,
      instanceRepo: instanceRepo,
      gatewayClient: gateway,
    ),
    instanceId: 'inst-1',
    agentId: 'local-1',
    achievementChecker: _MockAchievementChecker(),
    flushDelay: Duration.zero,
  );
  vm.state = const ChatSessionState(messages: LoadData(<Message>[]));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatViewModelProvider(_key).overrideWith((ref) => vm),
        attachmentPickerServiceProvider.overrideWithValue(
          _ThrowingAttachmentPicker(error),
        ),
      ],
      child: const MaterialApp(
        home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
      ),
    ),
  );
  await tester.pump();

  // 打开附件 sheet，点「拍照」→ _handlePickAttachment(camera) → pickImage
  // 抛 error → on Exception 捕获 → XiaToast.show。
  await tester.tap(find.byIcon(Icons.add));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('拍照'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

const _key = (instanceId: 'inst-1', agentId: 'local-1');

void main() {
  setUpAll(() {
    registerFallbackValue(
      Instance(
        id: 'fallback',
        name: 'fallback',
        gatewayUrl: 'ws://localhost:1',
        tokenRef: 'tok',
      ),
    );
  });

  group('ChatRoomPage', () {
    testWidgets('renders correctly with agent, input bar, and empty state', (
      tester,
    ) async {
      // ---- Setup: create and init ViewModel ----
      final agentRepo = InMemoryAgentRepo();
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
        themeColor: '#6c5ce7',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);

      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final instanceRepo = InMemoryInstanceRepo();
      final gateway = MockGatewayClient();

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: _MockAchievementChecker(),
      );
      await vm.init();
      vm.state = const ChatSessionState(messages: LoadData(<Message>[]));
      // No manual vm.dispose() — ProviderScope manages the lifecycle.
      // StateNotifier.debugIsMounted rejects dispose() while listeners exist.

      // ---- Pump widget ----
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatViewModelProvider(_key).overrideWith((ref) => vm)],
          child: const MaterialApp(
            home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
          ),
        ),
      );
      // pump() instead of pumpAndSettle() — TextField cursor prevents settling
      await tester.pump();

      // ---- Assert: agent name in app bar ----
      expect(find.text('产品虾'), findsOneWidget);

      // ---- Assert: chat input bar ----
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);

      // ---- Assert: empty state when no messages ----
      expect(find.text('Send a message to start'), findsOneWidget);
    });

    testWidgets('shows retryFeedback StatusBanner when retryFeedback is set', (
      tester,
    ) async {
      final agentRepo = InMemoryAgentRepo();
      final agent = Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: 'inst-1',
        name: '产品虾',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);

      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final instanceRepo = InMemoryInstanceRepo();
      final gateway = MockGatewayClient();

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: _MockAchievementChecker(),
      );
      // Don't call vm.init() — we set state directly to avoid triggering
      // stream subscriptions that would hang in the widget test environment.
      vm.state = const ChatSessionState(
        messages: LoadData(<Message>[]),
        retryFeedback: '实例离线，请等待自动重发',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatViewModelProvider(_key).overrideWith((ref) => vm)],
          child: const MaterialApp(
            home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
          ),
        ),
      );
      await tester.pump();

      // The retryFeedback text should be visible in a StatusBanner
      expect(find.text('实例离线，请等待自动重发'), findsOneWidget);
      // The icon should be error_outline (distinct from warning_amber)
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows reconnect banner when connectionState is '
        'reconnectExhausted', (tester) async {
      final agentRepo = InMemoryAgentRepo();
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
      ]);
      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final instanceRepo = InMemoryInstanceRepo();
      final gateway = MockGatewayClient();

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: _MockAchievementChecker(),
      );
      vm.state = const ChatSessionState(
        messages: LoadData(<Message>[]),
        connectionState: GatewayConnectionState.reconnectExhausted,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatViewModelProvider(_key).overrideWith((ref) => vm)],
          child: const MaterialApp(
            home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('无法连接到虾，请检查网络或实例状态。点击重试'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('tapping reconnect banner triggers orchestrator.reconnect', (
      tester,
    ) async {
      final agentRepo = InMemoryAgentRepo();
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
      ]);
      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final instanceRepo = InMemoryInstanceRepo();
      // Save the instance so _handleRetry's getById resolves it.
      await instanceRepo.save(
        Instance(
          id: 'inst-1',
          name: '测试虾',
          gatewayUrl: 'ws://localhost:9000',
          tokenRef: 'tok',
        ),
      );
      final gateway = MockGatewayClient();
      final orchestrator = _MockOrchestrator();
      when(() => orchestrator.reconnect(any())).thenAnswer((_) async {});

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: _MockAchievementChecker(),
      );
      vm.state = const ChatSessionState(
        messages: LoadData(<Message>[]),
        connectionState: GatewayConnectionState.reconnectExhausted,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatViewModelProvider(_key).overrideWith((ref) => vm),
            instanceRepoProvider.overrideWithValue(instanceRepo),
            connectionOrchestratorProvider.overrideWithValue(orchestrator),
          ],
          child: const MaterialApp(
            home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.warning_amber_rounded));
      // _handleRetry awaits getById (async) — pump to let microtasks flush.
      await tester.pumpAndSettle();

      verify(() => orchestrator.reconnect(any())).called(1);
    });

    // Audit ④ regression guard: when the user taps the retry banner on a
    // reconnectExhausted session but the instance has been deleted mid-flight
    // (e.g. user removed the instance from the list in another tab right
    // before tapping retry), the orchestrator MUST NOT be asked to reconnect
    // a non-existent entity. The fix surfaces the failure with a toast
    // instead of silently dropping the input — previously a tap would be a
    // no-op and the banner would stay up forever, looking like a stuck bug.
    testWidgets(
      'audit_④_retry_tap_withMissingInstance_toastsAndDoesNotReconnect',
      (tester) async {
        final agentRepo = InMemoryAgentRepo();
        await agentRepo.syncFromGateway('inst-1', [
          Agent(
            localId: 'local-1',
            remoteId: 'r-1',
            instanceId: 'inst-1',
            name: '产品虾',
          ),
        ]);
        final messageRepo = InMemoryMessageRepo();
        final conversationRepo = InMemoryConversationRepo();
        // Deliberately do NOT save the instance — getById returns null,
        // simulating the race window where the user deleted the instance
        // from the list while a stale reconnect-exhausted banner is on
        // screen.
        final instanceRepo = InMemoryInstanceRepo();
        final gateway = MockGatewayClient();
        final orchestrator = _MockOrchestrator();
        when(() => orchestrator.reconnect(any())).thenAnswer((_) async {});

        final vm = ChatViewModel(
          agentRepo: agentRepo,
          conversationRepo: conversationRepo,
          messageRepo: messageRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
          sendMessageUseCase: SendMessageUseCase(
            messageRepo: messageRepo,
            conversationRepo: conversationRepo,
            instanceRepo: instanceRepo,
            gatewayClient: gateway,
          ),
          instanceId: 'inst-1',
          agentId: 'local-1',
          achievementChecker: _MockAchievementChecker(),
        );
        vm.state = const ChatSessionState(
          messages: LoadData(<Message>[]),
          connectionState: GatewayConnectionState.reconnectExhausted,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatViewModelProvider(_key).overrideWith((ref) => vm),
              instanceRepoProvider.overrideWithValue(instanceRepo),
              connectionOrchestratorProvider.overrideWithValue(orchestrator),
            ],
            child: const MaterialApp(
              home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byIcon(Icons.warning_amber_rounded));
        // Microtask + post-frame callback for the toast.
        await tester.pump();
        await tester.pump();

        // Contract 1: the orchestrator must NOT be asked to reconnect
        // a non-existent instance.
        verifyNever(() => orchestrator.reconnect(any()));

        // Contract 2: the user gets visible feedback (the toast) so the
        // button doesn't feel dead. Toast overlay entry inserts via the
        // post-frame callback in XiaToast.show.
        expect(
          find.text('实例不存在或已被删除'),
          findsOneWidget,
          reason:
              'missing-instance retry path must toast instead of silently '
              'failing — original audit found this anti-pattern.',
        );
      },
    );

    testWidgets('shows history-truncated banner when instance is in '
        'catchUpTruncatedProvider', (tester) async {
      final agentRepo = InMemoryAgentRepo();
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
      ]);
      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final instanceRepo = InMemoryInstanceRepo();
      final gateway = MockGatewayClient();

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: _MockAchievementChecker(),
      );
      vm.state = const ChatSessionState(messages: LoadData(<Message>[]));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatViewModelProvider(_key).overrideWith((ref) => vm),
            // 预置该实例为"截断"状态，模拟 catch-up 撞顶后 provider 写入。
            catchUpTruncatedProvider.overrideWith((ref) => {'inst-1'}),
          ],
          child: const MaterialApp(
            home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('历史消息较多，仅同步了最近部分'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    // ---------------------------------------------------------------
    // Regression: clearCache 期间打开 chat_room 必须走 catch 分支，
    // 显示 SnackBar 并交还导航控制权。
    //
    // chatViewModelProvider 自己会读 clearCacheInProgressProvider；为 true
    // 时直接抛 ClearedDuringClearError。chat_room_page 用 try/catch 包裹
    // ref.watch，捕获后调用 handleClearedDuringClear(context, source:
    // widget.source) —— source 必须转发，否则 smartBack 在无 back stack 时
    // 落回默认 AppRoutes.claws tab，破坏 Smart Back Stack 不变量。
    // ---------------------------------------------------------------
    testWidgets(
      'shows SnackBar and returns SizedBox.shrink when guard is active '
      '(source forwarded to smartBack)',
      (tester) async {
        // Minimal GoRouter required for smartBack's context.canPop() check.
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const ChatRoomPage(
                agentId: 'local-1',
                instanceId: 'inst-1',
                source: 'messages',
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              // 触发 chatViewModelProvider 抛 ClearedDuringClearError
              clearCacheInProgressProvider.overrideWith((ref) => true),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        // Pump twice: once for the throw to propagate, once for the
        // post-frame callback scheduled by handleClearedDuringClear.
        await tester.pump();
        await tester.pump();

        // The catch path runs — SnackBar is shown with the guard message
        expect(find.text('缓存清理中，无法打开页面'), findsOneWidget);

        // The page body is a SizedBox.shrink (not the chat UI)
        expect(find.text('产品虾'), findsNothing);
        expect(find.byType(TextField), findsNothing);
      },
    );

    // Finding #9 fix: Gateway 诊断事件改走单独的 gatewayNoticeProvider
    // (StreamProvider),不再塞进 ChatSessionState——== 排除字段会导致
    // StateNotifier.state setter 去重,ref.listen 永不触发,toast 不弹。
    //
    // 本测试驱动 gatewayNoticeProvider:override gatewayClientProvider 为
    // MockGatewayClient,page 的 ref.listen(gatewayNoticeProvider) 订阅
    // mock 的 gatewayNoticeStream,emit notice -> toast 出现。
    testWidgets('pops page when closeRequested becomes true (tombstone)', (
      tester,
    ) async {
      final agentRepo = InMemoryAgentRepo();
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
      ]);
      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final instanceRepo = InMemoryInstanceRepo();
      final gateway = MockGatewayClient();

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: _MockAchievementChecker(),
      );
      vm.state = const ChatSessionState(
        messages: LoadData(<Message>[]),
        closeRequested: false,
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ChatRoomPage(
              agentId: 'local-1',
              instanceId: 'inst-1',
              source: 'messages',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatViewModelProvider(_key).overrideWith((ref) => vm)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');

      vm.state = vm.state.copyWith(closeRequested: true);
      // post-frame callback schedules the pop; pump twice to flush.
      await tester.pump();
      await tester.pump();

      expect(router.routerDelegate.currentConfiguration.uri.path, isNot('/'));
    });

    testWidgets('shows a toast when a Gateway notice arrives '
        '(via gatewayNoticeProvider — Finding #9 fix)', (tester) async {
      final agentRepo = InMemoryAgentRepo();
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
          themeColor: '#6c5ce7',
        ),
      ]);

      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final instanceRepo = InMemoryInstanceRepo();
      final gateway = MockGatewayClient();

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: _MockAchievementChecker(),
      );
      // Start from a clean, no-notice state — the page's
      // ref.listen(gatewayNoticeProvider) captures AsyncLoading as its
      // initial value on first build.
      vm.state = const ChatSessionState(messages: LoadData(<Message>[]));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatViewModelProvider(_key).overrideWith((ref) => vm),
            // gatewayNoticeProvider reads gatewayClientProvider internally;
            // override it with the same MockGatewayClient so emit*ForTesting
            // reaches the stream the page listens to.
            gatewayClientProvider.overrideWithValue(gateway),
          ],
          child: const MaterialApp(
            home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
          ),
        ),
      );
      await tester.pump();

      // Emit a notice via the mock's broadcast stream ->
      // gatewayNoticeProvider receives it -> page's ref.listen fires ->
      // post-frame XiaToast.show inserts the overlay entry.
      gateway.emitGatewayNoticeForTesting(
        'inst-1',
        LargePayloadNotice(
          sessionKey: 'agent:r-1:main',
          size: 30_000_000,
          limit: 26_214_400,
        ),
      );
      // 4 pumps: (1) flush microtask → listener → schedule post-frame;
      // (2) run post-frame → XiaToast.show → overlay.insert; (3-4) overlay
      // rebuilds the inserted OverlayEntry → _ToastOverlay.build. Fewer
      // pumps race the build (entry inserted but not yet built → find misses).
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The toast (formatGatewayNotice output for LargePayloadNotice)
      // contains the size byte count — proving gatewayNoticeProvider ->
      // ref.listen -> toast wired correctly without going through
      // ChatSessionState.
      expect(find.textContaining('30000000'), findsOneWidget);
    });

    // Review #14: 搜索高亮只在消息首载时应用一次。clearHighlight() 把
    // highlightedMessageId 置 null 后 ref.listen 会再次触发（null != highlightId），
    // 旧逻辑无限重新应用高亮 → 渐隐计时器永远重置，高亮永不消失。
    // _didApplyHighlight 标志阻止 clearHighlight 后的重新应用。
    testWidgets('search highlight applies once and does not re-apply after '
        'clearHighlight (review #14)', (tester) async {
      final agentRepo = InMemoryAgentRepo();
      await agentRepo.syncFromGateway('inst-1', [
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
      ]);
      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final instanceRepo = InMemoryInstanceRepo();
      final gateway = MockGatewayClient();

      // Insert the highlight target so loadHighlightWindow's
      // getAnchorWindow resolves it.
      final convId = Conversation.generateId('inst-1', 'local-1');
      await messageRepo.insert(
        Message(
          clientId: 'msg-X',
          conversationId: convId,
          agentId: 'local-1',
          role: MessageRole.agent,
          content: 'target message',
          type: MessageType.text,
          logicalClock: 1,
          timestamp: 1000,
        ),
      );

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
        achievementChecker: _MockAchievementChecker(),
        flushDelay: Duration.zero,
      );
      // Initial state: messages = LoadInProgress (default). Don't call
      // init() — drive state directly to control ref.listen timing.
      // Set a valid agent so build() can render _buildMessageList when
      // loadHighlightWindow swaps in a non-empty anchor window.
      vm.debugSetAgent(
        Agent(
          localId: 'local-1',
          remoteId: 'r-1',
          instanceId: 'inst-1',
          name: '产品虾',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatViewModelProvider(_key).overrideWith((ref) => vm)],
          child: const MaterialApp(
            home: ChatRoomPage(
              agentId: 'local-1',
              instanceId: 'inst-1',
              highlightMessageId: 'msg-X',
              highlightQuery: 'target',
            ),
          ),
        ),
      );
      await tester.pump(); // register ref.listen (state = LoadInProgress)

      // Simulate messages loading → ref.listen fires → applies highlight once.
      vm.state = vm.state.copyWith(messages: LoadData(<Message>[]));
      await tester.pump(); // listen fires → schedules post-frame
      await tester.pump(); // run post-frame → loadHighlightWindow (async)
      await tester.pump(); // flush loadHighlightWindow microtasks
      await tester.pump();
      expect(vm.state.highlightedMessageId, 'msg-X', reason: '消息首载后高亮应被应用一次');

      // Simulate the 2s fade timer firing clearHighlight (call directly).
      vm.clearHighlight();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // With the bug: clearHighlight sets highlightedMessageId=null →
      // ref.listen re-fires → loadHighlightWindow again → 'msg-X'.
      // With the fix: _didApplyHighlight=true → no re-apply → stays null.
      expect(
        vm.state.highlightedMessageId,
        isNull,
        reason: 'clearHighlight 后高亮不得被 ref.listen 重新应用 (review #14)',
      );
    });

    // Review #10 / #11 / #12: 附件选择失败必须被 _handlePickAttachment 捕获
    // 并 toast，而非变成手势处理器中的未处理异步异常（'+' 按钮无反馈）。
    // 三类异常都实现 Exception，由 `on Exception` 统一捕获；之前只 catch
    // PlatformException，FileSystemException / MissingPluginException 逃逸。
    testWidgets(
      'attachment pick PlatformException -> toast feedback (review #10)',
      (tester) async {
        await _pumpAndTapCameraWithThrowingPicker(
          tester,
          PlatformException(
            code: 'MISSING_PERMISSION',
            message: 'camera permission denied',
          ),
        );
        expect(
          find.text('无法选择附件，请检查权限或重试'),
          findsOneWidget,
          reason: 'PlatformException 必须被捕获并以 toast 反馈，不能静默抛出',
        );
      },
    );

    // #11: iOS 沙盒回收临时文件 / Android 13+ 撤销 SAF URI 时，pickImage 内
    // File.length() 抛 FileSystemException（实现 Exception，非 PlatformException）。
    // 之前 on PlatformException 不匹配 → 未 await 的 future 逃逸 → 无 toast。
    testWidgets('attachment pick FileSystemException -> toast feedback (#11)', (
      tester,
    ) async {
      await _pumpAndTapCameraWithThrowingPicker(
        tester,
        FileSystemException(
          'Cannot read file',
          '/tmp/picked.jpg',
          OSError('No such file or directory', 2),
        ),
      );
      expect(
        find.text('无法选择附件，请检查权限或重试'),
        findsOneWidget,
        reason: 'FileSystemException 必须被 on Exception 捕获并 toast（#11）',
      );
    });

    // #12: Proguard 裁剪的 Android 变体 / web 回退，image_picker 找不到平台
    // 实现抛 MissingPluginException（实现 Exception，非 PlatformException）。
    // 之前 on PlatformException 不匹配 → '+' 按钮静默失败，与 #11 同形态。
    testWidgets(
      'attachment pick MissingPluginException -> toast feedback (#12)',
      (tester) async {
        await _pumpAndTapCameraWithThrowingPicker(
          tester,
          MissingPluginException(
            'No implementation found for method pickImage',
          ),
        );
        expect(
          find.text('无法选择附件，请检查权限或重试'),
          findsOneWidget,
          reason: 'MissingPluginException 必须被 on Exception 捕获并 toast（#12）',
        );
      },
    );

    // Review #1: ToolCallCard renders under the matching message when the
    // toolCalls map key aligns with message.clientId. The VM re-keys tool
    // calls from sessionKey → clientId on agent message arrival; this test
    // pins the page's end of the contract (query by message.clientId) so a
    // future regression in either the re-key or the lookup is caught.
    testWidgets(
      'ToolCallCard renders under the matching message when keys align '
      '(review #1)',
      (tester) async {
        final agentRepo = InMemoryAgentRepo();
        await agentRepo.syncFromGateway('inst-1', [
          Agent(
            localId: 'local-1',
            remoteId: 'r-1',
            instanceId: 'inst-1',
            name: '产品虾',
          ),
        ]);
        final messageRepo = InMemoryMessageRepo();
        final conversationRepo = InMemoryConversationRepo();
        final instanceRepo = InMemoryInstanceRepo();
        final gateway = MockGatewayClient();

        final vm = ChatViewModel(
          agentRepo: agentRepo,
          conversationRepo: conversationRepo,
          messageRepo: messageRepo,
          instanceRepo: instanceRepo,
          gatewayClient: gateway,
          sendMessageUseCase: SendMessageUseCase(
            messageRepo: messageRepo,
            conversationRepo: conversationRepo,
            instanceRepo: instanceRepo,
            gatewayClient: gateway,
          ),
          instanceId: 'inst-1',
          agentId: 'local-1',
          achievementChecker: _MockAchievementChecker(),
          flushDelay: Duration.zero,
        );
        vm.debugSetAgent(
          Agent(
            localId: 'local-1',
            remoteId: 'r-1',
            instanceId: 'inst-1',
            name: '产品虾',
          ),
        );
        final msg = Message(
          clientId: 'msg-1',
          conversationId: 'conv',
          agentId: 'local-1',
          role: MessageRole.agent,
          content: 'reply',
          type: MessageType.text,
          logicalClock: 1,
          timestamp: 1000,
        );
        // ToolCall already re-keyed to the message's clientId (what the VM
        // produces after _rekeyToolCallForMessage).
        final tc = ToolCall(
          id: 'tc-1',
          messageId: 'msg-1',
          toolName: 'search',
          status: ToolCallStatus.success,
          outputResult: '{}',
        );
        vm.state = ChatSessionState(
          messages: LoadData(<Message>[msg]),
          toolCalls: {'msg-1': tc},
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [chatViewModelProvider(_key).overrideWith((ref) => vm)],
            child: const MaterialApp(
              home: ChatRoomPage(agentId: 'local-1', instanceId: 'inst-1'),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byType(ToolCallCard),
          findsOneWidget,
          reason: 'ToolCallCard 必须在 toolCalls key 与 message.clientId 对齐时渲染',
        );
      },
    );
  });
}
