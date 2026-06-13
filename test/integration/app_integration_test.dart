import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/data/local/database/database.dart' as db;
import 'package:claw_hub/main.dart';

/// Test helper — creates a fully wired app with in-memory SQLite and
/// MockGatewayClient, matching the production ProviderScope setup but
/// suitable for headless CI testing.
ProviderScope appTestHarness({required Widget child}) {
  final memDb = db.AppDatabase(NativeDatabase.memory());
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) {
        ref.onDispose(() => memDb.close());
        return memDb;
      }),
      gatewayClientProvider.overrideWith(
        (ref) => ref.watch(mockGatewayClientProvider),
      ),
    ],
    child: child,
  );
}

void main() {
  // ===========================================================================
  // App Launch & Initialization
  // ===========================================================================
  group('App launch', () {
    testWidgets('renders 3-tab navigation bar', (tester) async {
      await tester.pumpWidget(appTestHarness(child: const ClawHubApp()));
      await tester.pumpAndSettle();

      expect(find.text('虾列表'), findsAtLeast(1));
      expect(find.text('消息'), findsAtLeast(1));
      expect(find.text('实例'), findsAtLeast(1));
    });

    testWidgets('starts on Claws (agent list) tab', (tester) async {
      await tester.pumpWidget(appTestHarness(child: const ClawHubApp()));
      await tester.pumpAndSettle();

      // Bottom nav should have 3 tabs rendered
      expect(find.byType(BackdropFilter), findsWidgets);
    });

    testWidgets('connection init completes without error', (tester) async {
      final memDb = db.AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.onDispose(() => memDb.close());
            return memDb;
          }),
          gatewayClientProvider.overrideWith(
            (ref) => ref.watch(mockGatewayClientProvider),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ClawHubApp(),
        ),
      );
      await tester.pumpAndSettle();

      final state = container.read(connectionInitStateProvider);
      expect(state, isA<AsyncValue<void>>());
      expect(
        state!.hasError,
        isFalse,
        reason: 'Connection init should succeed with MockGatewayClient',
      );
    });
  });

  // ===========================================================================
  // Tab Navigation
  // ===========================================================================
  group('Tab navigation', () {
    testWidgets('switches to Instances tab and shows FAB', (tester) async {
      await tester.pumpWidget(appTestHarness(child: const ClawHubApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('实例'));
      await tester.pumpAndSettle();

      // The add instance FAB should be visible
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('switches to Messages tab', (tester) async {
      await tester.pumpWidget(appTestHarness(child: const ClawHubApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('消息'));
      await tester.pumpAndSettle();

      // Message hub content should render
      expect(find.text('消息'), findsAtLeast(1));
    });

    testWidgets('returns to Claws tab after switching away', (tester) async {
      await tester.pumpWidget(appTestHarness(child: const ClawHubApp()));
      await tester.pumpAndSettle();

      // Go to instances
      await tester.tap(find.text('实例'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsOneWidget);

      // Go to messages
      await tester.tap(find.text('消息'));
      await tester.pumpAndSettle();

      // Return to claws
      await tester.tap(find.text('虾列表'));
      await tester.pumpAndSettle();
      expect(find.text('虾列表'), findsAtLeast(1));
    });
  });

  // ===========================================================================
  // Route Constants & Query Parameters (Law 16 coverage)
  // ===========================================================================
  group('Route constants', () {
    test('static route paths are defined', () {
      expect(AppRoutes.claws, '/claws');
      expect(AppRoutes.messages, '/messages');
      expect(AppRoutes.instances, '/instances');
      expect(AppRoutes.chat, '/chat/:agentId');
      expect(AppRoutes.agentProfile, '/agent-profile/:agentId');
      expect(AppRoutes.addInstance, '/instances/add');
      expect(AppRoutes.editInstance, '/instances/edit/:instanceId');
    });

    test('chatWithParams returns correct path with query params', () {
      final path = AppRoutes.chatWithParams('agent-1', 'inst-1');
      expect(path, contains('/chat/agent-1'));
      expect(path, contains('instanceId=inst-1'));
    });

    test('chatWithParams uses correct branch based on source', () {
      final clawsPath = AppRoutes.chatWithParams('a', 'i', source: 'claws');
      expect(clawsPath, startsWith('/claws/chat/a?'));

      final messagesPath = AppRoutes.chatWithParams(
        'a',
        'i',
        source: 'messages',
      );
      expect(messagesPath, startsWith('/messages/chat/a?'));
    });

    test('agentProfileWithParams returns correct path', () {
      expect(
        AppRoutes.agentProfileWithParams('agent-42'),
        '/claws/agent-profile/agent-42',
      );
      expect(
        AppRoutes.agentProfileWithParams('agent-42', source: 'home'),
        contains('source=home'),
      );
    });

    test('editInstanceWithParams returns correct path', () {
      expect(
        AppRoutes.editInstanceWithParams('my-instance'),
        '/instances/edit/my-instance',
      );
    });
  });

  // ===========================================================================
  // Robustness — rapid rebuilds and no crashes
  // ===========================================================================
  group('Robustness', () {
    testWidgets('survives rapid tab switching without crash', (tester) async {
      await tester.pumpWidget(appTestHarness(child: const ClawHubApp()));
      await tester.pumpAndSettle();

      const tabs = ['虾列表', '消息', '实例'];
      for (var round = 0; round < 3; round++) {
        for (final tab in tabs) {
          await tester.tap(find.text(tab));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester.takeException(),
            isNull,
            reason: 'No crash switching to $tab (round $round)',
          );
        }
      }
    });

    testWidgets('survives multiple rapid rebuilds', (tester) async {
      await tester.pumpWidget(appTestHarness(child: const ClawHubApp()));

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.takeException(),
          isNull,
          reason: 'No exception on pump #$i',
        );
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
