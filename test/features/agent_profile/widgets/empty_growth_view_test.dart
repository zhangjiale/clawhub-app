import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/agent_profile/widgets/empty_growth_view.dart';

void main() {
  group('EmptyGrowthView (US-019 AC-3)', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders guidance copy and CTA button', (tester) async {
      await tester.pumpWidget(wrap(const EmptyGrowthView()));

      expect(find.text('🦐'), findsOneWidget);
      expect(find.text('刚开始养虾'), findsOneWidget);
      expect(find.text('快去对话吧！'), findsOneWidget);
      expect(find.text('💬 去对话'), findsOneWidget);
    });

    testWidgets('invokes onStartChat when the CTA is tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(EmptyGrowthView(onStartChat: () => taps++)));

      // Match the button label exactly — '去对话' also appears inside the
      // copy line "快去对话吧！", so a textContaining match would be ambiguous.
      await tester.tap(find.text('💬 去对话'));
      await tester.pump();

      expect(taps, 1, reason: 'CTA tap must propagate to onStartChat callback');
    });

    testWidgets('CTA tap is a no-op when onStartChat is null', (tester) async {
      await tester.pumpWidget(wrap(const EmptyGrowthView()));

      // Should not throw despite null callback (PrimaryButton disables itself).
      await tester.tap(find.text('💬 去对话'), warnIfMissed: false);
      await tester.pump();
    });
  });
}
