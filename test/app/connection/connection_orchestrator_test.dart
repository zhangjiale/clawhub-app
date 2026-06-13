import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/connection/connection_orchestrator.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/data/repositories/in_memory_repos.dart';
import 'package:claw_hub/domain/models/models.dart';

/// Fake IGatewayClient that records how many times connect() / fetchAgents()
/// was called per instance and never actually opens a socket.
///
/// Complies with Iron Law 16.B: internal state machine side effects
/// (connect → fetchAgents → syncFromGateway) must be verifiable via
/// Fake injection + call-count assertions.
///
/// Supports three emission modes via constructor params:
/// - **[pairingOnConnect]** (covering blind spot): emits `pairingRequired`
///   after `connecting`, simulating the real ConnectionManager's NOT_PAIRED
///   flow. A [pairingRequestId] can be provided for pairing info assertions.
///   Use [approveAndConnect] later to simulate server-side approval.
/// - **[synchronousEvents]** = true: emits inside connect(), matching real
///   WsGatewayClient timing. Catches "subscribe too late" bugs.
/// - **[synchronousEvents]** = false (legacy): defers via Future().
class _FakeGatewayClient implements IGatewayClient {
  final Map<String, int> connectCounts = {};
  final Map<String, int> fetchAgentsCounts = {};
  final Map<String, StreamController<GatewayConnectionState>> _stateCtrls = {};
  final bool _synchronousEvents;

  /// When true, connect() emits `pairingRequired` instead of `connected`.
  final bool _pairingOnConnect;
  final String _pairingRequestId;

  /// Agents to return from fetchAgents (instanceId → agents).
  final Map<String, List<Agent>> _stubAgents;

  /// instanceId → pairing info stream controller (for approveAndConnect).
  final Map<String, StreamController<GatewayPairingInfo?>> _pairingCtrls = {};

  _FakeGatewayClient({
    Map<String, List<Agent>> stubAgents = const {},
    bool synchronousEvents = false,
    bool pairingOnConnect = false,
    String pairingRequestId = 'req-test-001',
  }) : _stubAgents = stubAgents,
       _synchronousEvents = synchronousEvents,
       _pairingOnConnect = pairingOnConnect,
       _pairingRequestId = pairingRequestId;

  @override
  Future<void> connect(Instance instance) async {
    connectCounts[instance.id] = (connectCounts[instance.id] ?? 0) + 1;

    final ctrl = _stateCtrls.putIfAbsent(
      instance.id,
      () => StreamController<GatewayConnectionState>.broadcast(),
    );

    void emitConnecting() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connecting);
    }

    void emitConnected() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connected);
    }

    void emitPairingRequired() {
      if (!ctrl.isClosed) {
        ctrl.add(GatewayConnectionState.pairingRequired);
      }
      // Also emit pairing info so orchestrator's _onPairingInfo fires
      final pCtrl = _pairingCtrls.putIfAbsent(
        instance.id,
        () => StreamController<GatewayPairingInfo?>.broadcast(),
      );
      if (!pCtrl.isClosed) {
        pCtrl.add(
          GatewayPairingInfo(
            requestId: _pairingRequestId,
            deviceId: 'device-test-001',
          ),
        );
      }
    }

    if (_synchronousEvents) {
      // Emit connecting then connected synchronously inside connect(),
      // matching the real WsGatewayClient timing where both events fire
      // during the await manager.connect() call.
      //
      // No delay between events: emitConnecting is handled as a non-terminal
      // state (immediate no-op return in _onConnectionStateChanged), so there
      // is no race or ordering dependency that requires a wall-clock gap.
      emitConnecting();
      if (_pairingOnConnect) {
        emitPairingRequired();
      } else {
        emitConnected();
      }
    } else {
      Future(emitConnecting);
      if (_pairingOnConnect) {
        Future(emitPairingRequired);
      } else {
        Future(emitConnected);
      }
    }
  }

  /// Simulate server-side approval: emit `connected` on the state stream
  /// and clear pairing info, mimicking ConnectionManager._handleConnectResponse
  /// after a successful pairing retry.
  void approveAndConnect(String instanceId) {
    final ctrl = _stateCtrls[instanceId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(GatewayConnectionState.connecting);
      ctrl.add(GatewayConnectionState.connected);
    }
    final pCtrl = _pairingCtrls[instanceId];
    if (pCtrl != null && !pCtrl.isClosed) {
      pCtrl.add(null); // clear pairing info
    }
  }

  @override
  Future<void> disconnect(String instanceId) async {}

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) => throw UnimplementedError();

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async {
    fetchAgentsCounts[instanceId] = (fetchAgentsCounts[instanceId] ?? 0) + 1;
    return _stubAgents[instanceId] ?? <Agent>[];
  }

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) => throw UnimplementedError();

  @override
  Future<bool> testConnection(Instance instance) async => true;

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) {
    return _stateCtrls
        .putIfAbsent(
          instanceId,
          () => StreamController<GatewayConnectionState>.broadcast(),
        )
        .stream;
  }

  @override
  void resetConnectionState(String instanceId) {}

  @override
  Stream<Message> messageStream(String instanceId) =>
      throw UnimplementedError();

  @override
  Stream<ToolCall> toolCallStream(String instanceId) =>
      throw UnimplementedError();

  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId) {
    return _pairingCtrls
        .putIfAbsent(
          instanceId,
          () => StreamController<GatewayPairingInfo?>.broadcast(),
        )
        .stream;
  }

  @override
  Future<void> dispose() async {
    for (final ctrl in _stateCtrls.values) {
      await ctrl.close();
    }
    for (final ctrl in _pairingCtrls.values) {
      await ctrl.close();
    }
  }
}

