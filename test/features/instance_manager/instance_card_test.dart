import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/domain/models/models.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/features/instance_manager/widgets/instance_card.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Predicate: true iff the widget is an [AnimatedContainer] whose direct child
/// is an [Icon] matching [icon].
///
/// This uniquely identifies the _ActionBtn's animated container; the outer
/// InstanceCard's press animation wraps a plain Container, not an Icon.
bool Function(Widget) _actionButtonContainerFor(IconData icon) {
  return (Widget w) {
    if (w is! AnimatedContainer) return false;
    final child = w.child;
    return child is Icon && child.icon == icon;
  };
}

/// Predicate: true iff the widget is an [AnimatedScale] wrapping an
/// [AnimatedContainer] whose direct child is an [Icon] matching [icon].
///
/// Bug #4 regression — PressFeedback in builder mode ignores its own
/// `scale` param (press_feedback_buttons.dart:120-149), so the _ActionBtn
/// wraps the AnimatedContainer in an explicit AnimatedScale. This predicate
/// targets that wrapper so a future refactor that drops the scale cannot
/// silently regress the press-feedback contract.
bool Function(Widget) _actionButtonScaleFor(IconData icon) {
  return (Widget w) {
    if (w is! AnimatedScale) return false;
    final inner = w.child;
    if (inner is! AnimatedContainer) return false;
    final ic = inner.child;
    return ic is Icon && ic.icon == icon;
  };
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
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) =>
      const Stream<StreamingEvent>.empty();
  @override
  Stream<GatewayNotice> gatewayNoticeStream(String instanceId) =>
      const Stream<GatewayNotice>.empty();
  @override
  Future<void> dispose() async {}
}

class _NoopInstanceRepo implements IInstanceRepo {
  @override
  Future<List<Instance>> getAll() async => [];
  @override
  Future<Instance?> getById(String id) async => null;
  @override
  Future<Map<String, Instance>> getByIds(List<String> ids) async => {};
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
  Future<List<Agent>> getAllByInstanceId(String instanceId) async => [];
  @override
  Future<List<Agent>> getAll() async => [];
  @override
  Future<Agent?> getById(String localId) async => null;
  @override
  Future<Map<String, Agent>> getByIds(List<String> localIds) async => {};
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
  Future<void> clearAvatar(String localId) async {}
  @override
  Future<void> updateFullProfile(
    String localId, {
    String? nickname,
    String? avatarUrl,
    String? themeColor,
    List<QuickCommand>? quickCommands,
  }) async {}
  @override
  Future<void> deleteByInstanceId(String instanceId) async {}
  @override
  Stream<Agent?> watchById(String localId) => const Stream<Agent?>.empty();
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

      // Multiple GestureDetector widgets now (card + action buttons); tap the card
      await tester.tap(find.byType(InstanceCard));
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

