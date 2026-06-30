import 'dart:async';

import 'package:claw_hub/app/connection/instance_event.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_local_notification_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_notifier.dart';
import 'package:claw_hub/data/services/notification_dispatcher.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/notification_event.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_notification_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';

/// 通知协调器 (US-018 app 层装配)。
///
/// 把 Gateway 的 [IGatewayClient.messageStream] + [connectionStateStream]
/// 桥接为 domain [NotificationEvent] 流，喂给纯 data 层的
/// [NotificationDispatcher]。负责：
/// - 启动时主动枚举所有已保存实例建订阅 (避免漏掉首次连接)
/// - 监听 [orchestratorEvents] 的 [InstanceConnectedEvent]
///   作重连补充订阅
/// - Message(remoteId) → ReplyEvent：经 [IAgentRepo.findByCompositeKey]
///   解析 localId + displayName，构造点击深链 routePath
/// - GatewayConnectionState → NotificationConnectionState 折叠 +
///   per-instance 前态追踪 → ConnectionChangeEvent
/// - DND Timer 调度：
///   * 非DND 时段启动 → 立即补发跨重启积压，并排定下一个 DND 起点定时器；
///   * DND 时段 → 排定结束时刻定时器，到期触发 [NotificationDispatcher.flushDndSummary]；
///   * prefs 变更 → [onPrefsChanged] 重排。
class NotificationCoordinator {
  final Stream<InstanceEvent> orchestratorEvents;
  final IGatewayClient gatewayClient;
  final IInstanceRepo instanceRepo;
  final IAgentRepo agentRepo;
  final INotificationRepo notificationRepo;
  final ILocalNotificationService notificationService;
  final EvaluateNotificationUseCase evaluator;
  final UserPreferences Function() prefsProvider;
  final DateTime Function() clock;
  final ILogger logger;

  NotificationCoordinator({
    required this.orchestratorEvents,
    required this.gatewayClient,
    required this.instanceRepo,
    required this.agentRepo,
    required this.notificationRepo,
    required this.notificationService,
    required this.evaluator,
    required this.prefsProvider,
    required this.clock,
    required this.logger,
  });

  final StreamController<NotificationEvent> _eventSink =
      StreamController<NotificationEvent>.broadcast();

  /// instanceId → 当前已知连接态 (用于判定转换)。
  final Map<String, NotificationConnectionState> _lastConnState = {};

  /// instanceId → 各流订阅。重连补充时先取消旧的再建新的。
  final Map<String, _InstanceSubscriptions> _subs = {};

  StreamSubscription<InstanceEvent>? _orchestratorSub;
  Timer? _dndTimer;

  /// 上一次排定 Timer 时记录的 DND 签名 (是否启用 + 起止时分)。
  /// 用于 [onPrefsChanged] 跳过与 DND 无关的 prefs 变更 (如 notifyOnReply
  /// 切换)，避免无效的 getPending 查询与重复 flush。
  /// null 表示尚未排定过。
  String? _lastDndSignature;

  /// 由本 coordinator 拥有的 dispatcher (订阅 [_eventSink])。
  /// start() 前为 null；dispose() 据此判断是否需清理，避免访问未初始化的
  /// late 字段抛 LateInitializationError。
  NotificationDispatcher? _dispatcher;

  /// Exposes the dispatcher as [IBackgroundSyncNotifier] for the provider
  /// wiring. Returns a no-op notifier when not started (safe default).
  IBackgroundSyncNotifier get notifier =>
      _dispatcher ?? _NoOpBackgroundSyncNotifier();

  /// US-018: reseed the dispatcher's in-memory dedup LRU from persisted
  /// pending notifications. Called on main-isolate cold start so the live
  /// messageStream doesn't re-notify messages the background isolate enqueued.
  ///
  /// Must be called AFTER [start()] — [_dispatcher] is null before start.
  /// Null-safe: if [start()] failed or was never called, this is a no-op.
  Future<void> warmupDispatcherFromPending() async {
    await _dispatcher?.warmupFromPending();
  }

  bool _started = false;
  bool _disposed = false;

  /// 启动：构造并接线 dispatcher、枚举实例建订阅、监听重连事件、安排 DND Timer。
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // 构造 dispatcher 并接线 eventStream + routeFor。
    _dispatcher = NotificationDispatcher(
      eventStream: _eventSink.stream,
      prefsProvider: prefsProvider,
      repo: notificationRepo,
      notificationService: notificationService,
      evaluator: evaluator,
      clock: clock,
      logger: logger,
      routeFor: routeFor,
    );
    _dispatcher!.start();

    // 1. 主动枚举所有已保存实例，为每个建订阅。
    try {
      final instances = await instanceRepo.getAll();
      for (final inst in instances) {
        await _subscribeInstance(inst.id);
      }
    } catch (e, st) {
      logger.error(
        '[NotificationCoordinator] enumerate instances failed: $e',
        st,
      );
    }

