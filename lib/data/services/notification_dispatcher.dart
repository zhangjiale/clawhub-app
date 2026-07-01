import 'dart:async';
import 'dart:collection';

import 'package:claw_hub/core/i_local_notification_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_notifier.dart';
import 'package:claw_hub/domain/models/agent.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/notification_event.dart';
import 'package:claw_hub/domain/models/pending_notification.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/repositories/i_notification_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';
import 'package:claw_hub/data/services/background_notifier_shared.dart';
import 'package:flutter/foundation.dart';

/// 通知分发器 (US-018 核心消费层，纯 data)。
///
/// 订阅一条 [NotificationEvent] 流 (由 app 层 [NotificationCoordinator]
/// 把 messageStream + connectionStateStream 桥接而成)，对每条事件：
/// 1. 去重 (内存 LRU，上限 500，key = serverId ?? clientId)
/// 2. 调 [EvaluateNotificationUseCase] 判定决策
/// 3. [ShowDecision] → 立即 [ILocalNotificationService.show]
///    [DndSuppressedDecision] → 入 [INotificationRepo] 静默队列
///    [DroppedDecision] → 丢弃
///
/// DND 到期汇总：[flushDndSummary] 把队列里所有未投递条目合并成一条
/// "N 条新消息"通知发出，并标记 delivered。由 [NotificationCoordinator]
/// 在 DND 结束时 (Timer) 或 App 启动补发时调用。
///
/// **分层**：本类禁止 import `app/`。路由路径通过注入的 [routeFor]
/// 回调生成 (由 coordinator 提供基于 AppRoutes 的实现)，避免逆向依赖。
class NotificationDispatcher implements IBackgroundSyncNotifier {
  final Stream<NotificationEvent> eventStream;
  final UserPreferences Function() prefsProvider;
  final INotificationRepo repo;
  final ILocalNotificationService notificationService;
  final EvaluateNotificationUseCase evaluator;
  final DateTime Function() clock;
  final ILogger logger;

  /// 把事件转为点击跳转的路由路径 (由 app 层注入)。
  /// 返回 null 表示该事件无深链 (如连接变化)。
  final String? Function(NotificationEvent) routeFor;

  /// 连接变化事件的去重窗口 —— 同一 (instance, toState) 在此窗口内重复
  /// 出现被视为抖动，节流为一条；窗口外的再次出现仍会通知。
  ///
  /// 解决"首次掉线→重连→再掉线"被永久抑制的问题：连接事件不再进入
  /// 永久 LRU，而是按时间窗口节流。
  final Duration connectionDedupWindow;

  NotificationDispatcher({
    required this.eventStream,
    required this.prefsProvider,
    required this.repo,
    required this.notificationService,
    required this.evaluator,
    required this.clock,
    required this.logger,
    String? Function(NotificationEvent)? routeFor,
    this.connectionDedupWindow = const Duration(seconds: 30),
  }) : routeFor = routeFor ?? _defaultRouteFor {
    _nextNotificationId = clock().millisecondsSinceEpoch % _maxNotificationId;
  }

  StreamSubscription<NotificationEvent>? _subscription;

  /// LRU 去重集合 — 已通知过的回复消息身份 key。上限 [_dedupCap]，
  /// 超出后淘汰最旧 (LinkedHashSet 保持插入顺序 = LRU)。
  static const _dedupCap = 500;
  final LinkedHashSet<String> _notifiedKeys = LinkedHashSet<String>();

  /// 连接变化节流表 — `Object.hash(instanceId, toState)` → 最近一次记录的
  /// 毫秒时间戳。按 (instance, 状态) 数量有界 (实例数 × 3)，无需淘汰。
  final Map<int, int> _lastConnNotifyMs = {};

  /// 单调递增的通知 id (同一进程内)。回复/错误/连接共用一个 id 空间。
  ///
  /// 起点取自注入 clock 的毫秒时间戳对 [\_maxNotificationId] 取模 —— 进程
  /// 重启后起点通常随时间推进，与上一进程残留通知 id 碰撞的概率极低。
  /// (Android 按 id 去重，相同 id 的 show 会替换而非追加。)
  /// 用 clock 而非 DateTime.now() 以保证单测可注入固定时间。
  ///
  /// Android flutter_local_notifications 要求 id 在 32-bit signed int 范围内
  /// ([-2^31, 2^31-1])，因此对 2^31 取模并在递增时回卷。
  /// 回卷时跳过 [\_dndSummaryId]，避免与 DND 汇总通知碰撞。
  late int _nextNotificationId;

  /// 通知 id 上限 (2^31 - 1)，Android 要求 id 必须 ≤ 此值。
  static const _maxNotificationId = 0x7FFFFFFF;

