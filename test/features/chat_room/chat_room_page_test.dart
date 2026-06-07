import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/chat_room_page.dart';
import 'package:claw_hub/domain/models/agent.dart';
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
          child: const MaterialApp(
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
          child: const MaterialApp(
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

    testWidgets('shows empty state when no messages', (tester) async {
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
            messageRepoProvider.overrideWith((ref) => InMemoryMessageRepo()),
            gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
          ],
          child: const MaterialApp(
            home: ChatRoomPage(
              agentId: 'local-1',
              instanceId: 'inst-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Send a message to start'), findsOneWidget);
    });
  });
}
