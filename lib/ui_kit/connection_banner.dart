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

  /// 重连重试回调 — 仅在 [GatewayConnectionState.reconnectExhausted] 状态下生效。
  ///
  /// 该状态下 banner 文案为"点击重试"，需要由上层（ChatRoomPage）注入实际触发
  /// `orchestrator.reconnect` 的闭包。其他状态分支忽略此回调（保持不可点击），
  /// 因为它们要么是自动恢复中（connecting/recovering）、要么是终态不可手动恢复
  /// （disconnected/authFailed 走自动重连）。
  final VoidCallback? onRetry;

  const ConnectionBanner({
    super.key,
    required this.connectionState,
    this.onRetry,
  });

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
      widget.connectionState == GatewayConnectionState.recovering ||
      widget.connectionState == GatewayConnectionState.reconnectExhausted;

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
    if (widget.connectionState == GatewayConnectionState.reconnectExhausted) {
      // 防御：onRetry 为 null 时文案不应包含"点击重试"（bug #14）。
      // 生产环境中 fallback 为纯提示文案，避免误导用户点击无效横幅。
      assert(
        widget.onRetry != null,
        'reconnectExhausted 状态下 onRetry 必须提供，否则"点击重试"不可用',
      );
      return StatusBanner(
        message: widget.onRetry != null
            ? '无法连接到虾，请检查网络或实例状态。点击重试'
            : '无法连接到虾，请检查网络或实例状态',
        foregroundColor: XiaColors.red,
        backgroundColor: XiaColors.redMuted,
        icon: Icons.warning_amber_rounded,
        onTap: widget.onRetry,
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
