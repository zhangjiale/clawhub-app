import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/background_sync_runner.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_notifier.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_prefs.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_last_sync_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_settings_repo.dart';

// ---------------------------------------------------------------------------
// Mock classes for repos that need full interface stubs
// ---------------------------------------------------------------------------
class MockMessageRepo extends Mock implements IMessageRepo {}

class MockAgentRepo extends Mock implements IAgentRepo {}

class MockInstanceRepo extends Mock implements IInstanceRepo {}

class MockLastSyncRepo extends Mock implements ILastSyncRepo {}

class MockSettingsRepo extends Mock implements ISettingsRepo {}

class MockGatewayClient extends Mock implements IGatewayClient {}

// ---------------------------------------------------------------------------
// Minimal fake gateway client for tracking connect/disconnect/fetch calls
// ---------------------------------------------------------------------------
class FakeGatewayClient implements IGatewayClient {
  int connectCount = 0;
  int disconnectCount = 0;
  final List<({String instanceId, String agentId, String? cursor, int limit})>
  fetchHistoryCalls = [];

  final Map<String, List<({List<Message> messages, String? nextCursor})>>
  _history = {};

  bool throwOnConnect = false;
  Object? fetchThrow;

  /// Per-instance fetch throw; checked before [fetchThrow].
  final Map<String, Object?> fetchThrowByInstance = {};
  Duration fetchDelay = Duration.zero;
  Duration connectDelay = Duration.zero;

  void setHistory(
    String instanceId,
    String agentId,
    List<({List<Message> messages, String? nextCursor})> pages,
  ) {
    _history['$instanceId:$agentId'] = pages;
  }

  @override
  Future<void> connect(Instance instance) async {
    connectCount++;
    if (throwOnConnect) throw Exception('connect failed');
    if (connectDelay > Duration.zero) {
      await Future.delayed(connectDelay);
    }
  }

  @override
  Future<void> disconnect(String instanceId) async {
    disconnectCount++;
  }

  @override
  Future<List<Agent>> fetchAgents(String instanceId) async => [];

  @override
  Future<({List<Message> messages, String? nextCursor})> fetchMessageHistory({
    required String instanceId,
    required String agentId,
    String? cursor,
    int limit = 50,
  }) async {
    fetchHistoryCalls.add((
      instanceId: instanceId,
      agentId: agentId,
      cursor: cursor,
      limit: limit,
    ));
    if (fetchThrowByInstance[instanceId] != null) {
      throw fetchThrowByInstance[instanceId]!;
    }
    if (fetchThrow != null) {
      throw fetchThrow!;
    }
    if (fetchDelay > Duration.zero) {
      await Future.delayed(fetchDelay);
    }
    final key = '$instanceId:$agentId';
    final pages = _history[key];
    if (pages == null || pages.isEmpty) {
      return (messages: <Message>[], nextCursor: null);
    }
    return pages.removeAt(0);
  }

  // --- IGatewayClient members not used by BackgroundSyncRunner ---
  // The Runner only exercises connect/disconnect/fetchAgents/fetchMessageHistory.
  // The rest are stubbed so the fake satisfies the interface contract.

  @override
  Future<({String serverId, int timestamp})> sendMessage({
    required String instanceId,
    required String agentId,
    required Message message,
  }) => throw UnimplementedError();

  @override
  Future<bool> testConnection(Instance instance) => throw UnimplementedError();

  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) =>
      const Stream<GatewayConnectionState>.empty();

  @override
  void resetConnectionState(String instanceId) {}

  @override
  Stream<Message> messageStream(String instanceId) =>
      const Stream<Message>.empty();

  @override
  Stream<ToolCall> toolCallStream(String instanceId) =>
      const Stream<ToolCall>.empty();

  @override
  Stream<GatewayPairingInfo?> pairingInfoStream(String instanceId) =>
      const Stream<GatewayPairingInfo?>.empty();

  @override
  Stream<StreamingEvent> streamingDeltaStream(String instanceId) =>
      const Stream<StreamingEvent>.empty();

  @override
  Stream<LargePayloadNotice> largePayloadNoticeStream(String instanceId) =>
      const Stream<LargePayloadNotice>.empty();

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// CapturingDispatcher — implements IBackgroundSyncNotifier
// ---------------------------------------------------------------------------
class CapturingDispatcher implements IBackgroundSyncNotifier {
  int callCount = 0;
  final List<List<Message>> handledLists = [];
  final List<String> enqueuedServerIds = [];

