import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/acl/mock_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/instance_manager/instance_list_page.dart';
import 'package:claw_hub/features/instance_manager/add_instance_page.dart';

/// Integration tests for the save → pop → list refresh cross-page flow.
///
/// The bug: when [ref.invalidate] was called in the add page right before
/// `context.pop()`, the list page would sometimes show stale data because
/// the FutureProvider hadn't finished re-executing before the build.
///
/// The fix: the list page now does `await context.push(...)` then
/// `ref.invalidate(instanceListProvider)` — ensuring invalidation happens
/// after the widget is visible and can properly rebuild.
///
/// These tests exercise the full stack: GoRouter navigation, go_router's
/// context.push/pop, MockGatewayClient.testConnection, provider invalidation,
/// and InstanceCard health status rendering. Single-page widget tests missed
/// this because they never tested the navigation + data-refresh interaction.
void main() {
  late InMemoryInstanceRepo instanceRepo;

  setUp(() {
    instanceRepo = InMemoryInstanceRepo();
  });

  /// Build a minimal GoRouter matching the real instances branch.
  Widget buildTestApp({String initialLocation = '/instances'}) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/instances',
          builder: (context, state) => const InstanceListPage(),
          routes: [
            GoRoute(
              path: 'add',
              builder: (context, state) => const AddInstancePage(),
            ),
            GoRoute(
              path: 'edit/:instanceId',
              builder: (context, state) {
                final instanceId = state.pathParameters['instanceId']!;
                return AddInstancePage(instanceId: instanceId);
              },
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        instanceRepoProvider.overrideWith((ref) => instanceRepo),
        agentRepoProvider.overrideWith((ref) => InMemoryAgentRepo()),
        gatewayClientProvider.overrideWith((ref) => MockGatewayClient()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Navigate from list → bottom sheet → "Enter Manually" → add page.
  Future<void> navigateToAddPage(WidgetTester tester) async {
    await tester.tap(find.text('添加新实例'));
    await tester.pumpAndSettle();
    expect(find.text('Enter Manually'), findsOneWidget);
    await tester.tap(find.text('Enter Manually'));
    await tester.pumpAndSettle();
    expect(find.text('Add Instance'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
  }

  /// Fill the add-instance form and tap Save.
  /// Uses [pump] with explicit duration instead of [pumpAndSettle] to
  /// avoid timeouts from async delays in MockGatewayClient
  /// (testConnection: 800ms, connect: 500ms).
  Future<void> fillAndSave({
    required WidgetTester tester,
    required String name,
    required String url,
    required String token,
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), name);
    await tester.enterText(find.byType(TextFormField).at(1), url);
    await tester.enterText(find.byType(TextFormField).at(2), token);
    await tester.tap(find.text('Save'));

    // Pump through the async save flow (~1.3s of delays in mock):
    // - MockGatewayClient.testConnection: 800ms delay
    // - SaveInstanceUseCase: DB save
    // - ConnectionOrchestrator._connect: 500ms delay (if online)
    // - context.pop() navigation
    // - List page rebuild + provider refresh
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  group('Add → Save → Pop → Refresh', () {
    testWidgets('new instance appears as ONLINE after save and pop', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Empty list
      expect(find.text('还没有实例'), findsOneWidget);

      // Navigate to add page
      await navigateToAddPage(tester);

      // Fill and save — wss:// URL guarantees testConnection returns true
      await fillAndSave(
        tester: tester,
        name: 'Test Server',
        url: 'wss://test.example.com:18789',
        token: 'test-token-123',
      );

      // Back on list page with online instance
      expect(find.text('实例管理'), findsOneWidget);
      expect(find.text('Test Server'), findsOneWidget);
      expect(find.text('wss://test.example.com:18789'), findsOneWidget);
      expect(find.text('在线'), findsOneWidget);
    });

    testWidgets('edit instance returns to list with updated values', (
      tester,
    ) async {
      // Pre-populate with existing instance
      await instanceRepo.save(
        Instance(
          id: 'existing-1',
          name: 'Old Name',
          gatewayUrl: 'wss://old.example.com:18789',
          tokenRef: 'old-token',
          healthStatus: HealthStatus.online,
        ),
      );

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Old Name'), findsOneWidget);

      // Tap card to edit
      await tester.tap(find.text('Old Name'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Instance'), findsOneWidget);
      expect(find.text('Old Name'), findsOneWidget); // pre-filled

      // Change the name
      final nameField = tester.widget<TextFormField>(
        find.byType(TextFormField).at(0),
      );
      nameField.controller?.clear();
      await tester.enterText(find.byType(TextFormField).at(0), 'Updated Name');
      await tester.tap(find.text('Save'));

      // Pump through save + pop + refresh
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Back on list with updated name, old name gone
      expect(find.text('Updated Name'), findsOneWidget);
      expect(find.text('Old Name'), findsNothing);
    });
  });
}
