import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/empty_state.dart';

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title, and subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Icon(Icons.inbox),
              title: 'No Items',
              subtitle: 'Add your first item',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inbox), findsOneWidget);
      expect(find.text('No Items'), findsOneWidget);
      expect(find.text('Add your first item'), findsOneWidget);
    });

    testWidgets('renders emoji icon as Text widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: Text('🦐', style: TextStyle(fontSize: 48)),
              title: '还没有虾',
            ),
          ),
        ),
      );

      expect(find.text('🦐'), findsOneWidget);
      expect(find.text('还没有虾'), findsOneWidget);
    });

    testWidgets('renders action button when onAction provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyState(
              icon: const Icon(Icons.add),
              title: 'Empty',
              actionLabel: 'Add Now',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Add Now'), findsOneWidget);
      await tester.tap(find.text('Add Now'));
      expect(tapped, isTrue);
    });

    testWidgets('no action button when onAction is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(icon: Icon(Icons.inbox), title: 'Empty'),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('no subtitle when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyState(icon: Icon(Icons.inbox), title: 'Just Title'),
          ),
        ),
      );

      expect(find.text('Just Title'), findsOneWidget);
      // Should have icon Text + title Text = 2 Text widgets
      // (Icon is wrapped in Icon widget, not Text)
    });
  });
}
