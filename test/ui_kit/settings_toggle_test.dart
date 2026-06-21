import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/settings_toggle.dart';

void main() {
  group('SettingsToggle', () {
    testWidgets('renders toggle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SettingsToggle(value: false, onChanged: null)),
        ),
      );

      expect(find.byType(SettingsToggle), findsOneWidget);
    });

    testWidgets('toggles value when tapped', (tester) async {
      var currentValue = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SettingsToggle(
                value: currentValue,
                onChanged: (v) => setState(() => currentValue = v),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SettingsToggle));
      await tester.pumpAndSettle();
      expect(currentValue, isTrue);

      await tester.tap(find.byType(SettingsToggle));
      await tester.pumpAndSettle();
      expect(currentValue, isFalse);
    });

    testWidgets('does not toggle when onChanged is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SettingsToggle(value: false, onChanged: null)),
        ),
      );

      // Tap is no-op when disabled
      await tester.tap(find.byType(SettingsToggle));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsToggle), findsOneWidget);
    });

    testWidgets('has 40x22 dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SettingsToggle(value: false, onChanged: null)),
        ),
      );

      final size = tester.getSize(find.byType(SettingsToggle));
      expect(size.width, 40);
      expect(size.height, 22);
    });
  });
}
