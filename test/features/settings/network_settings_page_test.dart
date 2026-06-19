import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/settings/network_settings_page.dart';
import 'package:claw_hub/features/settings/providers/settings_providers.dart';

void main() {
  Widget buildTestWidget({
    List<ConnectivityResult> connectivityResults = const [
      ConnectivityResult.wifi,
    ],
  }) {
    return ProviderScope(
      overrides: [
        connectivityStateProvider.overrideWith(
          (ref) => Stream.value(connectivityResults),
        ),
      ],
      child: const MaterialApp(home: NetworkSettingsPage()),
    );
  }

  group('NetworkSettingsPage', () {
    testWidgets('renders all info rows with real-time state', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Static rows still present
      expect(find.text('📡  当前网络'), findsOneWidget);
      expect(find.text('📱  运行平台'), findsOneWidget);
      expect(find.text('🔌  连接协议'), findsOneWidget);
      expect(find.text('WebSocket (OpenClaw v4)'), findsOneWidget);

      // Real-time connectivity row added
      expect(find.text('📶  实时状态'), findsOneWidget);
      // Should show WiFi for the default override
      expect(find.text('WiFi'), findsOneWidget);
    });

    testWidgets('shows mobile network when connectivity reports mobile', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(connectivityResults: const [ConnectivityResult.mobile]),
      );
      await tester.pumpAndSettle();

      expect(find.text('移动网络'), findsOneWidget);
    });

    testWidgets('shows no connection label when offline', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(connectivityResults: const [ConnectivityResult.none]),
      );
      await tester.pumpAndSettle();

      expect(find.text('无网络连接'), findsOneWidget);
    });

    testWidgets('shows combined label for multiple connection types', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          connectivityResults: const [
            ConnectivityResult.wifi,
            ConnectivityResult.mobile,
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WiFi + 移动网络'), findsOneWidget);
    });

    testWidgets('renders app bar with back button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('网络设置'), findsOneWidget);
    });

    testWidgets('shows explanation footer', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('虾Hub 通过 WebSocket 连接 OpenClaw Gateway 实例'),
        findsOneWidget,
      );
    });
  });

  group('connectivityResultLabel', () {
    test('returns "无网络连接" for empty list', () {
      expect(connectivityResultLabel([]), '无网络连接');
    });

    test('returns "无网络连接" for none', () {
      expect(connectivityResultLabel([ConnectivityResult.none]), '无网络连接');
    });

    test('returns "WiFi" for wifi', () {
      expect(connectivityResultLabel([ConnectivityResult.wifi]), 'WiFi');
    });

    test('returns "移动网络" for mobile', () {
      expect(connectivityResultLabel([ConnectivityResult.mobile]), '移动网络');
    });

    test('returns "以太网" for ethernet', () {
      expect(connectivityResultLabel([ConnectivityResult.ethernet]), '以太网');
    });

    test('returns "蓝牙" for bluetooth', () {
      expect(connectivityResultLabel([ConnectivityResult.bluetooth]), '蓝牙');
    });

    test('returns "VPN" for vpn', () {
      expect(connectivityResultLabel([ConnectivityResult.vpn]), 'VPN');
    });

    test('joins multiple results with " + "', () {
      final label = connectivityResultLabel([
        ConnectivityResult.wifi,
        ConnectivityResult.ethernet,
      ]);
      expect(label, 'WiFi + 以太网');
    });

    test('skips none in mixed results', () {
      final label = connectivityResultLabel([
        ConnectivityResult.wifi,
        ConnectivityResult.none,
      ]);
      // none is filtered out because it's in the list with wifi
      // Actually, since list contains wifi (not just none), it goes to switch.
      // none case breaks without adding, wifi adds. Result: "WiFi"
      expect(label, 'WiFi');
    });
  });
}
