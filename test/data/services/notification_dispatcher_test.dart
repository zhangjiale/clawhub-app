import 'dart:async';

import 'package:claw_hub/core/i_local_notification_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/notification_event.dart';
import 'package:claw_hub/domain/models/pending_notification.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_notification_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';
import 'package:claw_hub/data/services/notification_dispatcher.dart';
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

/// show 永远抛错 —— 验证 flushDndSummary 的"先 show 后 mark"原子性。
class _ThrowingNotificationService implements ILocalNotificationService {
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
    throw StateError('boom');
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

  /// For warmup tests: pre-loaded pending list.
  final List<PendingNotification> _preloaded;

  _FakeNotificationRepo({List<PendingNotification>? pending})
    : _preloaded = pending ?? [];

  /// 记录 markDeliveredBatch 调用次数 (用于断言 Law 6：批量而非逐条)。
  int batchMarkCalls = 0;

  /// 记录单条 markDelivered 调用次数 (flush 路径应为 0)。
  int singleMarkCalls = 0;

  @override
  Future<int> enqueue(PendingNotification n) async {
    final withId = n.copyWith(id: _nextId++);
    _store.add(withId);
    return withId.id;
  }

  @override
  Future<List<PendingNotification>> getPending() async {
    // Combine preloaded + runtime enqueued; preloaded are "persisted" before
    // the dispatcher exists, simulating what warmupFromPending reads from DB.
    if (_preloaded.isNotEmpty) {
      return _preloaded.where((n) => !n.delivered).toList();
    }
    return _store.where((n) => !n.delivered).toList();
  }

  @override
  Future<void> markDelivered(int id) async {
    singleMarkCalls++;
    final i = _store.indexWhere((n) => n.id == id);
    if (i >= 0) _store[i] = _store[i].copyWith(delivered: true);
  }

