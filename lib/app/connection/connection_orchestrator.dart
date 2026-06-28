import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../core/acl/i_gateway_client.dart';
import '../../core/iconnectivity.dart';
import '../../core/utils/retry_strategy.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/instance.dart';
import '../../domain/repositories/i_agent_repo.dart';
import '../../domain/repositories/i_instance_repo.dart';
import '../../domain/usecases/instance_lifecycle.dart';
import 'instance_event.dart';

/// 实例连接编排器 — 管理所有 Gateway 实例的连接生命周期。
///
/// 职责：
/// - 应用启动时自动连接所有已保存的在线实例
/// - 实例保存/删除时触发相应的 connect/disconnect
/// - 监听网络变化（WiFi ↔ 4G），自动处理内网实例的降级与恢复
/// - 同步 GatewayConnectionState → HealthStatus（写回数据库）
///
/// 作为全局单例由 Riverpod Provider 持有，生命周期与 App 一致。
/// 初始化由 `ConnectionInitializer.initState` 在 widget 树首次 build 时触发。
///
/// 实现 [IInstanceLifecycle]，供 UseCase 层在持久化操作后回调，
/// 使 UI 层无需直接依赖本类。
class ConnectionOrchestrator implements IInstanceLifecycle {
  final IGatewayClient _gatewayClient;
  final IInstanceRepo _instanceRepo;
  final IAgentRepo _agentRepo;
  final IConnectivity _connectivity;

  /// 生命周期事件广播流 — 收编历史上累积的三个离散回调字段
  /// （agent 同步完成 / 配对信息变更 / 实例连接完成）。
  /// 新增生命周期关注点时只加 [InstanceEvent] 子类型，不扩构造函数签名。
  /// broadcast 模式：多个消费者可同时订阅；无订阅者时事件直接丢弃，不抛异常。
  final StreamController<InstanceEvent> _eventController =
      StreamController<InstanceEvent>.broadcast();

  /// 生命周期事件流。订阅必须在 [initialize] 之前完成 ——
  /// `connectionOrchestratorProvider` 的 body 同步建订阅，
  /// `initialize()` 由 `_ConnectionInitializer` 在其后异步调用，
  /// 故晚订阅丢事件的风险不存在（已核对 main.dart:76-77 时序）。
  Stream<InstanceEvent> get events => _eventController.stream;

  /// instanceId → GatewayConnectionState 订阅
  final Map<String, StreamSubscription<GatewayConnectionState>>
  _connectionSubscriptions = {};

  /// instanceId → GatewayPairingInfo 订阅
  final Map<String, StreamSubscription<GatewayPairingInfo?>>
  _pairingInfoSubscriptions = {};

  /// 网络监听订阅
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// 避免在 connect() 内部触发的状态同步中重复调用 disconnect
  final Set<String> _connecting = {};

  /// 避免同一实例的 agent 同步并发执行
  final Set<String> _syncingAgents = {};

  /// 同步期间收到新 connected 事件的实例 — 当前同步完成后触发重试。
  final Set<String> _syncPendingRetry = {};

  /// 防抖：记录每个实例最近一次 [reconnect] 调用时间，
  /// 忽略 2 秒内的重复点击。
  final Map<String, DateTime> _lastReconnectAttempt = {};

  /// 网络操作代数计数器 — 每次降级/恢复递增，
  /// 操作内每次 await 后校验，旧操作若被新操作取代则提前退出，
  /// 防止 WiFi→4G→WiFi 快速切换时降级与恢复交错执行。
  int _networkOpGeneration = 0;

  /// 标记 dispose 已调用，initialize() 中的异步操作应提前退出。
  bool _isDisposed = false;

  /// 按 instanceId 序列化 [_onConnectionStateChanged] 的异步调用（Bug 4）。
  ///
  /// Dart 广播流在 async 回调的 Future 完成前就会投递下一个事件。
  /// Completer 链保证同一实例的两次状态变化不会交错执行，
  /// 防止 await _instanceRepo.getById() 读到脏数据。
  final Map<String, Completer<void>> _stateSerializers = {};

  /// 可注入的时间函数，用于测试 reconnect 防抖逻辑。
  /// 生产环境默认使用 [DateTime.now]。
  final DateTime Function() _clock;

  /// do-while 同步循环迭代间的最小冷却时间。
  ///
  /// 防止 connected 事件在同步完成时恰好触发导致的即时重试风暴。
  /// 测试可注入 [Duration.zero] 以避免测试中的真实延迟。
  final Duration _syncLoopCooldown;