/// Helper to create an Agent with minimal required fields.
Agent _agent(String localId, String instanceId, String name) {
  return Agent(
    localId: localId,
    remoteId: 'r-$localId',
    instanceId: instanceId,
    name: name,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionOrchestrator', () {
    late InMemoryInstanceRepo instanceRepo;
    late InMemoryAgentRepo agentRepo;
    late _FakeGatewayClient gatewayClient;
    late ConnectionOrchestrator orchestrator;

    setUp(() {
      instanceRepo = InMemoryInstanceRepo();
      agentRepo = InMemoryAgentRepo();
      gatewayClient = _FakeGatewayClient();
      orchestrator = ConnectionOrchestrator(
        gatewayClient: gatewayClient,
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
      );
    });

    tearDown(() async {
      await orchestrator.dispose();
    });

    // -----------------------------------------------------------------------
    // Existing tests (preserved)
    // -----------------------------------------------------------------------

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

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(gatewayClient.connectCounts['inst-1'], 1);
    });

    test('calls gateway.connect even for offline instance', () async {
      final instance = Instance(
        id: 'inst-1',
        name: 'Test',
        gatewayUrl: 'ws://test:18789',
        tokenRef: 'token',
        healthStatus: HealthStatus.offline,
      );
      await instanceRepo.save(instance);

      await orchestrator.onInstanceSaved(instance);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 即使 healthStatus=offline，也应尝试建连 —
      // ConnectionManager 的自动重连机制会在连接成功后把 DB 更新为 online。
      expect(gatewayClient.connectCounts['inst-1'], 1);
    });

    test(
      'reconnects when onInstanceSaved is called twice (no _connecting leak)',
      () async {
        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'ws://test:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.online,
        );
        await instanceRepo.save(instance);

        await orchestrator.onInstanceSaved(instance);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          gatewayClient.connectCounts['inst-1'],
          1,
          reason: 'First save should trigger connect',
        );

        final edited = instance.copyWith(
          name: 'Test Updated',
          healthStatus: HealthStatus.online,
        );
        await instanceRepo.save(edited);

        await orchestrator.onInstanceSaved(edited);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          gatewayClient.connectCounts['inst-1'],
          2,
          reason: 'Second save should trigger reconnect (no _connecting leak)',
        );
      },
    );

    test('intermediate state (connecting) does NOT overwrite online '
        'health status', () async {
      final instance = Instance(
        id: 'inst-1',
        name: 'Test',
        gatewayUrl: 'ws://test:18789',
        tokenRef: 'token',
        healthStatus: HealthStatus.online,
      );
      await instanceRepo.save(instance);

      await orchestrator.onInstanceSaved(instance);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final current = await instanceRepo.getById('inst-1');
      expect(
        current?.healthStatus,
        HealthStatus.online,
        reason: 'Intermediate connecting state must not overwrite online',
      );
    });

    // -----------------------------------------------------------------------
    // NEW: Law 16.B — verify state-machine side effects
    // -----------------------------------------------------------------------

    test(
      'connected state triggers fetchAgents and syncs agents to repo',
      () async {
        // Configure fake to return stub agents so we can verify DB sync
        final gateway = _FakeGatewayClient(
          stubAgents: {
            'inst-1': [
              _agent('local-1', 'inst-1', '产品虾'),
              _agent('local-2', 'inst-1', '代码虾'),
            ],
          },
        );
        final orch = ConnectionOrchestrator(
          gatewayClient: gateway,
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
        );
        addTearDown(() => orch.dispose());

        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.online,
        );
        await instanceRepo.save(instance);

        await orch.onInstanceSaved(instance);
        // Allow microtasks: connecting → connected → _syncAgentsForInstance
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Side-effect 1: fetchAgents must have been called
        expect(
          gateway.fetchAgentsCounts['inst-1'],
          1,
          reason:
              'Connected state must trigger agents.list RPC '
              '(fetchAgents was silently skipped before the fix)',
        );

        // Side-effect 2: agents must be synced to local DB
        final agents = await agentRepo.getByInstanceId('inst-1');
        expect(
          agents.length,
          2,
          reason: 'fetchAgents result must be persisted via syncFromGateway',
        );
        expect(agents.map((a) => a.name), containsAll(['产品虾', '代码虾']));
      },
    );

    test(
      'offline instance connects and syncs agents on successful connection',
      () async {
        final gateway = _FakeGatewayClient(
          stubAgents: {
            'inst-1': [_agent('local-1', 'inst-1', '产品虾')],
          },
        );
        final orch = ConnectionOrchestrator(
          gatewayClient: gateway,
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
        );
        addTearDown(() => orch.dispose());

        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'ws://test:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.offline,
        );
        await instanceRepo.save(instance);

        await orch.onInstanceSaved(instance);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // 修复后：即使 healthStatus=offline，onInstanceSaved 也会调用 _connect()，
        // 连接成功后 _onConnectionStateChanged 自动触发 agent 同步。
        expect(
          gateway.fetchAgentsCounts['inst-1'],
          1,
          reason:
              'Even when saved as offline, a successful connection '
              'should trigger agent sync',
        );
        expect(gateway.connectCounts['inst-1'], 1);
      },
    );

    test(
      '_syncingAgents guard marks pending retry on concurrent connected event',
      () async {
        // Use a Completer to hold fetchAgents open, simulating slow Gateway
        final fetchStarted = Completer<void>();
        final fetchBlocker = Completer<void>();
        final gateway = _BlockingFetchGateway(
          fetchStarted: fetchStarted,
          fetchBlocker: fetchBlocker,
        );
        final orch = ConnectionOrchestrator(
          gatewayClient: gateway,
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
        );
        addTearDown(() => orch.dispose());

        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.online,
        );
        await instanceRepo.save(instance);

        // Trigger first connect — agent sync will block on fetchBlocker
        // after the Future() events fire (connecting → connected)
        final firstSave = orch.onInstanceSaved(instance);

        // Drain the event queue so that:
        // 1. _FakeGatewayClient.connect() fires connecting/connected events
        // 2. The orchestrator's listener calls _syncAgentsForInstance
        // 3. Which enters fetchAgents and blocks on fetchBlocker
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Wait for fetchAgents to be entered
        await fetchStarted.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('fetchAgents was never entered'),
        );

        // While the first sync is still in-flight, pump another connected
        // event. The _syncingAgents guard prevents a concurrent fetchAgents,
        // but marks _syncPendingRetry so the next sync includes fresh data.
        gateway.addConnectedEvent('inst-1');

        // Allow the second connected event to be processed by orchestrator
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Release blocker to allow first sync to complete
        fetchBlocker.complete();
        await firstSave;
        // Wait for the pending retry to also complete
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // First call (guarded) + one retry from _syncPendingRetry
        expect(
          gateway.fetchAgentsCounts['inst-1'],
          2,
          reason:
              'First sync completes, then the pending retry from the second '
              'connected event triggers a fresh sync',
        );
      },
    );

    // -----------------------------------------------------------------
    // _syncPendingRetry: failure recovery & lock safety
    // -----------------------------------------------------------------

    test(
      'pending retry fires after first cycle partially fails (do-while)',
      () async {
        // Gateway that fails on the FIRST call (attempt 0 in cycle 1),
        // then succeeds.  Verifies the do-while loop after a
        // partially-failed for-loop.
        final gateway = _FailsThenSucceedsGateway(
          failOnCalls: {1}, // fail the very first fetchAgents call
        );
        final orch = ConnectionOrchestrator(
          gatewayClient: gateway,
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
        );
        addTearDown(() => orch.dispose());

        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.online,
        );
        await instanceRepo.save(instance);

        // Trigger connect → connected → _syncAgentsForInstance.
        orch.onInstanceSaved(instance);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // While first cycle is in its 5s retry delay, inject a
        // pending retry from a new connected event.
        gateway.addConnectedEvent('inst-1');
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Wait for the 5s retry delay + second cycle to complete
        await Future<void>.delayed(const Duration(milliseconds: 5200));

        // Call 1 (fail) + Call 2 (cycle-1 retry success) +
        // Call 3 (cycle-2 from pending retry, success) = 3 total
        expect(
          gateway.fetchAgentsCounts['inst-1'],
          3,
          reason:
              'After first call fails and retry succeeds, the do-while '
              'must pick up the pending retry from the connected event '
              'and run a second sync cycle.',
        );
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      '_syncingAgents lock is released after all retries exhausted',
      () async {
        // Gateway that fails on every call.  Sync exhausts its 3
        // attempts (5s + 10s delays).  After it finishes, the lock
        // must be released so a fresh sync can run.
        final gateway = _FailsThenSucceedsGateway(
          failOnCalls: {1, 2, 3, 4, 5, 6},
        );
        final orch = ConnectionOrchestrator(
          gatewayClient: gateway,
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
        );
        addTearDown(() => orch.dispose());

        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.online,
        );
        await instanceRepo.save(instance);

        // Start sync — all 3 attempts will fail
        orch.onInstanceSaved(instance);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Wait for all retry delays to complete (5s + 10s)
        await Future<void>.delayed(const Duration(milliseconds: 15200));

        expect(gateway.fetchAgentsCounts['inst-1'], 3);

        // Allow subsequent calls to succeed and verify lock was freed
        gateway.failOnCalls.clear();
        gateway.addConnectedEvent('inst-1');
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(
          gateway.fetchAgentsCounts['inst-1'],
          4,
          reason:
              'After exhausting all retries, the _syncingAgents lock '
              'must be released so a fresh sync can acquire it. '
              'If still 3, the lock leaked and the guard blocked the '
              'new sync.',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'do-while exits after maxLoops to release lock during WebSocket flap',
      () async {
        // Gateway that blocks each fetchAgents call on a separate
        // Completer so the test can inject _syncPendingRetry entries
        // between loop iterations without real retry delays.
        final gateway = _CyclicBlockGateway(blockCount: 3);
        final orch = ConnectionOrchestrator(
          gatewayClient: gateway,
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
        );
        addTearDown(() => orch.dispose());

        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.online,
        );
        await instanceRepo.save(instance);

        // --- Loop 1: start sync, block, inject pending retry, release ---
        orch.onInstanceSaved(instance);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Inject a connected event while fetchAgents is blocked;
        // the guard marks _syncPendingRetry.
        gateway.addConnectedEvent('inst-1');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Release → sync succeeds → do-while sees pending retry → loops
        gateway.releaseCall(0);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // --- Loop 2: block again, inject another pending retry ---
        gateway.addConnectedEvent('inst-1');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        gateway.releaseCall(1);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // --- Loop 3: block again, inject another pending retry ---
        // (loopCount reaches maxLoops=3)
        gateway.addConnectedEvent('inst-1');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        gateway.releaseCall(2);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // After 3 loops the do-while must exit, even though
        // _syncPendingRetry was populated during the last loop.
        // With maxLoops=3, exactly 3 fetchAgents calls were made.
        expect(
          gateway.fetchAgentsCounts['inst-1'],
          3,
          reason:
              'do-while must exit after maxLoops (3) iterations, '
              'even with pending retries still arriving',
        );

        // --- Lock released: a fresh sync can now acquire it ---
        gateway.addConnectedEvent('inst-1');
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(
          gateway.fetchAgentsCounts['inst-1'],
          4,
          reason:
              'After the cap released the lock, a new connected event '
              'must be able to start a fresh sync. If still 3, the '
              '_syncingAgents lock leaked.',
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    // -------------------------------------------------------------------
    // Timing-sensitive: synchronous events (matching real WsGatewayClient)
    // -------------------------------------------------------------------

    test('receives sync when events fire synchronously during connect() '
        '(matching real WsGatewayClient timing)', () async {
      // synchronousEvents: true → events emit inside connect(), before
      // the method returns.  This is how the real WsGatewayClient works:
      // the WebSocket handshake completes and connected is emitted
      // during the await manager.connect() call.
      final gateway = _FakeGatewayClient(
        synchronousEvents: true,
        stubAgents: {
          'inst-1': [_agent('local-1', 'inst-1', '产品虾')],
        },
      );
      final orch = ConnectionOrchestrator(
        gatewayClient: gateway,
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
      );
      addTearDown(() => orch.dispose());

      final instance = Instance(
        id: 'inst-1',
        name: 'Test',
        gatewayUrl: 'wss://test.com:18789',
        tokenRef: 'token',
        healthStatus: HealthStatus.online,
      );
      await instanceRepo.save(instance);

      await orch.onInstanceSaved(instance);
      // The synchronous connected event already fired during connect().
      // Give time for _syncAgentsForInstance to complete.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        gateway.fetchAgentsCounts['inst-1'],
        1,
        reason:
            'Even when connected fires synchronously inside connect() '
            '(matching real WsGatewayClient behavior), the orchestrator '
            'must receive it because it subscribes BEFORE calling connect(). '
            'Before the subscribe-before-connect fix, the event was emitted '
            'before the listener was registered and this assertion failed.',
      );
    });

    // -----------------------------------------------------------------------
    // Blind-spot coverage: pairingRequired persistence & restart deadlock
    // -----------------------------------------------------------------------

    group('pairingRequired persistence (blind-spot fix)', () {
      test('pairingRequired state persists as offline in DB, '
          'NOT as pairingRequired', () async {
        final gateway = _FakeGatewayClient(
          pairingOnConnect: true,
          pairingRequestId: 'req-deadlock-01',
        );
        final orch = ConnectionOrchestrator(
          gatewayClient: gateway,
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
        );
        addTearDown(() => orch.dispose());

        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.online,
        );
        await instanceRepo.save(instance);

        await orch.onInstanceSaved(instance);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final saved = await instanceRepo.getById('inst-1');
        expect(saved, isNotNull);
        // The key assertion: pairingRequired must NOT leak into DB.
        // It should be stored as offline, matching the enum comment.
        expect(
          saved!.healthStatus,
          HealthStatus.offline,
          reason:
              'pairingRequired must be persisted as offline. '
              'If persisted as pairingRequired (value=5), on next app '
              'startup initialize() skips the instance (isConnectable=false) '
              'and the ConnectionManager pairing retry loop is never '
              're-established → permanent deadlock.',
        );
      });

      test('pairingRequired persists as offline and connects after simulated '
          'approval (approveAndConnect)', () async {
        final gateway = _FakeGatewayClient(
          pairingOnConnect: true,
          pairingRequestId: 'req-approve-02',
        );
        final orch = ConnectionOrchestrator(
          gatewayClient: gateway,
          instanceRepo: instanceRepo,
          agentRepo: agentRepo,
        );
        addTearDown(() => orch.dispose());

        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.online,
        );
        await instanceRepo.save(instance);

        // Step 1: connect → pairingRequired → DB = offline
        await orch.onInstanceSaved(instance);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          (await instanceRepo.getById('inst-1'))!.healthStatus,
          HealthStatus.offline,
        );

        // Step 2: simulate server-side approval
        gateway.approveAndConnect('inst-1');
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Step 3: DB should now be online
        expect(
          (await instanceRepo.getById('inst-1'))!.healthStatus,
          HealthStatus.online,
          reason:
              'After approval, the connected event should update DB '
              'from offline → online.',
        );
      });
    });

    group('initialize() startup reconnect (blind-spot fix)', () {
      test('initialize() calls connect() for offline instances', () async {
        final offlineInstance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.offline,
        );
        await instanceRepo.save(offlineInstance);

        await orchestrator.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // initialize() must attempt to connect offline instances —
        // they may have been pairingRequired→offline, and approval
        // may have happened during app downtime.
        expect(
          gatewayClient.connectCounts['inst-1'],
          1,
          reason:
              'initialize() must reconnect offline instances. '
              'Before the fix, offline.isConnectable==false caused '
              'these instances to be permanently skipped on restart.',
        );
      });

      test('initialize() calls connect() when DB has pairingRequired '
          '(legacy data backward compat)', () async {
        // Simulate legacy DB state: an instance with pairingRequired (5)
        // persisted before the fix was deployed.
        final legacyInstance = Instance(
          id: 'inst-1',
          name: 'Legacy',
          gatewayUrl: 'wss://legacy.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.pairingRequired,
        );
        await instanceRepo.save(legacyInstance);

        await orchestrator.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Even legacy pairingRequired data should trigger a reconnect
        // attempt. pairingRequired.isConnectable is false, but
        // initialize()'s broader filter catches it.
        expect(
          gatewayClient.connectCounts['inst-1'],
          1,
          reason:
              'Legacy DB rows with pairingRequired (value=5) must '
              'still trigger a reconnect on startup.',
        );
      });

      test(
        'initialize() does NOT reconnect expectedOffline instances',
        () async {
          final expectedOfflineInstance = Instance(
            id: 'inst-1',
            name: 'LAN Server',
            gatewayUrl: 'wss://lan.local:18789',
            tokenRef: 'token',
            healthStatus: HealthStatus.expectedOffline,
            isLocalNetwork: true,
          );
          await instanceRepo.save(expectedOfflineInstance);

          await orchestrator.initialize();
          await Future<void>.delayed(const Duration(milliseconds: 100));

          expect(
            gatewayClient.connectCounts['inst-1'],
            isNull,
            reason:
                'expectedOffline instances must wait for WiFi recovery, '
                'not reconnect on initialize().',
          );
        },
      );

      test(
        'initialize() reconnects multiple offline instances in parallel',
        () async {
          for (int i = 0; i < 3; i++) {
            await instanceRepo.save(
              Instance(
                id: 'inst-$i',
                name: 'Offline $i',
                gatewayUrl: 'wss://test-$i.com:18789',
                tokenRef: 'token',
                healthStatus: HealthStatus.offline,
              ),
            );
          }

          await orchestrator.initialize();
          await Future<void>.delayed(const Duration(milliseconds: 100));

          // All 3 offline instances must be reconnected.
          for (int i = 0; i < 3; i++) {
            expect(
              gatewayClient.connectCounts['inst-$i'],
              1,
              reason: 'inst-$i was offline, should be reconnected on startup',
            );
          }
        },
      );
    });

    group('reconnect() public API', () {
      test('reconnect() calls _connect() and gateway.connect()', () async {
        final instance = Instance(
          id: 'inst-1',
          name: 'Test',
          gatewayUrl: 'wss://test.com:18789',
          tokenRef: 'token',
          healthStatus: HealthStatus.offline,
        );
        await instanceRepo.save(instance);

        await orchestrator.reconnect(instance);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          gatewayClient.connectCounts['inst-1'],
          1,
          reason:
              'reconnect() must trigger a gateway connection attempt. '
              'This is the code path wired to the instance card refresh '
              'button — before the fix, the button was a no-op.',
        );
      });

      test(
        'reconnect() works even when already connecting (dedup safe)',
        () async {
          final gateway = _FakeGatewayClient(pairingOnConnect: true);
          final orch = ConnectionOrchestrator(
            gatewayClient: gateway,
            instanceRepo: instanceRepo,
            agentRepo: agentRepo,
          );
          addTearDown(() => orch.dispose());

          final instance = Instance(
            id: 'inst-1',
            name: 'Test',
            gatewayUrl: 'wss://test.com:18789',
            tokenRef: 'token',
            healthStatus: HealthStatus.online,
          );
          await instanceRepo.save(instance);

          // Rapid double-tap on refresh button
          await orch.reconnect(instance);
          await orch.reconnect(instance); // must not throw or deadlock
          await Future<void>.delayed(const Duration(milliseconds: 100));

          // The _connecting guard should prevent duplicate connect() calls.
          // Since synchronousEvents=false and pairingOnConnect=true, the
          // first call hasn't finished when the second arrives.
          // Regardless of dedup, at least 1 call must have fired.
          expect(gateway.connectCounts['inst-1'], greaterThanOrEqualTo(1));
        },
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Specialized fake for testing the _syncingAgents guard
// ---------------------------------------------------------------------------

class _BlockingFetchGateway implements IGatewayClient {
  final Completer<void> fetchStarted;
  final Completer<void> fetchBlocker;
  final Map<String, int> fetchAgentsCounts = {};
  final Map<String, int> connectCounts = {};
  final Map<String, StreamController<GatewayConnectionState>> _stateCtrls = {};

  _BlockingFetchGateway({
    required this.fetchStarted,
    required this.fetchBlocker,
  });

  @override
  Future<void> connect(Instance instance) async {
    connectCounts[instance.id] = (connectCounts[instance.id] ?? 0) + 1;
    final ctrl = _stateCtrls.putIfAbsent(
      instance.id,
      () => StreamController<GatewayConnectionState>.broadcast(),
    );
    // Use Future() (event queue) instead of Future.microtask so the
    // stream subscription is guaranteed to be set up before events fire.
    // If we used microtask, the events would fire during the await
    // continuation gap before the .listen() call registers the handler.
    Future(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connecting);
    });
    Future(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connected);
    });
  }

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async {
    fetchAgentsCounts[instanceId] = (fetchAgentsCounts[instanceId] ?? 0) + 1;

    // Signal that fetchAgents has been entered
    if (!fetchStarted.isCompleted) fetchStarted.complete();

    // Block until the test releases us
    await fetchBlocker.future;
    return [
      Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: instanceId,
        name: '测试虾',
      ),
    ];
  }

  @override
  Future<void> disconnect(String id) async {}
  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) => throw UnimplementedError();
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
  Stream<GatewayConnectionState> connectionStateStream(String id) {
    return _stateCtrls
        .putIfAbsent(
          id,
          () => StreamController<GatewayConnectionState>.broadcast(),
        )
        .stream;
  }

  @override
  void resetConnectionState(String id) {}
  @override
  Stream<Message> messageStream(String id) => throw UnimplementedError();
  @override
  Stream<ToolCall> toolCallStream(String id) => throw UnimplementedError();
  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String id) =>
      Stream.value(null);

  /// Helper for tests: emit an extra connected event on the instance's stream.
  void addConnectedEvent(String instanceId) {
    final ctrl = _stateCtrls[instanceId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(GatewayConnectionState.connected);
    }
  }

  @override
  Future<void> dispose() async {
    for (final c in _stateCtrls.values) {
      await c.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Specialized fake for testing _syncPendingRetry failure recovery
// ---------------------------------------------------------------------------

/// Gateway that throws on fetchAgents calls whose 1-based index is in
/// [failOnCalls] and succeeds otherwise.  Emits connecting/connected
/// events like [_FakeGatewayClient], and exposes [addConnectedEvent]
/// so tests can inject extra connected events to create pending retries.
class _FailsThenSucceedsGateway implements IGatewayClient {
  /// 1-based call indices on which fetchAgents should throw.
  Set<int> failOnCalls;
  int _callIndex = 0;
  final Map<String, int> fetchAgentsCounts = {};
  final Map<String, int> connectCounts = {};
  final Map<String, StreamController<GatewayConnectionState>> _stateCtrls = {};
  final Map<String, StreamController<GatewayPairingInfo?>> _pairingCtrls = {};

  _FailsThenSucceedsGateway({Set<int>? failOnCalls})
    : failOnCalls = failOnCalls ?? <int>{};

  @override
  Future<void> connect(Instance instance) async {
    connectCounts[instance.id] = (connectCounts[instance.id] ?? 0) + 1;
    final ctrl = _stateCtrls.putIfAbsent(
      instance.id,
      () => StreamController<GatewayConnectionState>.broadcast(),
    );
    Future(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connecting);
    });
    Future(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connected);
    });
  }

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async {
    fetchAgentsCounts[instanceId] = (fetchAgentsCounts[instanceId] ?? 0) + 1;
    _callIndex++;

    if (failOnCalls.contains(_callIndex)) {
      throw Exception('Simulated fetchAgents failure (call $_callIndex)');
    }
    return [
      Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: instanceId,
        name: '测试虾($_callIndex)',
      ),
    ];
  }

  @override
  Future<void> disconnect(String id) async {}
  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) => throw UnimplementedError();
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
  Stream<GatewayConnectionState> connectionStateStream(String id) {
    return _stateCtrls
        .putIfAbsent(
          id,
          () => StreamController<GatewayConnectionState>.broadcast(),
        )
        .stream;
  }

  @override
  void resetConnectionState(String id) {}
  @override
  Stream<Message> messageStream(String id) => throw UnimplementedError();
  @override
  Stream<ToolCall> toolCallStream(String id) => throw UnimplementedError();
  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String id) {
    return _pairingCtrls
        .putIfAbsent(
          id,
          () => StreamController<GatewayPairingInfo?>.broadcast(),
        )
        .stream;
  }

  void addConnectedEvent(String instanceId) {
    final ctrl = _stateCtrls[instanceId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(GatewayConnectionState.connected);
    }
  }

  @override
  Future<void> dispose() async {
    for (final c in _stateCtrls.values) {
      await c.close();
    }
    for (final c in _pairingCtrls.values) {
      await c.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Specialized fake for testing the do-while maxLoops cap
// ---------------------------------------------------------------------------

/// Gateway that blocks each fetchAgents call on a separate [Completer],
/// letting the test inject [_syncPendingRetry] entries between loop
/// iterations without real retry delays.
class _CyclicBlockGateway implements IGatewayClient {
  final List<Completer<void>> _blockers;
  int _callIndex = 0;
  final Map<String, int> fetchAgentsCounts = {};
  final Map<String, StreamController<GatewayConnectionState>> _stateCtrls = {};

  _CyclicBlockGateway({required int blockCount})
    : _blockers = List.generate(blockCount, (_) => Completer<void>());

  /// Releases the n-th blocked fetchAgents call (0-based).
  void releaseCall(int callIndex) {
    _blockers[callIndex].complete();
  }

  @override
  Future<void> connect(Instance instance) async {
    final ctrl = _stateCtrls.putIfAbsent(
      instance.id,
      () => StreamController<GatewayConnectionState>.broadcast(),
    );
    Future(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connecting);
    });
    Future(() {
      if (!ctrl.isClosed) ctrl.add(GatewayConnectionState.connected);
    });
  }

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async {
    fetchAgentsCounts[instanceId] = (fetchAgentsCounts[instanceId] ?? 0) + 1;
    final index = _callIndex++;
    if (index < _blockers.length) {
      await _blockers[index].future;
    }
    return [
      Agent(
        localId: 'local-1',
        remoteId: 'r-1',
        instanceId: instanceId,
        name: '测试虾($index)',
      ),
    ];
  }

  void addConnectedEvent(String instanceId) {
    final ctrl = _stateCtrls[instanceId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(GatewayConnectionState.connected);
    }
  }

  @override
  Future<void> disconnect(String id) async {}
  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) => throw UnimplementedError();
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
  Stream<GatewayConnectionState> connectionStateStream(String id) {
    return _stateCtrls
        .putIfAbsent(
          id,
          () => StreamController<GatewayConnectionState>.broadcast(),
        )
        .stream;
  }

  @override
  void resetConnectionState(String id) {}
  @override
  Stream<Message> messageStream(String id) => throw UnimplementedError();
  @override
  Stream<ToolCall> toolCallStream(String id) => throw UnimplementedError();
  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String id) =>
      Stream.value(null);
  @override
  Future<void> dispose() async {
    for (final c in _stateCtrls.values) {
      await c.close();
    }
  }
}
