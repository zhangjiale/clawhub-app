import 'package:flutter/material.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/app/theme/theme.dart';

/// A slim status banner that slides in below the AppBar when the Gateway
/// connection is disrupted.
///
/// Supports three visual states:
/// - **disconnected / authFailed** — red banner with wifi-off icon
/// - **connecting / recovering** — orange banner with sync icon
/// - **connected** — collapsed (zero height), no banner shown
///
/// Extracted from ChatRoomPage so other pages (AgentListPage, etc.) can
/// reuse it without copying the private `_buildConnectionBanner` / `_banner`
/// methods.
class ConnectionBanner extends StatelessWidget {
  final GatewayConnectionState connectionState;

  const ConnectionBanner({super.key, required this.connectionState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (connectionState == GatewayConnectionState.disconnected ||
        connectionState == GatewayConnectionState.authFailed) {
      return _banner(
        theme,
        '连接已断开，正在重连...',
        AppColors.statusOffline,
        Icons.wifi_off,
      );
    }
    if (connectionState == GatewayConnectionState.connecting ||
        connectionState == GatewayConnectionState.recovering) {
      return _banner(
        theme,
        '正在连接...',
        AppColors.statusConnecting,
        Icons.sync,
      );
    }
    return const SizedBox.shrink();
  }

  static Widget _banner(
    ThemeData theme,
    String message,
    Color color,
    IconData icon,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withAlpha(25),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
