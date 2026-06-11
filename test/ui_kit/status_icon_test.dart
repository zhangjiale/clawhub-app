import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/ui_kit/status_icon.dart';

void main() {
  group('StatusIcon', () {
    testWidgets('PENDING shows clock icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusIcon(status: MessageStatus.pending)),
        ),
      );
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('SENDING shows spinning indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusIcon(status: MessageStatus.sending)),
        ),
      );
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('SENT shows single check', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusIcon(status: MessageStatus.sent)),
        ),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('DELIVERED shows double check', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusIcon(status: MessageStatus.delivered)),
        ),
      );
      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });

    testWidgets('FAILED shows red error icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusIcon(status: MessageStatus.failed)),
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, const Color(0xFFC26464)); // XiaColors.red
      expect(icon.icon, Icons.error);
    });

    testWidgets('EXPIRED shows grey schedule icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusIcon(status: MessageStatus.expired)),
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.schedule);
    });

    testWidgets('DRAFT shows edit icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusIcon(status: MessageStatus.draft)),
        ),
      );
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });
  });
}
