import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';

import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// Instance card — V2 ComponentSpec Section 7.2.
///
/// V2: 36×36 icon (was 44), padding 12/14 (was 16/16), hairline border,
/// status pill r-full 2/8 padding, scale 0.97 press.
class InstanceCard extends ConsumerWidget {
  final Instance instance;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const InstanceCard({
    super.key,
    required this.instance,
    required this.onTap,
    this.onDelete,
  });

  Color _healthColor(HealthStatus status) {
    return switch (status) {
      HealthStatus.online => XiaColors.green,
      HealthStatus.offline => XiaColors.text4,
      HealthStatus.connecting => XiaColors.yellow,
      HealthStatus.pairingRequired => XiaColors.yellow,
      HealthStatus.expectedOffline => XiaColors.text4,
      HealthStatus.unknown => XiaColors.text4,
      HealthStatus.reconnectExhausted => XiaColors.red,
    };
  }

  String _healthLabel(HealthStatus status) {
    return switch (status) {
      HealthStatus.online => '在线',
      HealthStatus.connecting => '连接中…',
      HealthStatus.pairingRequired => '等待审批',
      HealthStatus.reconnectExhausted => '重连失败',
      _ => '离线',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 使用 select 仅监听本实例的配对信息变化，避免整个 Map 更新
    // 时触发所有 InstanceCard 不必要的重建。
    final pairingInfo = ref.watch(
      pairingInfoProvider.select((map) => map[instance.id]),
    );
    final showPairingHelp = pairingInfo != null;

    // 重连耗尽是瞬态状态，不落库（DB 里是 offline），只能通过
    // reconnectExhaustedProvider 实时感知。优先级高于 pairing —— 耗尽时
    // 实例已不可达，展示"重连失败"比"等待审批"更准确。
    final isExhausted = ref.watch(
      reconnectExhaustedProvider.select((set) => set.contains(instance.id)),
    );

    final effectiveStatus = isExhausted
        ? HealthStatus.reconnectExhausted
        : (showPairingHelp
              ? HealthStatus.pairingRequired
              : instance.healthStatus);

    return PressFeedback(
      scale: 0.97, // V2: 0.98 → 0.97
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.pagePaddingH,
          vertical: 4, // V2: 6 → 8px then ÷2 → 4px gap
        ),
        decoration: BoxDecoration(
          color: XiaColors.surface,
          borderRadius: BorderRadius.circular(XiaRadius.lg),
          border: Border.all(color: XiaColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12, // V2: 12px
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // V2: 36×36 icon (was 44)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: XiaColors.surface2,
                      borderRadius: BorderRadius.circular(XiaRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.dns,
                      size: 22,
                      color: XiaColors.text2,
                    ),
                  ),
                  const SizedBox(width: XiaSpacing.s4),
                  // Name + URL + status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          instance.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: XiaColors.text1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          instance.gatewayUrl,
                          style: const TextStyle(
                            fontSize: 13,
                            color: XiaColors.text3,
                            letterSpacing: -0.3,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: XiaSpacing.s1),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _healthColor(effectiveStatus),
                                shape: BoxShape.circle,
                                boxShadow:
                                    effectiveStatus == HealthStatus.online
                                    ? XiaShadow.onlineGlow
                                    : null,
                              ),
                            ),
                            const SizedBox(width: XiaSpacing.s1),
                            Text(
                              _healthLabel(effectiveStatus),
                              style: TextStyle(
                                fontSize: 12,
                                color: _healthColor(effectiveStatus),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Action buttons
                  Row(
                    children: [
                      _ActionBtn(
                        icon: Icons.refresh,
                        onTap: () => ref
                            .read(connectionOrchestratorProvider)
                            .reconnect(instance),
                      ),
                      if (onDelete != null) ...[
                        const SizedBox(width: XiaSpacing.s2),
                        _ActionBtn(
                          icon: Icons.delete_outline,
                          onTap: onDelete,
                          danger: true,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              // Pairing guidance
              if (showPairingHelp) ...[
                const SizedBox(height: XiaSpacing.s4),
                _PairingGuidanceBanner(
                  requestId: pairingInfo.requestId,
                  deviceId: pairingInfo.deviceId,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  const _ActionBtn({required this.icon, this.onTap, this.danger = false});

  // Cached decorations — `PressFeedback.builder` fires on every press/release,
  // so building a fresh BoxDecoration on each call allocates on the tap hot
  // path. Both danger × pressed variants are precomputed and shared across all
  // _ActionBtn instances. Color.lerp isn't const so we use static final.
  static final BoxDecoration _idleNormal = BoxDecoration(
    color: XiaColors.surface2,
    borderRadius: _radius,
  );
  static final BoxDecoration _idleDanger = BoxDecoration(
    color: XiaColors.redMuted,
    borderRadius: _radius,
  );
  static final BoxDecoration _pressedNormal = BoxDecoration(
    color: XiaColors.surface3,
    borderRadius: _radius,
    border: Border.all(
      color: XiaColors.accent,
      width: 1,
      strokeAlign: BorderSide.strokeAlignInside,
    ),
  );
  static final BoxDecoration _pressedDanger = BoxDecoration(
    color: Color.lerp(XiaColors.redMuted, Colors.black, 0.25)!,
    borderRadius: _radius,
    border: Border.all(
      color: XiaColors.red,
      width: 1,
      strokeAlign: BorderSide.strokeAlignInside,
    ),
  );
  static const _radius = BorderRadius.all(Radius.circular(XiaRadius.sm));

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      onTap: onTap,
      builder: (child, isPressed) => AnimatedScale(
        // PressFeedback in builder mode IGNORES its own `scale` param
        // (press_feedback_buttons.dart:120-149), so the 0.97 scale must
        // be applied here manually — without it, 36×36 buttons have only
        // the border / color change for feedback, imperceptible on dark
        // OLED or bright sunlight (instance_manager/instance_card_test.dart
        // 'scale guard' regression).
        scale: isPressed ? 0.97 : 1.0,
        duration: XiaMotion.durationFast,
        curve: XiaMotion.ease,
        child: AnimatedContainer(
          // Press feedback uses the accent border as the primary visible signal.
          // The previous color-only change (surface2→surface3) had only ~3%
          // luminance delta, imperceptible on a 36×36 button, and the danger
          // variant had zero color change.
          duration: XiaMotion.durationFast,
          curve: XiaMotion.ease,
          width: 36,
          height: 36,
          decoration: isPressed
              ? (danger ? _pressedDanger : _pressedNormal)
              : (danger ? _idleDanger : _idleNormal),
          alignment: Alignment.center,
          child: child,
        ),
      ),
      child: Icon(
        icon,
        size: 16,
        color: danger ? XiaColors.red : XiaColors.text3,
      ),
    );
  }
}

/// Inline banner shown when a device is pending server-side approval.
///
/// Displays the approval command with a one-tap copy button and the
/// truncated device ID for reference.
class _PairingGuidanceBanner extends StatelessWidget {
  final String requestId;
  final String deviceId;

  const _PairingGuidanceBanner({
    required this.requestId,
    required this.deviceId,
  });

  String get _command => 'openclaw devices approve $requestId';

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _command));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: $_command'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(XiaSpacing.s3),
      decoration: BoxDecoration(
        color: XiaColors.yellowMuted,
        borderRadius: BorderRadius.circular(XiaRadius.sm),
        border: Border.all(color: XiaColors.yellow.withAlpha(64)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚠️ 此设备尚未获得服务器审批',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: XiaColors.text2,
            ),
          ),
          const SizedBox(height: XiaSpacing.s1),
          const Text(
            '在服务器终端执行以下命令后，下拉刷新即可连接：',
            style: TextStyle(fontSize: 11, color: XiaColors.text3),
          ),
          const SizedBox(height: XiaSpacing.s2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: XiaSpacing.s2,
              vertical: XiaSpacing.s1,
            ),
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _command,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: XiaColors.text1,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _copy(context),
                  child: const Icon(
                    Icons.copy,
                    size: 14,
                    color: XiaColors.text3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: XiaSpacing.s1),
          Text(
            '设备ID: ${deviceId.length > 16 ? deviceId.substring(0, 16) : deviceId}…',
            style: const TextStyle(
              fontSize: 10,
              color: XiaColors.text4,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
