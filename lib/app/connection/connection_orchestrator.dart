import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../core/acl/i_gateway_client.dart';
import '../../core/iconnectivity.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/instance.dart';
import '../../domain/repositories/i_instance_repo.dart';
import '../../domain/usecases/instance_lifecycle.dart';

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
  final IConnectivity _connectivity;

  /// instanceId → GatewayConnectionState 订阅
  final Map<String, StreamSubscription<GatewayConnectionState>>
  _connectionSubscriptions = {};

  /// 网络监听订阅
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// 避免在 connect() 内部触发的状态同步中重复调用 disconnect
  final Set<String> _connecting = {};

  /// 网络操作代数计数器 — 每次降级/恢复递增，
  /// 操作内每次 await 后校验，旧操作若被新操作取代则提前退出，
  /// 防止 WiFi→4G→WiFi 快速切换时降级与恢复交错执行。
  int _networkOpGeneration = 0;

  /// 标记 dispose 已调用，initialize() 中的异步操作应提前退出。
  bool _isDisposed = false;

  ConnectionOrchestrator({
    required IGatewayClient gatewayClient,
    required IInstanceRepo instanceRepo,
    IConnectivity? connectivity,
  })  : _gatewayClient = gatewayClient,
        _instanceRepo = instanceRepo,
        _connectivity = connectivity ?? ConnectivityAdapter();

  // ---------------------------------------------------------------------------
  // 公开 API
  // ---------------------------------------------------------------------------

  /// 初始化：自动连接所有可连接的已保存实例，启动网络监听。
  ///
  /// 所有实例并行连接（每实例独立超时 10 秒），
  /// 避免多实例场景下串行阻塞的启动延迟。
  Future<void> initialize() async {
    final instances = await _instanceRepo.getAll();
    if (_isDisposed) return;

    final toConnect = instances.where(
      (i) => i.healthStatus.isConnectable,
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
    _connectivitySubscription = _connectivity.onConnectivityChanged
        .listen(_onConnectivityChanged);

    debugPrint(
      '[ConnectionOrchestrator] Initialized',
    );
  }

  /// 实例保存后调用（新建或编辑）。
  Future<void> onInstanceSaved(Instance instance) async {
    // 编辑：先断开旧连接，再重连
    if (_connectionSubscriptions.containsKey(instance.id)) {
      await _disconnect(instance.id);
    }

    // 连通性测试已在 SaveInstanceUseCase 中完成，
    // 只有在测试通过（online）时才建立 WebSocket 连接
    if (instance.healthStatus == HealthStatus.online) {
      await _connect(instance);
    }
  }

  /// 实例删除后调用。
  Future<void> onInstanceDeleted(String instanceId) async {
    await _disconnect(instanceId);
  }

  /// 释放所有资源。
  Future<void> dispose() async {
    _isDisposed = true;
    _connectivitySubscription?.cancel();

    // 断开所有活跃实例的 Gateway 连接
    final instanceIds = _connectionSubscriptions.keys.toList();
    for (final id in instanceIds) {
      await _gatewayClient.disconnect(id).catchError((_) {});
    }

    for (final sub in _connectionSubscriptions.values) {
      await sub.cancel();
    }
    _connectionSubscriptions.clear();
    _connecting.clear();
  }

  // ---------------------------------------------------------------------------
  // 内部：连接管理
  // ---------------------------------------------------------------------------

  Future<void> _connect(Instance instance) async {
    // 防止重复连接
    if (_connecting.contains(instance.id)) return;
    _connecting.add(instance.id);

    try {
      // 1. 通过 Gateway 建立 WebSocket 连接
      await _gatewayClient.connect(instance);

      // 2. 订阅连接状态变化 → 同步到 HealthStatus
      final sub = _gatewayClient
          .connectionStateStream(instance.id)
          .listen((state) => _onConnectionStateChanged(instance.id, state));

      // 替换已有订阅（编辑场景）
      await _connectionSubscriptions[instance.id]?.cancel();
      _connectionSubscriptions[instance.id] = sub;

      debugPrint(
        '[ConnectionOrchestrator] Connected to ${instance.id} (${instance.name})',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[ConnectionOrchestrator] Failed to connect to ${instance.id}: '
        '$error\n$stackTrace',
      );
      // 连接失败：清理可能已部分建立的 Gateway 连接，
      // 然后解除去重锁并标记为离线。
      await _gatewayClient.disconnect(instance.id).catchError((_) {});
      _connecting.remove(instance.id);
      await _updateHealthStatus(instance.id, HealthStatus.offline);
    }
  }

  Future<void> _disconnect(String instanceId) async {
    await _connectionSubscriptions.remove(instanceId)?.cancel();
    _connecting.remove(instanceId);
    await _gatewayClient.disconnect(instanceId);

    debugPrint(
      '[ConnectionOrchestrator] Disconnected from $instanceId',
    );
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
      GatewayConnectionState.recovering =>
        HealthStatus.connecting,
      GatewayConnectionState.disconnected ||
      GatewayConnectionState.authFailed =>
        HealthStatus.offline,
    };
  }

  Future<void> _onConnectionStateChanged(
    String instanceId,
    GatewayConnectionState state,
  ) async {
    final health = _mapToHealthStatus(state);

    try {
      // 只更新与当前数据库不同的状态（避免不必要的写入）
      final current = await _instanceRepo.getById(instanceId);
      if (current != null && current.healthStatus != health) {
        await _instanceRepo.updateHealthStatus(instanceId, health);
        if (health == HealthStatus.online) {
          await _instanceRepo.updateLastConnectedAt(
            instanceId,
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
        }
      }
    } catch (error) {
      // 实例可能已被删除 — 静默处理
      debugPrint(
        '[ConnectionOrchestrator] Failed to sync health status for '
        '$instanceId: $error',
      );
    } finally {
      // 终态 offline（authFailed / 彻底断开）时释放 _connect 的去重锁。
      // 放在 finally 中确保即使 DB 操作抛异常也不会永久泄漏锁。
      if (health == HealthStatus.offline) {
        _connecting.remove(instanceId);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 内部：网络变化处理
  // ---------------------------------------------------------------------------

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.isNotEmpty &&
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
      _degradeLocalNetworkInstances(_networkOpGeneration)
          .catchError((Object error, StackTrace s) {
        debugPrint(
          '[ConnectionOrchestrator] Uncaught error while degrading '
          'local instances: $error\n$s',
        );
      });
    } else {
      // WiFi 恢复：取消正在执行的降级操作，然后重连内网实例
      _networkOpGeneration++;
      _recoverLocalNetworkInstances(_networkOpGeneration)
          .catchError((Object error, StackTrace s) {
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
            i.isLocalNetwork &&
            i.healthStatus == HealthStatus.expectedOffline,
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
}