  ConnectionOrchestrator({
    required IGatewayClient gatewayClient,
    required IInstanceRepo instanceRepo,
    required IAgentRepo agentRepo,
    IConnectivity? connectivity,
    DateTime Function()? clock,
    Duration syncLoopCooldown = const Duration(seconds: 1),
  }) : _gatewayClient = gatewayClient,
       _instanceRepo = instanceRepo,
       _agentRepo = agentRepo,
       _connectivity = connectivity ?? ConnectivityAdapter(),
       _clock = clock ?? (() => DateTime.now()),
       _syncLoopCooldown = syncLoopCooldown;

  // ---------------------------------------------------------------------------
  // 公开 API
  // ---------------------------------------------------------------------------

  /// 初始化：自动连接所有可连接的已保存实例，启动网络监听。
  ///
  /// 启动时对除 [HealthStatus.expectedOffline] 外的所有实例尝试建连：
  /// - online / unknown：常规自动连接（通过 [HealthStatus.isConnectable]）。
  /// - offline：可能是上次运行的 authFailed / disconnected / connect 失败，
  ///   更关键的是 [HealthStatus.pairingRequired] 落库为 offline 的场景 —
  ///   服务器侧审批可能在 App 关闭期间完成，重启后重试即可恢复连接。
  /// - pairingRequired：向后兼容旧版 DB 数据（修复前落库的值=5），
  ///   后续不再产生新数据。
  /// - expectedOffline：因 WiFi→4G 被标记，等 WiFi 恢复事件再触发重连。
  ///
  /// 所有实例并行连接（每实例独立超时 10 秒），
  /// 避免多实例场景下串行阻塞的启动延迟。
  Future<void> initialize() async {
    final instances = await _instanceRepo.getAll();
    if (_isDisposed) return;

    final toConnect = instances.where(
      (i) => i.healthStatus.shouldAttemptReconnect,
    );

    // 并行连接所有候选实例
    if (toConnect.isNotEmpty) {
      await Future.wait(
        toConnect.map(
          (instance) => _connect(instance).timeout(
            const Duration(seconds: 10),
            onTimeout: () async {
              if (_isDisposed) return;
              debugPrint(
                '[ConnectionOrchestrator] Init connect timeout for '
                '${instance.id} (${instance.name})',
              );
              await _updateHealthStatus(instance.id, HealthStatus.offline);
            },
          ),
        ),
      );
    }
    if (_isDisposed) return;

    // 启动网络监听
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    debugPrint('[ConnectionOrchestrator] Initialized');
  }

  /// 实例保存后调用（新建或编辑）。
  ///
  /// 新建实例时建立初始 WebSocket 连接。
  /// 编辑已有实例时，若连接已存在则跳过重连——避免每次保存都触发
  /// agent 全量同步（syncFromGateway），防止因 Gateway 返回数据差异
  /// 或本地 DB 状态异常导致 agent 被意外 tombstone/重建。
  @override
  Future<void> onInstanceSaved(Instance instance) async {
    if (_connectionSubscriptions.containsKey(instance.id)) {
      // 编辑已有实例：连接已存在，不需重连。
      // 若需强制重连（如 token 变化），用户可通过 UI 手动刷新。
      return;
    }

    // 新建实例：建立初始连接
    await _connect(instance);
  }

  /// 实例删除后调用。
  @override
  Future<void> onInstanceDeleted(String instanceId) async {
    await _disconnect(instanceId);
  }

