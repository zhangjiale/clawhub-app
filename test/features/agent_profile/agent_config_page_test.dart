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
  });
}
