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
    testWidgets('renders correctly with agent, input bar, and empty state',
        (tester) async {
      // ---- Setup: create and init ViewModel ----
      final agentRepo = InMemoryAgentRepo();
      final agent = Agent(
        localId: 'local-1', remoteId: 'r-1',
        instanceId: 'inst-1', name: '产品虾',
        themeColor: '#6c5ce7',
      );
      await agentRepo.syncFromGateway('inst-1', [agent]);

      final messageRepo = InMemoryMessageRepo();
      final conversationRepo = InMemoryConversationRepo();
      final gateway = MockGatewayClient();

      final vm = ChatViewModel(
        agentRepo: agentRepo,
        conversationRepo: conversationRepo,
        messageRepo: messageRepo,
        gatewayClient: gateway,
        sendMessageUseCase: SendMessageUseCase(
          messageRepo: messageRepo,
          conversationRepo: conversationRepo,
          instanceRepo: InMemoryInstanceRepo(),
          gatewayClient: gateway,
        ),
        instanceId: 'inst-1',
        agentId: 'local-1',
      );
      await vm.init();
      vm.messagesNotifier.value = const LoadData(<Message>[]);
      addTearDown(vm.dispose);

      // ---- Pump widget ----
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatViewModelProvider(_key).overrideWith((ref) => vm),
          ],
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
  });
}