  /// 手动触发重连（如用户在 UI 点击刷新按钮）。
  ///
  /// 对任意状态（offline、pairingRequired、online 等）的实例发起连接，
  /// ConnectionManager 内置的指数退避/配对重试机制会接管后续流程。
  ///
  /// 内置 2 秒防抖：同一实例的快速重复点击会被忽略，
  /// 避免在 UI 快速连点时触发多次 WebSocket 连接尝试。
  Future<void> reconnect(Instance instance) async {
    final now = _clock();
    final lastAttempt = _lastReconnectAttempt[instance.id];
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 2)) {
      return; // debounce: ignore rapid re-taps
    }
    _lastReconnectAttempt[instance.id] = now;
    await _connect(instance);
  }

  /// 释放所有资源。
  Future<void> dispose() async {
    _isDisposed = true;
    _connectivitySubscription?.cancel();

    // 断开所有活跃实例的 Gateway 连接
    final instanceIds = _connectionSubscriptions.keys.toList();
    // iron-law-allow: Law8 -- fire-and-forget dispose, errors suppressed
    await Future.wait(
      instanceIds.map(
        (id) => _gatewayClient.disconnect(id).catchError((_) {
          // suppressed
        }),
      ),
    );

    for (final sub in _connectionSubscriptions.values) {
      await sub.cancel();
    }
    _connectionSubscriptions.clear();

    for (final sub in _pairingInfoSubscriptions.values) {
      await sub.cancel();
    }
    _pairingInfoSubscriptions.clear();
    _connecting.clear();

    await _eventController.close();
  }

  // ---------------------------------------------------------------------------
  // 内部：连接管理
  // ---------------------------------------------------------------------------

  Future<void> _connect(Instance instance) async {
    // 防止重复连接
    if (_connecting.contains(instance.id)) {
      return;
    }
    _connecting.add(instance.id);

    try {
      // 1. 订阅连接状态变化 BEFORE connect()，确保不会错过初始 connected 事件。
      //    connect() 内部完成 WebSocket 握手后立即发出 connected，若订阅在
      //    await connect() 之后才注册，BroadcastStream 会丢弃该事件，
      //    导致 _onConnectionStateChanged（包括 _syncAgentsForInstance）永不触发。
      final sub = _gatewayClient
          .connectionStateStream(instance.id)
          .listen((state) => _onConnectionStateChanged(instance.id, state));

      // 替换已有订阅（编辑场景：先取消旧订阅再保存新引用）
      await _connectionSubscriptions[instance.id]?.cancel();
      _connectionSubscriptions[instance.id] = sub;

      // 订阅配对信息流
      await _pairingInfoSubscriptions[instance.id]?.cancel();
      _pairingInfoSubscriptions[instance.id] = _gatewayClient
          .pairingInfoStream(instance.id)
          .listen((info) => _handlePairingInfo(instance.id, info));

      // 2. 通过 Gateway 建立 WebSocket 连接
      await _gatewayClient.connect(instance);
    } catch (error, stackTrace) {
      debugPrint(
        '[ConnectionOrchestrator] _connect FAILED — id=${instance.id}: '
        '$error\n$stackTrace',
      );
      // 连接失败：通过 _disconnect 执行完整的清理流程（取消订阅、
      // 清除配对信息、释放去重锁），然后标记为离线。
      // iron-law-allow: Law8 -- fire-and-forget cleanup on connect failure
      await _disconnect(instance.id).catchError((_) {
        // suppressed
      });
      await _updateHealthStatus(instance.id, HealthStatus.offline);
    } finally {
      // 无论成功或失败都释放去重锁，允许后续重连。
      _connecting.remove(instance.id);
    }
  }

  void _handlePairingInfo(String instanceId, GatewayPairingInfo? info) {
    _emitEvent(PairingInfoChangedEvent(instanceId: instanceId, info: info));
  }

  Future<void> _disconnect(String instanceId) async {
    await _connectionSubscriptions.remove(instanceId)?.cancel();
    await _pairingInfoSubscriptions.remove(instanceId)?.cancel();
    _connecting.remove(instanceId);
    _syncingAgents.remove(instanceId);
    _syncPendingRetry.remove(instanceId);
    _lastReconnectAttempt.remove(instanceId);
    await _gatewayClient.disconnect(instanceId);

    // 清除配对信息 — emit 事件，由 connectionOrchestratorProvider 的订阅消费
    // 并更新 pairingInfoProvider（info == null 表示移除该实例的配对信息）。
    _emitEvent(PairingInfoChangedEvent(instanceId: instanceId, info: null));

    debugPrint('[ConnectionOrchestrator] Disconnected from $instanceId');
  }

  /// 连接成功后自动同步 Agent 列表。
  ///
  /// 对齐 Gateway 协议流程：connect → challenge → connect req → hello-ok → agents.list。
  /// 使用 [_syncingAgents] 防重入，避免同一实例并发同步。
  /// 失败时自动指数退避重试（最多 2 次：5s → 10s）。
  ///
  /// 若同步期间再次收到 connected 事件，当前同步完成后自动重试，
  /// 确保断连→重连场景下不会丢失新的同步机会。
  ///
  /// 使用 do-while 循环而非递归 fire-and-forget，确保：
  /// - [_syncingAgents] 锁覆盖整个重试周期
  /// - 所有错误路径都有日志可追踪
  /// - 不会产生脱离生命周期管理的悬空 Future
  ///
  /// do-while 循环受 [_maxSyncLoops] 上限保护，防止 WebSocket 频繁
  /// 抖动时 [_syncingAgents] 锁被无限期持有。达到上限后锁会被释放，
  /// 后续 connected 事件可正常获取锁并开始新一轮同步。
  Future<void> _syncAgentsForInstance(String instanceId) async {
    if (!_syncingAgents.add(instanceId)) {
      // 已有同步进行中 — 标记待重试，当前同步结束后会检查此标记
      _syncPendingRetry.add(instanceId);
      return;
    }

    try {
      // Loop to handle pending retries from new connected events that
      // arrive while a sync is in progress.  The lock (_syncingAgents)
      // is held for the entire loop so concurrent connected events
      // queue up in _syncPendingRetry instead of starting a parallel
      // sync.
      const maxLoops = 3;
      var loopCount = 0;
      do {
        const retry = RetryStrategy.agentSync;
        for (var attempt = 0; retry.shouldRetry(attempt); attempt++) {
          try {
            final remoteAgents = await _gatewayClient.fetchAgents(instanceId);
            await _agentRepo.syncFromGateway(instanceId, remoteAgents);
            debugPrint(
              '[ConnectionOrchestrator] Synced ${remoteAgents.length} agents '
              'for $instanceId',
            );
            // 通知 UI 层 agent 数据已更新，触发 agentListProvider 重建。
            // 携带 instanceId 让 chat/agent_profile 的 ticker listener 能按实例
            // 过滤（BUG B 修复），避免跨实例 N+1 getById。
            _emitEvent(AgentsSyncedEvent(instanceId));
            // Success — break out of for-loop, then check
            // _syncPendingRetry for pending retries below.
            break;
          } catch (error, stackTrace) {
            if (retry.shouldRetry(attempt + 1)) {
              final delay = retry.delayForAttempt(attempt);
              debugPrint(
                '[ConnectionOrchestrator] Agent sync failed for $instanceId '
                '(attempt ${attempt + 1}/${retry.maxAttempts}), '
                'retrying in ${delay.inSeconds}s: $error',
              );
              await Future.delayed(delay);
            } else {
              debugPrint(
                '[ConnectionOrchestrator] Agent sync failed for $instanceId '
                'after ${retry.maxAttempts} attempts: $error\n$stackTrace',
              );
            }
          }
        }
        // Whether we succeeded or exhausted all retries, check if a
        // new connected event arrived during this sync cycle.
        // If so, loop once more to pick up any new agents.
        loopCount++;
        final hasPendingRetry = _syncPendingRetry.remove(instanceId);
        if (!hasPendingRetry || loopCount >= maxLoops) break;

        // Brief cooldown before re-entering the sync loop to avoid
        // hammering the Gateway when a connected event fires mid-sync.
        await Future<void>.delayed(_syncLoopCooldown);
      } while (true);

      if (loopCount >= maxLoops && _syncPendingRetry.remove(instanceId)) {
        debugPrint(
          '[ConnectionOrchestrator] Agent sync loop limit ($maxLoops) reached '
          'for $instanceId — releasing lock to unblock other instances. '
          'Pending retry discarded; next connected event will re-trigger sync.',
        );
      }

      // Bug 3: Emit InstanceConnectedEvent inside _syncAgentsForInstance
      // (not from .whenComplete) — guards against:
      //   (a) premature emission when early-returning due to lock contention,
      //   (b) stale emission after connection drops mid-sync clearing
      //       reconnectExhausted flag.
      // Only fires when sync DID real work (entered the do-while body,
      // i.e. lock was acquired) AND the connection subscription is still
      // alive (hasn't been cancelled by _disconnect).
      if (!_isDisposed && _connectionSubscriptions.containsKey(instanceId)) {
        _emitEvent(InstanceConnectedEvent(instanceId));
      }
    } finally {
      _syncingAgents.remove(instanceId);
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：状态同步
  // ---------------------------------------------------------------------------

  /// Gateway 连接状态 → 领域 HealthStatus
  HealthStatus _mapToHealthStatus(GatewayConnectionState state) {
    return switch (state) {
      GatewayConnectionState.connected => HealthStatus.online,
      GatewayConnectionState.connecting ||
      GatewayConnectionState.authenticating ||
      GatewayConnectionState.recovering => HealthStatus.connecting,
      GatewayConnectionState.pairingRequired => HealthStatus.pairingRequired,
      GatewayConnectionState.disconnected ||
      GatewayConnectionState.authFailed => HealthStatus.offline,
      GatewayConnectionState.reconnectExhausted =>
        HealthStatus.reconnectExhausted,
    };
  }

  Future<void> _onConnectionStateChanged(
    String instanceId,
    GatewayConnectionState state,
  ) async {
    // Bug 4: 按实例序列化异步调用。Dart 广播流在 async 回调的 Future
    // 完成前就会投递下一个事件 — 两次对同一 instanceId 的调用会在
    // await _instanceRepo.getById() 处交错，导致读到脏数据并写入
    // 错误的 DB 状态。Completer 链保证按到达顺序串行执行。
    final completer = Completer<void>();
    final previous = _stateSerializers[instanceId];
    _stateSerializers[instanceId] = completer;
    await previous?.future;

    try {
      // 中间状态（connecting / authenticating / recovering）不写入数据库。
      //
      // 原因：SaveInstanceUseCase 先写入 online，然后调用 _connect() 建连，
      // 建连过程会触发 connecting → connected 两次状态变化，两个 async handler
      // 可能同时读到 online 旧值，导致 connected handler 的 online==online 判
      // 跳过更新，而 connecting handler 的写入最终覆盖 DB，healthStatus 卡在
      // connecting，UI 显示"离线"。
      //
      // 只允许终态 + connected 传播到 DB。
      // connected 不是 isTerminal（传输层错误可能回退到 recovering），
      // 但作为稳态必须持久化。
      if (!state.isTerminal && state != GatewayConnectionState.connected) {
        return;
      }

      final health = _mapToHealthStatus(state);
      // 瞬态状态不持久化到 DB，改写为 offline 落库。
      // 瞬态信息由对应 Provider 实时传递（如 pairingInfoProvider、
      // reconnectExhaustedProvider）。
      final persistHealth = health.isTransient ? HealthStatus.offline : health;

      // Bug 2: ReconnectExhaustedEvent 必须在 try-DB 之前发射，
      // 确保 DB 写入失败时 UI 仍能收到重试入口。
      // 解耦 UI 事件（必须可达）与持久化（best-effort）。
      if (state == GatewayConnectionState.reconnectExhausted) {
        _emitEvent(ReconnectExhaustedEvent(instanceId));
      }

      try {
        // 只更新与当前数据库不同的状态（避免不必要的写入）
        final current = await _instanceRepo.getById(instanceId);
        if (current != null && current.healthStatus != persistHealth) {
          await _instanceRepo.updateHealthStatus(instanceId, persistHealth);
          if (health == HealthStatus.online) {
            await _instanceRepo.updateLastConnectedAt(
              instanceId,
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );
          }
        }

        // 连接成功后自动同步 Agent 列表（协议流程：connect → agents.list）
        // 放在 DB 状态更新之后，确保 healthStatus=online 已持久化。
        // fire-and-forget：同步失败不影响连接状态，且下一次连接/tick 会重试。
        //
        // Bug 3: InstanceConnectedEvent 由 _syncAgentsForInstance 内部发射
        //（仅在成功路径 + 连接仍存活时），不在 .whenComplete 中无条件发射，
        // 防止过期事件清除 reconnectExhausted 标记。
        if (state == GatewayConnectionState.connected) {
          unawaited(
            _syncAgentsForInstance(instanceId).catchError((
              Object e,
              StackTrace st,
            ) {
              debugPrint(
                '[ConnectionOrchestrator] Unhandled sync error for '
                '$instanceId: $e\n$st',
              );
            }),
          );
        }
      } catch (error) {
        // 实例可能已被删除 — 静默处理
        debugPrint(
          '[ConnectionOrchestrator] Failed to sync health status for '
          '$instanceId: $error',
        );
      } finally {
        // 终态（不可恢复）时释放 _connect 的去重锁。
        // 瞬态状态配对/耗尽为 offline 但也是终态，同样需释放锁。
        // 尽管 _connect() 的 finally 通常先执行，但在异步时序竞争下
        // _onConnectionStateChanged 可能先于 finally，此时额外释放一次
        // （Set.remove 是幂等的）防止永久泄漏。
        if (health == HealthStatus.offline || health.isTransient) {
          _connecting.remove(instanceId);
        }
      }
    } finally {
      completer.complete();
      // 如果当前 completer 仍是最新的（没有新事件注册到我们之后），
      // 则清理以防止内存泄漏。
      if (_stateSerializers[instanceId] == completer) {
        _stateSerializers.remove(instanceId);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：网络变化处理
  // ---------------------------------------------------------------------------

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork =
        results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
    final hasWifi = results.contains(ConnectivityResult.wifi);

    debugPrint(
      '[ConnectionOrchestrator] Network changed: $results '
      '(hasNetwork=$hasNetwork, hasWifi=$hasWifi)',
    );

    if (!hasNetwork) {
      // 所有网络断开 — 不做任何事，WebSocket 自身会超时断线并走重连逻辑
      return;
    }

    if (!hasWifi) {
      // 仅移动网络：取消正在执行的恢复，降级内网实例
      _networkOpGeneration++;
      _degradeLocalNetworkInstances(_networkOpGeneration).catchError((
        Object error,
        StackTrace s,
      ) {
        debugPrint(
          '[ConnectionOrchestrator] Uncaught error while degrading '
          'local instances: $error\n$s',
        );
      });
    } else {
      // WiFi 恢复：取消正在执行的降级操作，然后重连内网实例
      _networkOpGeneration++;
      _recoverLocalNetworkInstances(_networkOpGeneration).catchError((
        Object error,
        StackTrace s,
      ) {
        debugPrint(
          '[ConnectionOrchestrator] Uncaught error while recovering '
          'local instances: $error\n$s',
        );
      });
    }
  }

  Future<void> _degradeLocalNetworkInstances(int generation) async {
    try {
      final affectedIds = await _instanceRepo.batchUpdateStatusByNetwork(
        isLocalNetwork: true,
        status: HealthStatus.expectedOffline,
      );
      if (generation != _networkOpGeneration) return;

      // 断开内网实例的 WebSocket 连接（直接用返回的 ID 列表，
      // 无需再查一次 getAll()）
      for (final id in affectedIds) {
        if (generation != _networkOpGeneration) return;
        await _disconnect(id);
      }

      debugPrint(
        '[ConnectionOrchestrator] Degraded ${affectedIds.length} '
        'local-network instances to EXPECTED_OFFLINE',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[ConnectionOrchestrator] Failed to degrade local instances: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> _recoverLocalNetworkInstances(int generation) async {
    try {
      final instances = await _instanceRepo.getAll();
      if (generation != _networkOpGeneration) return;

      final toRecover = instances.where(
        (i) =>
            i.isLocalNetwork && i.healthStatus == HealthStatus.expectedOffline,
      );

      if (toRecover.isNotEmpty) {
        // 并行重连（每实例独立超时）
        await Future.wait(
          toRecover.map(
            (instance) => _connect(instance).timeout(
              const Duration(seconds: 10),
              onTimeout: () async {
                if (generation != _networkOpGeneration) return;
                debugPrint(
                  '[ConnectionOrchestrator] Recovery connect timeout for '
                  '${instance.id} (${instance.name})',
                );
                await _updateHealthStatus(instance.id, HealthStatus.offline);
              },
            ),
          ),
        );
      }
      if (generation != _networkOpGeneration) return;

      debugPrint(
        '[ConnectionOrchestrator] Recovered ${toRecover.length} '
        'local-network instances',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[ConnectionOrchestrator] Failed to recover local instances: '
        '$error\n$stackTrace',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：辅助方法
  // ---------------------------------------------------------------------------

  Future<void> _updateHealthStatus(
    String instanceId,
    HealthStatus status,
  ) async {
    try {
      await _instanceRepo.updateHealthStatus(instanceId, status);
    } catch (error) {
      debugPrint(
        '[ConnectionOrchestrator] Failed to update health status: $error',
      );
    }
  }

  /// 安全发射事件 — dispose 后静默丢弃（Bug 1 修复）。
  ///
  /// 所有 _eventController.add() 调用必须通过此方法路由，
  /// 防止 fire-and-forget 异步任务在 [dispose] 关闭控制器后
  /// 仍调用 .add() 导致 BadStateError 崩溃。
  /// 静默丢弃不违反 Law 8：dispose 意味着所有下游消费方已不可达，
  /// 事件无消费者，丢弃是正确行为。
  void _emitEvent(InstanceEvent event) {
    if (_isDisposed) return;
    _eventController.add(event);
  }
}
