// 内部基础设施 —— 仅由 lib/core/acl/ 下的两个 IGatewayClient 实现
// （WsGatewayClient、MockGatewayClient）使用。不导出到公共 API。

import 'dart:async';

import 'i_gateway_client.dart';

/// 连接状态流的"单一发射入口 + 晚订阅者种子"封装。
///
/// **解决的实际问题**：[StreamController.broadcast] 不会把历史事件投递
/// 到订阅后才连上的监听者。原本 `_getOrCreateConnectionController` 想在
/// 工厂里同步 `add(disconnected)` 做种子，但广播流没有监听者时事件直接
/// 丢弃 —— 晚订阅者（例如连接建立后才打开的聊天页）始终停在"未初始化"，
/// UI 误报"连接已断开"。[stream] getter 用 last 缓存补上这个洞。
///
/// **统一发射入口**：[emit] 原子地更新 last 缓存并转发到广播控制器。
/// 多个发射点（manager.connectionState 订阅回调、resetConnectionState、
/// _cleanup 的 emit 分支）不再各自直接 `ctrl.add()`，避免遗漏导致
/// last 与广播流不一致。
///
/// **Seed 策略**：仅当 last == connected 时才向新订阅者下沉初始事件。
/// 终态（disconnected / authFailed / reconnectExhausted / ...）不下沉，
/// 避免 ConnectionOrchestrator 在 reconnect()/编辑保存时重新订阅拿到
/// 陈旧终态（会触发 _connecting 锁提前释放、重发 ReconnectExhaustedEvent
/// 等过期事件）。详见 `WsGatewayClient.connectionStateStream` 的注释。
///
/// **多订阅语义**：[stream] 每次 getter 调用都返回**新的** seeded 流
/// （基于广播控制器），不缓存生成器。早期实现把 `async*` 生成器缓存进
/// `_seededView` 复用，但 `async*` 是单订阅流 —— 同实例第二个订阅者
/// （例如同一实例下第二个聊天页）或取消后重新订阅会抛
/// `StateError: Stream has already been listened to`，退化掉广播契约。
/// 每次 `.listen()` 分配一个轻量生成器的代价远小于破坏多订阅。
class ReplayableConnectionState {
  GatewayConnectionState? _last;

  final StreamController<GatewayConnectionState> _ctrl =
      StreamController<GatewayConnectionState>.broadcast();

  /// 单一发射入口：原子地更新 last 缓存并转发到广播控制器。
  /// 调用方**不得**直接持有 [StreamController] 另行 add —— 那会绕过
  /// 缓存同步，破坏封装。
  void emit(GatewayConnectionState state) {
    _last = state;
    // 守护 dispose 竞态：dispose 关闭 controller 是异步的，理论上 emit
    // 可能在 isClosed 读完后被打断；StateError 即可吞掉。
    try {
      if (!_ctrl.isClosed) _ctrl.add(state);
    } on StateError {
      // iron-law-allow: Law8 -- dispose 关闭 controller 的竞态守卫：
      // isClosed 检查与 add 之间理论上可被 dispose 打断，StateError 即可
      // 吞掉。Dart 单线程事件循环下实践中不可达，纯属防御性兜底。
    }
  }

  /// 重置 last 缓存为 `null`，表征"底层连接已消失"。
  /// 调用时机：[WsGatewayClient._cleanup] 在复用 `_InstanceConnection`、
  /// manager 已 dispose 但新 manager 尚未 emit 时。不发任何事件，避免向
  /// 尚未挂上的新 manager 路径投错信号。
  void clear() {
    _last = null;
  }

  /// 连接状态流。晚订阅者行为：
  /// - `last == connected`：先收到 connected seed，再透传后续广播事件；
  /// - 其他情况（null / connecting / 终态）：返回纯广播流，无 replay。
  ///
  /// 每次调用返回新的 seeded 流 —— 支持同实例多订阅与取消后重订阅。
  Stream<GatewayConnectionState> get stream {
    final last = _last;
    if (last != GatewayConnectionState.connected) return _ctrl.stream;
    return _seededConnected(_ctrl.stream);
  }

  /// 释放底层广播控制器。`dispose` 之后 [emit] 与 [stream] 不再生效。
  Future<void> dispose() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }

  /// 先投递 connected seed，再透传 [live] 广播流。
  static Stream<GatewayConnectionState> _seededConnected(
    Stream<GatewayConnectionState> live,
  ) async* {
    yield GatewayConnectionState.connected;
    yield* live;
  }
}
