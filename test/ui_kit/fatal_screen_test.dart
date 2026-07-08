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

  testWidgets(
    'Retry re-enables when error changes (showFatal reuse path - ARB #4)',
    (tester) async {
      // Regression for the persistent-failure lockout: in main.dart's showFatal
      // path, a second runApp(MaterialApp(home: FatalScreen(e2))) reuses the
      // existing _FatalScreenState (same runtimeType, no key) rather than
      // recreating it. Without a reset, _retrying stays true from the first
      // failed retry and the second failure is un-retryable - the user is
      // locked out until force-quit. Pumping a new FatalScreen with a different
      // error at the same slot reproduces that reconciliation.
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FatalScreen(
            error: 'first failure',
            stackTrace: StackTrace.current,
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.tap(find.text('重试'));
      expect(retries, 1);
      await tester.pump();

      // main() failed again -> showFatal(e2) reuses the State at the same slot.
      await tester.pumpWidget(
        MaterialApp(
          home: FatalScreen(
            error: 'second failure',
            stackTrace: StackTrace.current,
            onRetry: () => retries++,
          ),
        ),
      );
      await tester.tap(find.text('重试'));
      expect(
        retries,
        2,
        reason: 'a new failure reusing the State must be retryable',
      );
    },
  );
}
