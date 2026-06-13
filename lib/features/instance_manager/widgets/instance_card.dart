import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';

import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Instance card — matching ComponentSpec Section 7.2.
///
/// Layout: [44×44 icon] [name + url + status] [action buttons]
/// When [HealthStatus.pairingRequired], shows approval guidance inline.
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
    };
  }

  String _healthLabel(HealthStatus status) {
    return switch (status) {
      HealthStatus.online => '在线',
      HealthStatus.connecting => '连接中…',
      HealthStatus.pairingRequired => '等待审批',
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
    // pairingRequired 不持久化到 DB（落库时改写为 offline），
    // 因此不能用 instance.healthStatus 判断——直接以 pairingInfoProvider 为准。
    final showPairingHelp = pairingInfo != null;
    // 当配对进行中时，状态点和文字应反映"等待审批"，而非 DB 中持久化的 offline。
    final effectiveStatus = showPairingHelp
        ? HealthStatus.pairingRequired
        : instance.healthStatus;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.s6,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: XiaColors.surface,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(XiaRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(XiaSpacing.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Instance icon
                  Container(
                    width: 44,
                    height: 44,
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: danger ? XiaColors.redMuted : XiaColors.surface2,
        borderRadius: BorderRadius.circular(XiaRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(XiaRadius.sm),
          onTap: onTap,
          child: Icon(
            icon,
            size: 16,
            color: danger ? XiaColors.red : XiaColors.text3,
          ),
        ),
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
        border: Border.all(color: XiaColors.yellow.withAlpha(80)),
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
