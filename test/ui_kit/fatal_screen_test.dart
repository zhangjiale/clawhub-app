import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/fatal_screen.dart';

void main() {
  testWidgets('renders error message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FatalScreen(
          error: 'boom',
          stackTrace: StackTrace.current,
          onRetry: () {},
        ),
      ),
    );
    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('Retry button triggers callback on first tap', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FatalScreen(
          error: 'boom',
          stackTrace: StackTrace.current,
          onRetry: () => retries++,
        ),
      ),
    );
    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('Retry button disables after first tap (board 防双击)', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FatalScreen(
          error: 'boom',
          stackTrace: StackTrace.current,
          onRetry: () => retries++,
        ),
      ),
    );
    // 第一次点击：触发 callback，按钮 disable
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    await tester.pump();
    // 第二次点击：button 已 disabled，retries 不应再增加
    await tester.tap(find.text('重试'), warnIfMissed: false);
    expect(retries, 1, reason: 'Retry should be disabled after first tap');
  });
}
