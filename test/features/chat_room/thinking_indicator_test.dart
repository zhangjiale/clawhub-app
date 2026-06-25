import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/theme/agent_theme.dart';
import 'package:claw_hub/features/chat_room/widgets/thinking_indicator.dart';

void main() {
  group('ThinkingIndicator', () {
    Widget buildIndicator({AgentTheme? agentTheme}) {
      return MaterialApp(
        theme: ThemeData(extensions: agentTheme != null ? [agentTheme] : []),
        home: const Scaffold(body: ThinkingIndicator()),
      );
    }

    testWidgets(
      'does NOT render psychology avatar icon (spec §4.3: bubble+dots only)',
      (tester) async {
        await tester.pumpWidget(buildIndicator());

        expect(find.byIcon(Icons.psychology), findsNothing);
      },
    );

    testWidgets('renders three bouncing dots inside bubble', (tester) async {
      await tester.pumpWidget(buildIndicator());

      // Dots are now _BouncingDot widgets without keys — find by runtime type
      final dotFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_BouncingDot',
      );
      expect(dotFinder, findsNWidgets(3));
    });

    testWidgets('animates dots with bouncing motion', (tester) async {
      await tester.pumpWidget(buildIndicator());

      // All three dots should be present
      final dotFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_BouncingDot',
      );
      expect(dotFinder, findsNWidgets(3));

      // Pump forward to exercise the animation controller (now 800ms cycle)
      await tester.pump(const Duration(milliseconds: 300));
      // Three dots should still be present after animation ticks
      expect(dotFinder, findsNWidgets(3));
    });

    testWidgets('dots use AgentTheme primary color when present', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildIndicator(
          agentTheme: const AgentTheme(primary: Color(0xFF5F9B96)),
        ),
      );

      // Find dot Containers by BoxDecoration.shape == BoxShape.circle (only the
      // bouncing dots have circular decoration; the bubble Container has
      // BorderRadius, not shape).
      final dotFinder = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(dotFinder, findsNWidgets(3));
      for (final element in dotFinder.evaluate()) {
        final container = element.widget as Container;
        final decoration = container.decoration as BoxDecoration;
        expect(decoration.color, const Color(0xFF5F9B96));
      }
    });

    testWidgets(
      'dots fall back to sapphire (#4F83FF) when no AgentTheme in scope',
      (tester) async {
        await tester.pumpWidget(buildIndicator()); // no agentTheme

        final dotFinder = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        );
        expect(dotFinder, findsNWidgets(3));
        for (final element in dotFinder.evaluate()) {
          final container = element.widget as Container;
          final decoration = container.decoration as BoxDecoration;
          expect(decoration.color, const Color(0xFF4F83FF)); // V2 sapphire
        }
      },
    );
  });
}
