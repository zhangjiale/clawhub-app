import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/settings_section.dart';

void main() {
  group('SettingsSection', () {
    testWidgets('renders uppercase title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingsSection(
              title: '通知',
              children: [SettingsRow(label: '通知总开关')],
            ),
          ),
        ),
      );

      expect(find.text('通知'.toUpperCase()), findsOneWidget);
    });

    testWidgets('renders all child rows', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingsSection(
              title: 'Section',
              children: [
                SettingsRow(label: 'Row 1'),
                SettingsRow(label: 'Row 2'),
                SettingsRow(label: 'Row 3'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Row 1'), findsOneWidget);
      expect(find.text('Row 2'), findsOneWidget);
      expect(find.text('Row 3'), findsOneWidget);
    });

    testWidgets('renders value text and chevron when value provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsSection(
              title: 'Section',
              children: [
                SettingsRow(label: '免打扰', value: '22:00 - 08:00', onTap: () {}),
              ],
            ),
          ),
        ),
      );

      expect(find.text('22:00 - 08:00'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('calls onTap when row tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsSection(
              title: 'Section',
              children: [
                SettingsRow(label: 'Tap me', onTap: () => tapped = true),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap me'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
