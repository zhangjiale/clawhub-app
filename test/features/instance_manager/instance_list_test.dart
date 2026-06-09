import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/instance_manager/instance_list_page.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/app/di/providers.dart';

void main() {
  group('InstanceListPage', () {
    testWidgets('shows empty state when no instances', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instanceRepoProvider.overrideWith((ref) => InMemoryInstanceRepo()),
          ],
          child: const MaterialApp(home: InstanceListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Instances'), findsOneWidget);
      expect(find.text('Add your first OpenClaw instance'), findsOneWidget);
    });

    testWidgets('has inline add instance card when empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instanceRepoProvider.overrideWith((ref) => InMemoryInstanceRepo()),
          ],
          child: const MaterialApp(home: InstanceListPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Inline "添加新实例" card appears at bottom of empty list
      expect(find.text('添加新实例'), findsOneWidget);
    });

    testWidgets('shows instance cards when instances exist', (tester) async {
      final repo = InMemoryInstanceRepo();
      await repo.save(Instance(
        id: 'i1', name: 'Server A',
        gatewayUrl: 'wss://a.com:18789', tokenRef: 'r1',
        healthStatus: HealthStatus.online,
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instanceRepoProvider.overrideWith((ref) => repo),
          ],
          child: const MaterialApp(home: InstanceListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server A'), findsOneWidget);
      expect(find.text('wss://a.com:18789'), findsOneWidget);
    });
  });
}
