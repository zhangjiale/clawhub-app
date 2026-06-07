import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';

void main() {
  group('LoadingSkeleton', () {
    testWidgets('renders correct number of placeholder items', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingSkeleton(count: 3),
          ),
        ),
      );

      // Each skeleton item is a Card
      expect(find.byType(Card), findsNWidgets(3));
    });

    testWidgets('renders nothing when count is 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingSkeleton(count: 0),
          ),
        ),
      );

      expect(find.byType(Card), findsNothing);
    });

    testWidgets('renders single item by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingSkeleton(),
          ),
        ),
      );

      expect(find.byType(Card), findsOneWidget);
    });
  });
}
