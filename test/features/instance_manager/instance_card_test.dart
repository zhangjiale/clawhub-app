import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/features/instance_manager/widgets/instance_card.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// ProviderScope override that injects a test [ConnectionOrchestrator].
Widget _wrapWithOrchestrator(
  Widget child, {
  required ConnectionOrchestrator orchestrator,
}) {
  return ProviderScope(
    overrides: [connectionOrchestratorProvider.overrideWithValue(orchestrator)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Minimal fake orchestrator that tracks [reconnect] calls without
/// needing real Gateway/DB wiring.
class _TestOrchestrator extends ConnectionOrchestrator {
  final List<String> reconnectCalls = [];

  _TestOrchestrator()
    : super(
        gatewayClient: _NoopGatewayClient(),
        instanceRepo: _NoopInstanceRepo(),
        agentRepo: _NoopAgentRepo(),
      );

  @override
  Future<void> reconnect(Instance instance) async {
    reconnectCalls.add(instance.id);
  }
}

class _NoopGatewayClient implements IGatewayClient {
  @override
  Future<void> connect(Instance i) async {}
  @override
  Future<void> disconnect(String id) async {}
  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) => throw UnimplementedError();
  @override
  Future<List<Agent>> fetchAgents(String id) async => [];
  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) => throw UnimplementedError();
  @override
  Future<bool> testConnection(Instance i) async => true;
  @override
  Stream<GatewayConnectionState> connectionStateStream(String id) =>
      const Stream.empty();
  @override
  void resetConnectionState(String id) {}
  @override
  Stream<Message> messageStream(String id) => const Stream.empty();
  @override
  Stream<ToolCall> toolCallStream(String id) => const Stream.empty();
  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String id) =>
      const Stream.empty();
  @override
  Future<void> dispose() async {}
}

class _NoopInstanceRepo implements IInstanceRepo {
  @override
  Future<List<Instance>> getAll() async => [];
  @override
  Future<Instance?> getById(String id) async => null;
  @override
  Future<Instance> save(Instance instance) async => instance;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<bool> nameExists(String name, {String? excludeId}) async => false;
  @override
  Future<Instance> updateHealthStatus(String id, HealthStatus s) async =>
      throw UnimplementedError();
  @override
  Future<void> updateLastConnectedAt(String id, int ts) async {}
  @override
  Future<List<String>> batchUpdateStatusByNetwork({
    required bool isLocalNetwork,
    required HealthStatus status,
  }) async => [];
}

class _NoopAgentRepo implements IAgentRepo {
  @override
  Future<List<Agent>> getByInstanceId(String instanceId) async => [];
  @override
  Future<List<Agent>> getAll() async => [];
  @override
  Future<Agent?> getById(String localId) async => null;
  @override
  Future<Agent?> findByCompositeKey(String instanceId, String remoteId) async =>
      null;
  @override
  Future<List<Agent>> syncFromGateway(
    String instanceId,
    List<Agent> remoteAgents,
  ) async => [];
  @override
  Future<Agent> updateLocalProfile(
    String localId, {
    String? nickname,
    String? avatarUrl,
    String? themeColor,
  }) async => throw UnimplementedError();
  @override
  Future<Agent> togglePin(String localId) async => throw UnimplementedError();
  @override
  Future<void> deleteByInstanceId(String instanceId) async {}
}

void main() {
  final testInstance = Instance(
    id: 'inst-1',
    name: 'My Server',
    gatewayUrl: 'wss://example.com:18789',
    tokenRef: 'ref-1',
    healthStatus: HealthStatus.online,
  );

  group('InstanceCard', () {
    testWidgets('displays instance name and URL', (tester) async {
      await tester.pumpWidget(
        _wrap(InstanceCard(instance: testInstance, onTap: () {})),
      );

      expect(find.text('My Server'), findsOneWidget);
      expect(find.text('wss://example.com:18789'), findsOneWidget);
    });

    testWidgets('shows green dot when online', (tester) async {
      await tester.pumpWidget(
        _wrap(InstanceCard(instance: testInstance, onTap: () {})),
      );

      // Find the status dot container with green color
      final container = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).color == XiaColors.green,
        ),
      );
      expect(container, isNotNull);
    });

    testWidgets('shows grey dot when offline', (tester) async {
      final offline = testInstance.copyWith(healthStatus: HealthStatus.offline);
      await tester.pumpWidget(
        _wrap(InstanceCard(instance: offline, onTap: () {})),
      );

      final container = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).color == XiaColors.text4,
        ),
      );
      expect(container, isNotNull);
    });

    testWidgets('shows yellow dot and 等待审批 when pairingRequired', (
      tester,
    ) async {
      final pairing = testInstance.copyWith(
        healthStatus: HealthStatus.pairingRequired,
      );
      await tester.pumpWidget(
        _wrap(InstanceCard(instance: pairing, onTap: () {})),
      );

      expect(find.text('等待审批'), findsOneWidget);

      final container = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).color == XiaColors.yellow,
        ),
      );
      expect(container, isNotNull);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(InstanceCard(instance: testInstance, onTap: () => tapped = true)),
      );

      // Multiple InkWell widgets now (card + action buttons); tap the first
      await tester.tap(find.byType(InkWell).first);
      expect(tapped, isTrue);
    });

    testWidgets('refresh button exists with Icons.refresh', (tester) async {
      await tester.pumpWidget(
        _wrap(InstanceCard(instance: testInstance, onTap: () {})),
      );

      expect(
        find.byIcon(Icons.refresh),
        findsOneWidget,
        reason:
            'The refresh/reconnect button must be visible so users '
            'can manually trigger reconnection.',
      );
    });

    testWidgets('refresh button calls orchestrator.reconnect() when tapped', (
      tester,
    ) async {
      final orch = _TestOrchestrator();
      await tester.pumpWidget(
        _wrapWithOrchestrator(
          InstanceCard(instance: testInstance, onTap: () {}),
          orchestrator: orch,
        ),
      );

      // Tap the refresh button (the InkWell wrapping the refresh icon)
      final refreshBtn = find.byIcon(Icons.refresh);
      expect(refreshBtn, findsOneWidget);
      await tester.tap(refreshBtn);

      expect(
        orch.reconnectCalls,
        equals(['inst-1']),
        reason:
            'Tapping the refresh button must call reconnect(). '
            'Before the fix, the onTap callback was empty (() {}) '
            'making the button a no-op — users had no way to manually '
            'trigger reconnection after approval.',
      );
    });

    testWidgets('refresh button sends correct instance to reconnect()', (
      tester,
    ) async {
      final orch = _TestOrchestrator();
      final instance2 = testInstance.copyWith(id: 'inst-2', name: 'Server 2');
      await tester.pumpWidget(
        _wrapWithOrchestrator(
          InstanceCard(instance: instance2, onTap: () {}),
          orchestrator: orch,
        ),
      );

      await tester.tap(find.byIcon(Icons.refresh));

      expect(
        orch.reconnectCalls,
        equals(['inst-2']),
        reason:
            'reconnect() must receive the card\'s own instance, '
            'not a hardcoded ID.',
      );
    });
  });
}
