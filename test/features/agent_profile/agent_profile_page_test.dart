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
      // Agent name appears in both AppBar title and ProfileHeader
      expect(find.text('产品虾'), findsAtLeastNWidgets(1));
    });

    testWidgets('renders agent description', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text('产品规划、需求分析'), findsOneWidget);
    });

    testWidgets('shows edit button in AppBar', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });
  });
}
