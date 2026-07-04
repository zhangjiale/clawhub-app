import 'package:web_socket_channel/web_socket_channel.dart';

import 'connection_manager.dart';
import 'gateway_protocol.dart';
import 'i_device_token_store.dart';

/// Factory for creating [ConnectionManager] instances.
///
/// Centralizes the construction of per-instance connection managers so that
/// [WsGatewayClient] does not need to carry the WebSocket/timer/token-store
/// injection details in its core logic.
class GatewayConnectionFactory {
  const GatewayConnectionFactory({
    this._webSocketFactory,
    this._timerFactory,
    this._deviceTokenStore,
  });

  final WebSocketChannel Function(Uri)? _webSocketFactory;
  final TimerFactory? _timerFactory;
  final IDeviceTokenStore? _deviceTokenStore;

  /// Creates a new [ConnectionManager] for the given instance.
  ConnectionManager create({
    required String instanceId,
    required String gatewayUrl,
    required String token,
    required String deviceId,
    required ConnectionConfig config,
  }) {
    return ConnectionManager(
      instanceId: instanceId,
      gatewayUrl: gatewayUrl,
      token: token,
      deviceId: deviceId,
      config: config,
      webSocketFactory: _webSocketFactory,
      timerFactory: _timerFactory,
      deviceTokenStore: _deviceTokenStore,
    );
  }
}
