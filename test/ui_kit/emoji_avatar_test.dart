import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

void main() {
  group('EmojiAvatar', () {
    Widget buildAvatar({
      String displayName = '产品虾',
      String themeColor = '#6c5ce7',
      double radius = 36,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: EmojiAvatar(
            displayName: displayName,
            themeColor: themeColor,
            radius: radius,
          ),
        ),
      );
    }

    testWidgets('renders first character of displayName', (tester) async {
      await tester.pumpWidget(buildAvatar());
      expect(find.text('产'), findsOneWidget);
    });

    testWidgets('uses themeColor background', (tester) async {
      await tester.pumpWidget(buildAvatar(themeColor: '#0984e3'));
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundColor, const Color(0xFF0984E3));
    });

    testWidgets('respects radius parameter', (tester) async {
      await tester.pumpWidget(buildAvatar(radius: 24));
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, 24.0);
    });

    testWidgets('handles empty displayName', (tester) async {
      await tester.pumpWidget(buildAvatar(displayName: ''));
      expect(find.text(''), findsOneWidget);
    });
  });
}
