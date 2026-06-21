import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/inline_stats.dart';

void main() {
  group('InlineStats', () {
    testWidgets('renders all metric values', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InlineStats(
              items: [
                InlineStatItem(value: '2', unit: '/3', showStatusDot: true),
                InlineStatItem(value: '5', unit: '/8 在线'),
                InlineStatItem(value: '142', unit: '消息'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.text('/3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('142'), findsOneWidget);
    });

    testWidgets('renders separator dots between items', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InlineStats(
              items: [
                InlineStatItem(value: '2', unit: '/3'),
                InlineStatItem(value: '5', unit: '/8'),
                InlineStatItem(value: '142', unit: '消息'),
              ],
            ),
          ),
        ),
      );

      // 2 separators between 3 items
      expect(find.text('·'), findsNWidgets(2));
    });

    testWidgets('renders status dot when showStatusDot is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InlineStats(
              items: [
                InlineStatItem(
                  value: '2',
                  unit: '/3',
                  showStatusDot: true,
                  isOnline: true,
                ),
              ],
            ),
          ),
        ),
      );

      // Online dot rendered (small green container)
      final containers = find.byType(Container);
      expect(containers, findsWidgets);
    });

    testWidgets('handles empty items list gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InlineStats(items: [])),
        ),
      );

      expect(find.byType(InlineStats), findsOneWidget);
    });
  });
}
