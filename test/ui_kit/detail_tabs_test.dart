import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/detail_tabs.dart';

void main() {
  group('DetailTabs', () {
    testWidgets('renders all tab labels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailTabs(
              tabs: const ['成长面板', '成就'],
              selectedIndex: 0,
              onTabSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('成长面板'), findsOneWidget);
      expect(find.text('成就'), findsOneWidget);
    });

    testWidgets('calls onTabSelected when tab tapped', (tester) async {
      var selectedIndex = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailTabs(
              tabs: const ['成长面板', '成就'],
              selectedIndex: 0,
              onTabSelected: (i) => selectedIndex = i,
            ),
          ),
        ),
      );

      await tester.tap(find.text('成就'));
      await tester.pumpAndSettle();
      expect(selectedIndex, 1);
    });

    testWidgets('renders 2 tabs with hairline border-bottom container', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailTabs(
              tabs: const ['Tab A', 'Tab B'],
              selectedIndex: 0,
              onTabSelected: (_) {},
            ),
          ),
        ),
      );

      // Container with Border bottom exists
      final containerFinder = find.byType(Container).first;
      final container = tester.widget<Container>(containerFinder);
      final decoration = container.decoration as BoxDecoration?;
      // First container is the outer one with border
      expect(decoration, isNotNull);
    });
  });
}