  /// DND 汇总通知用的固定 id。
  static const _dndSummaryId = 999_001;

  void start() {
    _subscription = eventStream.listen(
      _handleEvent,
      onError: (Object e, StackTrace st) =>
          logger.error('[NotificationDispatcher] stream error: $e', st),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  // ---------------------------------------------------------------------------

  /// US-018 background sync entry point.
  ///
  /// Delegates to [BackgroundNotifierShared.enqueuePulled] for the evaluate
  /// → enqueue contract, then records enqueued dedup keys in the in-memory
  /// LRU so concurrent live events for the same serverId are suppressed.
  ///
  /// **Never** calls [notificationService.show] — the live `messageStream`
  /// (or DND flush) is the only path that shows. This keeps cross-isolate
  /// dedup convergent: the background isolate has an empty in-memory LRU,
  /// so the persistent index is the single source of truth.
  ///
  /// [resolveAgent] returns the agent (for name + tombstone) or null if the
  /// caller (BackgroundSyncRunner) decided to suppress (e.g. tombstoned).
  /// Null agent → message dropped, not enqueued.
  @override
  Future<void> handlePulledMessages({
    required List<Message> messages,
    required Agent? Function(String agentRemoteId) resolveAgent,
  }) async {
    await BackgroundNotifierShared.enqueuePulled(
      messages: messages,
      resolveAgent: resolveAgent,
      prefs: prefsProvider(),
      evaluator: evaluator,
      repo: repo,
      logger: logger,
      clock: clock,
      // Record each enqueued dedup key in the in-memory LRU so concurrent
      // live events for the same serverId are suppressed this session.
      onEnqueued: _recordNotified,
    );
  }

  /// Reseed the in-memory dedup LRU from persisted pending notifications.
  ///
  /// Called on main-isolate cold start (NotificationBootstrap) so the live
  /// `messageStream` doesn't re-notify messages the background isolate
  /// already enqueued. Only undelivered rows with a non-null serverId are
  /// seeded (delivered = already shown; null-serverId = not index-protected).
  Future<void> warmupFromPending() async {
    try {
      final pending = await repo.getPending();
      for (final p in pending) {
        if (p.delivered) continue;
        final key = p.messageServerId;
        if (key == null) continue;
        _notifiedKeys.add(key);
      }
      _evictIfFull();
    } catch (e, st) {
      logger.error('[Dispatcher] warmupFromPending failed: $e', st);
    }
  }

  /// Test-only: whether a dedup key is currently in the LRU.
  @visibleForTesting
  bool isNotified(String key) => _notifiedKeys.contains(key);

  /// Record a dedup key in the in-memory LRU, evicting oldest if full.
  void _recordNotified(String key) {
    _notifiedKeys.add(key);
    _evictIfFull();
  }

  // ---------------------------------------------------------------------------

  Future<void> _handleEvent(NotificationEvent event) async {
    try {
      // 连接变化：在评估前按时间窗口节流 (抖动抑制与通知开关无关)。
      if (event is ConnectionChangeEvent && _isConnDuplicate(event)) {
        return;
      }

      final prefs = prefsProvider();
      final decision = evaluator.evaluate(event, prefs, clock());

      switch (decision) {
        case ShowDecision(:final title, :final body, :final event):
          // 回复类仅在"实际会通知"时才占去重槽 —— 这样开关关闭期间到达的
          // 消息，用户事后打开开关、同一 serverId 再次投递时仍能补收。
          // 但若该 serverId 已被通知过 (catch-up 二次到达)，丢弃。
          if (event is ReplyEvent && _isReplyDuplicate(event)) return;
          _consumeReplyDedupSlot(event);
          await notificationService.show(
            id: _consumeNotificationId(),
            channel: _channelFor(event),
            title: title,
            body: body,
            routePath: routeFor(event),
          );
        case DndSuppressedDecision(:final event):
          if (event is ReplyEvent && _isReplyDuplicate(event)) return;
          _consumeReplyDedupSlot(event);
          // 命中 DND 入静默队列 (占槽避免 catch-up 二次到达重复入队)。
          await _enqueueSuppressed(event, prefs);
        case DroppedDecision():
          // 开关关闭 / 噪音 —— 不占回复去重槽，事后开开关仍可补收。
          break;
      }
    } catch (e, st) {
      logger.error('[NotificationDispatcher] handle event failed: $e', st);
    }
  }

  /// 回复事件去重槽：仅在通知/静默时占。重复 (catch-up 二次到达) 时返回
  /// false 提示已占。错误/连接变化不走此槽。
  void _consumeReplyDedupSlot(NotificationEvent event) {
    if (event is! ReplyEvent) return;
    final key = event.messageServerId ?? event.messageClientId;
    _notifiedKeys.add(key);
    _evictIfFull();
  }

  /// 该回复事件的去重槽是否已被占用 (catch-up 二次到达等)。
  bool _isReplyDuplicate(ReplyEvent event) {
    final key = event.messageServerId ?? event.messageClientId;
    return _notifiedKeys.contains(key);
  }

  /// 连接变化按 (instance, toState) 时间窗口节流。窗口内同状态重复视为
  /// 抖动返回 true；窗口外允许再次通知 (避免"掉线→重连→再掉线"被永久抑制)。
  bool _isConnDuplicate(ConnectionChangeEvent event) {
    // 用 Object.hash 生成 key，避免 instanceId 含 ':' 时与字符串拼接冲突。
    final key = Object.hash(event.instanceId, event.toState);
    final nowMs = clock().millisecondsSinceEpoch;
    final last = _lastConnNotifyMs[key];
    if (last != null && nowMs - last < connectionDedupWindow.inMilliseconds) {
      return true;
    }
    _lastConnNotifyMs[key] = nowMs;
    return false;
  }

  /// DND 到期汇总：把所有未投递条目合并成一条通知发出，标记 delivered。
  ///
  /// **原子性顺序**：先 `show` 再 `markDeliveredBatch` 再 `clearDelivered`。
  /// 理由：若 `show` 抛错，条目仍为未投递态，下次 flush 重试 (通知可重复，
  /// 丢消息不可接受)；若先 mark 后 show，show 失败会丢消息。show 成功后
  /// 才标记并清理。
  ///
  /// Law 6：单条 `markDeliveredBatch` 批量更新，避免逐 id N+1 写。
  Future<void> flushDndSummary() async {
    try {
      final pending = await repo.getPending();
      if (pending.isEmpty) return;

      final count = pending.length;
      final body = count == 1 ? pending.first.summary : '$count 条新消息';

      // 1. 先发通知。失败则条目保留在队列，下次 flush 重试 (消息不丢)。
      await notificationService.show(
        id: _dndSummaryId,
        channel: NotificationChannelId.reply,
        title: '虾Hub',
        body: body,
        // 汇总无法定位单条消息，不带深链；点击进 App 首页。
        routePath: null,
      );

      // 2. 通知成功后再批量标记 delivered (单条 SQL)。
      final ids = pending.map((n) => n.id).toList(growable: false);
      await repo.markDeliveredBatch(ids);

      // 3. 清理已投递条目。
      await repo.clearDelivered();
    } catch (e, st) {
      logger.error('[NotificationDispatcher] flush DND summary failed: $e', st);
    }
  }

  // ---------------------------------------------------------------------------

  Future<void> _enqueueSuppressed(
    NotificationEvent event,
    UserPreferences prefs,
  ) async {
    if (event is! ReplyEvent) {
      // 仅回复类入静默队列 (错误/连接变化在 DND 内静默丢弃，不补发)。
      return;
    }
    // Build the row via the shared factory so the row shape lives in one
    // place (same as BackgroundNotifierShared.enqueuePulled) — a future
    // PendingNotification field addition only needs to update the factory.
    await repo.enqueue(
      PendingNotification.fromReplyEvent(
        event,
        nowEpochSeconds: clock().millisecondsSinceEpoch ~/ 1000,
      ),
    );
  }

  /// 取出当前通知 id 并递增 (回卷保证不超 32-bit 上限)。
  ///
  /// 若当前 id 恰好等于 [\_dndSummaryId]，自动跳过下一个，避免与 DND
  /// 汇总通知碰撞 (Android 按 id 去重，碰撞会导致汇总被替换或反之)。
  int _consumeNotificationId() {
    var id = _nextNotificationId;
    _nextNotificationId = (_nextNotificationId + 1) % _maxNotificationId;
    // 跳过 DND 汇总 id — 递推消耗下一个。
    if (id == _dndSummaryId) {
      id = _nextNotificationId;
      _nextNotificationId = (_nextNotificationId + 1) % _maxNotificationId;
    }
    return id;
  }

  void _evictIfFull() {
    while (_notifiedKeys.length > _dedupCap) {
      _notifiedKeys.remove(_notifiedKeys.first);
    }
  }

  NotificationChannelId _channelFor(NotificationEvent event) {
    switch (event) {
      case ReplyEvent():
        return NotificationChannelId.reply;
      case ErrorEvent():
        return NotificationChannelId.error;
      case ConnectionChangeEvent():
        return NotificationChannelId.connection;
    }
  }

  /// 默认 routeFor — 不提供深链 (data 层不知路由)。
  /// coordinator 注入真实实现。
  static String? _defaultRouteFor(NotificationEvent event) => null;
}