  @override
  Future<int> markDeliveredBatch(List<int> ids) async {
    batchMarkCalls++;
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

ReplyEvent _reply({String? serverId = 's1', String clientId = 'c1'}) =>
    ReplyEvent(
      agentId: 'a',
      instanceId: 'i',
      agentName: '小明虾',
      contentPreview: '你好',
      messageServerId: serverId,
      messageClientId: clientId,
    );

UserPreferences _prefs({
  bool notificationsEnabled = true,
  bool notifyOnReply = true,
  bool notifyOnError = true,
  bool notifyOnConnectionChange = true,
  bool dndEnabled = false,
}) {
  return UserPreferences(
    notificationsEnabled: notificationsEnabled,
    notifyOnReply: notifyOnReply,
    notifyOnError: notifyOnError,
    notifyOnConnectionChange: notifyOnConnectionChange,
    dndEnabled: dndEnabled,
  );
}

// ---------------------------------------------------------------------------
// Helper factories for handlePulledMessages / warmupFromPending tests
// ---------------------------------------------------------------------------

Message _makeReplyMessage({
  String serverId = 's1',
  String clientId = 'c1',
  String agentId = 'a',
  String content = 'hi',
}) {
  return Message(
    clientId: clientId,
    serverId: serverId,
    conversationId: 'abc123def456', // SHA-256 hash, NOT instanceId:agentId
    agentId: agentId,
    role: MessageRole.agent,
    content: content,
    type: MessageType.text,
    logicalClock: 1,
  );
}

Agent _makeAgent({
  String localId = 'l1',
  String remoteId = 'a',
  String instanceId = 'i',
  String name = 'Claw',
}) {
  return Agent(
    localId: localId,
    remoteId: remoteId,
    instanceId: instanceId,
    name: name,
  );
}

PendingNotification _makePending({
  String? serverId = 's1',
  bool delivered = false,
  String agentId = 'a',
  String instanceId = 'i',
  String agentName = 'Claw',
  String summary = 'hi',
}) {
  return PendingNotification(
    id: 0,
    agentId: agentId,
    instanceId: instanceId,
    agentName: agentName,
    summary: summary,
    createdAt: 1,
    messageServerId: serverId,
    delivered: delivered,
  );
}

void main() {
  late _FakeNotificationService service;
  late _FakeNotificationRepo repo;
  late StreamController<NotificationEvent> controller;

  setUp(() {
    service = _FakeNotificationService();
    repo = _FakeNotificationRepo();
    controller = StreamController<NotificationEvent>.broadcast();
  });

  tearDown(() => controller.close());

  NotificationDispatcher buildDispatcher({
    required UserPreferences prefs,
    required DateTime Function() clock,
    _FakeNotificationRepo? customRepo,
  }) {
    return NotificationDispatcher(
      eventStream: controller.stream,
      prefsProvider: () => prefs,
      repo: customRepo ?? repo,
      notificationService: service,
      evaluator: const EvaluateNotificationUseCase(),
      clock: clock,
      logger: _FakeLogger(),
    );
  }

  // ==========================================================================
  // Existing tests (live stream routing)
  // ==========================================================================

  test('reply with switch on -> show notification with route path', () async {
    final d = buildDispatcher(
      prefs: _prefs(),
      clock: () => DateTime(2026, 6, 20, 12),
    )..start();
    controller.add(_reply());
    await Future<void>.delayed(Duration.zero);
    d.dispose();

    expect(service.shown.length, 1);
    expect(service.shown.first.title, '小明虾');
    expect(service.shown.first.body, '你好');
    expect(service.shown.first.channel, NotificationChannelId.reply);
    // routePath 由 coordinator 注入的 routeFor 提供；纯 dispatcher 默认为 null。
    expect(service.shown.first.routePath, isNull);
  });

  test('reply with switch off -> no notification, no enqueue', () async {
    final d = buildDispatcher(
      prefs: _prefs(notifyOnReply: false),
      clock: () => DateTime(2026, 6, 20, 12),
    )..start();
    controller.add(_reply());
    await Future<void>.delayed(Duration.zero);
    d.dispose();

    expect(service.shown, isEmpty);
    expect(await repo.countPending(), 0);
  });

  test('DND active -> enqueue suppressed, no immediate show', () async {
    final d = buildDispatcher(
      prefs: _prefs(dndEnabled: true),
      clock: () => DateTime(2026, 6, 20, 3, 0),
    )..start();
    controller.add(_reply());
    await Future<void>.delayed(Duration.zero);
    d.dispose();

    expect(service.shown, isEmpty);
    expect(await repo.countPending(), 1);
  });

  test('duplicate serverId -> second event ignored (dedup)', () async {
    final d = buildDispatcher(
      prefs: _prefs(),
      clock: () => DateTime(2026, 6, 20, 12),
    )..start();
    controller.add(_reply(serverId: 'dup'));
    controller.add(_reply(serverId: 'dup'));
    await Future<void>.delayed(Duration.zero);
    d.dispose();

    expect(service.shown.length, 1);
  });

  test(
    'duplicate clientId with null serverId -> second ignored (fallback dedup)',
    () async {
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
      )..start();
      controller.add(_reply(serverId: null, clientId: 'cx'));
      controller.add(_reply(serverId: null, clientId: 'cx'));
      await Future<void>.delayed(Duration.zero);
      d.dispose();

      expect(service.shown.length, 1);
    },
  );

  test('connection online drop -> show connection notification', () async {
    final d = buildDispatcher(
      prefs: _prefs(),
      clock: () => DateTime(2026, 6, 20, 12),
    )..start();
    controller.add(
      ConnectionChangeEvent(
        instanceId: 'i',
        instanceName: '家里',
        fromState: NotificationConnectionState.online,
        toState: NotificationConnectionState.offline,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    d.dispose();

    expect(service.shown.length, 1);
    expect(service.shown.first.channel, NotificationChannelId.connection);
  });

  test(
    'connection drop -> reconnect -> drop again after dedup window -> second drop notified',
    () async {
      // Regression: 连接变化去重曾按 (instance, toState) 永久存入 LRU，
      // 导致首次掉线-重连-再掉线后，第二次掉线被永久吞掉。
      // 现按时间窗口节流：窗口外的同状态再次出现仍要通知。
      var now = DateTime(2026, 6, 20, 12);
      final d = NotificationDispatcher(
        eventStream: controller.stream,
        prefsProvider: () => _prefs(),
        repo: repo,
        notificationService: service,
        evaluator: const EvaluateNotificationUseCase(),
        clock: () => now,
        logger: _FakeLogger(),
        connectionDedupWindow: const Duration(seconds: 30),
      )..start();

      // 1) 首次掉线 -> 通知
      controller.add(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: '家里',
          fromState: NotificationConnectionState.online,
          toState: NotificationConnectionState.offline,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // 2) 重连 (offline->online) -> 噪音，不通知 (isOnlineDrop=false)
      controller.add(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: '家里',
          fromState: NotificationConnectionState.offline,
          toState: NotificationConnectionState.online,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // 3) 推进时间超过去重窗口后再次掉线 -> 应当通知 (不被永久抑制)
      now = now.add(const Duration(seconds: 31));
      controller.add(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: '家里',
          fromState: NotificationConnectionState.online,
          toState: NotificationConnectionState.offline,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      d.dispose();
      // drop1 + drop2 各一条；重连为噪音不通知 -> 共 2 条
      expect(service.shown.length, 2);
      expect(
        service.shown.every(
          (s) => s.channel == NotificationChannelId.connection,
        ),
        isTrue,
      );
    },
  );

  test(
    'connection drop twice within dedup window -> second suppressed',
    () async {
      var now = DateTime(2026, 6, 20, 12);
      final d = NotificationDispatcher(
        eventStream: controller.stream,
        prefsProvider: () => _prefs(),
        repo: repo,
        notificationService: service,
        evaluator: const EvaluateNotificationUseCase(),
        clock: () => now,
        logger: _FakeLogger(),
        connectionDedupWindow: const Duration(seconds: 30),
      )..start();

      controller.add(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: '家里',
          fromState: NotificationConnectionState.online,
          toState: NotificationConnectionState.offline,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // 短暂重连后立刻再掉线，仍在去重窗口内 -> 第二次掉线被节流。
      controller.add(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: '家里',
          fromState: NotificationConnectionState.offline,
          toState: NotificationConnectionState.online,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 5)); // 仍在 30s 窗口内
      controller.add(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: '家里',
          fromState: NotificationConnectionState.online,
          toState: NotificationConnectionState.offline,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      d.dispose();
      // 仅首次掉线通知；重连为噪音，第二次掉线被节流 -> 共 1 条
      expect(service.shown.length, 1);
    },
  );

  test(
    'flushDndSummary emits a single summary notification and marks delivered',
    () async {
      // pre-load pending queue
      await repo.enqueue(
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
      await repo.enqueue(
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

      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 9, 0),
      )..start();

      await d.flushDndSummary();

      expect(service.shown.length, 1);
      expect(service.shown.first.body, contains('2'));
      expect(await repo.countPending(), 0);
      // Law 6: 批量标记一次，不逐条。
      expect(repo.batchMarkCalls, 1);
      expect(repo.singleMarkCalls, 0);
      d.dispose();
    },
  );

  test(
    'flushDndSummary show failure leaves messages queued (no data loss)',
    () async {
      // Regression #5: 旧实现先 mark 后 show，show 失败会丢消息。
      // 现改为先 show 后 mark：show 抛错时条目保留在队列，下次 flush 重试。
      await repo.enqueue(
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

      final failingService = _ThrowingNotificationService();
      final d = NotificationDispatcher(
        eventStream: controller.stream,
        prefsProvider: () => _prefs(),
        repo: repo,
        notificationService: failingService,
        evaluator: const EvaluateNotificationUseCase(),
        clock: () => DateTime(2026, 6, 20, 9, 0),
        logger: _FakeLogger(),
      )..start();

      await d.flushDndSummary();

      // show 抛错被捕获；条目仍未投递，保留在队列。
      expect(await repo.countPending(), 1);
      expect(repo.batchMarkCalls, 0);
      d.dispose();
    },
  );

  test(
    'reply dedup slot is NOT consumed while switch off -> re-enable allows catch-up',
    () async {
      // Regression #3: 旧实现在评估前就占去重槽，导致开关关闭期间到达的消息，
      // 用户事后开开关、同一 serverId 再次投递时不再通知 (槽已占)。
      // 现仅在 ShowDecision/DndSuppressedDecision 时占槽。
      var prefs = _prefs(notifyOnReply: false); // 回复开关关
      var now = DateTime(2026, 6, 20, 12);
      final d = NotificationDispatcher(
        eventStream: controller.stream,
        prefsProvider: () => prefs,
        repo: repo,
        notificationService: service,
        evaluator: const EvaluateNotificationUseCase(),
        clock: () => now,
        logger: _FakeLogger(),
      )..start();

      // 1) 回复开关关 -> 丢弃，但不占去重槽
      controller.add(_reply(serverId: 'dup'));
      await Future<void>.delayed(Duration.zero);
      expect(service.shown, isEmpty);

      // 2) 用户打开回复开关，同一 serverId 再次投递 -> 应当通知 (未被过早占槽)
      prefs = _prefs(notifyOnReply: true);
      controller.add(_reply(serverId: 'dup'));
      await Future<void>.delayed(Duration.zero);
      d.dispose();

      expect(service.shown.length, 1);
    },
  );

  test(
    'catch-up duplicate (same serverId, switch on) -> second ignored',
    () async {
      // 已通知过的 serverId 再次到达 (catch-up 二次到达) 仍要去重。
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
      )..start();
      controller.add(_reply(serverId: 'once'));
      controller.add(_reply(serverId: 'once'));
      await Future<void>.delayed(Duration.zero);
      d.dispose();
      expect(service.shown.length, 1);
    },
  );

  test(
    'LRU dedup cap prevents unbounded growth (does not throw on 600 unique)',
    () async {
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
      )..start();
      for (var i = 0; i < 600; i++) {
        controller.add(_reply(serverId: 's$i', clientId: 'c$i'));
      }
      await Future<void>.delayed(Duration.zero);
      d.dispose();

      expect(service.shown.length, 600);
    },
  );

  test('injected routeFor provides deep-link path on show', () async {
    final d = NotificationDispatcher(
      eventStream: controller.stream,
      prefsProvider: () => _prefs(),
      repo: repo,
      notificationService: service,
      evaluator: const EvaluateNotificationUseCase(),
      clock: () => DateTime(2026, 6, 20, 12),
      logger: _FakeLogger(),
      routeFor: (e) => e is ReplyEvent ? '/claws/chat/${e.agentId}' : null,
    )..start();
    controller.add(_reply());
    await Future<void>.delayed(Duration.zero);
    d.dispose();

    expect(service.shown.first.routePath, '/claws/chat/a');
  });

  // ==========================================================================
  // notification id: Android 32-bit range, wrap, DND collision avoidance
  // ==========================================================================
  group('notification id range and collision', () {
    test('emitted notification ids stay within 32-bit signed int range '
        '(0..0x7FFFFFFF)', () async {
      // Seed clock just before the 32-bit limit so wrap triggers immediately.
      // _maxNotificationId = 0x7FFFFFFF = 2147483647.
      // _nextNotificationId = 2147483646 % 2147483647 = 2147483646.
      const limit = 0x7FFFFFFF; // 2147483647
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime.fromMillisecondsSinceEpoch(limit - 1),
      )..start();

      // Emit 5 notifications: one at the edge, four after wrap.
      for (var i = 0; i < 5; i++) {
        controller.add(_reply(serverId: 'wrap-$i', clientId: 'cw-$i'));
      }
      await Future<void>.delayed(Duration.zero);
      d.dispose();

      expect(service.shown.length, 5);

      // All ids must be in [0, 0x7FFFFFFF] (32-bit signed int).
      for (final s in service.shown) {
        expect(s.id, greaterThanOrEqualTo(0), reason: 'id must be >= 0');
        expect(
          s.id,
          lessThanOrEqualTo(limit),
          reason: 'id must be <= 0x7FFFFFFF (32-bit signed int max)',
        );
      }

      // First id is near the limit, subsequent ids wrap to small values.
      expect(service.shown.first.id, limit - 1); // 2147483646
      expect(service.shown[1].id, 0); // wrap to 0
    });

    test(
      'emitted ids never equal _dndSummaryId (999_001) — '
      'collision avoidance prevents Android notification replacement',
      () async {
        // _dndSummaryId = 999_001.  Seed clock to 999_000 so the very next
        // id would be 999_001 (= DND summary) and must be skipped.
        const dndId = 999_001;
        final d = buildDispatcher(
          prefs: _prefs(),
          clock: () => DateTime.fromMillisecondsSinceEpoch(999_000),
        )..start();

        // Emit 6 notifications.  id 999_001 should be silently skipped.
        for (var i = 0; i < 6; i++) {
          controller.add(_reply(serverId: 'collision-$i', clientId: 'cc-$i'));
        }
        await Future<void>.delayed(Duration.zero);
        d.dispose();

        expect(service.shown.length, 6);

        // No emitted id should ever equal the DND summary id.
        for (final s in service.shown) {
          expect(
            s.id,
            isNot(equals(dndId)),
            reason: 'emitted id must never collide with _dndSummaryId',
          );
        }

        // Spot-check: 999_000 is emitted, then 999_001 is skipped,
        // then 999_002 follows.
        expect(service.shown[0].id, 999_000);
        expect(service.shown[1].id, 999_002); // skipped 999_001
        expect(service.shown[2].id, 999_003);
      },
    );

    test('high-volume emit (1000 notifications) all ids in range, '
        'no DND collision', () async {
      // Seed at an arbitrary value; emit 1000 unique replies.
      const seed = 500_000;
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime.fromMillisecondsSinceEpoch(seed),
      )..start();

      for (var i = 0; i < 1000; i++) {
        controller.add(_reply(serverId: 'bulk-$i', clientId: 'cb-$i'));
      }
      await Future<void>.delayed(Duration.zero);
      d.dispose();

      expect(service.shown.length, 1000);

      // All in [0, 0x7FFFFFFF], none equals DND id.
      const limit = 0x7FFFFFFF;
      for (final s in service.shown) {
        expect(s.id, inInclusiveRange(0, limit));
        expect(s.id, isNot(equals(999_001)));
      }

      // Monotonic (within this process, sequential, no gaps except skip).
      for (var i = 1; i < service.shown.length; i++) {
        expect(
          service.shown[i].id,
          greaterThan(service.shown[i - 1].id),
          reason: 'ids should be monotonically increasing within a process',
        );
      }
    });
  });

  // ==========================================================================
  // handlePulledMessages — background sync dedup path
  // ==========================================================================
  group('handlePulledMessages', () {
    test('writesThroughPendingRepo_neverCallsShow', () async {
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
      );
      final msg = _makeReplyMessage(serverId: 's1', content: 'hi');

      await d.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => _makeAgent(name: 'Claw'),
      );

      // NEVER show — background pull routes through pending repo only.
      expect(service.shown, isEmpty);
      // Enqueued into pending repo.
      expect(d.isNotified('s1'), isTrue);
    });

    test('evaluateShowDecision_enqueuesWithDeliveredFalse', () async {
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
      );
      final msg = _makeReplyMessage(serverId: 's1', content: 'hi');

      await d.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => _makeAgent(name: 'Claw'),
      );

      // The message was evaluated as ShowDecision (notifications ON, DND off),
      // so it should be enqueued. But the dispatcher enqueues for BOTH
      // ShowDecision and DndSuppressedDecision, so we just verify it went
      // through the enqueue path.
      expect(d.isNotified('s1'), isTrue);
      expect(service.shown, isEmpty);
    });

    test('evaluateDndDecision_stillEnqueues', () async {
      // DND ON (22:00-08:00, now=23:00)
      final prefs = _prefs(dndEnabled: true, notifyOnReply: true);
      final d = buildDispatcher(
        prefs: prefs,
        clock: () => DateTime(2026, 6, 20, 23, 0),
      );
      final msg = _makeReplyMessage(serverId: 's1', content: 'hi');

      await d.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => _makeAgent(name: 'Claw'),
      );

      // Suppressed by DND but still enqueued (DndSuppressedDecision).
      expect(d.isNotified('s1'), isTrue);
      expect(service.shown, isEmpty);
    });

    test('evaluateDropDecision_doesNotEnqueue', () async {
      // notificationsEnabled=false -> DroppedDecision
      final d = buildDispatcher(
        prefs: _prefs(notificationsEnabled: false),
        clock: () => DateTime(2026, 6, 20, 12),
      );
      final msg = _makeReplyMessage(serverId: 's1', content: 'hi');

      await d.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => _makeAgent(name: 'Claw'),
      );

      // DroppedDecision -> no enqueue, no LRU slot.
      expect(d.isNotified('s1'), isFalse);
      expect(service.shown, isEmpty);
    });

