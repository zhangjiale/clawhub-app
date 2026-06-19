import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';

class _MockOrchestrator extends Mock implements ConnectionOrchestrator {}

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
  });
}
