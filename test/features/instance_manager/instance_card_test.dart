import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/features/instance_manager/widgets/instance_card.dart';
import 'package:claw_hub/app/theme/theme.dart';

void main() {
  final testInstance = Instance(
    id: 'inst-1', name: 'My Server',
    gatewayUrl: 'wss://example.com:18789', tokenRef: 'ref-1',
    healthStatus: HealthStatus.online,
  );

  group('InstanceCard', () {
    testWidgets('displays instance name and URL', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstanceCard(instance: testInstance, onTap: () {}),
          ),
        ),
      );

      expect(find.text('My Server'), findsOneWidget);
      expect(find.text('wss://example.com:18789'), findsOneWidget);
    });

    testWidgets('shows green dot when online', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstanceCard(instance: testInstance, onTap: () {}),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byWidgetPredicate((w) =>
            w is Container && w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.statusOnline);
    });

    testWidgets('shows red dot when offline', (tester) async {
      final offline = testInstance.copyWith(healthStatus: HealthStatus.offline);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstanceCard(instance: offline, onTap: () {}),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byWidgetPredicate((w) =>
            w is Container && w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.statusOffline);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstanceCard(
              instance: testInstance,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });
  });
}
