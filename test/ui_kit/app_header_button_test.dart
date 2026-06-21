import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/app/theme/tokens.dart';

void main() {
  group('HeaderButton (V2)', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeaderButton(
              child: Icon(Icons.search, size: 18, color: XiaColors.text2),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('renders legacy icon param', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HeaderButton(icon: Icons.settings)),
        ),
      );

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeaderButton(
              onPressed: () => pressed = true,
              child: const Icon(Icons.search),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(HeaderButton));
      await tester.pumpAndSettle();
      expect(pressed, isTrue);
    });

    testWidgets('does not throw when onPressed null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HeaderButton(child: Icon(Icons.search))),
        ),
      );

      await tester.tap(find.byType(HeaderButton));
      await tester.pumpAndSettle();
      expect(find.byType(HeaderButton), findsOneWidget);
    });

    testWidgets('shows tooltip when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeaderButton(tooltip: 'Search', child: Icon(Icons.search)),
          ),
        ),
      );

      final tooltipWidget = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltipWidget.message, 'Search');
    });

    testWidgets('default size is 36', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HeaderButton(child: Icon(Icons.search))),
        ),
      );

      final size = tester.getSize(find.byType(HeaderButton));
      expect(size.width, 36);
      expect(size.height, 36);
    });

    testWidgets('custom size honored', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeaderButton(
              size: 32,
              child: Icon(Icons.more_vert, size: 16),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(HeaderButton));
      expect(size.width, 32);
      expect(size.height, 32);
    });
  });
}
