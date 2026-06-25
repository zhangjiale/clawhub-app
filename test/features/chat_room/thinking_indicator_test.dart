import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/thinking_indicator.dart';

void main() {
  group('ThinkingIndicator', () {
    Widget buildIndicator() {
      return const MaterialApp(home: Scaffold(body: ThinkingIndicator()));
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
  });
}
