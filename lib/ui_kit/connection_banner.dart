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
///
/// **Animation (B2)**: 350ms slide from top (translateY -100% → 0) using
/// ClipRect + AnimationController, matching design spec Section 10.4.
class ConnectionBanner extends StatefulWidget {
  final GatewayConnectionState connectionState;

  const ConnectionBanner({super.key, required this.connectionState});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  bool get _isVisible =>
      widget.connectionState == GatewayConnectionState.disconnected ||
      widget.connectionState == GatewayConnectionState.authFailed ||
      widget.connectionState == GatewayConnectionState.connecting ||
      widget.connectionState == GatewayConnectionState.recovering;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: XiaMotion.durationMid, // 350ms
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: XiaMotion.ease));

    if (_isVisible) {
      // Already visible on first build — show immediately without animation
      _slideController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant ConnectionBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionState != widget.connectionState) {
      _slideController
          .stop(); // Stop in-flight animation before changing direction
      if (_isVisible) {
        _slideController.forward();
      } else {
        _slideController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible && _slideController.value == 0.0) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: SlideTransition(position: _slideAnimation, child: _buildBanner()),
    );
  }

  Widget _buildBanner() {
    if (widget.connectionState == GatewayConnectionState.disconnected ||
        widget.connectionState == GatewayConnectionState.authFailed) {
      return const StatusBanner(
        message: '连接已断开，正在重连...',
        foregroundColor: XiaColors.yellow,
        backgroundColor: XiaColors.yellowMuted,
        icon: Icons.wifi_off,
      );
    }
    if (widget.connectionState == GatewayConnectionState.connecting ||
        widget.connectionState == GatewayConnectionState.recovering) {
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
