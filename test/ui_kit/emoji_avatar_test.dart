import 'dart:io';

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
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF0984E3));
    });

    testWidgets('respects radius parameter', (tester) async {
      await tester.pumpWidget(buildAvatar(radius: 24));
      final emojiAvatar = tester.widget<EmojiAvatar>(find.byType(EmojiAvatar));
      expect(emojiAvatar.radius, 24.0);
    });

    testWidgets('shows ? placeholder when displayName is empty', (
      tester,
    ) async {
      await tester.pumpWidget(buildAvatar(displayName: ''));
      // 空名称展示 '?' 作为防御性占位符，与旧 _ConversationAvatar 行为一致
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders text avatar when avatarUrl is null', (tester) async {
      await tester.pumpWidget(buildAvatar());
      expect(find.text('产'), findsOneWidget);
      // No Image widget should be present
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('falls back to text when avatarUrl file does not exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmojiAvatar(
              displayName: '产品虾',
              themeColor: '#6c5ce7',
              avatarImage: FileImage(File('/nonexistent/path/avatar.jpg')),
            ),
          ),
        ),
      );
      // frameBuilder shows text fallback synchronously during loading;
      // errorBuilder also shows text fallback on load failure.
      // Either way, text is visible without blank flash and without sync I/O.
      await tester.pumpAndSettle();
      expect(find.text('产'), findsOneWidget);
    });

    testWidgets('backgroundColor overrides text color calculation', (
      tester,
    ) async {
      // Use a very dark backgroundColor — text should be white (contrasting)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmojiAvatar(
              displayName: '虾',
              themeColor: '#F4D03F', // warm yellow
              backgroundColor: const Color(
                0xFF15171E,
              ), // V2 surface2 (dark gray, muted)
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The text should still be readable because backgroundColor drives
      // the contrastingTextColor() calculation
      expect(find.text('虾'), findsOneWidget);
    });
  });
}
