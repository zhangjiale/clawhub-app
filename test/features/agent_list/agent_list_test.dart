import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_list/agent_list_page.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/features/agent_list/providers/stats_providers.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('AgentListPage', () {
    testWidgets('shows empty state when no agents', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith(
              (ref) async => const AgentListData(
                agents: [],
                instanceNames: {},
                instanceStatuses: {},
              ),
            ),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有虾'), findsOneWidget);
    });

    testWidgets('shows agent cards when agents exist', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith(
              (ref) async => AgentListData(
                agents: [
                  Agent(
                    localId: 'local-1',
                    remoteId: 'r-1',
                    instanceId: 'inst-1',
                    name: '产品虾',
                    description: '产品规划',
                    themeColor: '#6c5ce7',
                  ),
                ],
                instanceNames: {'inst-1': 'My MacBook'},
                instanceStatuses: {'inst-1': HealthStatus.online},
              ),
            ),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('产品虾'), findsOneWidget);
      expect(find.text('产品规划'), findsOneWidget);
    });

    testWidgets('shows instance group headers', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith(
              (ref) async => AgentListData(
                agents: [
                  Agent(
                    localId: 'local-1',
                    remoteId: 'r-1',
                    instanceId: 'inst-1',
                    name: '产品虾',
                    themeColor: '#6c5ce7',
                  ),
                ],
                instanceNames: {'inst-1': 'My MacBook'},
                instanceStatuses: {'inst-1': HealthStatus.online},
              ),
            ),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My MacBook'), findsOneWidget);
    });

    testWidgets('shows stale data banner when sync has errors', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith(
              (ref) async => AgentListData(
                agents: [
                  Agent(
                    localId: 'local-1',
                    remoteId: 'r-1',
                    instanceId: 'inst-1',
                    name: '产品虾',
                    themeColor: '#6c5ce7',
                  ),
                ],
                instanceNames: {'inst-1': 'My MacBook'},
                instanceStatuses: {'inst-1': HealthStatus.online},
                syncErrors: {'inst-1': 'Connection refused'},
              ),
            ),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Banner is visible
      expect(find.text('无法获取最新列表'), findsOneWidget);
      // Agent cards are still shown (cached data fallback)
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('does not show stale banner when sync succeeds', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith(
              (ref) async => AgentListData(
                agents: [
                  Agent(
                    localId: 'local-1',
                    remoteId: 'r-1',
                    instanceId: 'inst-1',
                    name: '产品虾',
                    themeColor: '#6c5ce7',
                  ),
                ],
                instanceNames: {'inst-1': 'My MacBook'},
                instanceStatuses: {'inst-1': HealthStatus.online},
                syncErrors: const {},
              ),
            ),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('无法获取最新列表'), findsNothing);
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets(
      'shows stale banner and error empty state when no cached agents',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              agentListProvider.overrideWith(
                (ref) async => AgentListData(
                  agents: const [],
                  instanceNames: {'inst-1': 'My MacBook'},
                  instanceStatuses: {'inst-1': HealthStatus.unknown},
                  syncErrors: {'inst-1': 'Connection refused'},
                ),
              ),
              statsProvider.overrideWith((ref) async => StatsData.empty),
            ],
            child: const MaterialApp(home: AgentListPage()),
          ),
        );
        await tester.pumpAndSettle();

        // Banner is visible
        expect(find.text('无法获取最新列表'), findsOneWidget);
        // Error empty state is shown instead of misleading "Connect" message
        expect(find.text('无法获取 Agent 列表'), findsOneWidget);
        expect(find.text('请检查实例连接后下拉刷新重试'), findsOneWidget);
        // "Connect to an OpenClaw instance" should NOT appear
        expect(
          find.text('Connect to an OpenClaw instance to see agents'),
          findsNothing,
        );
      },
    );

    testWidgets('pull-to-refresh invalidates and reloads provider', (
      tester,
    ) async {
      var callCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith((ref) async {
              callCount++;
              return AgentListData(
                agents: [
                  Agent(
                    localId: 'local-$callCount',
                    remoteId: 'r-$callCount',
                    instanceId: 'inst-1',
                    name: callCount == 1 ? '旧虾' : '新虾',
                    themeColor: '#6c5ce7',
                  ),
                ],
                instanceNames: {'inst-1': 'My MacBook'},
                instanceStatuses: {'inst-1': HealthStatus.online},
                syncErrors: callCount == 1 ? {'inst-1': 'fail'} : const {},
              );
            }),
            statsProvider.overrideWith(
              (ref) async => const StatsData(
                activeInstances: 1,
                totalInstances: 1,
                onlineAgents: 1,
                totalAgents: 1,
                totalMessages: 0,
              ),
            ),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state: stale banner + old data
      expect(find.text('无法获取最新列表'), findsOneWidget);
      expect(find.text('旧虾'), findsOneWidget);

      // Pull down to trigger RefreshIndicator
      await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
      await tester.pumpAndSettle();

      // After refresh: banner gone, new data
      expect(callCount, greaterThan(1));
      expect(find.text('无法获取最新列表'), findsNothing);
    });
  });
}
