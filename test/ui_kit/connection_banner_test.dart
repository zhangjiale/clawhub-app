import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/ui_kit/connection_banner.dart';

void main() {
  group('ConnectionBanner', () {
    Widget buildBanner(GatewayConnectionState state, {VoidCallback? onRetry}) {
      return MaterialApp(
        home: Scaffold(
          body: ConnectionBanner(connectionState: state, onRetry: onRetry),
        ),
      );
    }

    testWidgets('shows disconnected banner with wifi-off icon', (tester) async {
      await tester.pumpWidget(buildBanner(GatewayConnectionState.disconnected));

      expect(find.text('连接已断开，正在重连...'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('shows authFailed banner with wifi-off icon', (tester) async {
      await tester.pumpWidget(buildBanner(GatewayConnectionState.authFailed));

      expect(find.text('连接已断开，正在重连...'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('shows connecting banner with sync icon', (tester) async {
      await tester.pumpWidget(buildBanner(GatewayConnectionState.connecting));

      expect(find.text('正在连接...'), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('shows recovering banner with sync icon', (tester) async {
      await tester.pumpWidget(buildBanner(GatewayConnectionState.recovering));

      expect(find.text('正在连接...'), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('collapses to zero height when connected', (tester) async {
      await tester.pumpWidget(buildBanner(GatewayConnectionState.connected));

      // No banner text or icons should be present
      expect(find.text('连接已断开，正在重连...'), findsNothing);
      expect(find.text('正在连接...'), findsNothing);
      expect(find.byIcon(Icons.wifi_off), findsNothing);
      expect(find.byIcon(Icons.sync), findsNothing);
    });

    testWidgets('shows reconnectExhausted banner with warning icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBanner(GatewayConnectionState.reconnectExhausted, onRetry: () {}),
      );

      expect(find.text('无法连接到虾，请检查网络或实例状态。点击重试'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('reconnectExhausted banner taps fire onRetry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        buildBanner(
          GatewayConnectionState.reconnectExhausted,
          onRetry: () => retried++,
        ),
      );

      await tester.tap(find.byIcon(Icons.warning_amber_rounded));
      expect(retried, 1);
    });

    testWidgets('onRetry does NOT fire for non-reconnectExhausted states', (
      tester,
    ) async {
      var retried = 0;
      await tester.pumpWidget(
        buildBanner(
          GatewayConnectionState.disconnected,
          onRetry: () => retried++,
        ),
      );

      // disconnected 分支不透传 onTap —— 点击不应触发重试。
      await tester.tap(find.byIcon(Icons.wifi_off));
      expect(retried, 0);
    });
  });
}
