import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/ui_kit/connection_banner.dart';

void main() {
  group('ConnectionBanner', () {
    Widget buildBanner(GatewayConnectionState state) {
      return MaterialApp(
        home: Scaffold(
          body: ConnectionBanner(connectionState: state),
        ),
      );
    }

    testWidgets('shows disconnected banner with wifi-off icon', (tester) async {
      await tester.pumpWidget(
        buildBanner(GatewayConnectionState.disconnected),
      );

      expect(find.text('连接已断开，正在重连...'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('shows authFailed banner with wifi-off icon', (tester) async {
      await tester.pumpWidget(
        buildBanner(GatewayConnectionState.authFailed),
      );

      expect(find.text('连接已断开，正在重连...'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('shows connecting banner with sync icon', (tester) async {
      await tester.pumpWidget(
        buildBanner(GatewayConnectionState.connecting),
      );

      expect(find.text('正在连接...'), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('shows recovering banner with sync icon', (tester) async {
      await tester.pumpWidget(
        buildBanner(GatewayConnectionState.recovering),
      );

      expect(find.text('正在连接...'), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('collapses to zero height when connected', (tester) async {
      await tester.pumpWidget(
        buildBanner(GatewayConnectionState.connected),
      );

      // No banner text or icons should be present
      expect(find.text('连接已断开，正在重连...'), findsNothing);
      expect(find.text('正在连接...'), findsNothing);
      expect(find.byIcon(Icons.wifi_off), findsNothing);
      expect(find.byIcon(Icons.sync), findsNothing);
    });
  });
}
