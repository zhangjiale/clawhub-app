import 'dart:async';

import 'package:claw_hub/app/connection/instance_event.dart';
import 'package:claw_hub/app/notifications/notification_coordinator.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_local_notification_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/pending_notification.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_notification_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLogger implements ILogger {
  @override
  void info(String message) {}
  @override
  void error(String message, [StackTrace? stackTrace]) {}
}

class _FakeNotificationService implements ILocalNotificationService {
  final List<
    ({
      int id,
      NotificationChannelId channel,
      String title,
      String body,
      String? routePath,
    })
  >
  shown = [];

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<void> show({
    required int id,
    required NotificationChannelId channel,
    required String title,
    required String body,
    String? routePath,
  }) async {
    shown.add((
      id: id,
      channel: channel,
      title: title,
      body: body,
      routePath: routePath,
    ));
  }

  @override
  Future<void> cancel(int id) async {}
  @override
  void setupOnTap(void Function(String? routePath) onTap) {}
  @override
  Future<void> dispose() async {}
}

class _FakeNotificationRepo implements INotificationRepo {
  final List<PendingNotification> _store = [];
  int _nextId = 1;

  void seed(PendingNotification n) {
    _store.add(n.copyWith(id: _nextId++));
  }

  @override
  Future<int> enqueue(PendingNotification n) async {
    final withId = n.copyWith(id: _nextId++);
    _store.add(withId);
    return withId.id;
  }

  @override
  Future<List<PendingNotification>> getPending() async =>
      _store.where((n) => !n.delivered).toList();

  @override
  Future<void> markDelivered(int id) async {
    final i = _store.indexWhere((n) => n.id == id);
    if (i >= 0) _store[i] = _store[i].copyWith(delivered: true);
  }

  @override
  Future<int> markDeliveredBatch(List<int> ids) async {
    var affected = 0;
    for (final id in ids) {
      final i = _store.indexWhere((n) => n.id == id);
      if (i >= 0 && !_store[i].delivered) {
        _store[i] = _store[i].copyWith(delivered: true);
        affected++;
      }
    }
    return affected;
  }

  @override
  Future<int> clearDelivered() async {
    final before = _store.length;
    _store.removeWhere((n) => n.delivered);
    return before - _store.length;
  }

  @override
  Future<int> countPending() async => _store.where((n) => !n.delivered).length;
}

