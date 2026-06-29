import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/agent_stats.dart';
import 'package:claw_hub/features/agent_profile/widgets/stats_grid.dart';

void main() {
  group('StatsGrid', () {
    Widget buildGrid({AgentStats? stats, int? fallbackMessageCount}) {
      return MaterialApp(
        home: Scaffold(
          body: StatsGrid(
            stats: stats,
            fallbackMessageCount: fallbackMessageCount,
          ),
        ),
      );
    }

    testWidgets('renders all 6 real values when AgentStats provided', (
      tester,
    ) async {
      final stats = AgentStats(
        agentId: 'agent-1',
        totalDialogs: 42,
        totalMessages: 1024,
        totalToolCalls: 23,
        activeDays: 18,
        currentStreak: 5,
        // Noon UTC is the safe pick for date-display tests: the rendered
        // "11/15" is stable in any timezone UTC-12..UTC+11, which covers
        // GitHub Actions (UTC) and most dev machines. Avoid midnight-UTC
        // timestamps — they flip days across timezone changes and break
        // CI. 1700000000 (2023-11-14 22:13 UTC) looks like 11/15 in
        // UTC+8 but 11/14 in UTC, which is what made this CI-flaky.
        firstDialogDate:
            DateTime.utc(2023, 11, 15, 12).millisecondsSinceEpoch ~/ 1000,
      );

      await tester.pumpWidget(buildGrid(stats: stats));

      // Check real values
      expect(find.text('42'), findsOneWidget);
      expect(find.text('1,024'), findsOneWidget);
      expect(find.text('23'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      // Date formatted as month/day
      expect(find.text('11/15'), findsOneWidget);
    });

    testWidgets('renders all labels', (tester) async {
      final stats = AgentStats(agentId: 'agent-1');
      await tester.pumpWidget(buildGrid(stats: stats));

      expect(find.text('对话'), findsOneWidget);
      expect(find.text('消息'), findsOneWidget);
      expect(find.text('工具'), findsOneWidget);
      expect(find.text('天数'), findsOneWidget);
      expect(find.text('连续'), findsOneWidget);
      expect(find.text('首聊'), findsOneWidget);
    });

    testWidgets('renders "--" for all stats when stats is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildGrid(stats: null));
      expect(find.text('--'), findsNWidgets(6));
    });

    testWidgets('shows fallback message count when stats is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildGrid(stats: null, fallbackMessageCount: 1024),
      );

      // 5 dashes (non-message fields) + formatted fallback message count
      expect(find.text('--'), findsNWidgets(5));
      expect(find.text('1,024'), findsOneWidget);
    });

    testWidgets('stats takes precedence over fallback when both provided', (
      tester,
    ) async {
      final stats = AgentStats(agentId: 'a1', totalMessages: 500);
      await tester.pumpWidget(
        buildGrid(stats: stats, fallbackMessageCount: 999),
      );

      // stats.totalMessages wins, not fallback
      expect(find.text('500'), findsOneWidget);
    });

    testWidgets('shows zero correctly', (tester) async {
      final stats = AgentStats(agentId: 'agent-1');

      await tester.pumpWidget(buildGrid(stats: stats));
      expect(find.text('0'), findsNWidgets(5)); // 对话, 消息, 工具, 天数, 连续
    });
  });
}
