import 'package:flutter/material.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/status_banner.dart';

/// A slim status banner that slides in below the AppBar.
///
/// Three visual states:
/// - **disconnected / authFailed** — yellow-tinted bg, yellow text
/// - **connecting / recovering** — accent-muted bg, accent text
/// - **connected** — collapsed (zero height)
class ConnectionBanner extends StatelessWidget {
  final GatewayConnectionState connectionState;

  const ConnectionBanner({super.key, required this.connectionState});

  @override
  Widget build(BuildContext context) {
    if (connectionState == GatewayConnectionState.disconnected ||
        connectionState == GatewayConnectionState.authFailed) {
      return const StatusBanner(
        message: '连接已断开，正在重连...',
        foregroundColor: XiaColors.yellow,
        backgroundColor: XiaColors.yellowMuted,
        icon: Icons.wifi_off,
      );
    }
    if (connectionState == GatewayConnectionState.connecting ||
        connectionState == GatewayConnectionState.recovering) {
      return const StatusBanner(
        message: '正在连接...',
        foregroundColor: XiaColors.accent,
        backgroundColor: XiaColors.accentMuted,
        icon: Icons.sync,
      );
    }
    return const SizedBox.shrink();
  }
}
