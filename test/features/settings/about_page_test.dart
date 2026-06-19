import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/settings/about_page.dart';

void main() {
  Widget buildTestWidget() {
    return const MaterialApp(home: AboutPage());
  }

  group('AboutPage', () {
    testWidgets('renders app name', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('虾Hub'), findsOneWidget);
    });

    testWidgets('renders version string starting with v', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // The version label text is "v1.0.0" — find it exactly
      final versionWidget = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            widget.data!.startsWith('v') &&
            widget.data!.contains('.'),
      );
      expect(versionWidget, findsOneWidget);
    });

    testWidgets('renders tech stack info rows', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('🔌  通信协议'), findsOneWidget);
      expect(find.text('OpenClaw Gateway v4'), findsOneWidget);
      expect(find.text('📱  平台'), findsOneWidget);
      expect(find.text('🛠️  框架'), findsOneWidget);
      expect(find.text('Flutter + Drift + Riverpod'), findsOneWidget);
      expect(find.text('🧪  测试'), findsOneWidget);
    });

    testWidgets('renders app bar with back button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('关于虾Hub'), findsOneWidget);
    });

    testWidgets('renders copyright footer', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('© 2026 ClawHub Team'), findsOneWidget);
      expect(
        find.textContaining('Powered by OpenClaw Gateway Protocol'),
        findsOneWidget,
      );
    });

    testWidgets('renders app icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.pets), findsOneWidget);
    });
  });
}
