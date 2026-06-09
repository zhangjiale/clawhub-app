import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/thinking_indicator.dart';

void main() {
  group('ThinkingIndicator', () {
    Widget buildIndicator() {
      return const MaterialApp(
        home: Scaffold(
          body: ThinkingIndicator(),
        ),
      );
    }

    testWidgets('renders psychology icon indicating AI thinking', (tester) async {
      await tester.pumpWidget(buildIndicator());

      expect(find.byIcon(Icons.psychology), findsOneWidget);
    });

    testWidgets('renders three bouncing dots inside bubble', (tester) async {
      await tester.pumpWidget(buildIndicator());

      expect(find.byKey(const ValueKey('thinking-dot-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('thinking-dot-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('thinking-dot-2')), findsOneWidget);
    });

    testWidgets('animates dots with bouncing motion', (tester) async {
      await tester.pumpWidget(buildIndicator());

      // All three dots should be present
      expect(find.byKey(const ValueKey('thinking-dot-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('thinking-dot-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('thinking-dot-2')), findsOneWidget);

      // Pump forward to exercise the animation controller
      await tester.pump(const Duration(milliseconds: 300));
      // Widget should still be present after animation ticks
      expect(find.byIcon(Icons.psychology), findsOneWidget);
    });
  });
}
