import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/models.dart';

/// Fake IGatewayClient that records how many times connect() was called
/// per instance and never actually opens a socket.
class _FakeGatewayClient implements IGatewayClient {
  final Map<String, int> connectCounts = {};
  final Map<String, StreamController<GatewayConnectionState>> _stateCtrls = {};

  @override
  Future<void> connect(Instance instance) async {
    connectCounts[instance.id] = (connectCounts[instance.id] ?? 0) + 1;

    // Emulate successful connection: emit connecting → connected
    final ctrl = _stateCtrls.putIfAbsent(
      instance.id,
      () => StreamController<GatewayConnectionState>.broadcast(),
    );
    // Fire-and-forget: pump states asynchronously so the orchestrator's
    // stream listener can pick them up.
    Future.microtask(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connecting);
    });
    Future.microtask(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connected);
    });
  }

  @override
  Future<void> disconnect(String instanceId) async {}

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Agent>> fetchAgents(String instanceId) => throw UnimplementedError();

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) =>
      throw UnimplementedError();

  @override
  Future<bool> testConnection(Instance instance) async => true;

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) {
    return _stateCtrls.putIfAbsent(
      instanceId,
      () => StreamController<GatewayConnectionState>.broadcast(),
    ).stream;
  }

  @override
  void resetConnectionState(String instanceId) {}

  @override
  Stream<Message> messageStream(String instanceId) => throw UnimplementedError();

  @override
  Stream<ToolCall> toolCallStream(String instanceId) =>
      throw UnimplementedError();

  @override
  Future<void> dispose() async {
    for (final ctrl in _stateCtrls.values) {
      await ctrl.close();
    }
  }
}

void main() {
  group('ConnectionOrchestrator', () {
    late InMemoryInstanceRepo instanceRepo;
    late _FakeGatewayClient gatewayClient;
    late ConnectionOrchestrator orchestrator;

    setUp(() {
      instanceRepo = InMemoryInstanceRepo();
      gatewayClient = _FakeGatewayClient();
      orchestrator = ConnectionOrchestrator(
        gatewayClient: gatewayClient,
        instanceRepo: instanceRepo,
      );
    });

    tearDown(() async {
      await orchestrator.dispose();
    });

    test('calls gateway.connect for online instance', () async {
      final instance = Instance(
        id: 'inst-1',
        name: 'Test',
        gatewayUrl: 'ws://test:18789',
        tokenRef: 'token',
        healthStatus: HealthStatus.online,
      );
      await instanceRepo.save(instance);

      await orchestrator.onInstanceSaved(instance);

      // Give time for microtasks to run (connect emits states)
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(gatewayClient.connectCounts['inst-1'], 1);
    });

    test('skips gateway.connect for offline instance', () async {
      final instance = Instance(
        id: 'inst-1',
        name: 'Test',
        gatewayUrl: 'ws://test:18789',
        tokenRef: 'token',
        healthStatus: HealthStatus.offline,
      );
      await instanceRepo.save(instance);

      await orchestrator.onInstanceSaved(instance);

      expect(gatewayClient.connectCounts['inst-1'], isNull);
    });

    test('reconnects when onInstanceSaved is called twice (no _connecting leak)',
        () async {
      final instance = Instance(
        id: 'inst-1',
        name: 'Test',
        gatewayUrl: 'ws://test:18789',
        tokenRef: 'token',
        healthStatus: HealthStatus.online,
      );
      await instanceRepo.save(instance);

      // First save — should connect
      await orchestrator.onInstanceSaved(instance);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(gatewayClient.connectCounts['inst-1'], 1,
          reason: 'First save should trigger connect');

      // Simulate re-save (e.g. user edited the instance)
      final edited = instance.copyWith(
        name: 'Test Updated',
        healthStatus: HealthStatus.online,
      );
      await instanceRepo.save(edited);

      await orchestrator.onInstanceSaved(edited);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Without the finally-block fix, this would still be 1
      // because _connecting was never cleared after the first success.
      expect(gatewayClient.connectCounts['inst-1'], 2,
          reason: 'Second save should trigger reconnect (no _connecting leak)');
    });
  });
}
