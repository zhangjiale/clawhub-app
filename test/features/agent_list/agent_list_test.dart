import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_list/agent_list_page.dart';
import 'package:claw_hub/features/agent_list/providers/agent_providers.dart';
import 'package:claw_hub/domain/usecases/sync_agents.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('AgentListPage', () {
    testWidgets('shows empty state when no agents', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith((ref) async => const AgentListData(
              agents: [],
              instanceNames: {},
              instanceStatuses: {},
            )),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Agents'), findsOneWidget);
    });

    testWidgets('shows agent cards when agents exist', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith((ref) async => AgentListData(
              agents: [
                Agent(
                  localId: 'local-1', remoteId: 'r-1',
                  instanceId: 'inst-1', name: '产品虾',
                  description: '产品规划', themeColor: '#6c5ce7',
                ),
              ],
              instanceNames: {'inst-1': 'My MacBook'},
              instanceStatuses: {'inst-1': HealthStatus.online},
            )),
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
            agentListProvider.overrideWith((ref) async => AgentListData(
              agents: [
                Agent(
                  localId: 'local-1', remoteId: 'r-1',
                  instanceId: 'inst-1', name: '产品虾',
                  themeColor: '#6c5ce7',
                ),
              ],
              instanceNames: {'inst-1': 'My MacBook'},
              instanceStatuses: {'inst-1': HealthStatus.online},
            )),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My MacBook'), findsOneWidget);
    });

    testWidgets('filters agents by search query', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith((ref) async => AgentListData(
              agents: [
                Agent(
                  localId: 'local-1', remoteId: 'r-1',
                  instanceId: 'inst-1', name: '产品虾',
                  themeColor: '#6c5ce7',
                ),
                Agent(
                  localId: 'local-2', remoteId: 'r-2',
                  instanceId: 'inst-1', name: '代码虾',
                  description: '编程助手',
                  themeColor: '#0984e3',
                ),
              ],
              instanceNames: {'inst-1': 'My MacBook'},
              instanceStatuses: {'inst-1': HealthStatus.online},
            )),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('产品虾'), findsOneWidget);
      expect(find.text('代码虾'), findsOneWidget);

      // Tap search to reveal search field
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField), '产品');
      await tester.pumpAndSettle();

      expect(find.text('产品虾'), findsOneWidget);
      expect(find.text('代码虾'), findsNothing);
    });

    testWidgets('shows no match message when search yields nothing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentListProvider.overrideWith((ref) async => AgentListData(
              agents: [
                Agent(
                  localId: 'local-1', remoteId: 'r-1',
                  instanceId: 'inst-1', name: '产品虾',
                  themeColor: '#6c5ce7',
                ),
              ],
              instanceNames: {'inst-1': 'My MacBook'},
              instanceStatuses: {'inst-1': HealthStatus.online},
            )),
          ],
          child: const MaterialApp(home: AgentListPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Open search and type non-matching query
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '不存在的虾');
      await tester.pumpAndSettle();

      expect(find.textContaining('No agents match'), findsOneWidget);
    });
  });
}
