import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_list/widgets/stats_bar.dart';

void main() {
  group('StatsBar', () {
    Widget buildBar({
      int activeInstances = 2,
      int totalInstances = 3,
      int onlineAgents = 5,
      int totalAgents = 7,
      int totalMessages = 42,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: StatsBar(
            activeInstances: activeInstances,
            totalInstances: totalInstances,
            onlineAgents: onlineAgents,
            totalAgents: totalAgents,
            totalMessages: totalMessages,
          ),
        ),
      );
    }

    testWidgets('renders instance stat with ratio', (tester) async {
      await tester.pumpWidget(buildBar(activeInstances: 2, totalInstances: 3));

      expect(find.text('Instances'), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('renders online claw stat with ratio', (tester) async {
      await tester.pumpWidget(buildBar(onlineAgents: 5, totalAgents: 7));

      expect(find.text('Online'), findsOneWidget);
      expect(find.text('5/7'), findsOneWidget);
    });

    testWidgets('renders messages stat', (tester) async {
      await tester.pumpWidget(buildBar(totalMessages: 42));

      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    // ----- _formatCount boundary tests (tested via rendered output) -----

    testWidgets('formats 0 as plain number', (tester) async {
      await tester.pumpWidget(buildBar(totalMessages: 0));
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('formats 999 as plain number', (tester) async {
      await tester.pumpWidget(buildBar(totalMessages: 999));
      expect(find.text('999'), findsOneWidget);
    });

    testWidgets('formats 1000 with k suffix', (tester) async {
      await tester.pumpWidget(buildBar(totalMessages: 1000));
      expect(find.text('1.0k'), findsOneWidget);
    });

    testWidgets('formats 1500 with one decimal', (tester) async {
      await tester.pumpWidget(buildBar(totalMessages: 1500));
      expect(find.text('1.5k'), findsOneWidget);
    });

    testWidgets('formats 9999 with k suffix', (tester) async {
      await tester.pumpWidget(buildBar(totalMessages: 9999));
      expect(find.text('10.0k'), findsOneWidget);
    });

    testWidgets('renders three icon widgets', (tester) async {
      await tester.pumpWidget(buildBar());

      expect(find.byIcon(Icons.dns), findsOneWidget);
      expect(find.byIcon(Icons.pets), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });
  });
}