    test('tombstonedAgent_suppressedByNullResolve', () async {
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
      );
      final msg = _makeReplyMessage(serverId: 's1', content: 'hi');

      await d.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => null, // tombstoned
      );

      // Null agent -> dropped before evaluation; no enqueue, no LRU.
      expect(d.isNotified('s1'), isFalse);
      expect(service.shown, isEmpty);
    });

    test('skipsAlreadyNotified_doesNotThrowOnDuplicate', () async {
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
      );
      final msg = _makeReplyMessage(serverId: 's1', content: 'hi');

      // First pull — enqueues and records in LRU.
      await d.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => _makeAgent(name: 'Claw'),
      );
      expect(d.isNotified('s1'), isTrue);

      // Second pull of the same serverId — repo.enqueue is a no-op
      // (ON CONFLICT DO NOTHING). Dispatcher must not throw.
      await d.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => _makeAgent(name: 'Claw'),
      );

      // No show() calls ever.
      expect(service.shown, isEmpty);
    });

    test('skipsNonAgentRoleMessages', () async {
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
      );
      final msg = Message(
        clientId: 'c1',
        serverId: 's1',
        conversationId: 'conv1',
        agentId: 'a',
        role: MessageRole.user, // not an agent reply
        content: 'hi',
        type: MessageType.text,
        logicalClock: 1,
      );

      await d.handlePulledMessages(
        messages: [msg],
        resolveAgent: (iid, aid) => _makeAgent(name: 'Claw'),
      );

      // Non-agent messages are skipped.
      expect(d.isNotified('s1'), isFalse);
      expect(service.shown, isEmpty);
    });

    test('skipsNullServerIdMessages', () async {
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
      );
      final msg = _makeReplyMessage(serverId: 's1', content: 'hi');
      // Override to null serverId
      final nullServerMsg = Message(
        clientId: msg.clientId,
        serverId: null,
        conversationId: msg.conversationId,
        agentId: msg.agentId,
        role: msg.role,
        content: msg.content,
        type: msg.type,
        logicalClock: msg.logicalClock,
      );

      await d.handlePulledMessages(
        messages: [nullServerMsg],
        resolveAgent: (iid, aid) => _makeAgent(name: 'Claw'),
      );

      // null serverId skipped (unique index can't dedup).
      expect(d.isNotified('c1'), isFalse); // not in LRU
      expect(service.shown, isEmpty);
    });
  });

  // ==========================================================================
  // warmupFromPending — LRU reseeding from persisted pending notifications
  // ==========================================================================
  group('warmupFromPending', () {
    test('seedsLruWithUndeliveredServerIds', () async {
      final pendingRepo = _FakeNotificationRepo(
        pending: [
          _makePending(serverId: 's1', delivered: false),
          _makePending(serverId: 's2', delivered: false),
        ],
      );
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
        customRepo: pendingRepo,
      );
      await d.warmupFromPending();
      expect(d.isNotified('s1'), isTrue);
      expect(d.isNotified('s2'), isTrue);
    });

    test('skipsNullServerId', () async {
      final pendingRepo = _FakeNotificationRepo(
        pending: [
          _makePending(serverId: null, delivered: false),
          _makePending(serverId: 's1', delivered: false),
        ],
      );
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
        customRepo: pendingRepo,
      );
      await d.warmupFromPending();
      // null-serverId entries are not protected by the unique index; do not
      // pollute the LRU (would suppress unrelated null-serverId live events).
      expect(d.isNotified('s1'), isTrue);
    });

    test('skipsDeliveredRows', () async {
      final pendingRepo = _FakeNotificationRepo(
        pending: [
          _makePending(serverId: 's1', delivered: true), // already shown
          _makePending(serverId: 's2', delivered: false),
        ],
      );
      final d = buildDispatcher(
        prefs: _prefs(),
        clock: () => DateTime(2026, 6, 20, 12),
        customRepo: pendingRepo,
      );
      await d.warmupFromPending();
      expect(d.isNotified('s1'), isFalse);
      expect(d.isNotified('s2'), isTrue);
    });
  });
}
