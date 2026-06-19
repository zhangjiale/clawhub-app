import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/status_banner.dart';

void main() {
  group('StatusBanner', () {
    testWidgets('onTap fires when banner is tapped', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatusBanner(
              message: '点击重试',
              foregroundColor: XiaColors.red,
              backgroundColor: XiaColors.redMuted,
              icon: Icons.warning_amber_rounded,
              onTap: () => tapped++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(StatusBanner));
      expect(tapped, 1);
    });

    testWidgets('renders without crash when onTap is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBanner(
              message: '纯展示',
              foregroundColor: XiaColors.yellow,
              backgroundColor: XiaColors.yellowMuted,
              icon: Icons.wifi_off,
            ),
          ),
        ),
      );

      expect(find.text('纯展示'), findsOneWidget);
      // const 构造、无回调：点击不应抛异常（GestureDetector 不存在，tap 命中 Container）。
      await tester.tap(find.byType(StatusBanner));
      expect(find.byType(GestureDetector), findsNothing);
    });
  });
}
