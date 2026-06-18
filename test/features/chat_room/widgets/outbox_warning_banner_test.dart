import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/chat_room/widgets/outbox_warning_banner.dart';
import 'package:claw_hub/ui_kit/status_banner.dart';

void main() {
  group('OutboxWarningBanner', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders nothing when outboxCount is 0', (tester) async {
      await tester.pumpWidget(wrap(const OutboxWarningBanner(outboxCount: 0)));

      expect(find.byType(StatusBanner), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget); // SizedBox.shrink
    });

    testWidgets('renders nothing when outboxCount is below threshold (19)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const OutboxWarningBanner(outboxCount: 19)));

      expect(find.byType(StatusBanner), findsNothing);
    });

    testWidgets('renders banner when outboxCount equals threshold (20)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const OutboxWarningBanner(outboxCount: 20)));

      expect(find.byType(StatusBanner), findsOneWidget);
      expect(find.text('有20条消息等待发送，请检查网络连接'), findsOneWidget);
    });

    testWidgets('renders banner when outboxCount exceeds threshold (50)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const OutboxWarningBanner(outboxCount: 50)));

      expect(find.byType(StatusBanner), findsOneWidget);
      expect(find.text('有50条消息等待发送，请检查网络连接'), findsOneWidget);
    });

    testWidgets('uses yellow warning color tokens', (tester) async {
      await tester.pumpWidget(wrap(const OutboxWarningBanner(outboxCount: 25)));

      final banner = tester.widget<StatusBanner>(find.byType(StatusBanner));
      expect(banner.foregroundColor, XiaColors.yellow);
      expect(banner.backgroundColor, XiaColors.yellowMuted);
      expect(banner.icon, Icons.warning_amber);
    });
  });
}
