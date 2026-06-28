import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/domain/models/achievement.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/domain/repositories/i_achievement_repo.dart';
import 'package:claw_hub/domain/repositories/i_activity_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/features/agent_profile/agent_config_page.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/ui_kit/color_grid.dart';
import 'package:claw_hub/ui_kit/placeholders/agent_removed_placeholder.dart';

class MockAgentRepo extends Mock implements IAgentRepo {}

class MockInstanceRepo extends Mock implements IInstanceRepo {}

class MockMessageRepo extends Mock implements IMessageRepo {}

class MockAchievementRepo extends Mock implements IAchievementRepo {}

class MockActivityRepo extends Mock implements IActivityRepo {}

class MockAvatarStorageService extends Mock implements IAvatarStorageService {}

void main() {
  setUpAll(() {
    registerFallbackValue(AgentStats(agentId: 'fallback'));
    registerFallbackValue(<String>{''});
  });

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
    late MockAchievementRepo achievementRepo;
    late MockActivityRepo activityRepo;
    late MockAvatarStorageService avatarStorageService;

    setUp(() {
      agentRepo = MockAgentRepo();
      instanceRepo = MockInstanceRepo();
      messageRepo = MockMessageRepo();
      achievementRepo = MockAchievementRepo();
      activityRepo = MockActivityRepo();
      avatarStorageService = MockAvatarStorageService();

      when(
        () => agentRepo.getById('local-1'),
      ).thenAnswer((_) async => testAgent);
      when(
        () => instanceRepo.getById('inst-1'),
      ).thenAnswer((_) async => testInstance);
      when(
        () => messageRepo.getMessageCount('local-1'),
      ).thenAnswer((_) async => 42);
      when(
        () => achievementRepo.computeStats(any()),
      ).thenAnswer((_) async => AgentStats(agentId: 'local-1'));
      when(
        () => achievementRepo.getUnlocks(any()),
      ).thenAnswer((_) async => <Achievement>[]);
      when(
        () => achievementRepo.batchUnlock(any(), any()),
      ).thenAnswer((_) async => <Achievement>[]);
      // Activity repo default: empty list (page doesn't show timeline
      // but VM init() still calls it).
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
              agentId: 'local-1',
            )..init(),
          ),
        ],
        child: const MaterialApp(home: AgentConfigPage(agentId: 'local-1')),
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
      // Save button is at the bottom of a lazy ListView — scroll down first
      await tester.drag(find.byType(ListView), const Offset(0, -500));
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

    testWidgets('shows error UI with retry button when agent not found', (
      tester,
    ) async {
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async => null);
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text('无法加载虾信息'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(ColorGrid), findsNothing);
    });

    testWidgets('retry button triggers refresh and reloads data', (
      tester,
    ) async {
      var callCount = 0;
      when(() => agentRepo.getById('local-1')).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? null : testAgent;
      });
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      // 第二次调用成功，表单渲染出来
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('🦐 基本信息'), findsOneWidget);
    });

    group('avatar', () {
      testWidgets('shows set avatar hint when no avatar', (tester) async {
        await tester.pumpWidget(buildPage());
        await tester.pumpAndSettle();
        expect(find.text('点击设置头像'), findsOneWidget);
      });

      testWidgets('shows change avatar hint when avatar is set', (
        tester,
      ) async {
        final agentWithAvatar = testAgent.copyWith(
          avatarUrl: '/path/to/avatar.jpg',
        );
        when(
          () => agentRepo.getById('local-1'),
        ).thenAnswer((_) async => agentWithAvatar);

        await tester.pumpWidget(buildPage());
        await tester.pumpAndSettle();
        expect(find.text('点击更换头像'), findsOneWidget);
      });

      testWidgets('does not show "头像暂不支持更换" text', (tester) async {
        await tester.pumpWidget(buildPage());
        await tester.pumpAndSettle();
        expect(find.text('头像暂不支持更换'), findsNothing);
      });

      testWidgets('renders EmojiAvatar', (tester) async {
        await tester.pumpWidget(buildPage());
        await tester.pumpAndSettle();
        // The EmojiAvatar should render the first character
        expect(find.text('产'), findsOneWidget);
      });
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
                  agentId: 'local-1',
                );
                // Step 6: 用 debugSetAgent 注入 tombstoned agent。
                vm.debugSetAgent(
                  Agent(
                    localId: 'local-1',
                    remoteId: 'remote-1',
                    instanceId: 'inst-1',
                    name: '产品虾',
                    themeColor: '#6c5ce7',
                    removedAt: 1719200000000,
                  ),
                );
                return vm;
              }),
            ],
            child: const MaterialApp(home: AgentConfigPage(agentId: 'local-1')),
          ),
        );
        await tester.pump();
        expect(find.byType(AgentRemovedPlaceholder), findsOneWidget);
        expect(find.text('该 Agent 已从 Gateway 移除'), findsOneWidget);
        // Config form must NOT render in tombstone state
        expect(find.byType(TextFormField), findsNothing);
      },
    );

    testWidgets(
      'renders config form normally when vm.agent.isRemoved is false',
      (tester) async {
        await tester.pumpWidget(buildPage());
        await tester.pumpAndSettle();
        expect(find.byType(AgentRemovedPlaceholder), findsNothing);
        expect(find.byType(TextFormField), findsOneWidget);
      },
    );
  });
}
