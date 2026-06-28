import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
import 'package:claw_hub/features/agent_profile/agent_profile_page.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/ui_kit/placeholders/agent_removed_placeholder.dart';
import '../../_helpers/fake_logger.dart';
import '../../_helpers/mocks.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(AgentStats(agentId: 'fallback'));
    registerFallbackValue(<String>{''});
  });

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
    late MockAchievementRepo achievementRepo;
    late MockActivityRepo activityRepo;
    late MockAvatarStorageService avatarStorageService;
    late FakeLogger logger;

    setUp(() {
      agentRepo = MockAgentRepo();
      instanceRepo = MockInstanceRepo();
      messageRepo = MockMessageRepo();
      achievementRepo = MockAchievementRepo();
      activityRepo = MockActivityRepo();
      avatarStorageService = MockAvatarStorageService();
      logger = FakeLogger();

      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(
        () => instanceRepo.getById('inst-1'),
      ).thenAnswer((_) async => testInstance);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 1024);
      // Achievement default stubs (best-effort, return empty data)
      when(
        () => achievementRepo.computeStats(any()),
      ).thenAnswer((_) async => AgentStats(agentId: 'local-1'));
      when(
        () => achievementRepo.getUnlocks(any()),
      ).thenAnswer((_) async => <Achievement>[]);
      when(
        () => achievementRepo.batchUnlock(any(), any()),
      ).thenAnswer((_) async => <Achievement>[]);
      // Default: activity repo returns empty list (timeline shows placeholder)
      when(
        () => activityRepo.getDailyActivity(
          any(),
          days: any(named: 'days'),
          now: any(named: 'now'),
        ),
      ).thenAnswer((_) async => const []);
    });

    Widget buildPage() {
      return ProviderScope(
        overrides: [
          agentProfileViewModelProvider('local-1').overrideWith(
            (ref) => AgentProfileViewModel(
              agentRepo: agentRepo,
              instanceRepo: instanceRepo,
              messageRepo: messageRepo,
              activityRepo: activityRepo,
              evaluateAchievements: EvaluateAchievementsUseCase(
                achievementRepo,
              ),
              avatarStorageService: avatarStorageService,
              logger: logger,
              agentId: 'local-1',
            )..init(),
          ),
        ],
        child: const MaterialApp(home: AgentProfilePage(agentId: 'local-1')),
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
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets(
      'renders AgentRemovedPlaceholder when vm.agent.isRemoved is true',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              agentProfileViewModelProvider('local-1').overrideWith((ref) {
                final vm = AgentProfileViewModel(
                  agentRepo: agentRepo,
                  instanceRepo: instanceRepo,
                  messageRepo: messageRepo,
                  activityRepo: activityRepo,
                  evaluateAchievements: EvaluateAchievementsUseCase(
                    achievementRepo,
                  ),
                  avatarStorageService: avatarStorageService,
                  logger: logger,
                  agentId: 'local-1',
                );
                // Step 6: 用 debugSetAgent 注入 tombstoned agent，UI 经
                // vm.agent.isRemoved 触发占位页分支。不调 refresh() 避免
                // 触发 4 个 detail loader（test 不关心它们）。
                vm.debugSetAgent(
                  Agent(
                    localId: 'local-1',
                    remoteId: 'remote-1',
                    instanceId: 'inst-1',
                    name: '产品虾',
                    description: '产品规划、需求分析',
                    themeColor: '#6c5ce7',
                    removedAt: 1719200000000,
                  ),
                );
                return vm;
              }),
            ],
            child: const MaterialApp(
              home: AgentProfilePage(agentId: 'local-1'),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(AgentRemovedPlaceholder), findsOneWidget);
        expect(find.text('该 Agent 已从 Gateway 移除'), findsOneWidget);
      },
    );

    testWidgets('renders profile normally when vm.agent.isRemoved is false', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.byType(AgentRemovedPlaceholder), findsNothing);
      expect(find.text('产品虾'), findsAtLeastNWidgets(1));
    });
  });
}