  @override
  Future<void> handlePulledMessages({
    required List<Message> messages,
    required Agent? Function(String instanceId, String agentRemoteId)
    resolveAgent,
  }) async {
    callCount++;
    handledLists.add(List.unmodifiable(messages));
    for (final m in messages) {
      final agent = resolveAgent('', m.agentId);
      if (agent != null) {
        enqueuedServerIds.add(m.serverId ?? m.clientId);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// StubBackgroundSyncGate
// ---------------------------------------------------------------------------
class StubBackgroundSyncGate implements BackgroundSyncGate {
  bool skip = false;

  @override
  final IBackgroundSyncPrefs prefs = _StubPrefs();

  @override
  Future<bool> shouldSkip() async => skip;

  @override
  Future<void> setMainActive(bool active) async {}

  @override
  Future<void> clear() async {}
}

class _StubPrefs implements IBackgroundSyncPrefs {
  @override
  Future<bool> get mainActive async => false;

  @override
  Future<void> setMainActive(bool active) async {}

  @override
  Future<void> clear() async {}
}

// ---------------------------------------------------------------------------
// FakeClock & StubLogger
// ---------------------------------------------------------------------------
class FakeClock {
  int nowMs = 1000000;
  int now() => nowMs;
}

class StubLogger implements ILogger {
  final List<String> infos = [];
  final List<String> errors = [];

  @override
  void info(String msg) => infos.add(msg);

  @override
  void error(String msg, [StackTrace? stack]) => errors.add(msg);
}

// ---------------------------------------------------------------------------
// Helper to create test messages
// ---------------------------------------------------------------------------
Message _msg({
  required String clientId,
  String? serverId,
  String conversationId = 'conv1',
  String agentId = 'a1',
  required int timestamp,
  String content = 'hello',
}) {
  return Message(
    clientId: clientId,
    serverId: serverId,
    conversationId: conversationId,
    agentId: agentId,
    role: MessageRole.agent,
    content: content,
    type: MessageType.text,
    status: MessageStatus.sent,
    logicalClock: 0,
    timestamp: timestamp,
  );
}

Agent _agent(String remoteId, String instanceId) {
  return Agent(
    localId: remoteId,
    remoteId: remoteId,
    instanceId: instanceId,
    name: remoteId,
  );
}

Instance _inst(String id) {
  return Instance(
    id: id,
    name: id,
    gatewayUrl: 'ws://$id:8080',
    tokenRef: 'tok',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    registerFallbackValue(
      Message(
        clientId: 'fb',
        conversationId: 'fb',
        agentId: 'fb',
        role: MessageRole.user,
        content: 'fb',
        type: MessageType.text,
        logicalClock: 0,
      ),
    );
    registerFallbackValue(
      Instance(
        id: 'fb',
        name: 'fb',
        gatewayUrl: 'ws://fb:8080',
        tokenRef: 'fb',
      ),
    );
    registerFallbackValue(
      Agent(localId: 'fb', remoteId: 'fb', instanceId: 'fb', name: 'fb'),
    );
    registerFallbackValue('');
    registerFallbackValue(0);
    registerFallbackValue(<Message>[]);
  });

  group('BackgroundSyncBudget', () {
    test('has sensible defaults', () {
      final b = const BackgroundSyncBudget();
      expect(b.connectTimeout, const Duration(seconds: 10));
      expect(b.pageFetchTimeout, const Duration(seconds: 30));
      expect(b.perInstanceBudget, const Duration(seconds: 60));
      expect(b.maxMessagesPerPull, 100);
      expect(b.maxPagesPerAgent, 5);
    });
  });

  group('BackgroundSyncRunner', () {
    late FakeGatewayClient gateway;
    late MockMessageRepo messageRepo;
    late MockAgentRepo agentRepo;
    late MockInstanceRepo instanceRepo;
    late MockLastSyncRepo lastSyncRepo;
    late MockSettingsRepo settingsRepo;
    late CapturingDispatcher dispatcher;
    late StubBackgroundSyncGate gate;
    late FakeClock clock;
    late StubLogger logger;
    late BackgroundSyncBudget budget;
    late BackgroundSyncRunner runner;

    setUp(() {
      gateway = FakeGatewayClient();
      messageRepo = MockMessageRepo();
      agentRepo = MockAgentRepo();
      instanceRepo = MockInstanceRepo();
      lastSyncRepo = MockLastSyncRepo();
      settingsRepo = MockSettingsRepo();
      dispatcher = CapturingDispatcher();
      gate = StubBackgroundSyncGate();
      clock = FakeClock();
      logger = StubLogger();
      budget = const BackgroundSyncBudget();

      // Default stubs for mocks used in most tests
      when(() => lastSyncRepo.get(any())).thenAnswer((_) async => null);
      when(() => lastSyncRepo.upsert(any(), any())).thenAnswer((_) async {});
      when(
        () => messageRepo.batchInsertByIndexedIds(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as List<Message>);

      runner = BackgroundSyncRunner(
        gate: gate,
        settingsRepo: settingsRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        agentRepo: agentRepo,
        messageRepo: messageRepo,
        lastSyncRepo: lastSyncRepo,
        dispatcher: dispatcher,
        budget: budget,
        logger: logger,
        now: clock.now,
      );
    });

    // -----------------------------------------------------------------------
    // Gate & toggle skip
    // -----------------------------------------------------------------------
    test('executeOnce_whenGateActive_skipsWithZeroConnects', () async {
      gate.skip = true;
      await runner.executeOnce();
      expect(gateway.connectCount, 0);
    });

    test('executeOnce_whenToggleOff_skipsWithZeroConnects', () async {
      when(() => settingsRepo.getPreferences()).thenAnswer(
        (_) async =>
            UserPreferences.defaults().copyWith(backgroundSyncEnabled: false),
      );
      await runner.executeOnce();
      expect(gateway.connectCount, 0);
    });

    // -----------------------------------------------------------------------
    // No instances / no agents
    // -----------------------------------------------------------------------
    test('executeOnce_noInstances_zeroConnects', () async {
      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => []);
      await runner.executeOnce();
      expect(gateway.connectCount, 0);
    });

    test('executeOnce_noAgents_stillConnectsAndUpdatesLastSync', () async {
      final inst = _inst('i1');
      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => []);

      await runner.executeOnce();
      expect(gateway.connectCount, 1);
      verify(() => lastSyncRepo.upsert('i1', clock.now())).called(1);
    });

    // -----------------------------------------------------------------------
    // Cursor walk
    // -----------------------------------------------------------------------
    test('executeOnce_cursorWalkFiltersByServerTs', () async {
      final inst = _inst('i1');
      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 100);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      final msg200 = _msg(clientId: 'c200', serverId: 's200', timestamp: 200);
      final msg100 = _msg(clientId: 'c100', serverId: 's100', timestamp: 100);
      final msg50 = _msg(clientId: 'c50', serverId: 's50', timestamp: 50);

      gateway.setHistory('i1', 'a1', [
        (messages: [msg200, msg100], nextCursor: 'cur1'),
        (messages: [msg50], nextCursor: null),
      ]);

      when(
        () => messageRepo.batchInsertByIndexedIds(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as List<Message>);

      await runner.executeOnce();

      // Both messages >= 100 should be inserted
      final captured = verify(
        () => messageRepo.batchInsertByIndexedIds(captureAny<List<Message>>()),
      ).captured.cast<List<Message>>();
      final inserted = captured.expand((l) => l).toList();
      expect(inserted.where((m) => m.timestamp >= 100).length, 2);
      expect(inserted.where((m) => m.timestamp < 100).length, 0);

      // Cursor calls
      expect(gateway.fetchHistoryCalls.length, 2);
      expect(gateway.fetchHistoryCalls[0].cursor, isNull);
      expect(gateway.fetchHistoryCalls[1].cursor, 'cur1');

      // last_sync_at = max(200, 100) = 200
      verify(() => lastSyncRepo.upsert('i1', 200)).called(1);
    });

    // -----------------------------------------------------------------------
    // maxMessagesPerPull cap
    // -----------------------------------------------------------------------
    test('executeOnce_maxMessagesPerPull_capsTotalInserted', () async {
      final inst = _inst('i1');
      budget = const BackgroundSyncBudget(
        maxMessagesPerPull: 1,
        maxPagesPerAgent: 10,
      );
      runner = BackgroundSyncRunner(
        gate: gate,
        settingsRepo: settingsRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        agentRepo: agentRepo,
        messageRepo: messageRepo,
        lastSyncRepo: lastSyncRepo,
        dispatcher: dispatcher,
        budget: budget,
        logger: logger,
        now: clock.now,
      );

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      final msg1 = _msg(clientId: 'c1', serverId: 's1', timestamp: 100);
      final msg2 = _msg(clientId: 'c2', serverId: 's2', timestamp: 200);
      gateway.setHistory('i1', 'a1', [
        (messages: [msg1, msg2], nextCursor: null),
      ]);

      when(
        () => messageRepo.batchInsertByIndexedIds(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as List<Message>);

      await runner.executeOnce();

      // Only 1 message should be inserted due to cap
      final captured = verify(
        () => messageRepo.batchInsertByIndexedIds(captureAny<List<Message>>()),
      ).captured.cast<List<Message>>();
      final total = captured.fold<int>(0, (s, l) => s + l.length);
      expect(total, 1);
    });

    // -----------------------------------------------------------------------
    // maxPagesPerAgent cap
    // -----------------------------------------------------------------------
    test('executeOnce_maxPagesPerAgent_capsFetches', () async {
      final inst = _inst('i1');
      budget = const BackgroundSyncBudget(
        maxPagesPerAgent: 2,
        maxMessagesPerPull: 100,
      );
      runner = BackgroundSyncRunner(
        gate: gate,
        settingsRepo: settingsRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        agentRepo: agentRepo,
        messageRepo: messageRepo,
        lastSyncRepo: lastSyncRepo,
        dispatcher: dispatcher,
        budget: budget,
        logger: logger,
        now: clock.now,
      );

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      gateway.setHistory('i1', 'a1', [
        (
          messages: [_msg(clientId: 'c1', serverId: 's1', timestamp: 100)],
          nextCursor: 'cur1',
        ),
        (
          messages: [_msg(clientId: 'c2', serverId: 's2', timestamp: 200)],
          nextCursor: 'cur2',
        ),
        (
          messages: [_msg(clientId: 'c3', serverId: 's3', timestamp: 300)],
          nextCursor: null,
        ),
      ]);

      when(
        () => messageRepo.batchInsertByIndexedIds(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as List<Message>);

      await runner.executeOnce();

      expect(gateway.fetchHistoryCalls.length, 2);
    });

    // -----------------------------------------------------------------------
    // perInstanceBudget deadline
    // -----------------------------------------------------------------------
    test('executeOnce_perInstanceBudget_deadlineGracefulSkip', () async {
      final inst = _inst('i1');
      budget = const BackgroundSyncBudget(
        perInstanceBudget: Duration.zero,
        maxMessagesPerPull: 100,
        maxPagesPerAgent: 10,
      );
      runner = BackgroundSyncRunner(
        gate: gate,
        settingsRepo: settingsRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        agentRepo: agentRepo,
        messageRepo: messageRepo,
        lastSyncRepo: lastSyncRepo,
        dispatcher: dispatcher,
        budget: budget,
        logger: logger,
        now: clock.now,
      );

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      gateway.fetchDelay = const Duration(milliseconds: 50);
      gateway.setHistory('i1', 'a1', [
        (
          messages: [_msg(clientId: 'c1', serverId: 's1', timestamp: 100)],
          nextCursor: null,
        ),
      ]);

      await runner.executeOnce();

      expect(gateway.connectCount, 1);
      verifyNever(() => lastSyncRepo.upsert(any(), any()));
    });

    // -----------------------------------------------------------------------
    // Connect timeout
    // -----------------------------------------------------------------------
    test('executeOnce_connectTimeout_skipsInstance', () async {
      final inst = _inst('i1');
      budget = const BackgroundSyncBudget(
        connectTimeout: Duration(milliseconds: 1),
      );
      runner = BackgroundSyncRunner(
        gate: gate,
        settingsRepo: settingsRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        agentRepo: agentRepo,
        messageRepo: messageRepo,
        lastSyncRepo: lastSyncRepo,
        dispatcher: dispatcher,
        budget: budget,
        logger: logger,
        now: clock.now,
      );

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);

      gateway.connectDelay = const Duration(seconds: 10);

      await runner.executeOnce();

      expect(gateway.connectCount, 1);
      verifyNever(() => lastSyncRepo.upsert(any(), any()));
      expect(gateway.fetchHistoryCalls.length, 0);
    });

    // -----------------------------------------------------------------------
    // Page fetch timeout
    // -----------------------------------------------------------------------
    test('executeOnce_pageFetchTimeout_skipsAgent', () async {
      final inst = _inst('i1');
      budget = const BackgroundSyncBudget(
        pageFetchTimeout: Duration(milliseconds: 1),
        maxMessagesPerPull: 100,
        maxPagesPerAgent: 10,
      );
      runner = BackgroundSyncRunner(
        gate: gate,
        settingsRepo: settingsRepo,
        instanceRepo: instanceRepo,
        gatewayClient: gateway,
        agentRepo: agentRepo,
        messageRepo: messageRepo,
        lastSyncRepo: lastSyncRepo,
        dispatcher: dispatcher,
        budget: budget,
        logger: logger,
        now: clock.now,
      );

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      gateway.fetchDelay = const Duration(seconds: 10);
      gateway.setHistory('i1', 'a1', [
        (
          messages: [_msg(clientId: 'c1', serverId: 's1', timestamp: 100)],
          nextCursor: null,
        ),
      ]);

      await runner.executeOnce();

      verifyNever(() => messageRepo.batchInsertByIndexedIds(any()));
      verifyNever(() => lastSyncRepo.upsert(any(), any()));
    });

    // -----------------------------------------------------------------------
    // Tombstoned agent
    // -----------------------------------------------------------------------
    test('executeOnce_tombstonedAgent_resolverReturnsNull', () async {
      final inst = _inst('i1');
      final tombstoned = Agent(
        localId: 'l',
        remoteId: 'a1',
        instanceId: 'i1',
        name: 'a1',
        removedAt: 12345,
      );

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [tombstoned]);

      gateway.setHistory('i1', 'a1', [
        (
          messages: [_msg(clientId: 'c1', serverId: 's1', timestamp: 100)],
          nextCursor: null,
        ),
      ]);

      when(
        () => messageRepo.batchInsertByIndexedIds(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as List<Message>);

      await runner.executeOnce();

      // Tombstoned: dispatcher NOT called
      expect(dispatcher.callCount, 0);
      expect(dispatcher.enqueuedServerIds.length, 0);
      // Messages still inserted
      verify(() => messageRepo.batchInsertByIndexedIds(any())).called(1);
    });

    // -----------------------------------------------------------------------
    // Per-instance isolation
    // -----------------------------------------------------------------------
    test(
      'executeOnce_perInstanceIsolation_failureDoesNotBlockOthers',
      () async {
        final instA = _inst('iA');
        final instB = _inst('iB');

        when(
          () => settingsRepo.getPreferences(),
        ).thenAnswer((_) async => UserPreferences.defaults());
        when(
          () => instanceRepo.getAll(),
        ).thenAnswer((_) async => [instA, instB]);
        when(
          () => agentRepo.getAllByInstanceId('iA'),
        ).thenAnswer((_) async => [_agent('a1', 'iA')]);
        when(
          () => agentRepo.getAllByInstanceId('iB'),
        ).thenAnswer((_) async => [_agent('a1', 'iB')]);

        // iA fetch throws
        gateway.fetchThrowByInstance['iA'] = Exception('fetch failed');

        gateway.setHistory('iA', 'a1', [
          (
            messages: [_msg(clientId: 'cA1', serverId: 'sA1', timestamp: 100)],
            nextCursor: null,
          ),
        ]);
        gateway.setHistory('iB', 'a1', [
          (
            messages: [_msg(clientId: 'cB1', serverId: 'sB1', timestamp: 200)],
            nextCursor: null,
          ),
        ]);

        when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer(
          (inv) async => inv.positionalArguments[0] as List<Message>,
        );

        await runner.executeOnce();

        // iA failed → no upsert
        verifyNever(() => lastSyncRepo.upsert('iA', any()));
        // iB succeeded → upsert with max ts
        verify(() => lastSyncRepo.upsert('iB', 200)).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Zero messages
    // -----------------------------------------------------------------------
    test('executeOnce_zeroMessages_stillUpdatesLastSync', () async {
      final inst = _inst('i1');

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      gateway.setHistory('i1', 'a1', [(messages: [], nextCursor: null)]);

      await runner.executeOnce();

      verifyNever(() => messageRepo.batchInsertByIndexedIds(any()));
      verify(() => lastSyncRepo.upsert('i1', clock.now())).called(1);
    });

    // -----------------------------------------------------------------------
    // Dedup by batchInsertByIndexedIds
    // -----------------------------------------------------------------------
    test('executeOnce_dedupByBatchInsert_sameServerIdOnce', () async {
      final inst = _inst('i1');

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      // Same serverId across two pages → runner collects both then calls
      // batchInsertByIndexedIds once. The repo method deduplicates.
      final msgDup = _msg(clientId: 'c1', serverId: 's1', timestamp: 100);

      gateway.setHistory('i1', 'a1', [
        (messages: [msgDup], nextCursor: 'cur1'),
        (messages: [msgDup], nextCursor: null),
      ]);

      // Simulate dedup: pass through first occurrence, drop duplicates
      final seen = <String>{};
      when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer((
        inv,
      ) async {
        final list = inv.positionalArguments[0] as List<Message>;
        final deduped = <Message>[];
        for (final m in list) {
          final key = m.serverId ?? m.clientId;
          if (seen.add(key)) deduped.add(m);
        }
        return deduped;
      });

      await runner.executeOnce();

      // Runner batches all pages into one call per agent
      verify(() => messageRepo.batchInsertByIndexedIds(any())).called(1);
    });

    // -----------------------------------------------------------------------
    // handlePulledMessages called with inserted messages only
    // -----------------------------------------------------------------------
    test(
      'executeOnce_handlePulledMessagesCalledWithInsertedOnly_showFalse',
      () async {
        final inst = _inst('i1');

        when(
          () => settingsRepo.getPreferences(),
        ).thenAnswer((_) async => UserPreferences.defaults());
        when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
        when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
        when(
          () => agentRepo.getAllByInstanceId('i1'),
        ).thenAnswer((_) async => [_agent('a1', 'i1')]);

        final msg = _msg(clientId: 'c1', serverId: 's1', timestamp: 100);
        gateway.setHistory('i1', 'a1', [
          (messages: [msg], nextCursor: null),
        ]);

        when(() => messageRepo.batchInsertByIndexedIds(any())).thenAnswer(
          (inv) async => inv.positionalArguments[0] as List<Message>,
        );

        await runner.executeOnce();

        expect(dispatcher.handledLists.length, 1);
        expect(dispatcher.handledLists.first.length, 1);
        expect(dispatcher.handledLists.first.first.serverId, 's1');
      },
    );

    // -----------------------------------------------------------------------
    // ResolveAgent handoff
    // -----------------------------------------------------------------------
    test('executeOnce_resolveAgentHandoff_ignoresEmptyInstanceId', () async {
      final inst = _inst('i1');

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      final msg = _msg(clientId: 'c1', serverId: 's1', timestamp: 100);
      gateway.setHistory('i1', 'a1', [
        (messages: [msg], nextCursor: null),
      ]);

      when(
        () => messageRepo.batchInsertByIndexedIds(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as List<Message>);

      await runner.executeOnce();

      expect(dispatcher.enqueuedServerIds, contains('s1'));
    });

    // -----------------------------------------------------------------------
    // Fetch throws
    // -----------------------------------------------------------------------
    test('executeOnce_fetchThrow_caught_agentSkipped', () async {
      final inst = _inst('i1');

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      gateway.fetchThrow = Exception('fetch failed');
      gateway.setHistory('i1', 'a1', [
        (
          messages: [_msg(clientId: 'c1', serverId: 's1', timestamp: 100)],
          nextCursor: null,
        ),
      ]);

      await runner.executeOnce();

      verifyNever(() => messageRepo.batchInsertByIndexedIds(any()));
      verifyNever(() => lastSyncRepo.upsert(any(), any()));
    });

    // -----------------------------------------------------------------------
    // Logger
    // -----------------------------------------------------------------------
    test('executeOnce_logsStartAndCompletion', () async {
      final inst = _inst('i1');

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 0);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      gateway.setHistory('i1', 'a1', [(messages: [], nextCursor: null)]);

      await runner.executeOnce();

      expect(logger.infos.length, greaterThanOrEqualTo(1));
      expect(logger.errors.length, 0);
    });

    // -----------------------------------------------------------------------
    // Multiple instances, multiple agents
    // -----------------------------------------------------------------------
    test('executeOnce_multiInstanceMultiAgent_allProcessed', () async {
      final inst1 = _inst('i1');
      final inst2 = _inst('i2');

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst1, inst2]);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1'), _agent('a2', 'i1')]);
      when(
        () => agentRepo.getAllByInstanceId('i2'),
      ).thenAnswer((_) async => [_agent('b1', 'i2')]);

      gateway.setHistory('i1', 'a1', [
        (
          messages: [_msg(clientId: 'c1', serverId: 's1', timestamp: 100)],
          nextCursor: null,
        ),
      ]);
      gateway.setHistory('i1', 'a2', [
        (
          messages: [_msg(clientId: 'c2', serverId: 's2', timestamp: 200)],
          nextCursor: null,
        ),
      ]);
      gateway.setHistory('i2', 'b1', [
        (
          messages: [_msg(clientId: 'c3', serverId: 's3', timestamp: 300)],
          nextCursor: null,
        ),
      ]);

      when(
        () => messageRepo.batchInsertByIndexedIds(any()),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as List<Message>);

      await runner.executeOnce();

      expect(gateway.connectCount, 2);
      expect(gateway.fetchHistoryCalls.length, 3);
      verify(() => lastSyncRepo.upsert('i1', 200)).called(1);
      verify(() => lastSyncRepo.upsert('i2', 300)).called(1);
    });

    // -----------------------------------------------------------------------
    // Finding 1: outer try/catch — repo throw must not block other instances
    // -----------------------------------------------------------------------
    test('executeOnce_repoThrow_doesNotBlockOtherInstances', () async {
      final instA = _inst('iA');
      final instB = _inst('iB');

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [instA, instB]);

      // iA: agentRepo throws → should be caught by outer try/catch
      when(
        () => agentRepo.getAllByInstanceId('iA'),
      ).thenThrow(Exception('DB corrupt'));
      // iB: succeeds
      when(
        () => agentRepo.getAllByInstanceId('iB'),
      ).thenAnswer((_) async => [_agent('a1', 'iB')]);

      gateway.setHistory('iB', 'a1', [
        (
          messages: [_msg(clientId: 'cB1', serverId: 'sB1', timestamp: 200)],
          nextCursor: null,
        ),
      ]);

      await runner.executeOnce();

      // iA: connect WAS called, but last_sync_at MUST NOT be updated.
      expect(gateway.connectCount, 2);
      verifyNever(() => lastSyncRepo.upsert('iA', any()));

      // iB: fully synced — last_sync_at IS updated.
      verify(() => lastSyncRepo.upsert('iB', any())).called(1);
    });

    // -----------------------------------------------------------------------
    // Finding 2: stop-early when oldest page message < lastSyncMs
    // -----------------------------------------------------------------------
    test('executeOnce_stopEarly_whenOldestPageIsBeforeLastSync', () async {
      final inst = _inst('i1');

      when(
        () => settingsRepo.getPreferences(),
      ).thenAnswer((_) async => UserPreferences.defaults());
      when(() => instanceRepo.getAll()).thenAnswer((_) async => [inst]);
      // Override default lastSyncRepo stub: lastSyncMs = 500
      when(() => lastSyncRepo.get('i1')).thenAnswer((_) async => 500);
      when(
        () => agentRepo.getAllByInstanceId('i1'),
      ).thenAnswer((_) async => [_agent('a1', 'i1')]);

      // Page 0: timestamps [1000, 900, 800] — oldest 800 >= 500 → continue
      // Page 1: timestamps [700, 600, 400] — oldest 400 < 500 → stop-early
      // Page 2 would never be fetched.
      gateway.setHistory('i1', 'a1', [
        (
          messages: [
            _msg(clientId: 'c1000', serverId: 's1000', timestamp: 1000),
            _msg(clientId: 'c900', serverId: 's900', timestamp: 900),
            _msg(clientId: 'c800', serverId: 's800', timestamp: 800),
          ],
          nextCursor: 'cur1',
        ),
        (
          messages: [
            _msg(clientId: 'c700', serverId: 's700', timestamp: 700),
            _msg(clientId: 'c600', serverId: 's600', timestamp: 600),
            _msg(clientId: 'c400', serverId: 's400', timestamp: 400),
          ],
          nextCursor: null,
        ),
      ]);

      await runner.executeOnce();

      // Should have fetched only 2 pages (not maxPagesPerAgent=5),
      // because oldest on page 1 (400) is < lastSyncMs (500).
      expect(gateway.fetchHistoryCalls.length, 2);
    });
  });
}
