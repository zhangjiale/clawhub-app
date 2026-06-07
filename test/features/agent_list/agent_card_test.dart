import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_list/widgets/agent_card.dart';
import 'package:claw_hub/domain/models/agent.dart';

void main() {
  group('AgentCard', () {
    final testAgent = Agent(
      localId: 'local-1',
      remoteId: 'remote-1',
      instanceId: 'inst-1',
      name: '产品虾',
      description: '产品规划、需求分析、PRD撰写',
      themeColor: '#6c5ce7',
    );

    Widget buildCard({Agent? agent, VoidCallback? onTap}) {
      return MaterialApp(
        home: Scaffold(
          body: AgentCard(
            agent: agent ?? testAgent,
            onTap: onTap ?? () {},
          ),
        ),
      );
    }

    testWidgets('renders agent name', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('renders agent description', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('产品规划、需求分析、PRD撰写'), findsOneWidget);
    });

    testWidgets('renders avatar circle with first character', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('产'), findsOneWidget);
    });

    testWidgets('shows pin icon when pinned', (tester) async {
      final pinnedAgent = testAgent.copyWith(isPinned: true);
      await tester.pumpWidget(buildCard(agent: pinnedAgent));
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });

    testWidgets('no pin icon when not pinned', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.byIcon(Icons.push_pin), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildCard(onTap: () => tapped = true));
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('uses themeColor for avatar background', (tester) async {
      await tester.pumpWidget(buildCard());
      final circleAvatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(circleAvatar.backgroundColor, const Color(0xFF6C5CE7));
    });
  });
}