    // 2. 监听重连补充订阅。
    _orchestratorSub = orchestratorEvents.listen((event) async {
      if (event is InstanceConnectedEvent) {
        // 实例重连后重新订阅 (旧订阅可能已失效)。
        await _subscribeInstance(event.instanceId);
      }
    });

    // 3. 安排 DND Timer (内部按当前是否在 DND 决定补发/排定)。
    _scheduleDndTimer();
  }

  /// 设置变更时重排 DND Timer。
  ///
  /// 由 [NotificationBootstrap] 在 prefs 流更新时调用。仅当 DND 相关字段
  /// (启用 / 起止时分) 真正变化时才重排 + 补发；与 DND 无关的 prefs 变更
  /// (如 notifyOnReply 切换) 通知由 dispatcher 经 prefsProvider 实时生效，
  /// 此处跳过，避免无效的 getPending 查询与重复 flush。
  void onPrefsChanged() {
    if (!_started || _disposed) return;
    final sig = _dndSignature(prefsProvider());
    if (sig == _lastDndSignature) return;
    _scheduleDndTimer();
  }

  /// DND 签名 —— 捕获影响 Timer 排定的字段。
  String _dndSignature(UserPreferences p) =>
      '${p.dndEnabled}|${p.dndStartHour}:${p.dndStartMinute}-'
      '${p.dndEndHour}:${p.dndEndMinute}';

  Future<void> dispose() async {
    _disposed = true;
    _dndTimer?.cancel();
    _dndTimer = null;
    await _orchestratorSub?.cancel();
    _orchestratorSub = null;
    for (final s in _subs.values) {
      await s.cancel();
    }
    _subs.clear();
    // start() 可能从未执行 (dispatcher 为 null)，需空判断。
    await _dispatcher?.dispose();
    _dispatcher = null;
    await _eventSink.close();
  }

  // ---------------------------------------------------------------------------

  Future<void> _subscribeInstance(String instanceId) async {
    if (_disposed) return;
    // 取消旧订阅 (重连补充场景) 并 await，避免快速重连时旧订阅 cancel
    // 与新订阅建立竞争 (fire-and-forget cancel 可能让旧流的事件在新流
    // 建立后才送达，造成重复/乱序)。
    await _subs.remove(instanceId)?.cancel();

    final messageSub = gatewayClient
        .messageStream(instanceId)
        .listen(
          (msg) => _onMessage(instanceId, msg),
          onError: (Object e, StackTrace st) => logger.error(
            '[NotificationCoordinator] messageStream error: $e',
            st,
          ),
        );

    final connSub = gatewayClient
        .connectionStateStream(instanceId)
        .listen(
          (state) => _onConnectionState(instanceId, state),
          onError: (Object e, StackTrace st) => logger.error(
            '[NotificationCoordinator] connectionStateStream error: $e',
            st,
          ),
        );

    _subs[instanceId] = _InstanceSubscriptions(messageSub, connSub);
  }

  Future<void> _onMessage(String instanceId, Message msg) async {
    // 仅 Agent 回复触发通知 (用户自己发的消息不通知)。
    if (msg.role != MessageRole.agent) return;
    if (msg.content == null || msg.content!.isEmpty) return;

    try {
      // Message.agentId 是 Gateway remoteId → 解析为本地 Agent (localId + 名称)。
      final agent = await agentRepo.findByCompositeKey(instanceId, msg.agentId);
      // US-021: 抑制 tombstoned agent 的回复通知。findByCompositeKey 故意
      // 不过滤 (OutboxProcessor/sync 复活契约)，但 UI 层（ChatRoom / Profile /
      // Config）均显示"已移除"占位页。Notification 与这些 UI 路径独立，若不
      // 显式过滤会出现"通知显示已删除 agent 的回复，但点进去看到占位页"
      // 的体验脱节。
      if (agent != null && agent.isRemoved) {
        logger.info(
          '[NotificationCoordinator] suppressed reply from tombstoned '
          'agent: remoteId=${msg.agentId}',
        );
        return;
      }
      final agentName = agent?.displayName ?? '虾';
      final localId = agent?.localId ?? msg.agentId;

      _eventSink.add(
        ReplyEvent(
          agentId: localId,
          instanceId: instanceId,
          agentName: agentName,
          contentPreview: msg.content!,
          messageServerId: msg.serverId,
          messageClientId: msg.clientId,
        ),
      );
    } catch (e, st) {
      logger.error('[NotificationCoordinator] resolve agent failed: $e', st);
    }
  }

  void _onConnectionState(String instanceId, GatewayConnectionState state) {
    final mapped = _mapConnState(state);
    final prev = _lastConnState[instanceId];
    _lastConnState[instanceId] = mapped;

    if (prev == null) {
      // 首次观察到的状态 — 不产生"变化"通知 (避免启动刷屏)。
      return;
    }
    if (prev == mapped) return;

    _resolveInstanceName(instanceId).then((name) {
      if (_disposed) return;
      // 陈旧校验：在异步解析实例名期间，若同一实例又收到一次状态变化，
      // _lastConnState 已被更新为新值。此时本次回调的 toState 已不再是
      // "当前态"，发出的会是过期事件 → 弱网抖动下可能乱序/误报 online drop。
      // 丢弃陈旧解析，让最新状态自己重新走一遍判定流程。
      if (_lastConnState[instanceId] != mapped) return;
      _eventSink.add(
        ConnectionChangeEvent(
          instanceId: instanceId,
          instanceName: name,
          fromState: prev,
          toState: mapped,
        ),
      );
    });
  }

  Future<String> _resolveInstanceName(String instanceId) async {
    try {
      final inst = await instanceRepo.getById(instanceId);
      return inst?.name ?? '实例';
    } catch (_) {
      return '实例';
    }
  }

  NotificationConnectionState _mapConnState(GatewayConnectionState s) {
    switch (s) {
      case GatewayConnectionState.connected:
        return NotificationConnectionState.online;
      case GatewayConnectionState.connecting:
      case GatewayConnectionState.authenticating:
      case GatewayConnectionState.recovering:
        return NotificationConnectionState.reconnecting;
      case GatewayConnectionState.disconnected:
      case GatewayConnectionState.authFailed:
      case GatewayConnectionState.pairingRequired:
      case GatewayConnectionState.reconnectExhausted:
        return NotificationConnectionState.offline;
    }
  }

  // ---------------------------------------------------------------------------
  // DND 到期 Timer

  void _scheduleDndTimer() {
    _dndTimer?.cancel();
    _dndTimer = null;
    if (_disposed) return;

    final prefs = prefsProvider();
    final now = clock();
    _lastDndSignature = _dndSignature(prefs);

    if (evaluator.isInDnd(prefs, now)) {
      // 当前在 DND 内 —— 排定结束时刻定时器，到期补发汇总后重排。
      final end = evaluator.nextDndEndTime(prefs, now);
      if (end == null) {
        // 全天 DND：没有结束时刻，不排定时器、不周期补发。
        // 积压由用户关闭 DND 时的 [onPrefsChanged] → 非DND 分支补发。
        return;
      }
      _dndTimer = Timer(end.difference(now), () {
        if (_disposed) return;
        _flushSummary();
        _scheduleDndTimer();
      });
    } else {
      // 当前不在 DND 内 —— 立即补发跨重启积压 (App 在 DND 内被杀后重启、
      // 或前台跨过整个 DND 窗口的场景)，然后排定下一个 DND 起点定时器。
      // flush 幂等：无积压时 getPending 返回空，直接返回。
      _flushSummary();

      final start = evaluator.nextDndStartTime(prefs, now);
      if (start == null) return; // DND 关闭 / 全天且不在窗口 (理论上不会到这里)
      final delay = start.difference(now);
      if (delay <= Duration.zero) {
        // 起点已到/已过 —— 直接重排 (进入在-DND 分支)。
        _scheduleDndTimer();
        return;
      }
      _dndTimer = Timer(delay, () {
        if (_disposed) return;
        // 进入 DND —— 重排为结束时刻定时器。
        _scheduleDndTimer();
      });
    }
  }

  Future<void> _flushSummary() async {
    try {
      await _dispatcher?.flushDndSummary();
    } catch (e, st) {
      logger.error('[NotificationCoordinator] flush summary failed: $e', st);
    }
  }

  /// 生成回复事件的点击深链路径 (注入 dispatcher 的 routeFor)。
  String? routeFor(NotificationEvent event) {
    if (event is ReplyEvent) {
      return AppRoutes.chatWithParams(
        event.agentId,
        event.instanceId,
        source: 'messages',
      );
    }
    // 错误/连接变化无单条深链。
    return null;
  }
}

/// 单个实例的两条流订阅。
class _InstanceSubscriptions {
  final StreamSubscription<Message> message;
  final StreamSubscription<GatewayConnectionState> connection;

  _InstanceSubscriptions(this.message, this.connection);

  Future<void> cancel() async {
    await message.cancel();
    await connection.cancel();
  }
}

/// No-op [IBackgroundSyncNotifier] used as a safe default when the
/// coordinator has not been started yet.
class _NoOpBackgroundSyncNotifier implements IBackgroundSyncNotifier {
  @override
  Future<void> handlePulledMessages({
    required List<Message> messages,
    required Agent? Function(String instanceId, String agentRemoteId)
    resolveAgent,
  }) async {
    // No-op: coordinator not started yet.
  }
}
