import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/instance_manager/add_instance_page.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/app/di/providers.dart';

void main() {
  Widget buildTestApp({String? instanceId}) {
    return ProviderScope(
      overrides: [
        instanceRepoProvider.overrideWith((ref) => InMemoryInstanceRepo()),
        gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
      ],
      child: MaterialApp(home: AddInstancePage(instanceId: instanceId)),
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

      // Tap save without entering name
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Instance name is required'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid URL', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Enter name but invalid URL
      await tester.enterText(find.byType(TextFormField).at(0), 'Test');
      await tester.enterText(find.byType(TextFormField).at(1), 'not-a-url');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid Gateway URL'), findsOneWidget);
    });
  });
}
