import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// 网络连接监听接口 — 面向接口编程，便于单测 mock 网络切换。
///
/// [connectivity_plus] 的 [Connectivity] 通过平台通道获取网络状态，
/// 单测中无法控制其行为。此接口将网络监听抽象化，使
/// [ConnectionOrchestrator] 的网络降级/恢复逻辑可被验证。
abstract class IConnectivity {
  /// 网络连接状态变化流。
  ///
  /// 发出当前连接类型列表（WiFi、移动网络、以太网等）。
  /// 空列表或 [ConnectivityResult.none] 表示无网络。
  Stream<List<ConnectivityResult>> get onConnectivityChanged;
}

/// [connectivity_plus] 的 [Connectivity] → [IConnectivity] 适配器。
class ConnectivityAdapter implements IConnectivity {
  final Connectivity _connectivity;

  ConnectivityAdapter({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;
}
