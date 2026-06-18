import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/features/chat_room/providers/chat_providers.dart';
import 'package:claw_hub/features/chat_room/viewmodels/chat_view_model.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/domain/usecases/send_message.dart';
import 'package:claw_hub/ui_kit/async_state.dart';

const _key = (instanceId: 'inst-1', agentId: 'local-1');

void main() {
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
  });
}