class _FakeInstanceRepo implements IInstanceRepo {
  @override
  Future<List<Instance>> getAll() async => [];
  @override
  Future<Instance?> getById(String id) async => null;
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAgentRepo implements IAgentRepo {
  @override
  Future<Agent?> findByCompositeKey(String instanceId, String remoteId) async =>
      null;
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGatewayClient implements IGatewayClient {
  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) =>
      const Stream<GatewayConnectionState>.empty();
  @override
  Stream<Message> messageStream(String instanceId) =>
      const Stream<Message>.empty();
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pump the microtask queue enough times for fire-and-forget flush chains
/// (getPending → show → markDelivered × N → clearDelivered) to settle.
Future<void> _pump([int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

UserPreferences _prefs({
  bool notificationsEnabled = true,
  bool dndEnabled = false,
  int dndStartHour = 22,
  int dndEndHour = 8,
}) {
  return UserPreferences(
    notificationsEnabled: notificationsEnabled,
    dndEnabled: dndEnabled,
    dndStartHour: dndStartHour,
    dndEndHour: dndEndHour,
  );
}

void main() {
  late _FakeNotificationService service;
  late _FakeNotificationRepo repo;
  late StreamController<InstanceEvent> orchestratorEvents;
  late UserPreferences prefs;
  late DateTime now;

  setUp(() {
    service = _FakeNotificationService();
    repo = _FakeNotificationRepo();
    orchestratorEvents = StreamController<InstanceEvent>.broadcast();
    prefs = _prefs();
    now = DateTime(2026, 6, 20, 15, 0); // 15:00 — outside 22-08 DND
  });

  tearDown(() async {
    await orchestratorEvents.close();
  });

  NotificationCoordinator buildCoordinator() {
    return NotificationCoordinator(
      orchestratorEvents: orchestratorEvents.stream,
      gatewayClient: _FakeGatewayClient(),
      instanceRepo: _FakeInstanceRepo(),
      agentRepo: _FakeAgentRepo(),
      notificationRepo: repo,
      notificationService: service,
      evaluator: const EvaluateNotificationUseCase(),
      prefsProvider: () => prefs,
      clock: () => now,
      logger: _FakeLogger(),
    );
  }

  test(
    'start while NOT in DND with backlog -> immediately flushes summary (cross-restart catch-up)',
    () async {
      // Regression: 旧实现 _scheduleDndTimer 仅在 isInDnd 时返回非 null end，
      // 非 DND 时直接 return —— 既不补发积压也不排定下一个 DND 起点。
      // App 在 DND 内被杀后于非 DND 时段重启，积压永不汇总。
      repo.seed(
        PendingNotification(
          id: 0,
          agentId: 'a',
          instanceId: 'i',
          agentName: '虾',
          summary: 'msg1',
          createdAt: 1,
          messageServerId: 's1',
        ),
      );
      repo.seed(
        PendingNotification(
          id: 0,
          agentId: 'b',
          instanceId: 'i',
          agentName: '虾2',
          summary: 'msg2',
          createdAt: 2,
          messageServerId: 's2',
        ),
      );

      final coordinator = buildCoordinator();
      await coordinator.start();
      await _pump();
      await coordinator.dispose();

      // 积压应被立即汇总补发。
      expect(service.shown.length, 1);
      expect(service.shown.first.body, contains('2'));
      expect(await repo.countPending(), 0);
    },
  );

  test(
    'start while IN DND with backlog -> does NOT flush; stays queued',
    () async {
      // 03:00 落在 22-08 DND 窗口内。
      now = DateTime(2026, 6, 20, 3, 0);
      prefs = _prefs(dndEnabled: true);
      repo.seed(
        PendingNotification(
          id: 0,
          agentId: 'a',
          instanceId: 'i',
          agentName: '虾',
          summary: 'msg1',
          createdAt: 1,
          messageServerId: 's1',
        ),
      );

      final coordinator = buildCoordinator();
      await coordinator.start();
      await _pump();
      // 仍在 DND 内 —— 不应补发，积压保留。
      expect(service.shown, isEmpty);
      expect(await repo.countPending(), 1);
      await coordinator.dispose();
    },
  );

  test('onPrefsChanged after disabling DND -> flushes backlog', () async {
    // 启动时在 DND 内，积压保留；用户随后关闭 DND → onPrefsChanged 重排
    // 进入非 DND 分支 → 立即补发。
    now = DateTime(2026, 6, 20, 3, 0);
    prefs = _prefs(dndEnabled: true);
    repo.seed(
      PendingNotification(
        id: 0,
        agentId: 'a',
        instanceId: 'i',
        agentName: '虾',
        summary: 'msg1',
        createdAt: 1,
        messageServerId: 's1',
      ),
    );

    final coordinator = buildCoordinator();
    await coordinator.start();
    await _pump();
    expect(service.shown, isEmpty);

    // 用户关闭 DND。
    prefs = _prefs(dndEnabled: false);
    coordinator.onPrefsChanged();
    await _pump();
    await coordinator.dispose();

    expect(service.shown.length, 1);
    expect(await repo.countPending(), 0);
  });

  test(
    'DND disabled + no backlog -> start flushes nothing, no summary',
    () async {
      final coordinator = buildCoordinator();
      await coordinator.start();
      await _pump();
      expect(service.shown, isEmpty);
      expect(await repo.countPending(), 0);
      await coordinator.dispose();
    },
  );

  test(
    'dispose without start does not throw (no late dispatcher access)',
    () async {
      // Regression #2: dispose() 曾访问 late final dispatcher，
      // start() 从未执行时抛 LateInitializationError。
      final coordinator = buildCoordinator();
      await expectLater(coordinator.dispose(), completes);
    },
  );

  test(
    'onPrefsChanged with non-DND prefs change -> no flush, no reschedule work',
    () async {
      // Regression #4: 与 DND 无关的 prefs 变更 (notifyOnReply 切换) 不应触发
      // 额外的 getPending/flush。用计数 repo 验证 flush 未被多余调用。
      final countingRepo = _CountingNotificationRepo(repo);
      final coordinator = NotificationCoordinator(
        orchestratorEvents: orchestratorEvents.stream,
        gatewayClient: _FakeGatewayClient(),
        instanceRepo: _FakeInstanceRepo(),
        agentRepo: _FakeAgentRepo(),
        notificationRepo: countingRepo,
        notificationService: service,
        evaluator: const EvaluateNotificationUseCase(),
        prefsProvider: () => prefs,
        clock: () => now,
        logger: _FakeLogger(),
      );
      await coordinator.start();
      await _pump();
      final getsAfterStart = countingRepo.getPendingCalls;

      // 切换 notifyOnReply (与 DND 无关)。
      prefs = _prefs(); // 同样的 DND 配置，仅通知开关语义不变 (默认全开)
      prefs = UserPreferences(
        notificationsEnabled: true,
        notifyOnReply: false, // 仅改这个
      );
      coordinator.onPrefsChanged();
      await _pump();
      await coordinator.dispose();

      // DND 签名未变 -> 不重排 -> 不应有额外 getPending。
      expect(countingRepo.getPendingCalls, getsAfterStart);
    },
  );

  test('onPrefsChanged after extending DND window -> reschedules', () async {
    // DND 时段变更应触发重排 (签名变化)。
    now = DateTime(2026, 6, 20, 3, 0); // 在 22-08 DND 内
    prefs = _prefs(dndEnabled: true);
    final coordinator = buildCoordinator();
    await coordinator.start();
    await _pump();
    // 在 DND 内 -> 不 flush，积压保留
    repo.seed(
      PendingNotification(
        id: 0,
        agentId: 'a',
        instanceId: 'i',
        agentName: '虾',
        summary: 'msg1',
        createdAt: 1,
        messageServerId: 's1',
      ),
    );
    // 改 DND 时段 (签名变化) 仍处于 DND 内 -> 不 flush
    prefs = _prefs(dndEnabled: true, dndStartHour: 20, dndEndHour: 6);
    coordinator.onPrefsChanged();
    await _pump();
    expect(service.shown, isEmpty); // 仍在 DND 内
    await coordinator.dispose();
  });

  // ── _onMessage → ReplyEvent 映射 ────────────────────────────────
  // 这组测试覆盖 coordinator 最复杂、此前未测的流桥接逻辑。

  group('_onMessage → ReplyEvent mapping', () {
    late _ControllableGatewayClient gateway;
    late _ControllableAgentRepo agentRepo;
    late _ControllableInstanceRepo instanceRepo;

    NotificationCoordinator build() {
      return NotificationCoordinator(
        orchestratorEvents: orchestratorEvents.stream,
        gatewayClient: gateway,
        instanceRepo: instanceRepo,
        agentRepo: agentRepo,
        notificationRepo: repo,
        notificationService: service,
        evaluator: const EvaluateNotificationUseCase(),
        prefsProvider: () => prefs,
        clock: () => now,
        logger: _FakeLogger(),
      );
    }

    setUp(() {
      gateway = _ControllableGatewayClient();
      agentRepo = _ControllableAgentRepo();
      instanceRepo = _ControllableInstanceRepo();
      // seed at least one instance so start() enumerates it and subscribes;
      // gateway streams are instance-independent, so any instanceId works.
      instanceRepo.instances['x'] = Instance(
        id: 'x',
        name: '测试',
        gatewayUrl: 'ws://192.168.1.10:8080',
        tokenRef: 'tok',
      );
    });

    test(
      'agent reply with resolved agent -> notifies with displayName + localId + deep link',
      () async {
        agentRepo.agents['remote-1'] = Agent(
          localId: 'local-1',
          remoteId: 'remote-1',
          instanceId: 'i',
          name: '小明虾',
          nickname: '虾虾',
        );

        final c = build();
        await c.start();
        // 先 start 建订阅，再投递消息 (broadcast 控制器不缓存历史)。
        gateway.messageController.add(
          Message(
            clientId: 'c1',
            serverId: 'srv1',
            conversationId: 'conv',
            agentId: 'remote-1',
            role: MessageRole.agent,
            content: '你好呀',
            type: MessageType.text,
            status: MessageStatus.delivered,
            logicalClock: 1,
            timestamp: 1000,
          ),
        );
        await _pump();
        await c.dispose();

        // displayName = nickname ?? name = '虾虾'；localId = 'local-1'。
        expect(service.shown.length, 1);
        expect(service.shown.first.title, '虾虾');
        expect(service.shown.first.body, '你好呀');
        expect(service.shown.first.channel, NotificationChannelId.reply);
        // routeFor(ReplyEvent) → chatWithParams(localId, instanceId, source:'messages')。
        expect(service.shown.first.routePath, contains('chat/local-1'));
        expect(service.shown.first.routePath, contains('instanceId=x'));
      },
    );

    test(
      'agent reply when agent not found -> falls back to "虾" name and remoteId',
      () async {
        // agentRepo 找不到 -> agentName='虾', localId=remoteId。
        final c = build();
        await c.start();
        gateway.messageController.add(
          Message(
            clientId: 'c1',
            serverId: 'srv1',
            conversationId: 'conv',
            agentId: 'unknown-remote',
            role: MessageRole.agent,
            content: '回复',
            type: MessageType.text,
            status: MessageStatus.delivered,
            logicalClock: 1,
            timestamp: 1000,
          ),
        );
        await _pump();
        await c.dispose();

        expect(service.shown.length, 1);
        expect(service.shown.first.title, '虾');
        // localId 兜底为 remoteId 'unknown-remote'。
        expect(service.shown.first.routePath, contains('chat/unknown-remote'));
      },
    );

    test('user role message -> not notified', () async {
      final c = build();
      await c.start();
      gateway.messageController.add(
        Message(
          clientId: 'c1',
          conversationId: 'conv',
          agentId: 'a',
          role: MessageRole.user,
          content: '我发的',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
          timestamp: 1000,
        ),
      );
      await _pump();
      await c.dispose();

      expect(service.shown, isEmpty);
    });

    test('agent reply with empty content -> not notified', () async {
      final c = build();
      await c.start();
      gateway.messageController.add(
        Message(
          clientId: 'c1',
          conversationId: 'conv',
          agentId: 'a',
          role: MessageRole.agent,
          content: '',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
          timestamp: 1000,
        ),
      );
      await _pump();
      await c.dispose();

      expect(service.shown, isEmpty);
    });

    // US-021: tombstoned agent (Gateway 已删除) 不应触发通知。
    // 漏网之鱼场景：findByCompositeKey 故意不过滤 (复活契约)，
    // 但 _onMessage 必须在发送通知前检查 isRemoved。
    // 否则用户会收到来自"已删除 agent"的最后一条回复推送，
    // 点击进入 ChatRoom 又看到 '虾已移除' 占位页 —— 体验脱节。
    test('agent reply when agent is tombstoned -> NOT notified '
        '(US-021 suppression)', () async {
      agentRepo.agents['remote-1'] = Agent(
        localId: 'local-1',
        remoteId: 'remote-1',
        instanceId: 'i',
        name: '已删除虾',
        removedAt: DateTime.now().millisecondsSinceEpoch,
      );

      final c = build();
      await c.start();
      gateway.messageController.add(
        Message(
          clientId: 'c1',
          serverId: 'srv1',
          conversationId: 'conv',
          agentId: 'remote-1',
          role: MessageRole.agent,
          content: '我是遗言',
          type: MessageType.text,
          status: MessageStatus.delivered,
          logicalClock: 1,
          timestamp: 1000,
        ),
      );
      await _pump();
      await c.dispose();

      expect(service.shown, isEmpty, reason: 'tombstoned agent 的回复不应触发本地通知推送');
    });
  });

  // ── _onConnectionState 状态转换 ─────────────────────────────────

  group('_onConnectionState transitions', () {
    late _ControllableGatewayClient gateway;
    late _ControllableInstanceRepo instanceRepo;

    NotificationCoordinator build() {
      return NotificationCoordinator(
        orchestratorEvents: orchestratorEvents.stream,
        gatewayClient: gateway,
        instanceRepo: instanceRepo,
        agentRepo: _ControllableAgentRepo(),
        notificationRepo: repo,
        notificationService: service,
        evaluator: const EvaluateNotificationUseCase(),
        prefsProvider: () => prefs,
        clock: () => now,
        logger: _FakeLogger(),
      );
    }

    setUp(() {
      gateway = _ControllableGatewayClient();
      instanceRepo = _ControllableInstanceRepo();
      instanceRepo.instances['i'] = Instance(
        id: 'i',
        name: '家里',
        gatewayUrl: 'ws://192.168.1.10:8080',
        tokenRef: 'tok',
        healthStatus: HealthStatus.online,
      );
    });

    test('first observed state -> no connection-change notification', () async {
      // 首次状态不应产生"变化"通知 (避免启动刷屏)。
      final c = build();
      await c.start();
      gateway.connController.add(GatewayConnectionState.connected);
      await _pump();
      await c.dispose();

      expect(service.shown, isEmpty);
    });

    test('online -> offline drop -> connection notification shown', () async {
      // 必须先建立一个"已知态"，才能产生转换。先 connected，再 disconnected。
      final c = build();
      await c.start();
      gateway.connController.add(GatewayConnectionState.connected);
      await _pump();
      // 此时 connected 为首态，不发通知。再发 disconnected 触发 drop。
      gateway.connController.add(GatewayConnectionState.disconnected);
      await _pump();
      await c.dispose();

      expect(service.shown.length, 1);
      expect(service.shown.first.channel, NotificationChannelId.connection);
      // isOnlineDrop 标题含实例名 + "已断开"。
      expect(service.shown.first.title, contains('家里'));
      expect(service.shown.first.title, contains('断开'));
    });

    test('same state repeated -> no new notification', () async {
      final c = build();
      await c.start();
      gateway.connController.add(GatewayConnectionState.connected);
      await _pump();
      gateway.connController.add(GatewayConnectionState.connected); // 同态
      await _pump();
      gateway.connController.add(GatewayConnectionState.connected); // 同态
      await _pump();
      await c.dispose();

      // 首态不发；后续同态不发 -> 0 条。
      expect(service.shown, isEmpty);
    });

    test(
      'reconnect success (offline->online) -> treated as noise, no notification',
      () async {
        final c = build();
        await c.start();
        gateway.connController.add(GatewayConnectionState.disconnected); // 首态
        await _pump();
        gateway.connController.add(GatewayConnectionState.connected); // 重连成功
        await _pump();
        await c.dispose();

        // isOnlineDrop=false (online 是 toState，非 drop) -> 噪音丢弃。
        expect(service.shown, isEmpty);
      },
    );
  });
}

/// 包装另一个 repo，统计 getPending 调用次数 (验证 #4 无冗余 flush)。
class _CountingNotificationRepo implements INotificationRepo {
  final INotificationRepo _inner;
  _CountingNotificationRepo(this._inner);

  int getPendingCalls = 0;

  @override
  Future<int> enqueue(PendingNotification n) => _inner.enqueue(n);
  @override
  Future<List<PendingNotification>> getPending() {
    getPendingCalls++;
    return _inner.getPending();
  }

  @override
  Future<void> markDelivered(int id) => _inner.markDelivered(id);
  @override
  Future<int> markDeliveredBatch(List<int> ids) =>
      _inner.markDeliveredBatch(ids);
  @override
  Future<int> clearDelivered() => _inner.clearDelivered();
  @override
  Future<int> countPending() => _inner.countPending();
}

/// 可驱动消息流 / 连接状态流的 GatewayClient fake。
///
/// 测试向 [messageController] / [connController] add 事件，观察 coordinator
/// 经 dispatcher 最终发出的通知 ([_FakeNotificationService.shown])。
class _ControllableGatewayClient implements IGatewayClient {
  final StreamController<Message> messageController =
      StreamController<Message>.broadcast();
  final StreamController<GatewayConnectionState> connController =
      StreamController<GatewayConnectionState>.broadcast();

  @override
  Stream<Message> messageStream(String instanceId) => messageController.stream;
  @override
  Stream<GatewayConnectionState> connectionStateStream(String instanceId) =>
      connController.stream;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 可预设 agent 解析结果的 AgentRepo fake。
/// [agents] key = remoteId (与 Message.agentId 一致)。
class _ControllableAgentRepo implements IAgentRepo {
  final Map<String, Agent> agents = {};

  @override
  Future<Agent?> findByCompositeKey(String instanceId, String remoteId) async =>
      agents[remoteId];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 可预设实例的 InstanceRepo fake。
/// [instances] key = instanceId。
class _ControllableInstanceRepo implements IInstanceRepo {
  final Map<String, Instance> instances = {};

  @override
  Future<List<Instance>> getAll() async => instances.values.toList();
  @override
  Future<Instance?> getById(String id) async => instances[id];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
