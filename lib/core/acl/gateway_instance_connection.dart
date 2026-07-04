import 'dart:async';

import '../../domain/models/models.dart';
import 'connection_manager.dart';
import 'gateway_protocol.dart';
import 'i_gateway_client.dart';
import 'replayable_connection_state.dart';

/// 单个 Gateway 实例的连接资源聚合。
///
/// 职责：
/// - 持有 [ConnectionManager] 与所有广播流控制器
/// - 管理连接状态 / Gateway 事件 / 配对信息的订阅
/// - 提供可复用的清理与完整释放方法
///
/// 不包含任何协议事件处理业务逻辑；事件通过 [onEvent] 回调转发给所有者。
class GatewayInstanceConnection {
  /// Connection manager. Set to null by [cleanupManager] / [dispose] as a
  /// re-entrancy guard — callers check `manager == null` to skip
  /// already-cleaned-up connections.
  ConnectionManager? manager;

  /// 连接状态流 + last 缓存封装。所有发射点必须经过它（详见
  /// [ReplayableConnectionState]），不得直接持有 StreamController 另行 add。
  final ReplayableConnectionState connectionState = ReplayableConnectionState();

  final StreamController<Message> messageCtrl;
  final StreamController<ToolCall> toolCallCtrl;
  final StreamController<GatewayPairingInfo?> pairingInfoCtrl;
  final StreamController<StreamingEvent> streamingCtrl;

  /// Gap #6: per-instance diagnostic stream for Gateway `payload.large`
  /// (and future diagnostic) events. Surfaced via
  /// [IGatewayClient.gatewayNoticeStream] so the UI layer can show a
  /// user-visible hint instead of silently failing. Element type is the
  /// sealed [GatewayNotice] union so new subtypes flow without retyping.
  final StreamController<GatewayNotice> gatewayNoticeCtrl =
      StreamController<GatewayNotice>.broadcast();

  StreamSubscription<EventFrame>? _eventSub;
  StreamSubscription<GatewayConnectionState>? _stateSub;
  StreamSubscription<GatewayPairingInfo?>? _pairingSub;

  GatewayInstanceConnection({
    required this.messageCtrl,
    required this.toolCallCtrl,
    required this.pairingInfoCtrl,
    required this.streamingCtrl,
  });

  /// Wires [manager] into this connection: subscribes to its streams and
  /// routes events through [onEvent].
  ///
  /// Safe to call multiple times (e.g. after a reconnect cleanup), but the
  /// caller is responsible for cancelling the previous manager's subscriptions
  /// first.
  void wire({
    required ConnectionManager manager,
    required void Function(EventFrame event) onEvent,
  }) {
    this.manager = manager;

    // 订阅连接状态
    _stateSub = manager.connectionState.listen(connectionState.emit);

    // 订阅 Gateway 事件
    _eventSub = manager.events.listen(onEvent);

    // 订阅配对信息
    _pairingSub = manager.pairingInfo.listen((info) {
      if (!pairingInfoCtrl.isClosed) {
        pairingInfoCtrl.add(info);
      }
    });
  }

  /// Cancels subscriptions and disposes the current [manager], but keeps the
  /// broadcast controllers alive so late subscribers can still attach.
  ///
  /// If [emitDisconnected] is true, emits [GatewayConnectionState.disconnected]
  /// after cleanup — used by [IGatewayClient.disconnect].
  Future<void> cleanupManager({bool emitDisconnected = false}) async {
    // Capture-and-null serves as a re-entrancy guard: if another call arrives
    // during an await below, manager will already be null and the call returns
    // immediately.
    final current = manager;
    if (current == null) return; // already being cleaned up
    manager = null;

    await _eventSub?.cancel();
    _eventSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    // 清空 last 缓存必须在 _stateSub 取消「之后」、剩余 await（pairingSub
    // 取消、manager.dispose）「之前」进行：
    //  - 之后：_stateSub 是唯一把旧 manager 的状态事件路由进
    //    connectionState.emit 的通道；取消后旧 manager 不可能再写入
    //    _last，故 clear() 不会被迟到的 emit 重新污染。
    //  - 之前：manager.dispose()（关闭 WebSocket，可达毫秒级）等 await 期间
    //    若有晚订阅者调用 connectionStateStream，_last 仍是 connected → 会
    //    拿到陈旧 connected seed。提前 clear() 关闭这个窗口。
    connectionState.clear();
    await _pairingSub?.cancel();
    _pairingSub = null;
    await current.dispose();

    if (emitDisconnected) {
      connectionState.emit(GatewayConnectionState.disconnected);
    }
  }

  /// Fully releases this connection: disposes the manager, closes all
  /// controllers, and clears the connection-state cache.
  Future<void> dispose() async {
    await cleanupManager();
    await connectionState.dispose();
    await _closeIfOpen(messageCtrl);
    await _closeIfOpen(toolCallCtrl);
    await _closeIfOpen(pairingInfoCtrl);
    await _closeIfOpen(streamingCtrl);
    await _closeIfOpen(gatewayNoticeCtrl);
  }

  static Future<void> _closeIfOpen<T>(StreamController<T> controller) async {
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}
