import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/instance_manager/add_instance_page.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/app/di/providers.dart';

void main() {
  Widget buildTestApp({String? instanceId, QrScanResult? scanResult}) {
    return ProviderScope(
      overrides: [
        instanceRepoProvider.overrideWith((ref) => InMemoryInstanceRepo()),
        gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
      ],
      child: MaterialApp(
        home: AddInstancePage(
          instanceId: instanceId,
          scanResult: scanResult,
        ),
      ),
    );
  }

  group('AddInstancePage', () {
    testWidgets('shows form fields', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Add Instance'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3)); // name, url, token
    });

    testWidgets('save button is present', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows edit title when instanceId provided', (tester) async {
      await tester.pumpWidget(buildTestApp(instanceId: 'inst-1'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Instance'), findsOneWidget);
    });

    testWidgets('shows validation error for empty name', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Instance name is required'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid URL', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'not-a-url');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid Gateway URL'), findsOneWidget);
    });

    // US-001: QR scan pre-fill tests
    testWidgets('displays scan pre-fill banner when scanResult provided',
        (tester) async {
      await tester.pumpWidget(buildTestApp(
        scanResult: const QrScanResult(
          name: 'Scanned Instance',
          gatewayUrl: 'wss://192.168.1.100:18789',
          token: 'scan-token',
        ),
      ));
      await tester.pumpAndSettle();

      // Banner should be visible
      expect(find.text('Info pre-filled from QR code'), findsOneWidget);
    });

    testWidgets('pre-fills form fields from scan result', (tester) async {
      await tester.pumpWidget(buildTestApp(
        scanResult: const QrScanResult(
          name: 'Scanned Instance',
          gatewayUrl: 'wss://192.168.1.100:18789',
          token: 'scan-token',
        ),
      ));
      await tester.pumpAndSettle();

      // Fields should be pre-filled
      expect(find.text('Scanned Instance'), findsOneWidget);
      expect(find.text('wss://192.168.1.100:18789'), findsOneWidget);
      // Token is obscured, verify it's filled by checking the field value
      final tokenField = tester.widget<TextFormField>(
        find.byType(TextFormField).at(2),
      );
      expect(tokenField.controller?.text, 'scan-token');
    });

    testWidgets('no scan banner when scanResult is null', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Info pre-filled from QR code'), findsNothing);
    });
  });
}
