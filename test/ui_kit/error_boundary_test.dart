import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/error_boundary.dart';

void main() {
  group('ErrorBoundary', () {
    testWidgets('renders child when no error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorBoundary(
              child: Text('All good'),
            ),
          ),
        ),
      );

      expect(find.text('All good'), findsOneWidget);
    });

    testWidgets('renders default fallback when child throws (global builder)',
        (tester) async {
      // The global ErrorWidget.builder is set in main().
      // We set it manually here for test isolation, saving and restoring
      // the previous builder to avoid polluting other tests.
      final previousBuilder = ErrorWidget.builder;
      ErrorWidget.builder = (details) => const DefaultErrorFallback();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorBoundary(
              child: _ThrowingWidget(),
            ),
          ),
        ),
      );

      // Take expected exception so it doesn't fail the test
      final exception = tester.takeException();
      expect(exception, isNotNull);

      await tester.pump();
      // Default fallback shows error icon and message
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);

      // Restore previous builder to avoid cross-test pollution
      ErrorWidget.builder = previousBuilder;
    });
  });

  group('DefaultErrorFallback', () {
    testWidgets('renders error icon and message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DefaultErrorFallback(error: 'Test'),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
    });
  });
}

/// Helper widget that throws on build
class _ThrowingWidget extends StatelessWidget {
  const _ThrowingWidget();

  @override
  Widget build(BuildContext context) {
    throw Exception('Test error');
  }
}
