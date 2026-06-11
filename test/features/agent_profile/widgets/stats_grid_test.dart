import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_profile/widgets/stats_grid.dart';

void main() {
  group('StatsGrid', () {
    Widget buildGrid({required int messageCount}) {
      return MaterialApp(
        home: Scaffold(body: StatsGrid(messageCount: messageCount)),
      );
    }

    testWidgets('renders message count as formatted value', (tester) async {
      await tester.pumpWidget(buildGrid(messageCount: 1024));
      expect(find.text('1,024'), findsOneWidget);
    });

    testWidgets('renders "消息总数" label', (tester) async {
      await tester.pumpWidget(buildGrid(messageCount: 0));
      expect(find.text('消息'), findsOneWidget);
    });

    testWidgets('renders placeholder "--" for unavailable stats',
        (tester) async {
      await tester.pumpWidget(buildGrid(messageCount: 5));
      expect(find.text('--'), findsNWidgets(5));
    });

    testWidgets('shows zero correctly', (tester) async {
      await tester.pumpWidget(buildGrid(messageCount: 0));
      expect(find.text('0'), findsOneWidget);
    });
  });
}
