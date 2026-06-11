import 'package:flutter/material.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/app/theme/tokens.dart';

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
    final theme = Theme.of(context);

    if (connectionState == GatewayConnectionState.disconnected ||
        connectionState == GatewayConnectionState.authFailed) {
      return _banner(
        theme,
        '连接已断开，正在重连...',
        XiaColors.yellow,
        const Color(0x1FC4A86A), // rgba(196,168,106,0.12)
        Icons.wifi_off,
      );
    }
    if (connectionState == GatewayConnectionState.connecting ||
        connectionState == GatewayConnectionState.recovering) {
      return _banner(
        theme,
        '正在连接...',
        XiaColors.accent,
        XiaColors.accentMuted,
        Icons.sync,
      );
    }
    return const SizedBox.shrink();
  }

  static Widget _banner(
    ThemeData theme,
    String message,
    Color fgColor,
    Color bgColor,
    IconData icon,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: XiaSpacing.s2,
      ),
      color: bgColor,
      child: Row(
        children: [
          Icon(icon, size: 16, color: fgColor),
          const SizedBox(width: XiaSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(color: fgColor),
            ),
          ),
        ],
      ),
    );
  }
}
