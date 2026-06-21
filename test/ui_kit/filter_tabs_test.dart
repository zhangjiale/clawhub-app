import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/filter_tabs.dart';

void main() {
  group('FilterTabs', () {
    testWidgets('renders all tab labels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilterTabs(
              tabs: const ['全部', '虾', '消息', '实例'],
              selectedIndex: 0,
              onTabSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('全部'), findsOneWidget);
      expect(find.text('虾'), findsOneWidget);
      expect(find.text('消息'), findsOneWidget);
      expect(find.text('实例'), findsOneWidget);
    });

    testWidgets('calls onTabSelected with index when tapped', (tester) async {
      var selectedIndex = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilterTabs(
              tabs: const ['全部', '虾'],
              selectedIndex: 0,
              onTabSelected: (i) => selectedIndex = i,
            ),
          ),
        ),
      );

      await tester.tap(find.text('虾'));
      await tester.pumpAndSettle();
      expect(selectedIndex, 1);
    });

    testWidgets('renders default active tab at selectedIndex', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilterTabs(
              tabs: const ['全部', '虾'],
              selectedIndex: 1,
              onTabSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('全部'), findsOneWidget);
      expect(find.text('虾'), findsOneWidget);
    });
  });
}