    testWidgets('shows red dot and 重连失败 when in reconnectExhaustedProvider', (
      tester,
    ) async {
      // DB 落库为 offline（reconnectExhausted 是瞬态不落库），
      // 但 provider 实时标记该实例已耗尽 —— card 必须显示"重连失败"而非"离线"。
      final offline = testInstance.copyWith(healthStatus: HealthStatus.offline);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reconnectExhaustedProvider.overrideWith((ref) => {'inst-1'}),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: InstanceCard(instance: offline, onTap: () {}),
            ),
          ),
        ),
      );

      expect(find.text('重连失败'), findsOneWidget);

      final container = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).color == XiaColors.red,
        ),
      );
      expect(container, isNotNull);
    });

    testWidgets('reconnectExhausted takes priority over pairingRequired', (
      tester,
    ) async {
      // 两态同时标记时，耗尽优先 —— 实例不可达比"等待审批"更准确。
      final pairing = testInstance.copyWith(
        healthStatus: HealthStatus.pairingRequired,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reconnectExhaustedProvider.overrideWith((ref) => {'inst-1'}),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: InstanceCard(instance: pairing, onTap: () {}),
            ),
          ),
        ),
      );

      expect(find.text('重连失败'), findsOneWidget);
      expect(find.text('等待审批'), findsNothing);
    });

    testWidgets('refresh button shows accent border on press', (tester) async {
      // The PRIMARY visible feedback signal — color-only or scale-only
      // changes are too subtle on a 36×36 button. A 1px accent border
      // (matching _AddInstanceCard pattern) is unambiguous on a real
      // device. Without this, the user has no way to know the tap
      // registered.
      final orch = _TestOrchestrator();
      await tester.pumpWidget(
        _wrapWithOrchestrator(
          InstanceCard(instance: testInstance, onTap: () {}),
          orchestrator: orch,
        ),
      );

      AnimatedContainer readActionContainer() =>
          find
                  .byWidgetPredicate(_actionButtonContainerFor(Icons.refresh))
                  .evaluate()
                  .single
                  .widget
              as AnimatedContainer;

      // Idle: no border, surface2 background.
      final idle = readActionContainer();
      expect(idle.decoration, isA<BoxDecoration>());
      expect(
        (idle.decoration as BoxDecoration).border,
        isNull,
        reason: 'Idle state must not have a border (avoids 1px layout shift)',
      );
      expect(
        (idle.decoration as BoxDecoration).color,
        equals(XiaColors.surface2),
      );

      // Press: 1px accent border.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.refresh)),
      );
      await tester.pump(
        XiaMotion.durationFast + const Duration(milliseconds: 50),
      );

      final pressed = readActionContainer();
      final pressedBorder =
          (pressed.decoration as BoxDecoration).border as Border;
      expect(
        pressedBorder.top.color,
        equals(XiaColors.accent),
        reason: 'Pressed state must show accent (bright blue) border',
      );

      await gesture.up();
    });

    testWidgets('delete button shows red border on press', (tester) async {
      // The danger variant must also get a clearly visible feedback signal
      // (red border, not just a tiny scale change). Before the fix, the
      // delete button had zero press feedback.
      await tester.pumpWidget(
        _wrap(
          InstanceCard(instance: testInstance, onTap: () {}, onDelete: () {}),
        ),
      );

      AnimatedContainer readActionContainer() =>
          find
                  .byWidgetPredicate(
                    _actionButtonContainerFor(Icons.delete_outline),
                  )
                  .evaluate()
                  .single
                  .widget
              as AnimatedContainer;

      final idle = readActionContainer();
      expect(
        (idle.decoration as BoxDecoration).border,
        isNull,
        reason: 'Idle state must not have a border (avoids 1px layout shift)',
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.delete_outline)),
      );
      await tester.pump(
        XiaMotion.durationFast + const Duration(milliseconds: 50),
      );

      final pressed = readActionContainer();
      final pressedBorder =
          (pressed.decoration as BoxDecoration).border as Border;
      expect(
        pressedBorder.top.color,
        equals(XiaColors.red),
        reason: 'Pressed delete button must show red border',
      );

      await gesture.up();
    });

    // ========================================================================
    // Bug #4 regression — AnimatedScale 0.97 on press
    // ========================================================================
    //
    // PressFeedback in `builder:` mode IGNORES its own `scale` parameter
    // (press_feedback_buttons.dart:120-149).  The _ActionBtn wraps the
    // AnimatedContainer in an explicit AnimatedScale to restore the
    // tactile press feedback that the spec requires.  Without this wrapper,
    // the 36×36 button has only border / color feedback, imperceptible
    // on dark OLED or bright sunlight.
    //
    // These two tests guard the scale wrapper so a future refactor that
    // drops the AnimatedScale (or moves back to non-builder PressFeedback
    // without re-asserting the scale) cannot silently regress.

    testWidgets(
      'refresh button wraps AnimatedContainer in AnimatedScale (Bug #4)',
      (tester) async {
        final orch = _TestOrchestrator();
        await tester.pumpWidget(
          _wrapWithOrchestrator(
            InstanceCard(instance: testInstance, onTap: () {}),
            orchestrator: orch,
          ),
        );

        AnimatedScale readActionScale() =>
            find
                    .byWidgetPredicate(_actionButtonScaleFor(Icons.refresh))
                    .evaluate()
                    .single
                    .widget
                as AnimatedScale;

        // Idle: scale must be 1.0 — no visual shrink at rest.
        final idle = readActionScale();
        expect(
          idle.scale,
          equals(1.0),
          reason: 'Idle AnimatedScale must be 1.0 (no shrink at rest)',
        );

        // Press: scale must shrink to 0.97.
        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.refresh)),
        );
        await tester.pump(
          XiaMotion.durationFast + const Duration(milliseconds: 50),
        );

        final pressed = readActionScale();
        expect(
          pressed.scale,
          equals(0.97),
          reason:
              'Pressed AnimatedScale must be 0.97 — restores tactile '
              'press feedback that the 36×36 button needs (border / color '
              'alone is imperceptible on dark OLED / bright sunlight).',
        );

        await gesture.up();
      },
    );

    testWidgets(
      'delete button wraps AnimatedContainer in AnimatedScale (Bug #4)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            InstanceCard(instance: testInstance, onTap: () {}, onDelete: () {}),
          ),
        );

        AnimatedScale readActionScale() =>
            find
                    .byWidgetPredicate(
                      _actionButtonScaleFor(Icons.delete_outline),
                    )
                    .evaluate()
                    .single
                    .widget
                as AnimatedScale;

        final idle = readActionScale();
        expect(idle.scale, equals(1.0));

        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.delete_outline)),
        );
        await tester.pump(
          XiaMotion.durationFast + const Duration(milliseconds: 50),
        );

        final pressed = readActionScale();
        expect(
          pressed.scale,
          equals(0.97),
          reason: 'Delete button must also have 0.97 scale on press',
        );

        await gesture.up();
      },
    );
  });
}
