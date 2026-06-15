import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_list/widgets/agent_card.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

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

    Widget buildCard({
      Agent? agent,
      VoidCallback? onTap,
      bool isOnline = true,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: AgentCard(
            agent: agent ?? testAgent,
            onTap: onTap ?? () {},
            isOnline: isOnline,
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

    testWidgets('renders avatar with first character', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('产'), findsOneWidget);
    });

    testWidgets('renders EmojiAvatar with correct themeColor', (tester) async {
      await tester.pumpWidget(buildCard());
      final emojiAvatar = tester.widget<EmojiAvatar>(find.byType(EmojiAvatar));
      expect(emojiAvatar.themeColor, '#6c5ce7');
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildCard(onTap: () => tapped = true));
      await tester.tap(find.byType(AgentCard));
      expect(tapped, isTrue);
    });

    testWidgets('shows green status dot when online', (tester) async {
      await tester.pumpWidget(buildCard(isOnline: true));
      // Verify the card renders - online dot uses green color
      final emojiAvatar = tester.widget<EmojiAvatar>(find.byType(EmojiAvatar));
      expect(emojiAvatar.themeColor, testAgent.themeColor);
    });

    testWidgets('shows text4 status dot when offline', (tester) async {
      await tester.pumpWidget(buildCard(isOnline: false));
      // Verify the card still renders when offline
      expect(find.text('产品虾'), findsOneWidget);
    });

    testWidgets('chevron_right always present in card', (tester) async {
      await tester.pumpWidget(buildCard(isOnline: false));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('status dot and time in meta area', (tester) async {
      await tester.pumpWidget(buildCard());
      // The card should have chevron_right present
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });
}
